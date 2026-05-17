import 'package:flutter_test/flutter_test.dart';

import 'package:graduabjj/api/dto/competition_dto.dart';
import 'package:graduabjj/models/competition_photo.dart' as legacy_photo;
import 'package:graduabjj/services/achievement_service.dart';

void main() {
  group('Achievement.fromApi', () {
    test('graduation type com from/to belt deriva título', () {
      final a = Achievement.fromApi(ApiAchievement.fromJson({
        'id': 'ach-1',
        'student_id': 's-1',
        'type': 'graduation',
        'from_belt': 'white',
        'to_belt': 'blue',
        'from_stripes': 4,
        'to_stripes': 0,
        'unlocked_at': '2025-12-01T10:00:00Z',
      }));
      expect(a.type, AchievementType.graduation);
      expect(a.title, 'Graduação: faixa white → blue');
      expect(a.fromBelt, 'white');
      expect(a.toBelt, 'blue');
    });

    test('competition type com position gold', () {
      final a = Achievement.fromApi(ApiAchievement.fromJson({
        'id': 'ach-2',
        'student_id': 's-1',
        'type': 'competition',
        'competition_id': 'cp-1',
        'position': 'gold',
        'unlocked_at': '2026-06-15T18:00:00Z',
      }));
      expect(a.type, AchievementType.competition);
      expect(a.position, CompetitionPosition.gold);
      expect(a.title, contains('gold'));
      expect(a.competitionId, 'cp-1');
    });

    test('stripe type deriva título com to_stripes', () {
      final a = Achievement.fromApi(ApiAchievement.fromJson({
        'id': 'ach-3',
        'student_id': 's-1',
        'type': 'stripe',
        'to_stripes': 3,
        'unlocked_at': '2026-01-15T10:00:00Z',
      }));
      expect(a.type, AchievementType.stripe);
      expect(a.title, 'Conquistou 3ª grau');
    });

    test('milestone type usa milestone_key como título', () {
      final a = Achievement.fromApi(ApiAchievement.fromJson({
        'id': 'ach-4',
        'student_id': 's-1',
        'type': 'milestone',
        'milestone_key': '100_treinos',
        'unlocked_at': '2026-03-01T10:00:00Z',
      }));
      expect(a.type, AchievementType.milestone);
      expect(a.title, '100_treinos');
      expect(a.milestone, '100_treinos');
    });

    test('studentName via param', () {
      final a = Achievement.fromApi(
        ApiAchievement.fromJson({
          'id': 'ach-1',
          'student_id': 's-1',
          'type': 'graduation',
          'unlocked_at': '2026-01-01T00:00:00Z',
        }),
        studentName: 'João',
      );
      expect(a.studentName, 'João');
    });
  });

  group('CompetitionPhoto.fromApi', () {
    test('mapeia campos principais', () {
      final p = legacy_photo.CompetitionPhoto.fromApi(ApiPhoto.fromJson({
        'id': 'ph-1',
        'competition_id': 'cp-1',
        'url': 'https://cdn.example/p1.jpg',
        'storage_path': 'photos/aid/cp-1/p1.jpg',
        'caption': 'Pódio',
        'student_id': 's-1',
        'uploaded_by_uid': 'admin-1',
        'uploaded_at': '2026-06-15T18:00:00Z',
      }));
      expect(p.id, 'ph-1');
      expect(p.competitionId, 'cp-1');
      expect(p.studentId, 's-1');
      expect(p.url, 'https://cdn.example/p1.jpg');
      expect(p.storagePath, 'photos/aid/cp-1/p1.jpg');
      expect(p.caption, 'Pódio');
      expect(p.createdBy, 'admin-1');
    });

    test('competition_name/student_name via param (denorm local)', () {
      final p = legacy_photo.CompetitionPhoto.fromApi(
        ApiPhoto.fromJson({
          'id': 'ph-1',
          'competition_id': 'cp-1',
          'url': 'https://e.com/p.jpg',
          'storage_path': 'p.jpg',
          'uploaded_at': '2026-06-15T18:00:00Z',
        }),
        competitionName: 'Open SP',
        studentName: 'Igor',
      );
      expect(p.competitionName, 'Open SP');
      expect(p.studentName, 'Igor');
    });

    test('student_id null vira empty string (legacy non-null)', () {
      final p = legacy_photo.CompetitionPhoto.fromApi(ApiPhoto.fromJson({
        'id': 'ph-1',
        'competition_id': 'cp-1',
        'url': 'https://e.com/p.jpg',
        'storage_path': 'p.jpg',
        'uploaded_at': '2026-06-15T18:00:00Z',
      }));
      expect(p.studentId, '');
    });

    test('likes/isHighlight/medalType defaults', () {
      final p = legacy_photo.CompetitionPhoto.fromApi(ApiPhoto.fromJson({
        'id': 'ph-1',
        'competition_id': 'cp-1',
        'url': 'https://e.com/p.jpg',
        'storage_path': 'p.jpg',
        'uploaded_at': '2026-06-15T18:00:00Z',
      }));
      expect(p.likes, 0);
      expect(p.isHighlight, isFalse);
      expect(p.medalType, isNull);
      expect(p.photoType, isNull);
    });
  });
}
