import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto/academy_dto.dart';
import '../api/dto/identity_dto.dart';
import '../api/repositories.dart';
import 'api_provider.dart';
import '../models/user.dart';
import '../services/firebase_service.dart';
import 'auth_provider.dart';

/// Source of truth for the currently selected academy id.
///
/// Post-migration (Fase 1): the id stored here is always a Postgres UUID
/// returned by Tatami `/v1/me`, NOT a Firestore document ID.
final selectedAcademyIdProvider = StateProvider<String?>((ref) => null);

/// State for the selected academy (kept for backwards compatibility — exposes
/// the cache + loading flag the UI uses for the multi-academy switcher).
class SelectedAcademyState {
  final Map<String, AcademyInfo> academyInfoCache;
  final bool isLoading;

  const SelectedAcademyState({
    this.academyInfoCache = const {},
    this.isLoading = false,
  });

  SelectedAcademyState copyWith({
    Map<String, AcademyInfo>? academyInfoCache,
    bool? isLoading,
  }) {
    return SelectedAcademyState(
      academyInfoCache: academyInfoCache ?? this.academyInfoCache,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Basic academy info for display
class AcademyInfo {
  final String id;
  final String name;
  final String? logoUrl;
  final String? studentId;
  final UserRole role;

  const AcademyInfo({
    required this.id,
    required this.name,
    this.logoUrl,
    this.studentId,
    required this.role,
  });
}

/// StateNotifier for managing the academy info cache + bootstrap of the
/// initial selected academy.
///
/// Post-migration: initialises from Tatami `/v1/me` (not Firestore), so the
/// academy id is always the Postgres UUID used by all subsequent API calls.
class SelectedAcademyNotifier extends StateNotifier<SelectedAcademyState> {
  final Ref _ref;

  SelectedAcademyNotifier(this._ref) : super(const SelectedAcademyState()) {
    _initialize();
  }

  /// Initialize from Tatami `/v1/me` — the single source of truth for
  /// memberships post-migration. Falls back to Firestore only on network error.
  Future<void> _initialize() async {
    try {
      final repo = _ref.read(identityRepoProvider);
      final me = await repo.getMe();

      final actives = me.activeMemberships;
      if (actives.isEmpty) return;

      // Pick initial academy: prefer primary, else first active.
      final primaryId = me.primaryAcademyId;
      final picked = () {
        if (primaryId != null) {
          for (final m in actives) {
            if (m.academyId == primaryId) return m;
          }
        }
        return actives.first;
      }();

      // Pre-populate cache for all memberships.
      final cache = <String, AcademyInfo>{};
      for (final m in actives) {
        final info = await _loadAcademyInfoFromTatami(m.academyId, m);
        if (info != null) cache[m.academyId] = info;
      }

      state = SelectedAcademyState(academyInfoCache: cache, isLoading: false);
      _ref.read(selectedAcademyIdProvider.notifier).state = picked.academyId;
      FirebaseService.setAcademyId(picked.academyId);
    } catch (_) {
      // Network failure — fall back to legacy Firestore path.
      await _initializeFromFirestore();
    }
  }

  /// Legacy fallback: reads Firestore `userAcademyMapping` collection.
  /// Only reached when Tatami is unreachable at boot time.
  Future<void> _initializeFromFirestore() async {
    final mapping = await _ref.read(userAcademyMappingProvider.future);
    if (mapping == null || mapping.academyIds.isEmpty) return;

    final primaryId = mapping.primaryAcademyId ?? mapping.academyIds.first;

    Map<String, AcademyInfo> newCache = Map.from(state.academyInfoCache);
    if (!newCache.containsKey(primaryId)) {
      final info = await _loadAcademyInfoFromFirestore(primaryId, mapping);
      if (info != null) newCache[primaryId] = info;
    }

    state = SelectedAcademyState(academyInfoCache: newCache, isLoading: false);
    _ref.read(selectedAcademyIdProvider.notifier).state = primaryId;
    FirebaseService.setAcademyId(primaryId);
  }

  /// Select a different academy.
  Future<void> selectAcademy(String academyId) async {
    final currentId = _ref.read(selectedAcademyIdProvider);
    if (currentId == academyId) return;

    state = state.copyWith(isLoading: true);

    try {
      Map<String, AcademyInfo> newCache = Map.from(state.academyInfoCache);
      if (!newCache.containsKey(academyId)) {
        final info = await _loadAcademyInfoFromTatamiById(academyId);
        if (info != null) newCache[academyId] = info;
      }

      state =
          SelectedAcademyState(academyInfoCache: newCache, isLoading: false);
      _ref.read(selectedAcademyIdProvider.notifier).state = academyId;
      FirebaseService.setAcademyId(academyId);
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  /// Load academy info from a Tatami membership + GET /v1/academies/{id}.
  Future<AcademyInfo?> _loadAcademyInfoFromTatami(
    String academyId,
    ApiMembership membership,
  ) async {
    try {
      final client = _ref.read(tatamiClientProvider);
      final json =
          await client.get<Map<String, dynamic>>('/v1/academies/$academyId');
      final academy = ApiAcademy.fromJson(json);

      return AcademyInfo(
        id: academy.id,
        name: academy.name,
        logoUrl: null, // Tatami doesn't expose logo_url yet
        studentId: membership.studentId,
        role: _mapApiRole(membership.role),
      );
    } catch (_) {
      return null;
    }
  }

  /// Load academy info by id only (for selectAcademy, when we don't have
  /// the membership handy — re-fetch /v1/me to get the role).
  Future<AcademyInfo?> _loadAcademyInfoFromTatamiById(
    String academyId,
  ) async {
    try {
      final repo = _ref.read(identityRepoProvider);
      final me = await repo.getMe();
      final membership = me.memberships.firstWhere(
        (m) => m.academyId == academyId,
        orElse: () => me.memberships.first,
      );
      return _loadAcademyInfoFromTatami(academyId, membership);
    } catch (_) {
      return null;
    }
  }

  /// Firestore fallback for _loadAcademyInfo.
  Future<AcademyInfo?> _loadAcademyInfoFromFirestore(
    String academyId,
    UserAcademyMapping mapping,
  ) async {
    try {
      final academyDoc = await FirebaseService.firestore
          .collection('academies')
          .doc(academyId)
          .get();

      if (!academyDoc.exists) return null;

      final data = academyDoc.data()!;
      final details = mapping.academyDetails?[academyId];

      return AcademyInfo(
        id: academyId,
        name: data['name'] ?? 'Academia',
        logoUrl: data['logoUrl'] as String?,
        studentId: details?.studentId,
        role: details?.role ?? UserRole.student,
      );
    } catch (_) {
      return null;
    }
  }

  static UserRole _mapApiRole(ApiRole role) {
    switch (role) {
      case ApiRole.admin:
        return UserRole.admin;
      case ApiRole.instructor:
        return UserRole.instructor;
      case ApiRole.monitor:
        return UserRole.instructor;
      case ApiRole.guardian:
        return UserRole.guardian;
      case ApiRole.student:
        return UserRole.student;
    }
  }

  /// Clear all cached state. Called on logout so the next login starts fresh.
  void clear() {
    state = const SelectedAcademyState();
    _ref.read(selectedAcademyIdProvider.notifier).state = null;
  }

  String? getCurrentStudentId() {
    final academyId = _ref.read(selectedAcademyIdProvider);
    if (academyId == null) return null;
    return state.academyInfoCache[academyId]?.studentId;
  }

  AcademyInfo? getCurrentAcademyInfo() {
    final academyId = _ref.read(selectedAcademyIdProvider);
    if (academyId == null) return null;
    return state.academyInfoCache[academyId];
  }

  Future<AcademyInfo?> getAcademyInfo(String academyId) async {
    if (state.academyInfoCache.containsKey(academyId)) {
      return state.academyInfoCache[academyId];
    }

    final info = await _loadAcademyInfoFromTatamiById(academyId);
    if (info != null) {
      state = state.copyWith(
        academyInfoCache: {...state.academyInfoCache, academyId: info},
      );
    }
    return info;
  }

  Future<void> refreshAcademyCache() async {
    try {
      final repo = _ref.read(identityRepoProvider);
      final me = await repo.getMe();

      Map<String, AcademyInfo> newCache = {};
      for (final m in me.activeMemberships) {
        final info = await _loadAcademyInfoFromTatami(m.academyId, m);
        if (info != null) newCache[m.academyId] = info;
      }

      state = state.copyWith(academyInfoCache: newCache);
    } catch (_) {
      // Silently fail — cache stays stale until next successful refresh.
    }
  }
}

/// Provider for selected academy state (cache + loading flag).
final selectedAcademyProvider =
    StateNotifierProvider<SelectedAcademyNotifier, SelectedAcademyState>((ref) {
      return SelectedAcademyNotifier(ref);
    });

/// Provider for current academy info — reads cache by current id.
final currentAcademyInfoProvider = Provider<AcademyInfo?>((ref) {
  final id = ref.watch(selectedAcademyIdProvider);
  if (id == null) return null;
  final cache = ref.watch(
    selectedAcademyProvider.select((s) => s.academyInfoCache),
  );
  return cache[id];
});

/// Provider to check if user has multiple academies
final hasMultipleAcademiesProvider = Provider<bool>((ref) {
  final cache = ref.watch(
    selectedAcademyProvider.select((s) => s.academyInfoCache),
  );
  return cache.length > 1;
});

/// Provider for list of user's academies with info
final userAcademiesInfoProvider = FutureProvider<List<AcademyInfo>>((
  ref,
) async {
  final notifier = ref.read(selectedAcademyProvider.notifier);
  await notifier.refreshAcademyCache();
  final cache = ref.read(selectedAcademyProvider).academyInfoCache;
  return cache.values.toList();
});

/// Academy data fetched on demand for the currently selected academy.
final currentAcademyDataProvider = FutureProvider<AcademyInfo?>((ref) async {
  final id = ref.watch(selectedAcademyIdProvider);
  if (id == null) return null;
  return ref.read(selectedAcademyProvider.notifier).getAcademyInfo(id);
});
