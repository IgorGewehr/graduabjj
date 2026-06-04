import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/firebase_service.dart';
import '../services/payment/payment_gateway_resolver.dart';

/// Resolves (and caches per academy) the connected payment gateway following
/// the MP > Asaas > AbacatePay precedence.
///
/// This is the single source of truth consumed by the financial and store
/// screens to decide which gateway generates charges, whether a card option is
/// offered ([PaymentGatewayCapabilities.cardSupported]) and whether the payer
/// CPF must be captured ([PaymentGatewayCapabilities.requireCpf]). Keyed by
/// `academyId` so each academy resolves at most once until invalidated.
final paymentGatewayProvider =
    FutureProvider.family<PaymentGateway, String>((ref, academyId) async {
  return PaymentGatewayResolver.resolve(academyId);
});

/// Convenience view of [paymentGatewayProvider] scoped to the currently active
/// academy ([FirebaseService.academyId]). Equivalent to watching the family
/// with that id — exposed so call sites that already operate on the active
/// academy don't have to thread the id through manually.
final currentPaymentGatewayProvider = FutureProvider<PaymentGateway>((ref) {
  return ref.watch(paymentGatewayProvider(FirebaseService.academyId).future);
});
