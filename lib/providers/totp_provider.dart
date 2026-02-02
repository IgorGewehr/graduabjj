import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/totp_service.dart';

/// TOTP Service Provider
final totpServiceProvider = Provider<TotpService>((ref) {
  return TotpService();
});

/// TOTP Enabled Provider - reads Firestore to check if user has TOTP enabled
final totpEnabledProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(totpServiceProvider);
  return service.isTotpEnabled();
});
