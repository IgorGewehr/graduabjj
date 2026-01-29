import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
import 'firebase_service.dart';

/// Payment Link Response
class PaymentLink {
  final String pixCode;
  final String? qrCodeUrl;
  final DateTime expiresAt;

  PaymentLink({
    required this.pixCode,
    this.qrCodeUrl,
    required this.expiresAt,
  });

  factory PaymentLink.fromJson(Map<String, dynamic> json) {
    return PaymentLink(
      pixCode: json['pixCode'] ?? '',
      qrCodeUrl: json['qrCodeUrl'],
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'])
          : DateTime.now().add(const Duration(hours: 24)),
    );
  }
}

/// Card Payment Result
class CardPaymentResult {
  final bool success;
  final String? transactionId;
  final String? message;

  CardPaymentResult({
    required this.success,
    this.transactionId,
    this.message,
  });

  factory CardPaymentResult.fromJson(Map<String, dynamic> json) {
    return CardPaymentResult(
      success: json['success'] ?? false,
      transactionId: json['data']?['transactionId'],
      message: json['data']?['message'] ?? json['error'],
    );
  }
}

/// Card Data for Payment
class CardData {
  final String cardNumber;
  final String cardHolder;
  final String expirationMonth;
  final String expirationYear;
  final String cvv;
  final String cpf;

  CardData({
    required this.cardNumber,
    required this.cardHolder,
    required this.expirationMonth,
    required this.expirationYear,
    required this.cvv,
    required this.cpf,
  });

  Map<String, dynamic> toJson() {
    return {
      'cardNumber': cardNumber.replaceAll(' ', ''),
      'cardHolder': cardHolder,
      'expirationMonth': expirationMonth,
      'expirationYear': expirationYear,
      'cvv': cvv,
      'cpf': cpf.replaceAll(RegExp(r'\D'), ''),
    };
  }
}

/// AbacatePay Service
/// Handles payment operations via the web API
class AbacatePayService {
  final String academyId;

  // Base URL for the API - uses AppConstants which is configured via dart-define
  static String get _baseUrl => AppConstants.apiBaseUrl;

  AbacatePayService(this.academyId);

  /// Get authentication headers with Firebase ID token
  Future<Map<String, String>> _getAuthHeaders() async {
    final user = FirebaseService.currentUser;
    if (user == null) {
      return {'Content-Type': 'application/json'};
    }

    try {
      final token = await user.getIdToken();
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
    } catch (_) {
      return {'Content-Type': 'application/json'};
    }
  }

  /// Check if AbacatePay is enabled for the academy
  Future<bool> isEnabled() async {
    try {
      final academyDoc = await FirebaseFirestore.instance
          .collection('academies')
          .doc(academyId)
          .get();

      if (!academyDoc.exists) return false;
      return academyDoc.data()?['abacatePayEnabled'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Create PIX payment for a financial record
  Future<PaymentLink?> createPixPayment({
    required double amount,
    required String financialId,
    required String studentId,
    required String studentName,
    String? description,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/payments/create-pix'),
        headers: headers,
        body: jsonEncode({
          'academyId': academyId,
          'amount': (amount * 100).round(), // Convert to cents
          'description': description ?? 'Mensalidade',
          'financialId': financialId,
          'studentId': studentId,
          'studentName': studentName,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return PaymentLink.fromJson(data['data']);
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Create PIX payment for a store order
  /// Note: amount should be in centavos (store orders store total in centavos)
  Future<PaymentLink?> createStoreOrderPayment({
    required double amount,
    required String orderId,
    required String studentId,
    required String studentName,
    String? description,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/payments/create-order-pix'),
        headers: headers,
        body: jsonEncode({
          'academyId': academyId,
          'amount': amount.round(), // Already in centavos (store orders use centavos)
          'description': description ?? 'Pedido da Loja',
          'orderId': orderId,
          'studentId': studentId,
          'studentName': studentName,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          return PaymentLink.fromJson(data['data']);
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Create card payment for a financial record
  Future<CardPaymentResult> createCardPayment({
    required double amount,
    required String financialId,
    required String studentId,
    required String studentName,
    required CardData cardData,
    String? description,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/payments/create-card'),
        headers: headers,
        body: jsonEncode({
          'academyId': academyId,
          'amount': (amount * 100).round(), // Convert to cents
          'description': description ?? 'Pagamento',
          'financialId': financialId,
          'studentId': studentId,
          'studentName': studentName,
          ...cardData.toJson(),
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return CardPaymentResult.fromJson(data);
      }

      return CardPaymentResult(
        success: false,
        message: data['error'] ?? 'Erro ao processar pagamento',
      );
    } catch (_) {
      return CardPaymentResult(
        success: false,
        message: 'Erro de conexao',
      );
    }
  }

  /// Create card payment for a store order
  /// Note: amount should be in centavos (store orders store total in centavos)
  Future<CardPaymentResult> createStoreOrderCardPayment({
    required double amount,
    required String orderId,
    required String studentId,
    required String studentName,
    required CardData cardData,
    String? description,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/payments/create-card'),
        headers: headers,
        body: jsonEncode({
          'academyId': academyId,
          'amount': amount.round(), // Already in centavos (store orders use centavos)
          'description': description ?? 'Pedido da Loja',
          'financialId': 'order_$orderId',
          'studentId': studentId,
          'studentName': studentName,
          ...cardData.toJson(),
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return CardPaymentResult.fromJson(data);
      }

      return CardPaymentResult(
        success: false,
        message: data['error'] ?? 'Erro ao processar pagamento',
      );
    } catch (_) {
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
      final headers = await _getAuthHeaders();
      final response = await http.post(
        Uri.parse('$_baseUrl/payments/withdraw'),
        headers: headers,
        body: jsonEncode({
          'academyId': academyId,
          'amount': amountInCents.round(),
          'pixKey': pixKey,
          'pixKeyType': pixKeyType,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return WithdrawalResult.fromJson(data);
      }

      return WithdrawalResult(
        success: false,
        message: data['error'] ?? 'Erro ao solicitar saque',
      );
    } catch (_) {
      return WithdrawalResult(
        success: false,
        message: 'Erro de conexao',
      );
    }
  }
}

/// Withdrawal Result
class WithdrawalResult {
  final bool success;
  final String? transactionId;
  final String? message;

  WithdrawalResult({
    required this.success,
    this.transactionId,
    this.message,
  });

  factory WithdrawalResult.fromJson(Map<String, dynamic> json) {
    return WithdrawalResult(
      success: json['success'] ?? false,
      transactionId: json['data']?['transactionId'],
      message: json['data']?['message'] ?? json['error'],
    );
  }
}

/// Provider helper
AbacatePayService createAbacatePayService(String academyId) {
  return AbacatePayService(academyId);
}
