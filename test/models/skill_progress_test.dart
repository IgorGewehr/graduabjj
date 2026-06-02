import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/models/skill_progress.dart';

void main() {
  group('SkillLevel', () {
    test('value/label round-trip', () {
      for (final l in SkillLevel.values) {
        expect(SkillLevelExtension.fromString(l.value), l);
        expect(l.label.isNotEmpty, isTrue);
      }
    });

    test('fromString null/invalid → null', () {
      expect(SkillLevelExtension.fromString(null), isNull);
      expect(SkillLevelExtension.fromString('xpto'), isNull);
    });

    test('only dominado is mastered', () {
      expect(SkillLevel.dominado.isMastered, isTrue);
      expect(SkillLevel.praticando.isMastered, isFalse);
      expect(SkillLevel.aprendendo.isMastered, isFalse);
    });
  });

  group('SkillProgress.docId', () {
    test('deterministic per (student, technique)', () {
      expect(SkillProgress.docId('s1', 't1'), 's1__t1');
      expect(SkillProgress.docId('s1', 't1'),
          SkillProgress.docId('s1', 't1'));
      expect(SkillProgress.docId('s1', 't1') ==
          SkillProgress.docId('s2', 't1'), isFalse);
    });
  });
}
