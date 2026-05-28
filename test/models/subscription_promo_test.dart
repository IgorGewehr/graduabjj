import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/constants.dart';
import 'package:graduabjj/models/academy.dart';

void main() {
  group('Desconto de 1º mês — DESLIGADO', () {
    test('cupom promocional está vazio (desligado)', () {
      expect(AppConstants.caktoMensalPromoCoupon, isEmpty);
    });

    test('conta nova em trial NÃO recebe desconto (promo off)', () {
      final sub = AcademySubscription(
        plan: SubscriptionPlan.free,
        status: SubscriptionStatus.active,
        createdAt: DateTime.now(),
      );
      // Está em trial, mas como o cupom está desligado, não há desconto.
      expect(sub.isTrialing, isTrue);
      expect(sub.isFirstMonthPromoEligible, isFalse);
    });
  });
}
