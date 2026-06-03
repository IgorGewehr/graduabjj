import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graduabjj/models/academy_event.dart';
import 'package:graduabjj/services/event_service.dart';

// fake_cloud_firestore is NOT a dev_dependency in this repo (see pubspec) and
// DocumentSnapshot is sealed, so Firestore-backed CRUD tests are out of scope.
// We test the pure model via AcademyEvent.fromMap (the same code path
// fromFirestore delegates to): round-trip, copyWith, legacy-default behavior,
// plus the pure notification payload + slug helpers.

AcademyEvent _sample({
  PostType postType = PostType.seminar,
  String? sourceId = 'src-123',
}) {
  return AcademyEvent(
    id: 'campeonato-de-verao',
    academyId: 'acad-1',
    title: 'Campeonato de Verão',
    slug: 'campeonato-de-verao',
    description: 'Inscrições abertas',
    coverUrl: 'https://cdn/cover.jpg',
    coverStoragePath: 'academies/acad-1/events/x/cover.jpg',
    startDate: DateTime.utc(2026, 7, 1, 9),
    endDate: DateTime.utc(2026, 7, 1, 18),
    location: 'Tatame Central',
    ctaUrl: 'https://inscrever',
    ctaLabel: 'Inscrever',
    isPublished: true,
    postType: postType,
    sourceId: sourceId,
    createdAt: DateTime.utc(2026, 6, 1),
    updatedAt: DateTime.utc(2026, 6, 2),
  );
}

void main() {
  group('AcademyEvent.fromFirestore / toFirestore round-trip', () {
    test('round-trips all fields including postType and sourceId', () {
      final original = _sample();
      final map = original.toFirestore();

      // toFirestore stamps a server timestamp for updatedAt; fromFirestore
      // tolerates the sentinel by falling back. Replace with a concrete
      // Timestamp so the round-trip is deterministic.
      map['updatedAt'] = Timestamp.fromDate(original.updatedAt);
      map['createdAt'] = Timestamp.fromDate(original.createdAt);

      final restored = AcademyEvent.fromMap(original.id, map);

      expect(restored.id, original.id);
      expect(restored.academyId, original.academyId);
      expect(restored.title, original.title);
      expect(restored.slug, original.slug);
      expect(restored.description, original.description);
      expect(restored.coverUrl, original.coverUrl);
      expect(restored.coverStoragePath, original.coverStoragePath);
      // Timestamp.toDate() returns local time, so compare instants.
      expect(restored.startDate.toUtc(), original.startDate.toUtc());
      expect(restored.endDate!.toUtc(), original.endDate!.toUtc());
      expect(restored.location, original.location);
      expect(restored.ctaUrl, original.ctaUrl);
      expect(restored.ctaLabel, original.ctaLabel);
      expect(restored.isPublished, original.isPublished);
      expect(restored.postType, PostType.seminar);
      expect(restored.sourceId, 'src-123');
    });

    test('toFirestore serializes postType as its name', () {
      expect(_sample(postType: PostType.news).toFirestore()['postType'], 'news');
      expect(_sample(postType: PostType.event).toFirestore()['postType'],
          'event');
    });

    test('toFirestore sets updatedAt to a server timestamp sentinel', () {
      final map = _sample().toFirestore();
      expect(map['updatedAt'], isA<FieldValue>());
    });
  });

  group('legacy default', () {
    test('missing postType falls back to PostType.event', () {
      final restored = AcademyEvent.fromMap('legacy', {
        'academyId': 'acad-1',
        'title': 'Old event',
        'slug': 'old-event',
        'description': '',
        'startDate': Timestamp.fromDate(DateTime.utc(2025, 1, 1)),
        'isPublished': true,
        // no postType, no sourceId
      });
      expect(restored.postType, PostType.event);
      expect(restored.sourceId, isNull);
    });

    test('unknown postType string falls back to PostType.event', () {
      final restored = AcademyEvent.fromMap('weird', {
        'startDate': Timestamp.fromDate(DateTime.utc(2025, 1, 1)),
        'postType': 'podcast',
      });
      expect(restored.postType, PostType.event);
    });
  });

  group('copyWith', () {
    test('overrides only the provided fields', () {
      final base = _sample();
      final copy = base.copyWith(
        title: 'Novo Título',
        postType: PostType.news,
        isPublished: false,
      );
      expect(copy.title, 'Novo Título');
      expect(copy.postType, PostType.news);
      expect(copy.isPublished, false);
      // untouched
      expect(copy.id, base.id);
      expect(copy.sourceId, base.sourceId);
      expect(copy.startDate, base.startDate);
    });

    test('no args returns an equivalent copy', () {
      final base = _sample();
      final copy = base.copyWith();
      expect(copy.id, base.id);
      expect(copy.postType, base.postType);
      expect(copy.sourceId, base.sourceId);
    });
  });

  group('isUpcoming / isOngoing', () {
    test('isUpcoming true for a future startDate', () {
      final e = _sample().copyWith(
        startDate: DateTime.now().add(const Duration(days: 5)),
        endDate: null,
      );
      expect(e.isUpcoming, isTrue);
      expect(e.isOngoing, isFalse);
    });

    test('isOngoing true when started and not yet ended', () {
      final e = _sample().copyWith(
        startDate: DateTime.now().subtract(const Duration(hours: 1)),
        endDate: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(e.isOngoing, isTrue);
      expect(e.isUpcoming, isFalse);
    });
  });

  group('EventService.buildPublishNotification (pure helper)', () {
    test('prefixes the title with the post-type emoji', () {
      final p = EventService.buildPublishNotification(
        _sample(postType: PostType.seminar),
      );
      expect(p.title, '🥋 Campeonato de Verão');

      final pNews = EventService.buildPublishNotification(
        _sample(postType: PostType.news),
      );
      expect(pNews.title, '📰 Campeonato de Verão');

      final pEvent = EventService.buildPublishNotification(
        _sample(postType: PostType.event),
      );
      expect(pEvent.title, '📅 Campeonato de Verão');
    });

    test('route points at the portal event detail with the id', () {
      final p = EventService.buildPublishNotification(_sample());
      expect(p.data['route'], '/portal/eventos/campeonato-de-verao');
      expect(p.route, '/portal/eventos/campeonato-de-verao');
    });
  });

  group('EventService.slugify', () {
    test('strips accents and non-alphanumerics', () {
      expect(EventService.slugify('Campeonato de Verão!'),
          'campeonato-de-verao');
      expect(EventService.slugify('  Olá   Mundo  '), 'ola-mundo');
    });

    test('falls back to "post" for empty/symbol-only titles', () {
      expect(EventService.slugify('!!!'), 'post');
      expect(EventService.slugify(''), 'post');
    });
  });
}
