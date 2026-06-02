import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/measurement_input.dart';

void main() {
  group('parseDecimalInput', () {
    test('parses pt-BR and en decimals + trims', () {
      expect(parseDecimalInput('82,5'), 82.5);
      expect(parseDecimalInput('82.5'), 82.5);
      expect(parseDecimalInput('  90 '), 90);
      expect(parseDecimalInput('178'), 178);
    });

    test('null for empty/invalid (incl. multiplos separadores)', () {
      expect(parseDecimalInput(''), isNull);
      expect(parseDecimalInput('   '), isNull);
      expect(parseDecimalInput(null), isNull);
      expect(parseDecimalInput('abc'), isNull);
      expect(parseDecimalInput('80,5,5'), isNull); // antes era engolido em silencio
    });
  });

  group('validateOptionalMeasure', () {
    test('vazio é válido (campo opcional)', () {
      expect(validateOptionalMeasure('', label: 'Peso'), isNull);
      expect(validateOptionalMeasure(null, label: 'Peso'), isNull);
    });

    test('número inválido é rejeitado (não engolido)', () {
      expect(validateOptionalMeasure('80,5,5', label: 'Peso'), 'Número inválido');
      expect(validateOptionalMeasure('abc', label: 'Peso'), 'Número inválido');
    });

    test('zero/negativo rejeitado', () {
      expect(validateOptionalMeasure('0', label: 'Peso'), 'Deve ser maior que zero');
      expect(validateOptionalMeasure('-5', label: 'Peso'), 'Deve ser maior que zero');
    });

    test('faixa min/max', () {
      // altura em metros (1,80) cai abaixo do minimo de 50 cm
      expect(validateOptionalMeasure('1,80', label: 'Altura', min: 50, max: 250),
          'Mín. 50');
      expect(validateOptionalMeasure('260', label: 'Altura', min: 50, max: 250),
          'Máx. 250');
      expect(validateOptionalMeasure('178', label: 'Altura', min: 50, max: 250),
          isNull);
    });
  });
}
