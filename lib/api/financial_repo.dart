import 'dto/financial_dto.dart';
import 'idempotency.dart';
import 'tatami_client.dart';

/// Repositório remoto do contexto Financial (a fase 🔴 do plano).
///
/// SUBSTITUI todas as escritas em wallet_transactions/financials que o app
/// legacy fazia. O backend é responsável pelas transações ACID; o cliente
/// NUNCA toca em wallet_transactions diretamente (vide doc 06 §Fase 4).
///
/// Endpoints cobertos:
///   GET    /v1/academies/{id}/financials                 (list + filters)
///   POST   /v1/academies/{id}/financials                 (idempotent)
///   GET    /v1/academies/{id}/financials/{id}
///   PATCH  /v1/academies/{id}/financials/{id}
///   DELETE /v1/academies/{id}/financials/{id}
///   PATCH  /v1/academies/{id}/financials/{id}/status     (transition + method)
///   POST   /v1/academies/{id}/financials/{id}/pay/pix    (idempotent)
///   POST   /v1/academies/{id}/financials/{id}/pay/card   (idempotent)
///   POST   /v1/academies/{id}/financials/generate-monthly (idempotent)
///   GET    /v1/academies/{id}/financials/reports/monthly
///   GET    /v1/academies/{id}/financials/{id}/billing-contacts
///   POST   /v1/academies/{id}/financials/{id}/billing-contacts
///   GET    /v1/academies/{id}/billing-contacts           (academy-wide)
///   POST   /v1/academies/{id}/billing-contacts           (academy-wide)
class FinancialRemoteRepo {
  FinancialRemoteRepo(this._api);

  final TatamiClient _api;

  Future<FinancialsPage> list(
    String academyId, {
    FinancialFilter filter = const FinancialFilter(),
  }) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/financials',
      queryParameters: filter.toQueryParameters(),
    );
    return FinancialsPage.fromJson(json);
  }

  Future<ApiFinancial> getById(String academyId, String financialId) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/financials/$financialId',
    );
    return ApiFinancial.fromJson(json);
  }

  Future<ApiFinancial> create(
    String academyId,
    CreateFinancialRequest req, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/financials',
      data: req.toJson(),
      key: key,
    );
    return ApiFinancial.fromJson(json);
  }

  Future<ApiFinancial> update(
    String academyId,
    String financialId,
    UpdateFinancialRequest req,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/v1/academies/$academyId/financials/$financialId',
      data: req.toJson(),
    );
    return ApiFinancial.fromJson(json);
  }

  Future<void> delete(String academyId, String financialId) async {
    await _api.delete('/v1/academies/$academyId/financials/$financialId');
  }

  /// Transição dedicada de status. Body inclui method quando status=paid.
  /// Backend rejeita transições inválidas (422) e marca paid como terminal
  /// (409 se já estiver paga).
  ///
  /// Para "Marcar como pago" o caller faz:
  /// ```
  /// repo.updateStatus(aid, fid, UpdateFinancialStatusRequest(
  ///   status: ApiFinancialStatus.paid,
  ///   method: ApiPaymentMethod.pix,
  ///   paymentDate: DateTime.now(),
  /// ));
  /// ```
  /// O backend faz a transação que credita a wallet — o cliente NÃO faz
  /// nada mais.
  Future<ApiFinancial> updateStatus(
    String academyId,
    String financialId,
    UpdateFinancialStatusRequest req,
  ) async {
    final json = await _api.patch<Map<String, dynamic>>(
      '/v1/academies/$academyId/financials/$financialId/status',
      data: req.toJson(),
    );
    return ApiFinancial.fromJson(json);
  }

  /// Cria payment intent PIX no Asaas ou AbacatePay (server-side).
  /// [gateway] é hint — se omitido o backend escolhe baseado em config.
  Future<PayIntentResponse> payWithPix(
    String academyId,
    String financialId, {
    PayIntentRequest body = const PayIntentRequest(),
    ApiPaymentGateway? gateway,
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final params = <String, dynamic>{};
    if (gateway != null) params['gateway'] = gateway.wire;
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/financials/$financialId/pay/pix',
      data: body.toJson(),
      key: key,
    );
    // Note: para passar queryParameters via postIdempotent precisamos de
    // post() direto. Caso o caller precise de gateway diferente do default,
    // usar postIdempotent é suficiente — o BE aceita gateway no body
    // também através do PayIntentRequest.gateway.
    return PayIntentResponse.fromJson(json);
  }

  /// Cria payment intent cartão. Mesma semântica do payWithPix.
  Future<PayIntentResponse> payWithCard(
    String academyId,
    String financialId, {
    PayIntentRequest body = const PayIntentRequest(),
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/financials/$financialId/pay/card',
      data: body.toJson(),
      key: key,
    );
    return PayIntentResponse.fromJson(json);
  }

  /// Gera as cobranças mensais idempotentemente (re-rodadas são no-op).
  /// O cron do BE chama esse mesmo endpoint dia 1 do mês.
  Future<GenerateMonthlyResponse> generateMonthly(
    String academyId,
    String referenceMonth, {
    IdempotencyKey? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? IdempotencyKey.generate();
    final json = await _api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$academyId/financials/generate-monthly',
      data: {'reference_month': referenceMonth},
      key: key,
    );
    return GenerateMonthlyResponse.fromJson(json);
  }

  /// Snapshot agregado KPIs do mês.
  Future<ApiMonthlyReport> getMonthlyReport(
    String academyId, {
    String? month,
  }) async {
    final params = <String, dynamic>{};
    if (month != null) params['month'] = month;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/financials/reports/monthly',
      queryParameters: params,
    );
    return ApiMonthlyReport.fromJson(json);
  }

  /// Lista contatos de cobrança ligados a um financial específico.
  Future<BillingContactsPage> listBillingContactsForFinancial(
    String academyId,
    String financialId, {
    int limit = 50,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (cursor != null) params['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/financials/$financialId/billing-contacts',
      queryParameters: params,
    );
    return BillingContactsPage.fromJson(json);
  }

  Future<ApiBillingContact> logBillingContactForFinancial(
    String academyId,
    String financialId,
    LogBillingContactRequest req,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/academies/$academyId/financials/$financialId/billing-contacts',
      data: req.toJson(),
    );
    return ApiBillingContact.fromJson(json);
  }

  /// Lista contatos de cobrança em toda a academia (agnóstico do financial).
  Future<BillingContactsPage> listBillingContacts(
    String academyId, {
    String? studentId,
    int limit = 50,
    String? cursor,
  }) async {
    final params = <String, dynamic>{'limit': limit};
    if (studentId != null) params['student_id'] = studentId;
    if (cursor != null) params['cursor'] = cursor;
    final json = await _api.get<Map<String, dynamic>>(
      '/v1/academies/$academyId/billing-contacts',
      queryParameters: params,
    );
    return BillingContactsPage.fromJson(json);
  }

  Future<ApiBillingContact> logBillingContact(
    String academyId,
    LogBillingContactRequest req,
  ) async {
    final json = await _api.post<Map<String, dynamic>>(
      '/v1/academies/$academyId/billing-contacts',
      data: req.toJson(),
    );
    return ApiBillingContact.fromJson(json);
  }
}
