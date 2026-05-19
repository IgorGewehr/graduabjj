import 'package:flutter/material.dart';

import '../../../api/dto/student_dto.dart' as api_student;
import '../../../services/belt_progression_service.dart';

/// Timeline event types
enum TimelineEventType { graduation, stripe, competition, milestone, start }

/// Timeline event model
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

  TimelineEvent({
    required this.id,
    required this.date,
    required this.type,
    required this.title,
    this.description,
    this.position,
    this.belt,
    this.stripes,
    this.academyName,
  });
}

/// Config class for event type visual representation
class EventConfig {
  final IconData icon;
  final Color color;
  final Color bgColor;

  EventConfig({
    required this.icon,
    required this.color,
    required this.bgColor,
  });
}

/// Adapter inline: ApiBeltProgression → BeltProgression legacy.
BeltProgression beltProgressionFromApi(api_student.ApiBeltProgression p) =>
    BeltProgression(
      id: p.id,
      studentId: p.studentId,
      previousBelt: p.previousBelt.wire,
      previousStripes: p.previousStripes,
      newBelt: p.newBelt.wire,
      newStripes: p.newStripes,
      promotionDate: p.promotionDate,
      totalClasses: p.totalClasses,
      effectiveCountAtPromotion: p.effectiveCountAtPromotion,
      promotedBy: p.promotedByUid,
      promotedByName: null,
      notes: p.notes,
      sport: p.sport.wire,
      createdAt: p.createdAt ?? p.promotionDate,
    );
