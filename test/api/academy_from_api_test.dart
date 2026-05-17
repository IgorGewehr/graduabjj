import 'package:flutter_test/flutter_test.dart';

import 'package:graduabjj/api/dto/academy_dto.dart';
import 'package:graduabjj/models/academy.dart';

void main() {
  ApiAcademy mk({
    String id = 'aid',
    String name = 'Academia Alpha',
    String slug = 'alpha',
    String ownerUid = 'uid-owner',
    String status = 'active',
    String? cnpj,
    String? email,
    String? pixKeyType,
    Map<String, dynamic>? address,
    bool autoGrad = false,
    int? autoGradAttendances,
    bool storeEnabled = false,
    String? subscriptionPlan,
    String? subscriptionExpiresAt,
  }) =>
      ApiAcademy.fromJson({
        'id': id,
        'name': name,
        'slug': slug,
        'owner_uid': ownerUid,
        'subscription_status': status,
        'created_at': '2025-01-01T10:00:00Z',
        'updated_at': '2026-05-01T08:00:00Z',
        if (cnpj != null) 'cnpj': cnpj,
        if (email != null) 'email': email,
        if (pixKeyType != null) 'pix_key_type': pixKeyType,
        if (address != null) 'address': address,
        'auto_graduation_enabled': autoGrad,
        if (autoGradAttendances != null)
          'auto_graduation_attendances': autoGradAttendances,
        'store_enabled': storeEnabled,
        if (subscriptionPlan != null) 'subscription_plan': subscriptionPlan,
        if (subscriptionExpiresAt != null)
          'subscription_expires_at': subscriptionExpiresAt,
      });

  group('Academy.fromApi', () {
    test('mapeamento dos campos principais', () {
      final a = Academy.fromApi(mk(
        cnpj: '12.345.678/0001-99',
        email: 'admin@alpha.com',
      ));
      expect(a.id, 'aid');
      expect(a.name, 'Academia Alpha');
      expect(a.slug, 'alpha');
      expect(a.ownerId, 'uid-owner');
      expect(a.cnpj, '12.345.678/0001-99');
      expect(a.email, 'admin@alpha.com');
      expect(a.createdAt, DateTime.parse('2025-01-01T10:00:00Z'));
    });

    test('campos opcionais null materializam null no legacy', () {
      final a = Academy.fromApi(mk());
      expect(a.cnpj, isNull);
      expect(a.email, isNull);
      expect(a.phone, isNull);
      expect(a.pixKey, isNull);
      expect(a.pixKeyType, isNull);
      expect(a.address, isNull);
      expect(a.city, isNull);
      expect(a.state, isNull);
      expect(a.zipCode, isNull);
      // Branding NÃO existe no contrato Tatami — sempre null.
      expect(a.logoUrl, isNull);
      expect(a.portalSlogan, isNull);
      expect(a.sidebarLogoUrl, isNull);
      expect(a.adminBackgroundUrl, isNull);
    });

    test('endereço estruturado → string única + city/state/zip separados', () {
      final a = Academy.fromApi(mk(address: {
        'street': 'Rua A, 123',
        'city': 'São Paulo',
        'state': 'SP',
        'zip_code': '01000-000',
      }));
      expect(a.address, 'Rua A, 123, São Paulo/SP, 01000-000');
      expect(a.city, 'São Paulo');
      expect(a.state, 'SP');
      expect(a.zipCode, '01000-000');
    });

    test('endereço vazio (todos campos null) → null no legacy', () {
      final a = Academy.fromApi(mk(address: {}));
      expect(a.address, isNull);
      expect(a.city, isNull);
    });

    test('subscription_status canceled → cancelled (mapeamento de borda)', () {
      final a = Academy.fromApi(mk(status: 'canceled'));
      expect(a.subscription, isNotNull);
      expect(a.subscription!.status, SubscriptionStatus.cancelled);
    });

    test('subscription_status suspended → cancelled (degradação segura)', () {
      final a = Academy.fromApi(mk(status: 'suspended'));
      expect(a.subscription!.status, SubscriptionStatus.cancelled);
    });

    test('subscription_status trial → trialing', () {
      final a = Academy.fromApi(mk(status: 'trial'));
      expect(a.subscription!.status, SubscriptionStatus.trialing);
    });

    test('subscription_status past_due → pastDue', () {
      final a = Academy.fromApi(mk(status: 'past_due'));
      expect(a.subscription!.status, SubscriptionStatus.pastDue);
    });

    test('subscription_plan ausente vira plan.free', () {
      final a = Academy.fromApi(mk());
      expect(a.subscription!.plan, SubscriptionPlan.free);
    });

    test('subscription_plan premium é mapeado para o enum legacy', () {
      final a = Academy.fromApi(mk(subscriptionPlan: 'premium'));
      expect(a.subscription!.plan, SubscriptionPlan.premium);
    });

    test('pix_key_type CNPJ é mapeado', () {
      final a = Academy.fromApi(mk(pixKeyType: 'cnpj'));
      expect(a.pixKeyType, PixKeyType.cnpj);
    });

    test('auto_graduation: enabled + attendances copia limpo', () {
      final a =
          Academy.fromApi(mk(autoGrad: true, autoGradAttendances: 75));
      expect(a.autoGraduationEnabled, true);
      expect(a.autoGraduationAttendances, 75);
    });

    test('booleans default false quando ausentes', () {
      final a = Academy.fromApi(mk());
      expect(a.abacatePayEnabled, false);
      expect(a.asaasEnabled, false);
      expect(a.autoGraduationEnabled, false);
      expect(a.storeEnabled, false);
      expect(a.storePublished, false);
      expect(a.studentCheckinEnabled, false);
    });

    test('expires_at em ISO8601 é parseado corretamente', () {
      final a = Academy.fromApi(
          mk(subscriptionExpiresAt: '2027-12-31T23:59:59Z'));
      expect(
        a.subscription!.expiresAt,
        DateTime.parse('2027-12-31T23:59:59Z'),
      );
    });
  });
}
