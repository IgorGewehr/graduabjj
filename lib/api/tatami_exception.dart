// Erro tipado para respostas application/problem+json (RFC 7807) do Tatami.
//
// Toda chamada do TatamiClient que falhar surgem como DioException cujo
// `.error` é uma instância desta classe — vide problem_interceptor.dart.

class FieldError {
  const FieldError({required this.field, required this.message, this.code});

  final String field;
  final String message;
  final String? code;

  factory FieldError.fromJson(Map<String, dynamic> j) => FieldError(
    field: j['field'] as String? ?? '',
    message: j['message'] as String? ?? '',
    code: j['code'] as String?,
  );
}

class TatamiException implements Exception {
  const TatamiException({
    required this.status,
    required this.type,
    required this.title,
    this.detail,
    this.instance,
    this.traceId,
    this.errors = const [],
    this.raw = const {},
  });

  final int status;
  final String type;
  final String title;
  final String? detail;
  final String? instance;
  final String? traceId;
  final List<FieldError> errors;
  final Map<String, dynamic> raw;

  /// Constrói a partir de um payload problem+json. Aceita corpo malformado
  /// (string, null, lista) caindo em uma exception genérica.
  factory TatamiException.fromResponse(int status, dynamic data) {
    if (data is! Map<String, dynamic>) {
      return TatamiException(
        status: status,
        type: 'https://tatami.dev/errors/unknown',
        title: 'Unexpected error',
        detail: data?.toString(),
      );
    }
    final errs = (data['errors'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(FieldError.fromJson)
            .toList() ??
        const <FieldError>[];
    return TatamiException(
      status: (data['status'] as num?)?.toInt() ?? status,
      type: data['type'] as String? ?? 'about:blank',
      title: data['title'] as String? ?? 'Error',
      detail: data['detail'] as String?,
      instance: data['instance'] as String?,
      traceId: data['trace_id'] as String?,
      errors: errs,
      raw: data,
    );
  }

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isNotFound => status == 404;
  bool get isValidation => status == 422;
  bool get isConflict => status == 409;
  bool get isRateLimited => status == 429;
  bool get isServerError => status >= 500;
  bool get isNetworkError => status == 0;

  /// Mensagem amigável em PT-BR para mostrar ao usuário final. Para erros
  /// de validação, retorna a primeira mensagem de campo quando existe.
  String forUser({String fallback = 'Algo deu errado. Tente novamente.'}) {
    if (isNetworkError) return 'Sem conexão. Verifique sua internet.';
    if (isUnauthorized) return 'Sua sessão expirou. Faça login novamente.';
    if (isForbidden) return 'Você não tem permissão para esta ação.';
    if (isNotFound) return 'Não encontramos o que você procurava.';
    if (isValidation) {
      if (errors.isNotEmpty) return errors.first.message;
      return fallback;
    }
    if (isConflict) return 'Esta operação já foi feita ou conflita com outra.';
    if (isRateLimited) return 'Muitas tentativas. Aguarde um momento.';
    if (isServerError) return 'Erro no servidor. Tente novamente em instantes.';
    if (detail != null && detail!.isNotEmpty) return detail!;
    if (title.isNotEmpty && title != 'Error') return title;
    return fallback;
  }

  @override
  String toString() =>
      'TatamiException($status $type: ${detail ?? title})${traceId == null ? '' : ' [trace=$traceId]'}';
}
