import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/models/combo.dart';

void main() {
  group('comboLevelOrder', () {
    test('orders iniciante < intermediario < avancado', () {
      expect(comboLevelOrder('iniciante'), 0);
      expect(comboLevelOrder('intermediario'), 1);
      expect(comboLevelOrder('avancado'), 2);
    });
    test('unknown/null -> 0 (iniciante)', () {
      expect(comboLevelOrder(null), 0);
      expect(comboLevelOrder('garbage'), 0);
    });
  });

  group('comboLevelLabel', () {
    test('pt-BR labels', () {
      expect(comboLevelLabel('iniciante'), 'Iniciante');
      expect(comboLevelLabel('intermediario'), 'Intermediário');
      expect(comboLevelLabel('avancado'), 'Avançado');
    });
    test('fallback -> Iniciante', () {
      expect(comboLevelLabel(null), 'Iniciante');
      expect(comboLevelLabel('x'), 'Iniciante');
    });
  });
}
