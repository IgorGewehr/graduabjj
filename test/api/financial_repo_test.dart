import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import 'package:graduabjj/api/dto/financial_dto.dart';
import 'package:graduabjj/api/financial_repo.dart';
import 'package:graduabjj/api/idempotency.dart';
import 'package:graduabjj/api/tatami_client.dart';
import 'package:graduabjj/api/tatami_exception.dart';

import 'fakes/fake_firebase_auth.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late FinancialRemoteRepo repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test.tatami.dev'));
    adapter = DioAdapter(dio: dio);
    final client = TatamiClient(
      baseUrl: 'https://api.test.tatami.dev',
      dio: dio,
      auth: FakeFirebaseAuth.unauthenticated(),
    );
    repo = FinancialRemoteRepo(client);
  });

  Map<String, dynamic> financialJson({
    String id = 'f-1',
    String status = 'pending',
    String amount = '200.00',
  }) =>
      {
        'id': id,
        'academy_id': 'aid',
        'student_id': 's-1',
        'type': 'monthly_tuition',
        'amount': amount,
        'due_date': '2026-06-05',
        'status': status,
        'reference_month': '2026-06',
      };

  group('list + filters', () {
    test('passa filter completo como query params', () async {
      adapter.onGet(
        '/v1/academies/aid/financials',
        (s) => s.reply(200, {
          'items': [financialJson()],
          'next_cursor': 'cur',
          'has_more': true,
        }),
        queryParameters: {
          'limit': 25,
          'status': 'overdue',
          'student_id': 's-1',
          'type': 'monthly_tuition',
          'due_from': '2026-05-01',
          'due_to': '2026-05-31',
        },
      );

      final page = await repo.list(
        'aid',
        filter: FinancialFilter(
          status: ApiFinancialStatus.overdue,
          studentId: 's-1',
          type: ApiBillingType.monthly_tuition,
          dueFrom: DateTime(2026, 5, 1),
          dueTo: DateTime(2026, 5, 31),
          limit: 25,
        ),
      );
      expect(page.items, hasLength(1));
      expect(page.hasMore, isTrue);
    });
  });

  group('updateStatus (Marcar como pago)', () {
    test('PATCH status + method marca como pago sem creditar wallet', () async {
      adapter.onPatch(
        '/v1/academies/aid/financials/f-1/status',
        (s) => s.reply(200, financialJson(status: 'paid')),
        data: {
          'status': 'paid',
          'method': 'pix',
          'payment_date': '2026-05-16T10:00:00.000Z',
        },
      );

      final f = await repo.updateStatus(
        'aid',
        'f-1',
        UpdateFinancialStatusRequest(
          status: ApiFinancialStatus.paid,
          method: ApiPaymentMethod.pix,
          paymentDate: DateTime.utc(2026, 5, 16, 10, 0, 0),
        ),
      );
      expect(f.status, ApiFinancialStatus.paid);
      expect(f.isPaid, isTrue);
    });

    test('409 quando já pago (terminal)', () async {
      adapter.onPatch(
        '/v1/academies/aid/financials/f-1/status',
        (s) => s.reply(409, {
          'type': 'https://tatami.dev/errors/financial-already-paid',
          'title': 'Financial already paid',
          'status': 409,
        }),
        data: {'status': 'paid', 'method': 'pix'},
      );

      try {
        await repo.updateStatus(
          'aid',
          'f-1',
          const UpdateFinancialStatusRequest(
            status: ApiFinancialStatus.paid,
            method: ApiPaymentMethod.pix,
          ),
        );
        fail('expected 409');
      } on DioException catch (e) {
        expect((e.error as TatamiException).isConflict, isTrue);
      }
    });

    test('422 transição inválida (paid sem method)', () async {
      adapter.onPatch(
        '/v1/academies/aid/financials/f-1/status',
        (s) => s.reply(422, {
          'type': 'https://tatami.dev/errors/validation',
          'title': 'Validation',
          'status': 422,
          'errors': [
            {'field': 'method', 'message': 'required when status=paid'},
          ],
        }),
        data: {'status': 'paid'},
      );
      try {
        await repo.updateStatus(
          'aid',
          'f-1',
          const UpdateFinancialStatusRequest(status: ApiFinancialStatus.paid),
        );
        fail('expected 422');
      } on DioException catch (e) {
        final t = e.error as TatamiException;
        expect(t.isValidation, isTrue);
        expect(t.errors.first.field, 'method');
      }
    });
  });

  group('payWithPix', () {
    test('retorna copy-paste + QR base64', () async {
      adapter.onPost(
        '/v1/academies/aid/financials/f-1/pay/pix',
        (s) => s.reply(200, {
          'external_id': 'asaas-pay-123',
          'gateway': 'asaas',
          'receipt_url': 'https://asaas.com/r/123',
          'pix_copy_paste': '00020126...',
          'pix_qr_code': 'iVBORw0KGgo...',
        }),
        data: <String, dynamic>{},
      );
      final intent = await repo.payWithPix(
        'aid',
        'f-1',
        idempotencyKey: IdempotencyKey.fromString(
            'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
      );
      expect(intent.externalId, 'asaas-pay-123');
      expect(intent.gateway, ApiPaymentGateway.asaas);
      expect(intent.hasQrCode, isTrue);
    });
  });

  group('payWithCard', () {
    test('passa gateway abacatepay no body', () async {
      adapter.onPost(
        '/v1/academies/aid/financials/f-1/pay/card',
        (s) => s.reply(200, {
          'external_id': 'abacate-456',
          'gateway': 'abacatepay',
          'receipt_url': 'https://abacatepay.com/r/456',
        }),
        data: {'gateway': 'abacatepay'},
      );
      final intent = await repo.payWithCard(
        'aid',
        'f-1',
        body: const PayIntentRequest(gateway: ApiPaymentGateway.abacatepay),
        idempotencyKey: IdempotencyKey.fromString(
            'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
      );
      expect(intent.gateway, ApiPaymentGateway.abacatepay);
      expect(intent.hasQrCode, isFalse);
    });
  });

  group('generateMonthly', () {
    test('idempotente: 2 chamadas com mesmo reference_month → skipped_count', () async {
      adapter.onPost(
        '/v1/academies/aid/financials/generate-monthly',
        (s) => s.reply(200, {
          'generated_count': 0,
          'skipped_count': 50,
          'reference_month': '2026-06',
        }),
        data: {'reference_month': '2026-06'},
      );
      final r = await repo.generateMonthly(
        'aid',
        '2026-06',
        idempotencyKey: IdempotencyKey.fromString(
            'cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
      );
      expect(r.generatedCount, 0);
      expect(r.skippedCount, 50);
    });
  });

  group('getMonthlyReport', () {
    test('parses report sem query month', () async {
      adapter.onGet(
        '/v1/academies/aid/financials/reports/monthly',
        (s) => s.reply(200, {
          'month': '2026-05',
          'total_revenue': '5000.00',
          'outstanding': '1200.00',
          'overdue_count': 4,
          'paid_count': 30,
          'pending_count': 6,
          'cancelled_count': 1,
        }),
      );
      final r = await repo.getMonthlyReport('aid');
      expect(r.month, '2026-05');
      expect(r.totalRevenue, '5000.00');
      expect(r.paidCount, 30);
    });

    test('aceita month override', () async {
      adapter.onGet(
        '/v1/academies/aid/financials/reports/monthly',
        (s) => s.reply(200, {
          'month': '2026-04',
          'total_revenue': '4500.00',
          'outstanding': '0',
          'overdue_count': 0,
          'paid_count': 28,
          'pending_count': 0,
          'cancelled_count': 0,
        }),
        queryParameters: {'month': '2026-04'},
      );
      final r = await repo.getMonthlyReport('aid', month: '2026-04');
      expect(r.month, '2026-04');
    });
  });

  group('billing contacts (academy-wide)', () {
    test('list + filter por student_id', () async {
      adapter.onGet(
        '/v1/academies/aid/billing-contacts',
        (s) => s.reply(200, {
          'items': [
            {
              'id': 'bc-1',
              'academy_id': 'aid',
              'student_id': 's-1',
              'student_name_snapshot': 'João',
              'contact_date': '2026-05-15T10:00:00Z',
              'method': 'whatsapp',
              'result': 'promised_payment',
              'created_by_uid': 'admin-1',
            },
          ],
          'has_more': false,
        }),
        queryParameters: {'limit': 50, 'student_id': 's-1'},
      );
      final page = await repo.listBillingContacts('aid', studentId: 's-1');
      expect(page.items, hasLength(1));
      expect(page.items.first.method, ApiBillingContactMethod.whatsapp);
      expect(page.items.first.result, ApiBillingContactResult.promised_payment);
    });

    test('log POST', () async {
      adapter.onPost(
        '/v1/academies/aid/billing-contacts',
        (s) => s.reply(201, {
          'id': 'bc-new',
          'academy_id': 'aid',
          'student_id': 's-1',
          'student_name_snapshot': 'João',
          'contact_date': '2026-05-16T10:00:00Z',
          'method': 'whatsapp',
          'result': 'no_answer',
          'created_by_uid': 'admin-1',
          'notes': 'Sem resposta',
        }),
        data: {
          'student_id': 's-1',
          'method': 'whatsapp',
          'result': 'no_answer',
          'notes': 'Sem resposta',
        },
      );
      final bc = await repo.logBillingContact(
        'aid',
        const LogBillingContactRequest(
          studentId: 's-1',
          method: ApiBillingContactMethod.whatsapp,
          result: ApiBillingContactResult.no_answer,
          notes: 'Sem resposta',
        ),
      );
      expect(bc.id, 'bc-new');
    });
  });
}
