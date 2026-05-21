import 'dto/financial_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Repositório remoto para wallet da academia.
///
/// Endpoints:
///   GET /v1/academies/{id}/wallet
///   GET /v1/academies/{id}/wallet/transactions  (paginado por cursor)
///
/// O cliente nunca cria/altera wallet_transactions — o backend faz tudo
/// somente a partir do webhook confirmado da AbacatePay, já com a taxa do
/// gateway descontada. Marcar um financeiro como `paid` manualmente não
/// credita a carteira.
class WalletRemoteRepo {
  WalletRemoteRepo(this._api);

  final TatamiClient _api;

  Future<ApiWallet> get(String academyId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/wallet',
    );
    return ApiWallet.fromJson(json);
  }

  /// Lista transações da wallet (créditos por pagamento + débitos por payout
  /// + refunds) com filtros opcionais.
  Future<WalletTransactionsPage> listTransactions(
    String academyId, {
    ApiWalletTxnKind? kind,
    int limit = 50,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (kind != null) params['kind'] = kind.wire;
    if (cursor != null) params['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/wallet/transactions',
      queryParameters: params,
    );
    return WalletTransactionsPage.fromJson(json);
  }

  /// Solicita saque da wallet da academia.
  /// [amountBRL] é o valor em reais (ex: 150.00).
  /// Backend exige Idempotency-Key (enviado via postIdempotent) e
  /// campo `destination_pix_key` (não `pix_key`). Amount deve ser string decimal.
  Future<Map<String, dynamic>> requestWithdrawal(
    String academyId, {
    required double amountBRL,
    required String pixKey,
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/wallet/withdrawals',
      data: {
        'amount': amountBRL.toStringAsFixed(2),
        'destination_pix_key': pixKey,
      },
      key: key,
    );
    return json;
  }
}
