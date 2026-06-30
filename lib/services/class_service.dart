import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/sports.dart';
import '../models/student.dart';
import 'firebase_service.dart';

/// Converte "HH:MM" em minutos do dia. Retorna null em horário malformado
/// (vazio, "19", "19:00:00" parcial, não-numérico) — um doc de schedule sujo
/// NÃO pode derrubar isHappeningNow/getCurrentClass (que rodam na home do
/// aluno com int.parse cru e quebravam a tela inteira).
int? _hhmmToMinutes(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim());
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

/// Class Schedule Model
class ClassSchedule {
  final int dayOfWeek; // 0 = Sunday, 6 = Saturday
  final String startTime;
  final String endTime;

  ClassSchedule({
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
  });

  factory ClassSchedule.fromMap(Map<String, dynamic> map) {
    return ClassSchedule(
      dayOfWeek: map['dayOfWeek'] ?? 0,
      startTime: map['startTime'] ?? '00:00',
      endTime: map['endTime'] ?? '00:00',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'dayOfWeek': dayOfWeek,
      'startTime': startTime,
      'endTime': endTime,
    };
  }
}

/// BJJ Class Model
class BJJClass {
  final String id;
  final String name;
  final String? description;
  final String? instructorId;
  final String? instructorName;
  final List<String> studentIds;
  final List<ClassSchedule> schedule;
  final StudentCategory? category;
  final String? sport; // Multi-sport: defaults to 'bjj' if absent
  final String? minBelt;
  final String? maxBelt;
  final int? maxStudents;
  final bool isActive;
  /// Enrollment gate for QR check-in:
  /// - `true`  → open class, anyone in the academy can check in (studentIds ignored).
  /// - `false` → strict, must appear in studentIds.
  /// - `null`  → legacy fallback: open iff studentIds is empty (back-compat for
  ///             classes created before this field existed).
  final bool? isOpenClass;
  /// Optional weight applied to attendances marked in this class. Only
  /// effective when the academy has `useClassWeights = true`. Null/1 means
  /// "counts as one normal attendance" — the default for any new class.
  final double? weight;
  final DateTime createdAt;
  final DateTime updatedAt;

  BJJClass({
    required this.id,
    required this.name,
    this.description,
    this.instructorId,
    this.instructorName,
    this.studentIds = const [],
    this.schedule = const [],
    this.category,
    this.sport,
    this.minBelt,
    this.maxBelt,
    this.maxStudents,
    this.isActive = true,
    this.isOpenClass,
    this.weight,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Whether this class accepts QR check-ins from non-enrolled students.
  /// Captures the legacy fallback so call sites don't repeat the rule.
  bool acceptsCheckinFrom(String studentId) {
    if (isOpenClass == true) return true;
    if (isOpenClass == false) return studentIds.contains(studentId);
    return studentIds.isEmpty || studentIds.contains(studentId);
  }

  /// Returns the effective sport for this class (backward compat: absent = 'bjj')
  SportId getSport() => SportId.fromString(sport ?? 'bjj');

  /// Effective weight (default 1 when unset).
  double effectiveWeight() => weight ?? 1.0;

  factory BJJClass.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BJJClass(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'],
      instructorId: data['instructorId'],
      instructorName: data['instructorName'],
      studentIds: data['studentIds'] != null
          ? List<String>.from(data['studentIds'])
          : [],
      schedule: data['schedule'] != null
          ? (data['schedule'] as List)
              .map((s) => ClassSchedule.fromMap(s as Map<String, dynamic>))
              .toList()
          : [],
      category: data['category'] != null
          ? StudentCategoryExtension.fromString(data['category'])
          : null,
      sport: data['sport'],
      minBelt: data['minBelt'],
      maxBelt: data['maxBelt'],
      maxStudents: data['maxStudents'],
      isActive: data['isActive'] ?? true,
      isOpenClass: data['isOpenClass'] is bool ? data['isOpenClass'] as bool : null,
      weight: data['weight'] is num ? (data['weight'] as num).toDouble() : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // Check if class is happening now
  bool isHappeningNow() {
    final now = DateTime.now();
    final currentDayOfWeek = now.weekday % 7; // Convert to 0-6 format
    final currentMinutes = now.hour * 60 + now.minute;

    for (final s in schedule) {
      if (s.dayOfWeek != currentDayOfWeek) continue;

      final startMinutes = _hhmmToMinutes(s.startTime);
      final endMinutes = _hhmmToMinutes(s.endTime);
      if (startMinutes == null || endMinutes == null) continue;

      if (currentMinutes >= startMinutes && currentMinutes <= endMinutes) {
        return true;
      }
    }
    return false;
  }

  // Get schedule for a specific day
  ClassSchedule? getScheduleForDay(int dayOfWeek) {
    return schedule.where((s) => s.dayOfWeek == dayOfWeek).firstOrNull;
  }
}

/// Class Service - Multi-tenant class management
class ClassService {
  final String academyId;
  late final Collections _collections;

  ClassService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _classesRef => _collections.classes;

  // ============================================
  // List All Active Classes
  // ============================================
  Future<List<BJJClass>> list() async {
    final query = await _classesRef
        .where('isActive', isEqualTo: true)
        .get();

    var classes = query.docs.map((doc) => BJJClass.fromFirestore(doc)).toList();
    classes.sort((a, b) => a.name.compareTo(b.name));
    return classes;
  }

  // ============================================
  // Get Class by ID
  // ============================================
  Future<BJJClass?> getById(String id) async {
    final doc = await _collections.classDoc(id).get();
    if (!doc.exists) return null;
    return BJJClass.fromFirestore(doc);
  }

  // ============================================
  // Get Classes by Day of Week
  // ============================================
  Future<List<BJJClass>> getByDayOfWeek(int dayOfWeek) async {
    final allClasses = await list();
    return allClasses.where((cls) =>
        cls.schedule.any((s) => s.dayOfWeek == dayOfWeek)
    ).toList();
  }

  // ============================================
  // Get Today's Classes
  // ============================================
  Future<List<BJJClass>> getTodayClasses() async {
    final dayOfWeek = DateTime.now().weekday % 7;
    return getByDayOfWeek(dayOfWeek);
  }

  // ============================================
  // Get Current Class (happening now or starting soon)
  // ============================================
  Future<BJJClass?> getCurrentClass() async {
    final now = DateTime.now();
    final dayOfWeek = now.weekday % 7;
    final currentMinutes = now.hour * 60 + now.minute;

    final todayClasses = await getByDayOfWeek(dayOfWeek);

    for (final cls in todayClasses) {
      for (final schedule in cls.schedule) {
        if (schedule.dayOfWeek != dayOfWeek) continue;

        final startMinutes = _hhmmToMinutes(schedule.startTime);
        final endMinutes = _hhmmToMinutes(schedule.endTime);
        if (startMinutes == null || endMinutes == null) continue;

        // Check if within 30 min before start or during class
        if (currentMinutes >= startMinutes - 30 && currentMinutes <= endMinutes) {
          return cls;
        }
      }
    }

    return null;
  }

  // ============================================
  // Get Classes by Category
  // ============================================
  Future<List<BJJClass>> getByCategory(StudentCategory category) async {
    final query = await _classesRef
        .where('category', isEqualTo: category.value)
        .where('isActive', isEqualTo: true)
        .get();

    var classes = query.docs.map((doc) => BJJClass.fromFirestore(doc)).toList();
    classes.sort((a, b) => a.name.compareTo(b.name));
    return classes;
  }

  // ============================================
  // Get Weekly Schedule
  // ============================================
  Future<Map<int, List<BJJClass>>> getWeeklySchedule() async {
    final allClasses = await list();
    final schedule = <int, List<BJJClass>>{
      0: [], // Sunday
      1: [], // Monday
      2: [], // Tuesday
      3: [], // Wednesday
      4: [], // Thursday
      5: [], // Friday
      6: [], // Saturday
    };

    for (final cls in allClasses) {
      for (final s in cls.schedule) {
        if (!schedule[s.dayOfWeek]!.any((c) => c.id == cls.id)) {
          schedule[s.dayOfWeek]!.add(cls);
        }
      }
    }

    // Sort each day by start time
    for (final day in schedule.keys) {
      schedule[day]!.sort((a, b) {
        final aTime = a.schedule.where((s) => s.dayOfWeek == day).firstOrNull?.startTime ?? '00:00';
        final bTime = b.schedule.where((s) => s.dayOfWeek == day).firstOrNull?.startTime ?? '00:00';
        return aTime.compareTo(bTime);
      });
    }

    return schedule;
  }

  // ============================================
  // Get Classes for Date
  // ============================================
  Future<List<BJJClass>> getClassesForDate(DateTime date) async {
    final dayOfWeek = date.weekday % 7;
    return getByDayOfWeek(dayOfWeek);
  }

  // ============================================
  // WRITE OPERATIONS
  // ============================================

  // ============================================
  // Create Class
  // ============================================
  Future<BJJClass> create({
    required String name,
    String? description,
    String? instructorId,
    String? instructorName,
    List<ClassSchedule>? schedule,
    StudentCategory? category,
    String? sport,
    String? minBelt,
    String? maxBelt,
    int? maxStudents,
    double? weight,
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'description': description,
      'instructorId': instructorId,
      'instructorName': instructorName,
      'studentIds': [],
      'schedule': schedule?.map((s) => s.toMap()).toList() ?? [],
      'category': category?.value,
      'sport': sport,
      'minBelt': minBelt,
      'maxBelt': maxBelt,
      'maxStudents': maxStudents,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (weight != null && weight != 1.0) {
      payload['weight'] = weight;
    }
    final docRef = await _classesRef.add(payload);

    final doc = await docRef.get();
    return BJJClass.fromFirestore(doc);
  }

  // ============================================
  // Update Class
  // ============================================
  Future<BJJClass> update(String id, Map<String, dynamic> data) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _collections.classDoc(id).update(data);
    final updated = await getById(id);
    return updated!;
  }

  // ============================================
  // Delete Class (Soft Delete)
  // ============================================
  Future<void> delete(String id) async {
    await _collections.classDoc(id).update({
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Hard Delete Class
  // ============================================
  Future<void> hardDelete(String id) async {
    await _collections.classDoc(id).delete();
  }

  // ============================================
  // Add Student to Class (membership-only, no sport enrollment side-effects)
  // ============================================
  Future<void> addStudentToClass(String classId, String studentId) async {
    await _collections.classDoc(classId).update({
      'studentIds': FieldValue.arrayUnion([studentId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Remove Student from Class (membership-only)
  // ============================================
  Future<void> removeStudentFromClass(String classId, String studentId) async {
    await _collections.classDoc(classId).update({
      'studentIds': FieldValue.arrayRemove([studentId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Add Student to Class
  //
  // Also enrolls the student in the class's sport: adds the sport to
  // `sports` array, seeds `sportData[sport]` with the lowest-rank grade
  // for that sport, and sets `primarySport` if the student doesn't have one.
  // ============================================
  Future<BJJClass> addStudent(String classId, String studentId) async {
    final cls = await getById(classId);
    if (cls == null) throw Exception('Turma não encontrada');

    await _collections.classDoc(classId).update({
      'studentIds': FieldValue.arrayUnion([studentId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _enrollStudentInSport(studentId, cls.getSport(), cls.category);

    final updated = await getById(classId);
    return updated!;
  }

  /// Ensures the student doc carries the sport in `sports`, `sportData`,
  /// and `primarySport`. Idempotent — safe to call when already enrolled.
  Future<void> _enrollStudentInSport(
    String studentId,
    SportId sport,
    StudentCategory? classCategory,
  ) async {
    final studentRef = _collections.student(studentId);
    final snap = await studentRef.get();
    if (!snap.exists) return;

    final data = snap.data() as Map<String, dynamic>;
    final sportValue = sport.value;

    final existingSports = (data['sports'] as List?)?.cast<String>() ?? const [];
    final existingSportData =
        (data['sportData'] as Map?)?.cast<String, dynamic>() ?? const {};
    final existingPrimary = data['primarySport'] as String?;

    final updates = <String, dynamic>{};

    if (!existingSports.contains(sportValue)) {
      updates['sports'] = FieldValue.arrayUnion([sportValue]);
    }

    if (!existingSportData.containsKey(sportValue)) {
      final category = classCategory?.value ??
          (data['category'] as String?) ??
          'adult';
      // Muay Thai's starting grade depends on the academy's chosen ladder.
      String? muaythaiVariant;
      if (sport == SportId.muaythai) {
        final academyDoc = await _collections.academy.get();
        muaythaiVariant = (academyDoc.data()
                as Map<String, dynamic>?)?['muaythaiGradeSystem'] as String?;
      }
      final grades = getGradesForSport(
        sport,
        category: category,
        muaythaiVariant: muaythaiVariant,
      );
      final defaultGrade = grades.isNotEmpty ? grades.first.id : 'white';

      // For BJJ the legacy `currentBelt`/`currentStripes` fields already hold
      // the grade — preserve them so we don't downgrade existing students.
      final isLegacyBjj = sport == SportId.bjj && data['currentBelt'] != null;
      updates['sportData.$sportValue'] = {
        'currentGrade': isLegacyBjj ? data['currentBelt'] : defaultGrade,
        'currentStripes':
            isLegacyBjj ? (data['currentStripes'] ?? 0) : 0,
      };
    }

    if (existingPrimary == null || existingPrimary.isEmpty) {
      updates['primarySport'] = sportValue;
    }

    if (updates.isEmpty) return;
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await studentRef.update(updates);
  }

  // ============================================
  // Remove Student from Class
  // ============================================
  Future<BJJClass> removeStudent(String classId, String studentId) async {
    await _collections.classDoc(classId).update({
      'studentIds': FieldValue.arrayRemove([studentId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final updated = await getById(classId);
    return updated!;
  }

  // ============================================
  // Toggle Student in Class
  // ============================================
  Future<BJJClass> toggleStudent(String classId, String studentId) async {
    final cls = await getById(classId);
    if (cls == null) throw Exception('Turma não encontrada');

    if (cls.studentIds.contains(studentId)) {
      return removeStudent(classId, studentId);
    } else {
      return addStudent(classId, studentId);
    }
  }
}

// ============================================
// Factory Function
// ============================================
ClassService createClassService(String academyId) {
  return ClassService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
ClassService get classService => ClassService(FirebaseService.academyId);
