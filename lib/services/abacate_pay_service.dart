import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

/// Payment Link Response
class PaymentLink {
  final String pixCode;
  final String? qrCodeUrl;
  final DateTime expiresAt;
  final String? abacatePayId;

  PaymentLink({
    required this.pixCode,
    this.qrCodeUrl,
    required this.expiresAt,
    this.abacatePayId,
  });

  factory PaymentLink.fromMap(Map<String, dynamic> map) {
    return PaymentLink(
      pixCode: map['pixCode'] ?? '',
      qrCodeUrl: map['qrCodeUrl'],
      expiresAt: map['expiresAt'] != null
          ? DateTime.parse(map['expiresAt'])
          : DateTime.now().add(const Duration(hours: 24)),
      abacatePayId: map['abacatePayId'],
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

  factory CardPaymentResult.fromMap(Map<String, dynamic> map) {
    return CardPaymentResult(
      success: map['success'] ?? false,
      transactionId: map['transactionId'],
      message: map['message'],
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

  factory WithdrawalResult.fromMap(Map<String, dynamic> map) {
    return WithdrawalResult(
      success: map['success'] ?? false,
      transactionId: map['transactionId'],
      message: map['message'],
    );
  }
}

/// AbacatePay Service
/// Handles payment operations via Firebase Cloud Functions
class AbacatePayService {
  final String academyId;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  AbacatePayService(this.academyId);

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
      final callable = _functions.httpsCallable('createPixPayment');
      final result = await callable.call({
        'academyId': academyId,
        'amount': amount, // Send in reais — API handles centavo conversion
        'description': description ?? 'Mensalidade',
        'financialId': financialId,
        'studentId': studentId,
        'studentName': studentName,
      });

      final data = Map<String, dynamic>.from(result.data);
      return PaymentLink.fromMap(data);
    } on FirebaseFunctionsException catch (e) {
      print('[AbacatePay] createPixPayment error: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      print('[AbacatePay] createPixPayment exception: $e');
      return null;
    }
  }

  /// Create PIX payment for a store order
  /// Note: amount is in Reais (must match Firestore order total); Cloud Function converts to cents
  Future<PaymentLink?> createStoreOrderPayment({
    required double amount,
    required String orderId,
    required String studentId,
    required String studentName,
    String? description,
  }) async {
    try {
      final callable = _functions.httpsCallable('createOrderPixPayment');
      final result = await callable.call({
        'academyId': academyId,
        'amount': amount.round(), // In Reais - CF validates against order total and converts to cents
        'description': description ?? 'Pedido da Loja',
        'orderId': orderId,
        'studentId': studentId,
        'studentName': studentName,
      });

      final data = Map<String, dynamic>.from(result.data);
      return PaymentLink.fromMap(data);
    } on FirebaseFunctionsException catch (e) {
      print('[AbacatePay] createStoreOrderPayment error: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      print('[AbacatePay] createStoreOrderPayment exception: $e');
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
      final callable = _functions.httpsCallable('createCardPayment');
      final result = await callable.call({
        'academyId': academyId,
        'amount': amount, // Send in reais — API handles centavo conversion
        'description': description ?? 'Pagamento',
        'financialId': financialId,
        'studentId': studentId,
        'studentName': studentName,
        ...cardData.toJson(),
      });

      final data = Map<String, dynamic>.from(result.data);
      return CardPaymentResult.fromMap(data);
    } on FirebaseFunctionsException catch (e) {
      return CardPaymentResult(
        success: false,
        message: e.message ?? 'Erro ao processar pagamento',
      );
    } catch (_) {
      return CardPaymentResult(
        success: false,
        message: 'Erro de conexao',
      );
    }
  }

  /// Create card payment for a store order
  /// Note: amount is in Reais (must match Firestore order total); Cloud Function converts to cents
  Future<CardPaymentResult> createStoreOrderCardPayment({
    required double amount,
    required String orderId,
    required String studentId,
    required String studentName,
    required CardData cardData,
    String? description,
  }) async {
    try {
      final callable = _functions.httpsCallable('createCardPayment');
      final result = await callable.call({
        'academyId': academyId,
        'amount': amount.round(), // In Reais - CF validates against order total and converts to cents
        'description': description ?? 'Pedido da Loja',
        'financialId': 'order_$orderId',
        'studentId': studentId,
        'studentName': studentName,
        ...cardData.toJson(),
      });

      final data = Map<String, dynamic>.from(result.data);
      return CardPaymentResult.fromMap(data);
    } on FirebaseFunctionsException catch (e) {
      return CardPaymentResult(
        success: false,
        message: e.message ?? 'Erro ao processar pagamento',
      );
    } catch (_) {
      return CardPaymentResult(
        success: false,
        message: 'Erro de conexao',
      );
    }
  }

  /// Check PIX payment status via polling
  Future<String> checkPaymentStatus(String abacatePayId) async {
    try {
      final callable = _functions.httpsCallable('checkPixStatus');
      final result = await callable.call({
        'abacatePayId': abacatePayId,
      });

      final data = Map<String, dynamic>.from(result.data);
      return data['status'] as String? ?? 'PENDING';
    } on FirebaseFunctionsException catch (e) {
      print('[AbacatePay] checkPaymentStatus error: ${e.code} - ${e.message}');
      return 'PENDING';
    } catch (e) {
      print('[AbacatePay] checkPaymentStatus exception: $e');
      return 'PENDING';
    }
  }

  /// Request withdrawal to PIX key
  /// Calls the Next.js API route directly via HTTP
  Future<WithdrawalResult> requestWithdrawal({
    required double amountInCents,
    required String pixKey,
    required String pixKeyType,
  }) async {
    try {
      // Get Firebase Auth token for authentication
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return WithdrawalResult(
          success: false,
          message: 'Usuario nao autenticado',
        );
      }

      final token = await user.getIdToken();
      if (token == null) {
        return WithdrawalResult(
          success: false,
          message: 'Erro de autenticacao',
        );
      }

      final url = Uri.parse('${AppConstants.apiBaseUrl}/payments/withdraw');

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
      print('[AbacatePay] requestWithdrawal exception: $e');
      return WithdrawalResult(
        success: false,
        message: 'Erro de conexao',
      );
    }
  }
}

/// Provider helper
AbacatePayService createAbacatePayService(String academyId) {
  return AbacatePayService(academyId);
}
