import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/providers/store_checkout_provider.dart';

void main() {
  late ProviderContainer container;
  StoreCheckoutNotifier notifier() =>
      container.read(storeCheckoutProvider.notifier);
  StoreCheckoutState state() => container.read(storeCheckoutProvider);

  setUp(() {
    container = ProviderContainer();
    // Keep the autoDispose notifier alive for the duration of the test.
    container.listen(storeCheckoutProvider, (prev, next) {}, fireImmediately: true);
  });

  tearDown(() => container.dispose());

  group('StoreCheckoutState reducer', () {
    test('starts on review', () {
      expect(state().step, StoreCheckoutStep.review);
      expect(state().paymentMethod, isNull);
      expect(state().order, isNull);
    });

    test('nextStep: review -> payment', () {
      notifier().nextStep();
      expect(state().step, StoreCheckoutStep.payment);
    });

    test('nextStep never auto-enters processing or advances past payment', () {
      notifier().nextStep(); // payment
      notifier().nextStep(); // stays on payment (placeOrder owns processing)
      expect(state().step, StoreCheckoutStep.payment);
    });

    test('previousStep: payment -> review, and is a no-op on review', () {
      notifier().nextStep();
      expect(state().step, StoreCheckoutStep.payment);
      notifier().previousStep();
      expect(state().step, StoreCheckoutStep.review);
      notifier().previousStep();
      expect(state().step, StoreCheckoutStep.review);
    });

    test('goToStep jumps and clears the error', () {
      notifier().goToStep(StoreCheckoutStep.done);
      expect(state().step, StoreCheckoutStep.done);
    });

    test('canProceed gates on the selected method at the payment step', () {
      notifier().nextStep();
      expect(state().canProceed, isFalse);
      notifier().setPaymentMethod(StoreCheckoutMethod.pix);
      expect(state().paymentMethod, StoreCheckoutMethod.pix);
      expect(state().canProceed, isTrue);
    });

    test('processing step can never proceed', () {
      notifier().goToStep(StoreCheckoutStep.processing);
      expect(state().canProceed, isFalse);
    });

    test('setNotes trims and nulls out blanks', () {
      notifier().setNotes('  retirar amanha  ');
      expect(state().notes, 'retirar amanha');
      notifier().setNotes('   ');
      expect(state().notes, isNull);
    });

    test('reset returns to the initial state', () {
      notifier().nextStep();
      notifier().setPaymentMethod(StoreCheckoutMethod.creditCard);
      notifier().reset();
      expect(state().step, StoreCheckoutStep.review);
      expect(state().paymentMethod, isNull);
    });
  });

  group('StoreCheckoutState.copyWith', () {
    test('clears nullable fields explicitly via sentinel', () {
      const s = StoreCheckoutState(
        paymentMethod: StoreCheckoutMethod.pix,
        notes: 'x',
        error: 'boom',
      );
      final cleared = s.copyWith(paymentMethod: null, notes: null, error: null);
      expect(cleared.paymentMethod, isNull);
      expect(cleared.notes, isNull);
      expect(cleared.error, isNull);
    });

    test('omitted fields are preserved', () {
      const s = StoreCheckoutState(
        paymentMethod: StoreCheckoutMethod.pix,
        notes: 'keep',
      );
      final next = s.copyWith(step: StoreCheckoutStep.payment);
      expect(next.step, StoreCheckoutStep.payment);
      expect(next.paymentMethod, StoreCheckoutMethod.pix);
      expect(next.notes, 'keep');
    });
  });
}
