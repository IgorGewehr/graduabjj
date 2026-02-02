import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

/// TOTP Setup Result
class TotpSetupResult {
  final bool success;
  final String? secret;
  final String? qrCodeUri;
  final String? message;

  TotpSetupResult({
    required this.success,
    this.secret,
    this.qrCodeUri,
    this.message,
  });
}

/// TOTP Verify Result
class TotpVerifyResult {
  final bool success;
  final List<String>? backupCodes;
  final String? message;

  TotpVerifyResult({
    required this.success,
    this.backupCodes,
    this.message,
  });
}

/// TOTP Validate Result
class TotpValidateResult {
  final bool success;
  final String? message;

  TotpValidateResult({
    required this.success,
    this.message,
  });
}

/// TOTP Service
/// Handles 2FA TOTP operations via Next.js API routes (per-user, no academyId)
class TotpService {
  Future<String?> _getToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Check if TOTP is enabled for the current user (reads Firestore directly)
  Future<bool> isTotpEnabled() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) return false;
      return doc.data()?['totpEnabled'] == true;
    } catch (e) {
      print('[TOTP] isTotpEnabled error: $e');
      return false;
    }
  }

  /// Start TOTP setup - returns secret and QR code URI
  Future<TotpSetupResult> setupTotp() async {
    try {
      final token = await _getToken();
      if (token == null) {
        return TotpSetupResult(
          success: false,
          message: 'Usuario nao autenticado',
        );
      }

      final url = Uri.parse('${AppConstants.apiBaseUrl}/auth/totp/setup');
      final response = await http.post(url, headers: _headers(token));
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        final data = body['data'] as Map<String, dynamic>;
        return TotpSetupResult(
          success: true,
          secret: data['secret'] as String?,
          qrCodeUri: data['qrCodeUri'] as String?,
        );
      } else {
        return TotpSetupResult(
          success: false,
          message: body['error'] ?? 'Erro ao iniciar configuracao 2FA',
        );
      }
    } catch (e) {
      print('[TOTP] setupTotp exception: $e');
      return TotpSetupResult(
        success: false,
        message: 'Erro de conexao',
      );
    }
  }

  /// Verify TOTP setup with a code from the authenticator app
  Future<TotpVerifyResult> verifySetup(String code) async {
    try {
      final token = await _getToken();
      if (token == null) {
        return TotpVerifyResult(
          success: false,
          message: 'Usuario nao autenticado',
        );
      }

      final url =
          Uri.parse('${AppConstants.apiBaseUrl}/auth/totp/verify-setup');
      final response = await http.post(
        url,
        headers: _headers(token),
        body: jsonEncode({'code': code}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        final data = body['data'] as Map<String, dynamic>;
        final backupCodes = (data['backupCodes'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList();
        return TotpVerifyResult(
          success: true,
          backupCodes: backupCodes,
        );
      } else {
        return TotpVerifyResult(
          success: false,
          message: body['error'] ?? 'Codigo invalido',
        );
      }
    } catch (e) {
      print('[TOTP] verifySetup exception: $e');
      return TotpVerifyResult(
        success: false,
        message: 'Erro de conexao',
      );
    }
  }

  /// Validate a TOTP code (used before sensitive actions like withdrawals)
  Future<TotpValidateResult> validateCode(String code) async {
    try {
      final token = await _getToken();
      if (token == null) {
        return TotpValidateResult(
          success: false,
          message: 'Usuario nao autenticado',
        );
      }

      final url = Uri.parse('${AppConstants.apiBaseUrl}/auth/totp/validate');
      final response = await http.post(
        url,
        headers: _headers(token),
        body: jsonEncode({'code': code}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        return TotpValidateResult(success: true);
      } else {
        return TotpValidateResult(
          success: false,
          message: body['error'] ?? 'Codigo invalido',
        );
      }
    } catch (e) {
      print('[TOTP] validateCode exception: $e');
      return TotpValidateResult(
        success: false,
        message: 'Erro de conexao',
      );
    }
  }

  /// Disable TOTP for the current user (requires a valid code)
  Future<TotpValidateResult> disableTotp(String code) async {
    try {
      final token = await _getToken();
      if (token == null) {
        return TotpValidateResult(
          success: false,
          message: 'Usuario nao autenticado',
        );
      }

      final url = Uri.parse('${AppConstants.apiBaseUrl}/auth/totp/disable');
      final response = await http.post(
        url,
        headers: _headers(token),
        body: jsonEncode({'code': code}),
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        return TotpValidateResult(success: true);
      } else {
        return TotpValidateResult(
          success: false,
          message: body['error'] ?? 'Erro ao desativar 2FA',
        );
      }
    } catch (e) {
      print('[TOTP] disableTotp exception: $e');
      return TotpValidateResult(
        success: false,
        message: 'Erro de conexao',
      );
    }
  }
}
