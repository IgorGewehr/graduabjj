import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'abacate_pay_service.dart' show PaymentLink;

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

  /// PIX for a tuition (financial) record. [amount] in REAIS (converted to
  /// centavos for the CF, matching the AbacatePay contract).
  Future<PaymentLink?> createPixPayment({
    required double amount,
    required String financialId,
    required String studentId,
    required String studentName,
    String? description,
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
      });
      return PaymentLink.fromMap(Map<String, dynamic>.from(result.data));
    } on FirebaseFunctionsException catch (e) {
      print('[MercadoPago] createPixPayment error: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      print('[MercadoPago] createPixPayment exception: $e');
      return null;
    }
  }

  /// PIX for a store order. [amount] in REAIS (CF uses it directly, matching
  /// the AbacatePay store contract).
  Future<PaymentLink?> createStoreOrderPayment({
    required double amount,
    required String orderId,
    required String studentId,
    required String studentName,
    String? description,
  }) async {
    try {
      final result =
          await _functions.httpsCallable('createMpOrderPixPayment').call({
        'academyId': academyId,
        'amount': amount.round(), // reais (CF uses directly)
        'description': description ?? 'Pedido da Loja',
        'orderId': orderId,
        'studentId': studentId,
        'studentName': studentName,
      });
      return PaymentLink.fromMap(Map<String, dynamic>.from(result.data));
    } on FirebaseFunctionsException catch (e) {
      print('[MercadoPago] createStoreOrderPayment error: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      print('[MercadoPago] createStoreOrderPayment exception: $e');
      return null;
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
