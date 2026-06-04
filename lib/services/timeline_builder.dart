import '../core/sports.dart';
import '../models/student.dart';
import 'achievement_service.dart';
import 'belt_progression_service.dart';

/// Shared, UI-agnostic motor for the portal timeline.
///
/// Extracted from `timeline_screen.dart` so the same ordering/filter/event
/// synthesis can be reused (and unit-tested) without depending on Flutter
/// widgets. This file does NO Firestore I/O and observes nothing — callers pass
/// already-fetched data in. It is purely additive: the screen feeds it the same
/// academy-scoped providers it already watched.

/// Timeline event types rendered on the portal "Sua Jornada" list.
enum TimelineEventType {
  graduation,
  stripe,
  competition,
  milestone,
  start,
  attendanceStreak,
  rankingPosition,
  trainingPr,
}

/// Immutable timeline event model consumed by the timeline widgets.
class TimelineEvent {
  final String id;
  final DateTime date;
  final TimelineEventType type;
  final String title;
  final String? description;
  final String? position;
  final String? belt;
  final int? stripes;
  final String? academyName;

  /// Modalidade do evento (define cor/label da faixa). Default BJJ.
  final SportId sportId;

  const TimelineEvent({
    required this.id,
    required this.date,
    required this.type,
    required this.title,
    this.description,
    this.position,
    this.belt,
    this.stripes,
    this.academyName,
    this.sportId = SportId.bjj,
  });
}

/// Reads sportData[sport.value]['startDate'] defensively (DateTime, ISO string
/// or Firestore Timestamp). Returns null when absent or of an unexpected type —
/// never throws. Mirrors MySportsScreen so the per-sport origin date agrees.
DateTime? sportStartDate(Student student, SportId sport) {
  final raw = student.sportData?[sport.value];
  if (raw is! Map) return null;
  final value = raw['startDate'];
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  try {
    final dynamic dyn = value;
    if (dyn != null) {
      final maybe = dyn.toDate();
      if (maybe is DateTime) return maybe;
    }
  } catch (_) {/* unexpected type — ignore */}
  return null;
}

/// Maps an [AchievementType] coming from the achievement store onto its
/// [TimelineEventType] for rendering. Graduation/stripe are intentionally
/// excluded here because those events are sourced from belt progressions (to
/// avoid duplicates). Returns null for types the timeline should skip.
TimelineEventType? timelineTypeForAchievement(AchievementType type) {
  switch (type) {
    case AchievementType.competition:
      return TimelineEventType.competition;
    case AchievementType.milestone:
      return TimelineEventType.milestone;
    case AchievementType.attendanceStreak:
      return TimelineEventType.attendanceStreak;
    case AchievementType.rankingPosition:
      return TimelineEventType.rankingPosition;
    case AchievementType.trainingPr:
      return TimelineEventType.trainingPr;
    case AchievementType.graduation:
    case AchievementType.stripe:
      // Sourced from belt progressions — skip to avoid duplicate entries.
      return null;
  }
}

/// Builds the unified, ordered list of timeline events for a student.
///
/// Combines three sources, in this exact precedence:
///   1. A synthetic "Inicio da Jornada" start marker (per-sport startDate when
///      available, falling back to the student's BJJ/legacy start date).
///   2. Belt progressions → graduation/stripe events.
///   3. Achievements (competitions, generic milestones, and the gamification
///      markers); graduation/stripe achievements are skipped to avoid dupes.
///
/// The result is sorted by date **ascending** (oldest first). When [sportFilter]
/// is non-null (multi-sport student filtering by tab) the list is restricted to
/// events of that sport; legacy/null-sport events default to BJJ. Rendering the
/// list newest-first is the caller's concern.
List<TimelineEvent> buildTimelineEvents({
  required Student student,
  required List<Achievement> achievements,
  required List<BeltProgression> progressions,
  String? academyName,
  SportId? sportFilter,
}) {
  final events = <TimelineEvent>[];

  // Add start event. Tag it to whichever sport is being viewed (sportFilter
  // when a multi-sport student selected a tab) so every sport tab keeps a
  // "Inicio da Jornada" origin marker. Single-sport / unfiltered views fall
  // back to the primary sport. When a per-sport startDate exists in
  // sportData it takes precedence, mirroring MySportsScreen.
  final startSport = sportFilter ?? student.getPrimarySport();
  events.add(
    TimelineEvent(
      id: 'start',
      date: sportStartDate(student, startSport) ??
          student.jiujitsuStartDate ??
          student.startDate,
      type: TimelineEventType.start,
      title: 'Inicio da Jornada',
      description: 'Primeiro treino na academia',
      belt: 'white',
      academyName: academyName,
      sportId: startSport,
    ),
  );

  // Add belt progressions.
  for (final p in progressions) {
    events.add(
      TimelineEvent(
        id: 'progression_${p.id}',
        date: p.promotionDate,
        type: p.isBeltChange
            ? TimelineEventType.graduation
            : TimelineEventType.stripe,
        title: p.isBeltChange
            ? 'Faixa ${getGradeLabel(p.getSport(), p.newBelt)}'
            : '${p.newStripes}o Grau',
        description: p.notes,
        belt: p.newBelt,
        stripes: p.newStripes,
        academyName: academyName,
        sportId: p.getSport(),
      ),
    );
  }

  // Add achievements. Graduations/stripes come from belt progressions, so we
  // render the remaining achievement-store types: competitions, generic
  // milestones, and the gamification markers (attendance streak, ranking
  // position, training PR). Skipped types map to null and are ignored.
  for (final a in achievements) {
    final mapped = timelineTypeForAchievement(a.type);
    if (mapped == null) continue;
    events.add(
      TimelineEvent(
        id: 'achievement_${a.id}',
        date: a.date,
        type: mapped,
        title: a.title,
        description: a.description,
        position: a.position?.value,
        academyName: academyName,
        // Respect the achievement's stored sport so multi-sport students
        // see markers under the correct tab. Legacy records without a sport
        // fall back to the primary sport.
        sportId: a.sport != null
            ? SportId.fromString(a.sport!)
            : student.getPrimarySport(),
      ),
    );
  }

  // Sort by date ascending (oldest first).
  events.sort((a, b) => a.date.compareTo(b.date));

  // Client-side sport filter. Only applied for multi-sport students
  // (sportFilter != null). TimelineEvent.sportId defaults to BJJ, so
  // legacy/null-sport events are already grouped under BJJ.
  // NOTE: this filters the in-memory list — no extra Firestore query and no
  // composite index.
  if (sportFilter == null) return events;
  return events.where((e) => e.sportId == sportFilter).toList();
}
