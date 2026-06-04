import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/store_service.dart';
import 'auth_provider.dart';
import 'store_provider.dart';

/// The step the store checkout is currently on.
///
/// Pickup-only flow (retirada na academia) — there is intentionally NO
/// address/delivery step: the buyer reviews the cart, picks a payment method,
/// the order is placed (processing) and the flow lands on [done].
enum StoreCheckoutStep {
  /// Cart review (items + notes), before choosing how to pay.
  review,

  /// Payment-method selection (PIX / Cartao via `PaymentMethodSheet`).
  payment,

  /// The order is being created on the server (`StoreService.createOrder`).
  processing,

  /// The order was created (pending payment) and is returned to the caller.
  done,
}

/// Selected payment method for the store checkout.
///
/// Display-level only: the actual charge is created by the existing
/// PIX/Card sheets and validated server-side. Mirrors the marketplace's
/// `PaymentMethod` so the UI can pre-select before opening a sheet.
enum StoreCheckoutMethod { pix, creditCard }

/// Immutable state of the store checkout state machine.
///
/// Follows the marketplace `CheckoutState` shape (sentinel `copyWith` so
/// nullable fields can be explicitly cleared). Money stays server-authoritative:
/// the total shown comes from the cart, but the order amount is (re)derived from
/// database prices inside [StoreService.createOrder] — the client total is never
/// trusted.
class StoreCheckoutState {
  /// Current step of the flow.
  final StoreCheckoutStep step;

  /// Chosen payment method (null until the buyer picks one on [step.payment]).
  final StoreCheckoutMethod? paymentMethod;

  /// Optional buyer notes attached to the order.
  final String? notes;

  /// The order created by [StoreCheckoutNotifier.placeOrder]. Null until the
  /// flow reaches [StoreCheckoutStep.done].
  final StoreOrder? order;

  /// Whether an async action (placing the order) is in flight.
  final bool isLoading;

  /// User-facing error from the last failed action, if any.
  final String? error;

  const StoreCheckoutState({
    this.step = StoreCheckoutStep.review,
    this.paymentMethod,
    this.notes,
    this.order,
    this.isLoading = false,
    this.error,
  });

  static const _sentinel = Object();

  StoreCheckoutState copyWith({
    StoreCheckoutStep? step,
    Object? paymentMethod = _sentinel,
    Object? notes = _sentinel,
    Object? order = _sentinel,
    bool? isLoading,
    Object? error = _sentinel,
  }) {
    return StoreCheckoutState(
      step: step ?? this.step,
      paymentMethod: paymentMethod == _sentinel
          ? this.paymentMethod
          : paymentMethod as StoreCheckoutMethod?,
      notes: notes == _sentinel ? this.notes : notes as String?,
      order: order == _sentinel ? this.order : order as StoreOrder?,
      isLoading: isLoading ?? this.isLoading,
      error: error == _sentinel ? this.error : error as String?,
    );
  }

  /// Whether the flow can advance from the current [step].
  bool get canProceed {
    switch (step) {
      case StoreCheckoutStep.review:
        return true;
      case StoreCheckoutStep.payment:
        return paymentMethod != null;
      case StoreCheckoutStep.processing:
        return false;
      case StoreCheckoutStep.done:
        return true;
    }
  }
}

/// Drives the store checkout state machine
/// (review -> payment -> processing -> done) and places the order.
///
/// Pure reducer for the step transitions plus a single side-effecting
/// [placeOrder] that delegates price/stock validation to the server. No
/// address/delivery — orders are picked up at the academy.
class StoreCheckoutNotifier extends StateNotifier<StoreCheckoutState> {
  final Ref ref;

  StoreCheckoutNotifier(this.ref) : super(const StoreCheckoutState());

  // --- Reducer (step machine) -------------------------------------------

  /// Jump to an explicit [step].
  void goToStep(StoreCheckoutStep step) {
    state = state.copyWith(step: step, error: null);
  }

  /// Advance to the next logical step. Stops at [StoreCheckoutStep.done] and
  /// never auto-enters [StoreCheckoutStep.processing] (that is owned by
  /// [placeOrder]).
  void nextStep() {
    switch (state.step) {
      case StoreCheckoutStep.review:
        state = state.copyWith(step: StoreCheckoutStep.payment, error: null);
        break;
      case StoreCheckoutStep.payment:
      case StoreCheckoutStep.processing:
      case StoreCheckoutStep.done:
        break;
    }
  }

  /// Step back towards [StoreCheckoutStep.review]. No-op on the first/terminal
  /// steps.
  void previousStep() {
    switch (state.step) {
      case StoreCheckoutStep.payment:
        state = state.copyWith(step: StoreCheckoutStep.review, error: null);
        break;
      case StoreCheckoutStep.review:
      case StoreCheckoutStep.processing:
      case StoreCheckoutStep.done:
        break;
    }
  }

  /// Set (or clear, with null/blank) the buyer notes.
  void setNotes(String? notes) {
    final trimmed = notes?.trim();
    state = state.copyWith(notes: (trimmed == null || trimmed.isEmpty) ? null : trimmed);
  }

  /// Choose the payment method on the payment step.
  void setPaymentMethod(StoreCheckoutMethod method) {
    state = state.copyWith(paymentMethod: method, error: null);
  }

  /// Clear the last error without touching the rest of the state.
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Reset the machine back to its initial [StoreCheckoutStep.review] state.
  void reset() {
    state = const StoreCheckoutState();
  }

  // --- Side effect -------------------------------------------------------

  /// Creates the pending order on the server and returns it.
  ///
  /// Moves the flow into [StoreCheckoutStep.processing] while the call is in
  /// flight, then to [StoreCheckoutStep.done] (storing the created [StoreOrder]
  /// in state) on success. On failure it surfaces a friendly [error] and
  /// returns to [StoreCheckoutStep.review] (or stays on [payment]).
  ///
  /// SECURITY: the amount is never sent from the client — [StoreService.createOrder]
  /// re-reads each product's price/stock from the database and derives the total,
  /// so a tampered cart total cannot change what is charged. Ownership is
  /// preserved by passing the authenticated user's own `studentId`.
  Future<StoreOrder?> placeOrder() async {
    if (state.isLoading) return null;

    final previousStep = state.step;

    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null || currentUser.studentId == null) {
      state = state.copyWith(
        error: 'Voce precisa estar vinculado a um aluno para fazer um pedido.',
      );
      return null;
    }

    final service = ref.read(storeServiceProvider);
    if (service == null) {
      state = state.copyWith(error: 'Nao foi possivel acessar a loja.');
      return null;
    }

    final items = ref.read(cartProvider);
    if (items.isEmpty) {
      state = state.copyWith(error: 'Seu carrinho esta vazio.');
      return null;
    }

    state = state.copyWith(
      isLoading: true,
      step: StoreCheckoutStep.processing,
      error: null,
    );

    try {
      // Server validates prices and stock and derives the authoritative total.
      final order = await service.createOrder(
        studentId: currentUser.studentId!,
        studentName: currentUser.displayName,
        items: items,
        notes: state.notes,
      );

      state = state.copyWith(
        order: order,
        isLoading: false,
        step: StoreCheckoutStep.done,
      );
      return order;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        step: previousStep == StoreCheckoutStep.processing
            ? StoreCheckoutStep.review
            : previousStep,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
      return null;
    }
  }
}

/// Store checkout provider — autoDispose so each checkout session starts fresh
/// (the cart is the source of truth; stale checkout state must never leak into
/// the next purchase).
final storeCheckoutProvider =
    StateNotifierProvider.autoDispose<StoreCheckoutNotifier, StoreCheckoutState>(
  (ref) => StoreCheckoutNotifier(ref),
);
