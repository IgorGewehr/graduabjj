import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../services/firebase_service.dart';
import 'auth_provider.dart';

/// Source of truth for the currently selected academy id.
///
/// This is intentionally a `StateProvider<String?>` so that flipping the id is
/// cheap (no Firebase queries) and any provider that watches it via
/// `ref.watch(selectedAcademyIdProvider.select((id) => id))` will automatically
/// rebuild on change — eliminating the previous `ref.invalidate` cascade in
/// `selectAcademy()`.
///
/// Initialised by [SelectedAcademyNotifier] from `userAcademyMappingProvider`,
/// or set by `selectAcademy(id)` when the user switches academies.
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
/// initial selected academy. Mutations to the selected id go through
/// [selectedAcademyIdProvider] (no manual invalidations of dependent
/// providers — they auto-react via `.select` on the id).
class SelectedAcademyNotifier extends StateNotifier<SelectedAcademyState> {
  final Ref _ref;

  SelectedAcademyNotifier(this._ref) : super(const SelectedAcademyState()) {
    _initialize();
  }

  /// Initialize with user's primary academy
  Future<void> _initialize() async {
    final mapping = await _ref.read(userAcademyMappingProvider.future);
    if (mapping != null && mapping.academyIds.isNotEmpty) {
      final primaryId = mapping.primaryAcademyId ?? mapping.academyIds.first;
      await _selectAcademyInternal(primaryId, mapping);
    }
  }

  /// Select a different academy. Only mutates [selectedAcademyIdProvider] +
  /// the local cache; downstream providers (currentUser/currentStudent/etc)
  /// rebuild automatically because they watch the id provider with `.select`.
  Future<void> selectAcademy(String academyId) async {
    final currentId = _ref.read(selectedAcademyIdProvider);
    if (currentId == academyId) return;

    state = state.copyWith(isLoading: true);

    try {
      final mapping = await _ref.read(userAcademyMappingProvider.future);
      if (mapping == null || !mapping.academyIds.contains(academyId)) {
        throw Exception('Academia nao encontrada ou sem acesso');
      }

      await _selectAcademyInternal(academyId, mapping);
    } catch (e) {
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  Future<void> _selectAcademyInternal(
    String academyId,
    UserAcademyMapping mapping,
  ) async {
    // Load academy info if not cached
    Map<String, AcademyInfo> newCache = Map.from(state.academyInfoCache);
    if (!newCache.containsKey(academyId)) {
      final info = await _loadAcademyInfo(academyId, mapping);
      if (info != null) {
        newCache[academyId] = info;
      }
    }

    // Flip the cache + loading flag first so the cache lookup below
    // (used by `currentAcademyInfoProvider`) is consistent when listeners
    // rebuild.
    state = SelectedAcademyState(academyInfoCache: newCache, isLoading: false);

    // Single authoritative source-of-truth update: triggers the rebuild
    // cascade for currentUserProvider, currentStudentProvider, etc.
    _ref.read(selectedAcademyIdProvider.notifier).state = academyId;

    // Keep FirebaseService in sync for legacy services/screens that still
    // read FirebaseService.academyId directly (phased out progressively).
    FirebaseService.setAcademyId(academyId);
  }

  Future<AcademyInfo?> _loadAcademyInfo(
    String academyId,
    UserAcademyMapping mapping,
  ) async {
    try {
      // TODO(tatami): substituir por identityRepoProvider.getMe() ou um
      //   endpoint GET /v1/academies/{id} quando tatami expor o entity de academia
      //   com name/logoUrl. Por ora lê direto do Firestore (academy doc).
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
        logoUrl: data['logoUrl'],
        studentId: details?.studentId,
        role: details?.role ?? UserRole.student,
      );
    } catch (e) {
      return null;
    }
  }

  /// Get current student ID for the selected academy
  String? getCurrentStudentId() {
    final academyId = _ref.read(selectedAcademyIdProvider);
    if (academyId == null) return null;
    return state.academyInfoCache[academyId]?.studentId;
  }

  /// Get academy details for the selected academy
  AcademyInfo? getCurrentAcademyInfo() {
    final academyId = _ref.read(selectedAcademyIdProvider);
    if (academyId == null) return null;
    return state.academyInfoCache[academyId];
  }

  /// Get academy info by ID (from cache or load)
  Future<AcademyInfo?> getAcademyInfo(String academyId) async {
    if (state.academyInfoCache.containsKey(academyId)) {
      return state.academyInfoCache[academyId];
    }

    final mapping = await _ref.read(userAcademyMappingProvider.future);
    if (mapping == null) return null;

    final info = await _loadAcademyInfo(academyId, mapping);
    if (info != null) {
      state = state.copyWith(
        academyInfoCache: {...state.academyInfoCache, academyId: info},
      );
    }
    return info;
  }

  /// Refresh academy info cache
  Future<void> refreshAcademyCache() async {
    final mapping = await _ref.read(userAcademyMappingProvider.future);
    if (mapping == null) return;

    Map<String, AcademyInfo> newCache = {};
    for (final academyId in mapping.academyIds) {
      final info = await _loadAcademyInfo(academyId, mapping);
      if (info != null) {
        newCache[academyId] = info;
      }
    }

    state = state.copyWith(academyInfoCache: newCache);
  }
}

/// Provider for selected academy state (cache + loading flag).
final selectedAcademyProvider =
    StateNotifierProvider<SelectedAcademyNotifier, SelectedAcademyState>((ref) {
      return SelectedAcademyNotifier(ref);
    });

/// Provider for current academy info — reads cache by current id.
/// Cheap rebuild: only fires when id or cache entry for that id change.
final currentAcademyInfoProvider = Provider<AcademyInfo?>((ref) {
  final id = ref.watch(selectedAcademyIdProvider);
  if (id == null) return null;
  // Watch only the cache map identity (changes on cache writes).
  final cache = ref.watch(
    selectedAcademyProvider.select((s) => s.academyInfoCache),
  );
  return cache[id];
});

/// Provider to check if user has multiple academies
final hasMultipleAcademiesProvider = Provider<bool>((ref) {
  final mapping = ref.watch(userAcademyMappingProvider).valueOrNull;
  return mapping?.hasMultipleAcademies ?? false;
});

/// Provider for list of user's academies with info
final userAcademiesInfoProvider = FutureProvider<List<AcademyInfo>>((
  ref,
) async {
  final mapping = await ref.watch(userAcademyMappingProvider.future);
  if (mapping == null || mapping.academyIds.isEmpty) return [];

  final notifier = ref.read(selectedAcademyProvider.notifier);
  final List<AcademyInfo> academies = [];

  for (final academyId in mapping.academyIds) {
    final info = await notifier.getAcademyInfo(academyId);
    if (info != null) {
      academies.add(info);
    }
  }

  return academies;
});

/// Academy data fetched on demand for the currently selected academy.
///
/// Exposes the academy document data (name/logo/etc) keyed by the selected
/// id. Listeners only re-fetch when the id actually changes (no cascade from
/// unrelated state in [selectedAcademyProvider]).
final currentAcademyDataProvider = FutureProvider<AcademyInfo?>((ref) async {
  final id = ref.watch(selectedAcademyIdProvider);
  if (id == null) return null;

  // Reuse the cache + loader on the notifier so we don't re-fetch the same
  // academy document twice.
  return ref.read(selectedAcademyProvider.notifier).getAcademyInfo(id);
});
