import 'package:flutter_test/flutter_test.dart';

import 'package:graduabjj/api/dto/notification_dto.dart';
import 'package:graduabjj/services/notification_service.dart';

void main() {
  ApiNotification mk({
    String type = 'payment_due',
    String title = 'Cobrança pendente',
    String? readAt,
    Map<String, dynamic>? metadata,
    List<String> channels = const ['inbox', 'push'],
  }) =>
      ApiNotification.fromJson({
        'id': 'n-1',
        'academy_id': 'aid',
        'recipient_uid': 'u-1',
        'type': type,
        'title': title,
        'body': 'Detalhe da notif',
        'channels': channels,
        'created_at': '2026-05-15T08:00:00Z',
        if (readAt != null) 'read_at': readAt,
        if (metadata != null) 'metadata': metadata,
      });

  group('AppNotification.fromApi', () {
    test('payment_due → paymentPending', () {
      final n = AppNotification.fromApi(mk());
      expect(n.type, NotificationType.paymentPending);
    });

    test('payment_paid → paymentReceived', () {
      final n = AppNotification.fromApi(mk(type: 'payment_paid'));
      expect(n.type, NotificationType.paymentReceived);
    });

    test('payment_overdue → paymentOverdue', () {
      final n = AppNotification.fromApi(mk(type: 'payment_overdue'));
      expect(n.type, NotificationType.paymentOverdue);
    });

    test('graduation_eligible → graduationEligible', () {
      final n = AppNotification.fromApi(mk(type: 'graduation_eligible'));
      expect(n.type, NotificationType.graduationEligible);
    });

    test('graduation_promoted → studentMilestone', () {
      final n = AppNotification.fromApi(mk(type: 'graduation_promoted'));
      expect(n.type, NotificationType.studentMilestone);
    });

    test('competition_announcement → competitionReminder', () {
      final n = AppNotification.fromApi(mk(type: 'competition_announcement'));
      expect(n.type, NotificationType.competitionReminder);
    });

    test('store_order_update → orderPaid', () {
      final n = AppNotification.fromApi(mk(type: 'store_order_update'));
      expect(n.type, NotificationType.orderPaid);
    });

    test('generic → system', () {
      final n = AppNotification.fromApi(mk(type: 'generic'));
      expect(n.type, NotificationType.system);
    });

    test('read_at presente → read=true', () {
      final n = AppNotification.fromApi(
          mk(readAt: '2026-05-16T10:00:00Z'));
      expect(n.read, isTrue);
      expect(n.readAt, isNotNull);
    });

    test('metadata espalha studentId / financialId / competitionId', () {
      final n = AppNotification.fromApi(mk(metadata: {
        'student_id': 's-1',
        'financial_id': 'f-1',
        'competition_id': 'cp-1',
      }));
      expect(n.studentId, 's-1');
      expect(n.financialId, 'f-1');
      expect(n.competitionId, 'cp-1');
    });

    test('channels viram strings legacy', () {
      final n = AppNotification.fromApi(mk(channels: ['inbox', 'whatsapp']));
      expect(n.channels, ['inbox', 'whatsapp']);
    });

    test('priority sempre normal (Tatami não modela)', () {
      final n = AppNotification.fromApi(mk());
      expect(n.priority, NotificationPriority.normal);
    });
  });
}
