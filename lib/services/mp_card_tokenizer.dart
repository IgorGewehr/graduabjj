import 'dart:convert';
import 'package:http/http.dart' as http;

/// Result of a Mercado Pago card tokenization.
class MpCardToken {
  final String tokenId;
  final String? lastFourDigits;
  const MpCardToken({required this.tokenId, this.lastFourDigits});
}

/// Tokenization failure with a user-facing pt-BR [message] (mapped from the
/// Mercado Pago `cause` codes). `toString()` returns the bare message so even
/// generic `e.toString()` surfaces stay legible.
class MpCardTokenizationException implements Exception {
  final String message;
  const MpCardTokenizationException(this.message);

  @override
  String toString() => message;
}

/// Tokenizes a card directly with Mercado Pago using the academy's PUBLIC key.
///
/// PCI-compliant: the raw card data goes from the device straight to Mercado
/// Pago (`/v1/card_tokens`), never through our backend. We only ever handle the
/// resulting opaque token. Pure Dart over HTTP — no native SDK needed.
class MpCardTokenizer {
  static const _base = 'https://api.mercadopago.com/v1/card_tokens';

  /// [publicKey] is the connected academy's `mpPublicKey`.
  static Future<MpCardToken> tokenize({
    required String publicKey,
    required String cardNumber,
    required String expirationMonth,
    required String expirationYear,
    required String securityCode,
    required String cardholderName,
    required String cpf,
    String identificationType = 'CPF',
  }) async {
    final res = await http.post(
      Uri.parse('$_base?public_key=$publicKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'card_number': cardNumber.replaceAll(RegExp(r'\D'), ''),
        'expiration_month': expirationMonth,
        'expiration_year': expirationYear,
        'security_code': securityCode,
        'cardholder': {
          'name': cardholderName,
          'identification': {
            'type': identificationType,
            'number': cpf.replaceAll(RegExp(r'\D'), ''),
          },
        },
      }),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      // NEVER log res.body here: the request carries raw card data and the MP
      // error body may echo parts of it back.
      throw MpCardTokenizationException(
          _friendlyError(res.body, res.statusCode));
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tokenId = data['id'] as String?;
    if (tokenId == null || tokenId.isEmpty) {
      throw const MpCardTokenizationException(
          'Cartão inválido. Verifique os dados e tente novamente.');
    }
    return MpCardToken(
      tokenId: tokenId,
      lastFourDigits: data['last_four_digits'] as String?,
    );
  }

  /// Maps the MP error body (`cause: [{code, description}]`) to an actionable
  /// pt-BR message. Codes per the card_tokens API: E301 invalid card number,
  /// E302 invalid security code, 316 invalid cardholder name, 324 invalid
  /// identification number, 325/326 invalid expiration month/year. Falls back
  /// to a generic message; the body itself is never logged or surfaced.
  static String _friendlyError(String body, int statusCode) {
    const byCode = <String, String>{
      'E301': 'Número do cartão inválido.',
      'E302': 'CVV inválido.',
      '316': 'Nome no cartão inválido.',
      '324': 'CPF do titular inválido.',
      '325': 'Data de validade incorreta.',
      '326': 'Data de validade incorreta.',
    };
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final cause = decoded['cause'];
        if (cause is List) {
          for (final c in cause) {
            if (c is! Map) continue;
            final message = byCode[c['code']?.toString()];
            if (message != null) return message;
          }
        }
      }
    } catch (_) {
      // Unparseable body — fall through to the generic message.
    }
    return 'Não foi possível validar o cartão ($statusCode). '
        'Verifique os dados e tente novamente.';
  }
}
