import 'package:flutter_test/flutter_test.dart';

import 'package:graduabjj/api/dto/competition_dto.dart';
import 'package:graduabjj/api/dto/store_dto.dart';
import 'package:graduabjj/services/competition_service.dart';
import 'package:graduabjj/services/store_service.dart';

void main() {
  group('StoreProduct.fromApi', () {
    test('stockQty=10 → inStock', () {
      final p = StoreProduct.fromApi(ApiProduct.fromJson({
        'id': 'p1',
        'academy_id': 'aid',
        'name': 'Kimono',
        'price': '450.00',
        'stock_quantity': 10,
        'is_active': true,
        'images': ['https://e.com/k.jpg'],
        'category': 'uniform',
      }));
      expect(p.price, 450.0);
      expect(p.stockType, StoreStockType.inStock);
      expect(p.stockQuantity, 10);
      expect(p.category, StoreProductCategory.uniform);
      expect(p.imageUrls, ['https://e.com/k.jpg']);
    });

    test('stockQty=0 → onDemand (conservador)', () {
      final p = StoreProduct.fromApi(ApiProduct.fromJson({
        'id': 'p1',
        'academy_id': 'aid',
        'name': 'Sob encomenda',
        'price': '99.00',
        'stock_quantity': 0,
        'is_active': true,
      }));
      expect(p.stockType, StoreStockType.onDemand);
      expect(p.stockQuantity, 0);
    });

    test('category null → other', () {
      final p = StoreProduct.fromApi(ApiProduct.fromJson({
        'id': 'p1',
        'academy_id': 'aid',
        'name': 'X',
        'price': '10.00',
        'stock_quantity': 1,
        'is_active': true,
      }));
      expect(p.category, StoreProductCategory.other);
    });
  });

  group('StoreOrder.fromApi', () {
    Map<String, dynamic> orderJson({String status = 'paid'}) => {
          'id': 'o-1',
          'academy_id': 'aid',
          'student_id': 's-1',
          'items': [
            {
              'product_id': 'p-1',
              'quantity': 2,
              'unit_price': '50.00',
              'name': 'Item A',
            },
          ],
          'total': '100.00',
          'status': status,
          'created_at': '2026-05-16T10:00:00Z',
        };

    test('paid status mapeia + items', () {
      final o = StoreOrder.fromApi(ApiOrder.fromJson(orderJson()));
      expect(o.total, 100.0);
      expect(o.status, StoreOrderStatus.paid);
      expect(o.isPaid, isTrue);
      expect(o.items, hasLength(1));
      expect(o.items.first.productName, 'Item A');
      expect(o.items.first.quantity, 2);
    });

    test('pending_payment status mapeia', () {
      final o = StoreOrder.fromApi(
          ApiOrder.fromJson(orderJson(status: 'pending_payment')));
      expect(o.status, StoreOrderStatus.pendingPayment);
      expect(o.isPending, isTrue);
    });

    test('cancelled status mapeia', () {
      final o = StoreOrder.fromApi(
          ApiOrder.fromJson(orderJson(status: 'cancelled')));
      expect(o.status, StoreOrderStatus.cancelled);
    });

    test('studentName override', () {
      final o = StoreOrder.fromApi(
        ApiOrder.fromJson(orderJson()),
        studentName: 'Igor',
      );
      expect(o.studentName, 'Igor');
    });
  });

  group('Competition.fromApi', () {
    Map<String, dynamic> compJson({
      String status = 'upcoming',
      int? teamPosition,
    }) =>
        {
          'id': 'cp-1',
          'academy_id': 'aid',
          'name': 'Open SP',
          'date': '2026-06-15T08:00:00Z',
          'status': status,
          'transport_capacity': 20,
          'team_notes': 'Notas do time',
          if (teamPosition != null) 'team_position': teamPosition,
        };

    test('mapeia campos + status', () {
      final c = Competition.fromApi(ApiCompetition.fromJson(compJson()));
      expect(c.id, 'cp-1');
      expect(c.name, 'Open SP');
      expect(c.status, CompetitionStatus.upcoming);
      expect(c.transportCapacity, 20);
      expect(c.teamNotes, 'Notas do time');
    });

    test('completed status', () {
      final c = Competition.fromApi(
          ApiCompetition.fromJson(compJson(status: 'completed')));
      expect(c.status, CompetitionStatus.completed);
    });

    test('teamPosition int → string medal', () {
      expect(
        Competition.fromApi(ApiCompetition.fromJson(compJson(teamPosition: 1)))
            .teamPosition,
        'gold',
      );
      expect(
        Competition.fromApi(ApiCompetition.fromJson(compJson(teamPosition: 2)))
            .teamPosition,
        'silver',
      );
      expect(
        Competition.fromApi(ApiCompetition.fromJson(compJson(teamPosition: 3)))
            .teamPosition,
        'bronze',
      );
      expect(
        Competition.fromApi(ApiCompetition.fromJson(compJson(teamPosition: 5)))
            .teamPosition,
        isNull,
      );
    });

    test('transportStatus sempre null (semantics não casam entre legacy e API)', () {
      final c = Competition.fromApi(ApiCompetition.fromJson({
        ...compJson(),
        'transport_status': 'departed',
      }));
      expect(c.transportStatus, isNull);
    });

    test('enrolledStudentIds sempre vazio (caller busca separado)', () {
      final c = Competition.fromApi(ApiCompetition.fromJson(compJson()));
      expect(c.enrolledStudentIds, isEmpty);
    });
  });
}
