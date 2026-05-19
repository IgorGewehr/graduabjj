import 'dto/financial_dto.dart';
import 'tatami_client.dart';

/// Repositório remoto para wallet da academia.
///
/// Endpoints:
///   GET /v1/academies/{id}/wallet
///   GET /v1/academies/{id}/wallet/transactions  (paginado por cursor)
///
/// O cliente nunca cria/altera wallet_transactions — o backend faz tudo
/// dentro da transação que muda o status do financial para `paid` (ou via
/// webhook do gateway). Vide doc 06 §Fase 4 sobre por que essa fase é a
/// mais sensível do plano.
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
  /// [amountInCents] é o valor em centavos.
  /// Retorna o id da transação gerada pelo backend.
  Future<Map<String, dynamic>> requestWithdrawal(
    String academyId, {
    required double amountInCents,
    required String pixKey,
    required String pixKeyType,
  }) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/academies/$academyId/wallet/withdrawals',
      data: {
        'amount': amountInCents.round(),
        'pix_key': pixKey,
        'pix_key_type': pixKeyType,
      },
    );
    return json;
  }
}
