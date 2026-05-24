import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/academy.dart';
import '../services/firebase_service.dart';
import 'auth_provider.dart';

/// Real-time stream of the current academy's subscription.
/// Null while the user hasn't joined any academy yet.
final subscriptionProvider = StreamProvider<AcademySubscription?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  final academyId = user?.academyId;
  if (academyId == null) return Stream.value(null);

  return FirebaseService.firestore
      .collection('academies')
      .doc(academyId)
      .snapshots()
      .map((snap) {
    if (!snap.exists) return null;
    final data = snap.data() as Map<String, dynamic>;
    final subMap = data['subscription'] as Map<String, dynamic>?;
    if (subMap == null) return null;
    return AcademySubscription.fromMap(subMap);
  });
});

/// True when the admin has active access (trial, paid, or override).
/// Defaults to true while loading to avoid flickering paywall on startup.
final hasSubscriptionAccessProvider = Provider<bool>((ref) {
  final sub = ref.watch(subscriptionProvider);
  return sub.when(
    data: (s) => s?.hasAccess ?? true,
    loading: () => true,
    error: (e, _) => true,
  );
});
