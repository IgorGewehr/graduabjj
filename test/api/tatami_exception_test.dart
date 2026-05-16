import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/api/tatami_exception.dart';

void main() {
  group('TatamiException.fromResponse', () {
    test('parses a full problem+json payload', () {
      final e = TatamiException.fromResponse(404, {
        'type': 'https://tatami.dev/errors/not-found',
        'title': 'Not found',
        'status': 404,
        'detail': 'student 42 does not exist',
        'instance': '/v1/academies/abc/students/42',
        'trace_id': 'trace-abc-123',
      });

      expect(e.status, 404);
      expect(e.type, 'https://tatami.dev/errors/not-found');
      expect(e.title, 'Not found');
      expect(e.detail, 'student 42 does not exist');
      expect(e.instance, '/v1/academies/abc/students/42');
      expect(e.traceId, 'trace-abc-123');
      expect(e.isNotFound, isTrue);
      expect(e.isUnauthorized, isFalse);
    });

    test('parses validation errors (422 + errors array)', () {
      final e = TatamiException.fromResponse(422, {
        'type': 'https://tatami.dev/errors/validation',
        'title': 'Validation failed',
        'status': 422,
        'errors': [
          {'field': 'name', 'message': 'must not be empty', 'code': 'required'},
          {'field': 'birth_date', 'message': 'invalid format'},
        ],
      });

      expect(e.isValidation, isTrue);
      expect(e.errors, hasLength(2));
      expect(e.errors.first.field, 'name');
      expect(e.errors.first.message, 'must not be empty');
      expect(e.errors.first.code, 'required');
      expect(e.errors.last.code, isNull);
    });

    test('falls back gracefully when body is not a map', () {
      final e = TatamiException.fromResponse(500, 'internal server error');
      expect(e.status, 500);
      expect(e.type, 'https://tatami.dev/errors/unknown');
      expect(e.title, 'Unexpected error');
      expect(e.detail, 'internal server error');
      expect(e.isServerError, isTrue);
    });

    test('falls back when body is null', () {
      final e = TatamiException.fromResponse(503, null);
      expect(e.status, 503);
      expect(e.title, 'Unexpected error');
      expect(e.detail, isNull);
    });

    test('uses HTTP status when payload omits "status"', () {
      final e = TatamiException.fromResponse(403, {
        'type': 'https://tatami.dev/errors/forbidden',
        'title': 'Forbidden',
      });
      expect(e.status, 403);
      expect(e.isForbidden, isTrue);
    });

    test('classifier helpers cover the main HTTP codes', () {
      Map<String, dynamic> empty() => <String, dynamic>{};
      expect(TatamiException.fromResponse(401, empty()).isUnauthorized, isTrue);
      expect(TatamiException.fromResponse(403, empty()).isForbidden, isTrue);
      expect(TatamiException.fromResponse(404, empty()).isNotFound, isTrue);
      expect(TatamiException.fromResponse(409, empty()).isConflict, isTrue);
      expect(TatamiException.fromResponse(422, empty()).isValidation, isTrue);
      expect(TatamiException.fromResponse(429, empty()).isRateLimited, isTrue);
      expect(TatamiException.fromResponse(500, empty()).isServerError, isTrue);
      expect(TatamiException.fromResponse(502, empty()).isServerError, isTrue);
    });
  });

  group('TatamiException.forUser', () {
    test('returns network message when status is 0', () {
      final e = TatamiException.fromResponse(0, null);
      expect(e.forUser(), 'Sem conexão. Verifique sua internet.');
    });

    test('returns session expired on 401', () {
      final e = TatamiException.fromResponse(401, <String, dynamic>{});
      expect(e.forUser(), 'Sua sessão expirou. Faça login novamente.');
    });

    test('returns first field message on validation error', () {
      final e = TatamiException.fromResponse(422, {
        'errors': [
          {'field': 'email', 'message': 'E-mail inválido'},
        ],
      });
      expect(e.forUser(), 'E-mail inválido');
    });

    test('falls back when validation has no field errors', () {
      final e = TatamiException.fromResponse(422, <String, dynamic>{});
      expect(e.forUser(), 'Algo deu errado. Tente novamente.');
    });

    test('toString includes trace id when present', () {
      final e = TatamiException.fromResponse(500, {
        'title': 'Boom',
        'trace_id': 'abc-123',
      });
      expect(e.toString(), contains('abc-123'));
    });
  });
}
