import 'dart:convert';
import 'package:http/http.dart' as http;

/// Result of a Mercado Pago card tokenization.
class MpCardToken {
  final String tokenId;
  final String? lastFourDigits;
  const MpCardToken({required this.tokenId, this.lastFourDigits});
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
      throw Exception('Falha ao validar o cartao (${res.statusCode}).');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final tokenId = data['id'] as String?;
    if (tokenId == null || tokenId.isEmpty) {
      throw Exception('Cartao invalido.');
    }
    return MpCardToken(
      tokenId: tokenId,
      lastFourDigits: data['last_four_digits'] as String?,
    );
  }
}
