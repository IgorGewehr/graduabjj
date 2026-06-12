import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'abacate_pay_service.dart' show PaymentLink, CardData, CardPaymentResult;
import 'mp_card_tokenizer.dart';

/// Mercado Pago marketplace/split service (student -> admin receivables).
///
/// The academy connects its OWN MP account via OAuth; charges settle directly
/// into it (0% platform fee, no platform wallet). PIX only. Mirrors the
/// AbacatePayService method shapes so the payment UI can swap gateways with a
/// simple resolver. Returns the shared [PaymentLink] so the QR/pix sheets are
/// unchanged.
class MercadoPagoService {
  final String academyId;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  MercadoPagoService(this.academyId);

  /// True when the academy has connected its Mercado Pago account.
  Future<bool> isEnabled() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('academies')
          .doc(academyId)
          .get();
      if (!doc.exists) return false;
      return doc.data()?['mpConnected'] == true;
    } catch (_) {
      return false;
    }
  }

  String? get _payerEmail => FirebaseAuth.instance.currentUser?.email;

  /// Reads the academy's connected MP public key (for client-side card
  /// tokenization).
  Future<String?> _publicKey() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('academies')
          .doc(academyId)
          .get();
      return doc.data()?['mpPublicKey'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// PIX for a tuition (financial) record. [amount] in REAIS (converted to
  /// centavos for the CF, matching the AbacatePay contract). [cpf] is the
  /// payer's CPF — Mercado Pago requires it for PIX.
  Future<PaymentLink?> createPixPayment({
    required double amount,
    required String financialId,
    required String studentId,
    required String studentName,
    String? description,
    String? cpf,
  }) async {
    try {
      final result =
          await _functions.httpsCallable('createMpPixPayment').call({
        'academyId': academyId,
        'amount': (amount * 100).round(), // centavos (CF divides by 100)
        'description': description ?? 'Mensalidade',
        'financialId': financialId,
        'studentId': studentId,
        'studentName': studentName,
        'payerCpf': cpf,
        'payerEmail': _payerEmail,
      });
      return PaymentLink.fromMap(Map<String, dynamic>.from(result.data));
    } on FirebaseFunctionsException catch (e) {
      print('[MercadoPago] createPixPayment error: ${e.code} - ${e.message}');
      rethrow; // let the UI show the MP message (e.g. seller PIX not enabled)
    } catch (e) {
      print('[MercadoPago] createPixPayment exception: $e');
      return null;
    }
  }

  /// PIX for a store order. [amount] in REAIS (converted to CENTAVOS for the
  /// CF — the CF divides by 100, matching the tuition contract; the value is
  /// only a cross-check since the CF derives the charge from the stored order).
  Future<PaymentLink?> createStoreOrderPayment({
    required double amount,
    required String orderId,
    required String studentId,
    required String studentName,
    String? description,
    String? cpf,
  }) async {
    try {
      final result =
          await _functions.httpsCallable('createMpOrderPixPayment').call({
        'academyId': academyId,
        'amount': (amount * 100).round(), // centavos (CF derives & cross-checks)
        'description': description ?? 'Pedido da Loja',
        'orderId': orderId,
        'studentId': studentId,
        'studentName': studentName,
        'payerCpf': cpf,
        'payerEmail': _payerEmail,
      });
      return PaymentLink.fromMap(Map<String, dynamic>.from(result.data));
    } on FirebaseFunctionsException catch (e) {
      print('[MercadoPago] createStoreOrderPayment error: ${e.code} - ${e.message}');
      rethrow;
    } catch (e) {
      print('[MercadoPago] createStoreOrderPayment exception: $e');
      return null;
    }
  }

  /// Card payment for a tuition (financial) record. Tokenizes [cardData]
  /// client-side with the academy's public key, then charges via the CF.
  Future<CardPaymentResult> createCardPayment({
    required double amount,
    required String financialId,
    required String studentId,
    required String studentName,
    required CardData cardData,
    String? description,
    int installments = 1,
  }) {
    return _chargeCard(
      amount: (amount * 100).round(), // centavos (CF divides by 100)
      idKey: 'financialId',
      idValue: financialId,
      studentId: studentId,
      studentName: studentName,
      cardData: cardData,
      description: description ?? 'Mensalidade',
      installments: installments,
    );
  }

  /// Starts a recurring card subscription (MP Preapproval) for a recurring
  /// plan. The card is tokenized client-side (PCI-safe); the monthly value,
  /// term and billing day are derived server-side from the plan.
  Future<({bool success, String message, String? subscriptionId, String? status})>
      createSubscription({
    required String planId,
    required String studentId,
    required String studentName,
    required CardData cardData,
  }) async {
    try {
      final pk = await _publicKey();
      if (pk == null || pk.isEmpty) {
        return (
          success: false,
          message: 'Mercado Pago nao conectado.',
          subscriptionId: null,
          status: null,
        );
      }
      final token = await MpCardTokenizer.tokenize(
        publicKey: pk,
        cardNumber: cardData.cardNumber,
        expirationMonth: cardData.expirationMonth,
        expirationYear: cardData.expirationYear,
        securityCode: cardData.cvv,
        cardholderName: cardData.cardHolder,
        cpf: cardData.cpf,
      );
      final result =
          await _functions.httpsCallable('createMpSubscription').call({
        'academyId': academyId,
        'planId': planId,
        'studentId': studentId,
        'studentName': studentName,
        'cardToken': token.tokenId,
        'payerCpf': cardData.cpf,
        'payerEmail': _payerEmail,
      });
      final data = Map<String, dynamic>.from(result.data);
      final status = data['status'] as String?;
      // A mensagem reflete o status real do preapproval: 'authorized' já está
      // cobrando; 'pending' ainda aguarda a autorização do cartão no MP.
      return (
        success: true,
        message: status == 'authorized'
            ? 'Assinatura ativada!'
            : 'Assinatura criada! Aguardando autorizacao do cartao.',
        subscriptionId: data['subscriptionId'] as String?,
        status: status,
      );
    } on FirebaseFunctionsException catch (e) {
      // e.message vem pt-BR do backend (ex.: failed-precondition de
      // assinatura duplicada) — exibe direto ao usuario.
      return (
        success: false,
        message: (e.message?.trim().isNotEmpty ?? false)
            ? e.message!.trim()
            : 'Falha ao criar a assinatura. Tente novamente.',
        subscriptionId: null,
        status: null,
      );
    } catch (e) {
      debugPrint('[MercadoPago] createSubscription exception: $e');
      return (
        success: false,
        message: 'Nao foi possivel criar a assinatura. Verifique os dados '
            'do cartao e tente novamente.',
        subscriptionId: null,
        status: null,
      );
    }
  }

  /// Card payment for a store order. [amount] in REAIS (converted to CENTAVOS
  /// for the CF, matching the PIX contract; the CF derives & cross-checks).
  Future<CardPaymentResult> createStoreOrderCardPayment({
    required double amount,
    required String orderId,
    required String studentId,
    required String studentName,
    required CardData cardData,
    String? description,
    int installments = 1,
  }) {
    return _chargeCard(
      amount: (amount * 100).round(), // centavos (CF derives & cross-checks)
      idKey: 'orderId',
      idValue: orderId,
      studentId: studentId,
      studentName: studentName,
      cardData: cardData,
      description: description ?? 'Pedido da Loja',
      installments: installments,
    );
  }

  Future<CardPaymentResult> _chargeCard({
    required int amount,
    required String idKey,
    required String idValue,
    required String studentId,
    required String studentName,
    required CardData cardData,
    required String description,
    required int installments,
  }) async {
    try {
      final pk = await _publicKey();
      if (pk == null || pk.isEmpty) {
        return CardPaymentResult(
            success: false, message: 'Mercado Pago nao conectado.');
      }
      final token = await MpCardTokenizer.tokenize(
        publicKey: pk,
        cardNumber: cardData.cardNumber,
        expirationMonth: cardData.expirationMonth,
        expirationYear: cardData.expirationYear,
        securityCode: cardData.cvv,
        cardholderName: cardData.cardHolder,
        cpf: cardData.cpf,
      );
      final result = await _functions.httpsCallable('createMpCardPayment').call({
        'academyId': academyId,
        'amount': amount,
        'description': description,
        idKey: idValue,
        'studentId': studentId,
        'studentName': studentName,
        'cardToken': token.tokenId,
        'installments': installments,
        'payerCpf': cardData.cpf,
        'payerEmail': _payerEmail,
      });
      return CardPaymentResult.fromMap(Map<String, dynamic>.from(result.data));
    } on FirebaseFunctionsException catch (e) {
      return CardPaymentResult(
          success: false, message: e.message ?? 'Falha no pagamento.');
    } catch (e) {
      return CardPaymentResult(success: false, message: e.toString());
    }
  }

  /// Starts the OAuth connect flow; returns the MP authorization URL to open.
  Future<String?> startConnect() async {
    try {
      final result =
          await _functions.httpsCallable('startMercadoPagoConnect').call({
        'academyId': academyId,
      });
      return (result.data as Map?)?['url'] as String?;
    } catch (e) {
      print('[MercadoPago] startConnect exception: $e');
      return null;
    }
  }

  /// Disconnects the academy's Mercado Pago account.
  Future<bool> disconnect() async {
    try {
      await _functions.httpsCallable('disconnectMercadoPago').call({
        'academyId': academyId,
      });
      return true;
    } catch (e) {
      print('[MercadoPago] disconnect exception: $e');
      return false;
    }
  }
}
