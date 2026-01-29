import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user.dart';
import '../services/firebase_service.dart';
import 'auth_provider.dart';
import 'portal_providers.dart';

/// State for the selected academy
class SelectedAcademyState {
  final String? selectedAcademyId;
  final Map<String, AcademyInfo> academyInfoCache;
  final bool isLoading;

  const SelectedAcademyState({
    this.selectedAcademyId,
    this.academyInfoCache = const {},
    this.isLoading = false,
  });

  SelectedAcademyState copyWith({
    String? selectedAcademyId,
    Map<String, AcademyInfo>? academyInfoCache,
    bool? isLoading,
  }) {
    return SelectedAcademyState(
      selectedAcademyId: selectedAcademyId ?? this.selectedAcademyId,
      academyInfoCache: academyInfoCache ?? this.academyInfoCache,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  bool get hasSelectedAcademy => selectedAcademyId != null;
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

/// StateNotifier for managing selected academy
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

  /// Select a different academy
  Future<void> selectAcademy(String academyId) async {
    if (state.selectedAcademyId == academyId) return;

    state = state.copyWith(isLoading: true);

    try {
      final mapping = await _ref.read(userAcademyMappingProvider.future);
      if (mapping == null || !mapping.academyIds.contains(academyId)) {
        throw Exception('Academia nao encontrada ou sem acesso');
      }

      await _selectAcademyInternal(academyId, mapping);

      // Invalidate providers that depend on academy context
      _invalidateDependentProviders();
    } catch (e) {
      print('[SelectedAcademy] Error selecting academy: $e');
      state = state.copyWith(isLoading: false);
      rethrow;
    }
  }

  Future<void> _selectAcademyInternal(
    String academyId,
    UserAcademyMapping mapping,
  ) async {
    // Update FirebaseService context
    FirebaseService.setAcademyId(academyId);

    // Load academy info if not cached
    Map<String, AcademyInfo> newCache = Map.from(state.academyInfoCache);
    if (!newCache.containsKey(academyId)) {
      final info = await _loadAcademyInfo(academyId, mapping);
      if (info != null) {
        newCache[academyId] = info;
      }
    }

    state = SelectedAcademyState(
      selectedAcademyId: academyId,
      academyInfoCache: newCache,
      isLoading: false,
    );
  }

  Future<AcademyInfo?> _loadAcademyInfo(
    String academyId,
    UserAcademyMapping mapping,
  ) async {
    try {
      // Get academy document for name/logo
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
      print('[SelectedAcademy] Error loading academy info: $e');
      return null;
    }
  }

  /// Invalidate providers that depend on the selected academy
  void _invalidateDependentProviders() {
    // These providers will re-fetch data for the new academy
    _ref.invalidate(currentUserProvider);
    _ref.invalidate(academySettingsProvider);
    _ref.invalidate(currentStudentProvider);
  }

  /// Get current student ID for the selected academy
  String? getCurrentStudentId() {
    final academyId = state.selectedAcademyId;
    if (academyId == null) return null;
    return state.academyInfoCache[academyId]?.studentId;
  }

  /// Get academy details for the selected academy
  AcademyInfo? getCurrentAcademyInfo() {
    final academyId = state.selectedAcademyId;
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

/// Provider for selected academy state
final selectedAcademyProvider =
    StateNotifierProvider<SelectedAcademyNotifier, SelectedAcademyState>((ref) {
  return SelectedAcademyNotifier(ref);
});

/// Provider for the currently selected academy ID
final selectedAcademyIdProvider = Provider<String?>((ref) {
  return ref.watch(selectedAcademyProvider).selectedAcademyId;
});

/// Provider for current academy info
final currentAcademyInfoProvider = Provider<AcademyInfo?>((ref) {
  final state = ref.watch(selectedAcademyProvider);
  if (state.selectedAcademyId == null) return null;
  return state.academyInfoCache[state.selectedAcademyId];
});

/// Provider to check if user has multiple academies
final hasMultipleAcademiesProvider = Provider<bool>((ref) {
  final mapping = ref.watch(userAcademyMappingProvider).valueOrNull;
  return mapping?.hasMultipleAcademies ?? false;
});

/// Provider for list of user's academies with info
final userAcademiesInfoProvider = FutureProvider<List<AcademyInfo>>((ref) async {
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
