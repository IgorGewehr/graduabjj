import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import 'abacate_pay_service.dart';

/// Asaas Payment Service
/// Handles payment operations via Next.js API routes (Asaas sub-accounts).
/// Mirrors the AbacatePayService interface but calls HTTP API routes
/// instead of Firebase Cloud Functions.
class AsaasPaymentService {
  final String academyId;

  AsaasPaymentService(this.academyId);

  /// Get Firebase Auth token
  Future<String?> _getAuthToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  /// Check if Asaas is enabled for the academy
  Future<bool> isEnabled() async {
    try {
      final academyDoc = await FirebaseFirestore.instance
          .collection('academies')
          .doc(academyId)
          .get();

      if (!academyDoc.exists) return false;
      return academyDoc.data()?['asaasEnabled'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Create PIX payment for a financial record
  /// Amount is in centavos (the API route converts via toAsaasAmount)
  Future<PaymentLink?> createPixPayment({
    required double amount,
    required String financialId,
    required String studentId,
    required String studentName,
    String? description,
  }) async {
    try {
      final token = await _getAuthToken();
      if (token == null) return null;

      final url = Uri.parse('${AppConstants.apiBaseUrl}/payments/asaas/create-pix');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'academyId': academyId,
          'amount': (amount * 100).round(), // Convert to centavos
          'description': description ?? 'Mensalidade',
          'financialId': financialId,
          'studentId': studentId,
          'studentName': studentName,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['data'] != null) {
        final data = body['data'] as Map<String, dynamic>;
        return PaymentLink(
          pixCode: data['pixCode'] ?? '',
          qrCodeUrl: data['qrCodeUrl'],
          expiresAt: data['expiresAt'] != null
              ? DateTime.parse(data['expiresAt'])
              : DateTime.now().add(const Duration(hours: 24)),
        );
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Create PIX payment for a store order
  /// Amount is in Reais (the API route uses it directly)
  Future<PaymentLink?> createStoreOrderPayment({
    required double amount,
    required String orderId,
    required String studentId,
    required String studentName,
    String? description,
  }) async {
    try {
      final token = await _getAuthToken();
      if (token == null) return null;

      final url = Uri.parse('${AppConstants.apiBaseUrl}/store/asaas-generate-payment');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'academyId': academyId,
          'orderId': orderId,
          'method': 'PIX',
          'customerEmail': '',
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['paymentLink'] != null) {
        final data = body['paymentLink'] as Map<String, dynamic>;
        return PaymentLink(
          pixCode: data['pixCode'] ?? '',
          qrCodeUrl: data['qrCodeUrl'],
          expiresAt: data['expiresAt'] != null
              ? DateTime.parse(data['expiresAt'])
              : DateTime.now().add(const Duration(hours: 24)),
        );
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Create card payment for a financial record
  /// Amount is in centavos (the API route converts via toAsaasAmount)
  Future<CardPaymentResult> createCardPayment({
    required double amount,
    required String financialId,
    required String studentId,
    required String studentName,
    required CardData cardData,
    String? description,
  }) async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        return CardPaymentResult(
          success: false,
          message: 'Usuario nao autenticado',
        );
      }

      final url = Uri.parse('${AppConstants.apiBaseUrl}/payments/asaas/create-card');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'academyId': academyId,
          'amount': (amount * 100).round(), // Convert to centavos
          'description': description ?? 'Pagamento',
          'financialId': financialId,
          'studentId': studentId,
          'studentName': studentName,
          ...cardData.toJson(),
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        return CardPaymentResult(
          success: true,
          transactionId: body['data']?['transactionId'],
          message: body['data']?['message'] ?? 'Pagamento aprovado',
        );
      }

      return CardPaymentResult(
        success: false,
        message: body['error'] ?? 'Erro ao processar pagamento',
      );
    } catch (e) {
      return CardPaymentResult(
        success: false,
        message: 'Erro de conexao',
      );
    }
  }

  /// Create card payment for a store order
  /// Amount is in Reais (converted to centavos before sending to API)
  Future<CardPaymentResult> createStoreOrderCardPayment({
    required double amount,
    required String orderId,
    required String studentId,
    required String studentName,
    required CardData cardData,
    String? description,
  }) async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        return CardPaymentResult(
          success: false,
          message: 'Usuario nao autenticado',
        );
      }

      final url = Uri.parse('${AppConstants.apiBaseUrl}/payments/asaas/create-card');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'academyId': academyId,
          'amount': (amount * 100).round(), // Convert to centavos
          'description': description ?? 'Pedido da Loja',
          'financialId': 'order_$orderId',
          'studentId': studentId,
          'studentName': studentName,
          ...cardData.toJson(),
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        return CardPaymentResult(
          success: true,
          transactionId: body['data']?['transactionId'],
          message: body['data']?['message'] ?? 'Pagamento aprovado',
        );
      }

      return CardPaymentResult(
        success: false,
        message: body['error'] ?? 'Erro ao processar pagamento',
      );
    } catch (e) {
      return CardPaymentResult(
        success: false,
        message: 'Erro de conexao',
      );
    }
  }

  /// Request withdrawal to PIX key
  Future<WithdrawalResult> requestWithdrawal({
    required double amountInCents,
    required String pixKey,
    required String pixKeyType,
  }) async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        return WithdrawalResult(
          success: false,
          message: 'Usuario nao autenticado',
        );
      }

      final url = Uri.parse('${AppConstants.apiBaseUrl}/payments/asaas/withdraw');

      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'academyId': academyId,
          'amount': amountInCents.round(),
          'pixKey': pixKey,
          'pixKeyType': pixKeyType,
        }),
      );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        final data = body['data'] as Map<String, dynamic>?;
        return WithdrawalResult(
          success: true,
          transactionId: data?['transactionId'],
          message: data?['message'] ?? 'Saque solicitado com sucesso',
        );
      } else {
        return WithdrawalResult(
          success: false,
          message: body['error'] ?? 'Erro ao solicitar saque',
        );
      }
    } catch (e) {
      return WithdrawalResult(
        success: false,
        message: 'Erro de conexao',
      );
    }
  }
}

/// Provider helper
AsaasPaymentService createAsaasPaymentService(String academyId) {
  return AsaasPaymentService(academyId);
}
