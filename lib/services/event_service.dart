import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/academy_event.dart';
import 'firebase_service.dart';

class EventService {
  final String academyId;

  EventService(this.academyId);

  CollectionReference get _ref =>
      FirebaseService.firestore.collection('academies/$academyId/events');

  Future<List<AcademyEvent>> listPublished() async {
    final snap = await _ref
        .where('isPublished', isEqualTo: true)
        .orderBy('startDate')
        .get();
    return snap.docs.map((d) => AcademyEvent.fromFirestore(d)).toList();
  }

  /// Returns only events that haven't ended yet (upcoming + ongoing).
  Future<List<AcademyEvent>> listUpcoming({int limit = 5}) async {
    final all = await listPublished();
    final now = DateTime.now();
    return all
        .where((e) => e.endDate == null
            ? e.startDate.isAfter(now.subtract(const Duration(hours: 3)))
            : e.endDate!.isAfter(now))
        .take(limit)
        .toList();
  }
}

EventService createEventService(String academyId) => EventService(academyId);
