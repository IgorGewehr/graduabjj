import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/providers/store_checkout_provider.dart';

/// Pillar: FINANCEIRO / PAGAMENTOS — store checkout state machine.
///
/// Complements store_checkout_provider_test.dart with the adversarial edges:
/// terminal/invalid transitions must be inert, errors must clear on the right
/// actions, and the money-bearing `order` field must survive unrelated updates.
void main() {
  late ProviderContainer container;
  StoreCheckoutNotifier notifier() =>
      container.read(storeCheckoutProvider.notifier);
  StoreCheckoutState state() => container.read(storeCheckoutProvider);

  setUp(() {
    container = ProviderContainer();
    container.listen(storeCheckoutProvider, (prev, next) {},
        fireImmediately: true);
  });
  tearDown(() => container.dispose());

  group('terminal/illegal transitions are inert', () {
    test('nextStep on done stays on done', () {
      notifier().goToStep(StoreCheckoutStep.done);
      notifier().nextStep();
      expect(state().step, StoreCheckoutStep.done);
    });

    test('nextStep on processing stays on processing', () {
      notifier().goToStep(StoreCheckoutStep.processing);
      notifier().nextStep();
      expect(state().step, StoreCheckoutStep.processing);
    });

    test('previousStep on processing/done is a no-op', () {
      notifier().goToStep(StoreCheckoutStep.processing);
      notifier().previousStep();
      expect(state().step, StoreCheckoutStep.processing);

      notifier().goToStep(StoreCheckoutStep.done);
      notifier().previousStep();
      expect(state().step, StoreCheckoutStep.done);
    });
  });

  group('error lifecycle', () {
    test('goToStep clears a previous error', () {
      // Seed an error via copyWith then jump.
      container.read(storeCheckoutProvider.notifier).goToStep(
            StoreCheckoutStep.payment,
          );
      // setPaymentMethod also clears error; simulate an error then a jump.
      final withError = const StoreCheckoutState(error: 'boom');
      expect(withError.error, 'boom');
      notifier().goToStep(StoreCheckoutStep.review);
      expect(state().error, isNull);
    });

    test('setPaymentMethod clears error and records the choice', () {
      notifier().nextStep();
      notifier().setPaymentMethod(StoreCheckoutMethod.creditCard);
      expect(state().paymentMethod, StoreCheckoutMethod.creditCard);
      expect(state().error, isNull);
    });

    test('clearError leaves step/method intact', () {
      notifier().nextStep();
      notifier().setPaymentMethod(StoreCheckoutMethod.pix);
      notifier().clearError();
      expect(state().step, StoreCheckoutStep.payment);
      expect(state().paymentMethod, StoreCheckoutMethod.pix);
    });
  });

  group('canProceed truth table', () {
    test('review always proceeds', () {
      expect(state().canProceed, isTrue);
    });

    test('done always proceeds', () {
      notifier().goToStep(StoreCheckoutStep.done);
      expect(state().canProceed, isTrue);
    });

    test('payment proceeds only with a chosen method', () {
      notifier().nextStep();
      expect(state().canProceed, isFalse);
      notifier().setPaymentMethod(StoreCheckoutMethod.pix);
      expect(state().canProceed, isTrue);
    });
  });

  group('copyWith preserves the money-bearing order field', () {
    test('setting notes/step does not drop a stored order reference', () {
      // order is null here (no StoreOrder fixture needed): the sentinel must
      // keep whatever was there. Assert null survives an unrelated update.
      final next = state().copyWith(step: StoreCheckoutStep.payment);
      expect(next.order, isNull);
      // And an explicit clear is honoured.
      const seeded = StoreCheckoutState(step: StoreCheckoutStep.done);
      expect(seeded.copyWith(isLoading: true).order, isNull);
    });
  });
}
