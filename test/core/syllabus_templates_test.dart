import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/core/sports.dart';
import 'package:graduabjj/core/syllabus_templates.dart';

void main() {
  // Every seed item must reference a real grade id of its sport — guards against
  // typos that would orphan techniques on an inexistent belt.
  void checkGradeIds(String sportValue, List<SyllabusSeedItem> template) {
    final sport = SportId.values.firstWhere((s) => s.value == sportValue);
    final ids = getGradesForSport(sport).map((g) => g.id).toSet();
    for (final item in template) {
      expect(ids.contains(item.gradeId), isTrue,
          reason: '$sportValue: gradeId "${item.gradeId}" não existe');
    }
  }

  test('karate template gradeIds are valid', () {
    expect(karateStarterTemplate, isNotEmpty);
    checkGradeIds('karate', karateStarterTemplate);
  });

  test('judo template gradeIds are valid', () {
    expect(judoStarterTemplate, isNotEmpty);
    checkGradeIds('judo', judoStarterTemplate);
  });

  test('bjj template gradeIds are valid', () {
    checkGradeIds('bjj', bjjStarterTemplate);
  });

  group('syllabusTemplateFor', () {
    test('returns templates for bjj/karate/judo', () {
      expect(syllabusTemplateFor('bjj'), isNotEmpty);
      expect(syllabusTemplateFor('karate'), isNotEmpty);
      expect(syllabusTemplateFor('judo'), isNotEmpty);
    });
    test('null for sports without a template', () {
      expect(syllabusTemplateFor('boxing'), isNull);
      expect(syllabusTemplateFor('musculacao'), isNull);
    });
  });
}
