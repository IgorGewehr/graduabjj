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
  final String? ticketUrl;

  PaymentLink({
    required this.pixCode,
    this.qrCodeUrl,
    required this.expiresAt,
    this.abacatePayId,
    this.ticketUrl,
  });

  factory PaymentLink.fromMap(Map<String, dynamic> map) {
    return PaymentLink(
      pixCode: map['pixCode'] ?? '',
      qrCodeUrl: map['qrCodeUrl'],
      expiresAt: map['expiresAt'] != null
          ? DateTime.parse(map['expiresAt'])
          : DateTime.now().add(const Duration(hours: 24)),
      abacatePayId: map['abacatePayId'],
      ticketUrl: map['ticketUrl'],
    );
  }
}

/// Card Payment Result
class CardPaymentResult {
  final bool success;
  final String? transactionId;
  final String? message;

  // Auditoria MP: a CF createMpCardPayment retorna status/statusDetail/threeDsUrl
  // (server_functions.js:4211-4218). Antes eram descartados aqui, então o
  // desafio 3DS nunca era aberto e um pagamento 'in_process'/'pending' aparecia
  // como recusado, levando o aluno a um retry que duplica a cobrança pendente.
  /// Status bruto do MP: 'approved', 'in_process', 'pending', 'rejected', etc.
  final String? status;

  /// Detalhe do status do MP (status_detail), ex.: 'pending_challenge'.
  final String? statusDetail;

  /// URL do desafio 3DS (three_ds_info.external_resource_url) quando o emissor
  /// exige autenticação; a UI deve abrir esta URL em vez de exibir erro.
  final String? threeDsUrl;

  CardPaymentResult({
    required this.success,
    this.transactionId,
    this.message,
    this.status,
    this.statusDetail,
    this.threeDsUrl,
  });

  /// true quando o MP ainda não confirmou (in_process/pending): NÃO é recusa.
  /// A UI deve mostrar 'aguardando confirmação' e bloquear novo submit para a
  /// mesma cobrança, evitando cobrança pendente duplicada (auditoria MP).
  bool get isPending => status == 'in_process' || status == 'pending';

  /// true quando há um desafio 3DS a ser concluído pelo aluno.
  bool get requiresThreeDs => threeDsUrl != null && threeDsUrl!.isNotEmpty;

  factory CardPaymentResult.fromMap(Map<String, dynamic> map) {
    final threeDs = map['threeDsUrl'] as String?;
    return CardPaymentResult(
      success: map['success'] ?? false,
      transactionId: map['transactionId'],
      message: map['message'],
      status: map['status'] as String?,
      statusDetail: map['statusDetail'] as String?,
      threeDsUrl: (threeDs != null && threeDs.isNotEmpty) ? threeDs : null,
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
        'amount': (amount * 100).round(), // Convert to centavos — Cloud Function passes directly to AbacatePay
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
        'amount': (amount * 100).round(), // Convert to centavos — Cloud Function passes directly to AbacatePay
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
