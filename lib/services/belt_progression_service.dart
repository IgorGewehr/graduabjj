import 'package:cloud_firestore/cloud_firestore.dart';

import '../api/dto/student_dto.dart' as api;
import '../core/sports.dart';
import 'firebase_service.dart';

/// Belt Order (adult)
const List<String> beltOrder = ['white', 'blue', 'purple', 'brown', 'black'];

/// Stripe Requirements (legacy fallback when the academy hasn't configured
/// `autoGraduationAttendances`). Kept as a transitional default — new
/// deployments should set a single threshold per academy in Settings.
const Map<String, List<int>> stripeRequirements = {
  'white': [30, 60, 90, 120],
  'blue': [50, 100, 150, 200],
  'purple': [75, 150, 225, 300],
  'brown': [100, 200, 300, 400],
  'black': [150, 300, 450, 600],
};

/// Snapshot of the academy-level graduation configuration. Used by the
/// eligibility helpers so a single config read can serve a whole batch
/// (e.g. computing eligibility for every active student).
class AcademyGraduationConfig {
  final int? threshold;        // `autoGraduationAttendances` if set
  final bool useClassWeights;  // `useClassWeights`

  const AcademyGraduationConfig({
    this.threshold,
    this.useClassWeights = false,
  });
}

/// Belt Progression Model
class BeltProgression {
  final String id;
  final String studentId;
  final String previousBelt;
  final int previousStripes;
  final String newBelt;
  final int newStripes;
  final DateTime promotionDate;
  /// Simple attendance count at the time of promotion (kept for back-compat
  /// and reporting). When the academy uses class weights, this still records
  /// the *raw* count of attendances — the weighted snapshot lives in
  /// [effectiveCountAtPromotion].
  final int totalClasses;
  /// Snapshot of the value that was compared against the academy's
  /// graduation threshold at the moment of this promotion. For weighted
  /// academies this is the weighted sum; otherwise it equals totalClasses.
  /// Used by checkEligibility to count attendances *since the last
  /// promotion* — preventing the "graduate at 75, become instantly eligible
  /// again at 82" bug.
  final int? effectiveCountAtPromotion;
  final String? promotedBy;
  final String? promotedByName;
  final String? notes;
  final String? sport; // Multi-sport: absent = 'bjj'
  final DateTime createdAt;

  BeltProgression({
    required this.id,
    required this.studentId,
    required this.previousBelt,
    required this.previousStripes,
    required this.newBelt,
    required this.newStripes,
    required this.promotionDate,
    required this.totalClasses,
    this.effectiveCountAtPromotion,
    this.promotedBy,
    this.promotedByName,
    this.notes,
    this.sport,
    required this.createdAt,
  });

  /// Returns the effective sport for this progression (backward compat: absent = 'bjj')
  SportId getSport() => SportId.fromString(sport ?? 'bjj');

  /// Returns the count to subtract from a current attendance total when
  /// computing "attendances since this promotion". Falls back to totalClasses
  /// for legacy docs that don't have effectiveCountAtPromotion stored.
  int get baselineCount => effectiveCountAtPromotion ?? totalClasses;

  factory BeltProgression.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BeltProgression(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      previousBelt: data['previousBelt'] ?? 'white',
      previousStripes: data['previousStripes'] ?? 0,
      newBelt: data['newBelt'] ?? 'white',
      newStripes: data['newStripes'] ?? 0,
      promotionDate: (data['promotionDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalClasses: data['totalClasses'] ?? 0,
      effectiveCountAtPromotion: data['effectiveCountAtPromotion'] is int
          ? data['effectiveCountAtPromotion'] as int
          : null,
      promotedBy: data['promotedBy'],
      promotedByName: data['promotedByName'],
      notes: data['notes'],
      sport: data['sport'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Constrói uma [BeltProgression] a partir do DTO [api.ApiBeltProgression]
  /// (resposta de `GET /v1/academies/{id}/students/{sid}/belt-progressions`).
  ///
  /// Sprint 2 wiring (FE-only). Pontos de atenção:
  /// - `promotedBy` recebe `promotedByUid` (snake_case → camelCase).
  /// - `promotedByName` fica `null`: o BE só expõe o UID; o nome do
  ///   instrutor deve ser denormalizado no caller se necessário (lookup
  ///   em membership/identity).
  /// - `sport` é serializado como `wire` (mesmo formato textual do
  ///   legacy: `'bjj'`, `'judo'`, etc.).
  /// - `createdAt` cai pra `promotionDate` se ausente — o BE garante
  ///   `created_at`, mas tratamos defensivamente para parity com fromFirestore.
  factory BeltProgression.fromApi(api.ApiBeltProgression a) {
    return BeltProgression(
      id: a.id,
      studentId: a.studentId,
      previousBelt: a.previousBelt.wire,
      previousStripes: a.previousStripes,
      newBelt: a.newBelt.wire,
      newStripes: a.newStripes,
      promotionDate: a.promotionDate,
      totalClasses: a.totalClasses,
      effectiveCountAtPromotion: a.effectiveCountAtPromotion,
      promotedBy: a.promotedByUid.isEmpty ? null : a.promotedByUid,
      promotedByName: null,
      notes: a.notes,
      sport: a.sport.wire,
      createdAt: a.createdAt ?? a.promotionDate,
    );
  }

  // Computed properties
  bool get isBeltChange => previousBelt != newBelt;
  bool get isStripeChange => previousStripes != newStripes;

  // Convenience getters (for backwards compatibility)
  DateTime get date => promotionDate;
  String get belt => newBelt;
  int get stripes => newStripes;
}

/// Eligibility Check Result
class EligibilityResult {
  final bool eligible;
  final String? nextBelt;
  final int? nextStripes;
  final int currentClasses;
  final int requiredClasses;
  final int missingClasses;
  final String message;
  final bool weighted; // true when current count used Class.weight summation

  EligibilityResult({
    required this.eligible,
    this.nextBelt,
    this.nextStripes,
    required this.currentClasses,
    required this.requiredClasses,
    required this.missingClasses,
    required this.message,
    this.weighted = false,
  });
}

/// Per-student eligibility row used by the students list.
class EligibilitySnapshotEntry {
  final String studentId;
  final bool eligible;
  final int currentClasses;
  final int requiredClasses;
  final int missingClasses;
  final bool weighted;

  const EligibilitySnapshotEntry({
    required this.studentId,
    required this.eligible,
    required this.currentClasses,
    required this.requiredClasses,
    required this.missingClasses,
    required this.weighted,
  });
}

/// Belt Progression Service - Multi-tenant belt progression management
class BeltProgressionService {
  final String academyId;
  late final Collections _collections;

  BeltProgressionService(this.academyId) {
    _collections = Collections(academyId);
  }

  // Note: Progressions might be stored under achievements or a dedicated collection
  // For now, we'll work with what's available

  // ============================================
  // Calculate Next Promotion (sport-aware)
  // ============================================
  Map<String, dynamic>? getNextPromotion(String currentBelt, int currentStripes, {SportId sportId = SportId.bjj, String category = 'adult'}) {
    final sport = getSport(sportId);

    // No grade system = no promotions
    if (sport.gradeSystem == GradeSystem.none) return null;

    final grades = getGradesForSport(sportId, category: category);
    if (grades.isEmpty) return null;

    final currentGrade = grades.where((g) => g.id == currentBelt).firstOrNull;
    final maxStripes = currentGrade?.maxStripes ?? 4;

    if (sport.supportsStripes && currentStripes < maxStripes) {
      // Next is a stripe
      return {
        'belt': currentBelt,
        'stripes': currentStripes + 1,
      };
    } else {
      // Next is a grade change
      final gradeIds = grades.map((g) => g.id).toList();
      final currentIndex = gradeIds.indexOf(currentBelt);
      if (currentIndex < 0 || currentIndex >= gradeIds.length - 1) {
        return null; // Already at max grade
      }
      return {
        'belt': gradeIds[currentIndex + 1],
        'stripes': 0,
      };
    }
  }

  // ============================================
  // Check Eligibility for Promotion
  //
  // [config.threshold] overrides the per-belt [stripeRequirements] table.
  // Used by academies that prefer "X aulas/pontos para qualquer graduação".
  // [config.useClassWeights] only flips the message unit (pts vs aulas) —
  // the caller is responsible for passing a weighted [totalClasses] when
  // weights are active. Use `checkEligibilityForStudent` to let the service
  // do the math end-to-end.
  // ============================================
  EligibilityResult checkEligibility({
    required String currentBelt,
    required int currentStripes,
    required int totalClasses,
    SportId sportId = SportId.bjj,
    String category = 'adult',
    AcademyGraduationConfig? config,
  }) {
    final cfg = config ?? const AcademyGraduationConfig();
    final nextPromotion = getNextPromotion(currentBelt, currentStripes, sportId: sportId, category: category);

    if (nextPromotion == null) {
      return EligibilityResult(
        eligible: false,
        currentClasses: totalClasses,
        requiredClasses: 0,
        missingClasses: 0,
        message: 'Grau máximo atingido',
        weighted: cfg.useClassWeights,
      );
    }

    int requiredClasses;
    if (cfg.threshold != null && cfg.threshold! > 0) {
      // Single configurable threshold for any belt/stripe transition.
      requiredClasses = cfg.threshold!;
    } else {
      // Legacy fallback: per-belt requirements (BJJ only — other sports always eligible).
      final requirements = sportId == SportId.bjj
          ? (stripeRequirements[currentBelt] ?? [0, 0, 0, 0])
          : <int>[];
      requiredClasses = requirements.length > currentStripes
          ? requirements[currentStripes]
          : 0;
    }
    final missingClasses = requiredClasses > 0
        ? (requiredClasses - totalClasses).clamp(0, requiredClasses).toInt()
        : 0;
    final eligible = requiredClasses > 0 && totalClasses >= requiredClasses;

    final nextBelt = nextPromotion['belt'] as String;
    final nextStripes = nextPromotion['stripes'] as int;
    final gradeLabel = getGradeLabel(sportId, nextBelt);
    final unit = cfg.useClassWeights ? 'pontos' : 'aulas';

    String message;
    if (eligible) {
      message = nextStripes == 0
          ? 'Elegível para faixa $gradeLabel!'
          : 'Elegível para $nextStripesº grau!';
    } else {
      final target = nextStripes == 0 ? 'faixa $gradeLabel' : '$nextStripesº grau';
      message = 'Faltam $missingClasses $unit para $target';
    }

    return EligibilityResult(
      eligible: eligible,
      nextBelt: nextBelt,
      nextStripes: nextStripes,
      currentClasses: totalClasses,
      requiredClasses: requiredClasses,
      missingClasses: missingClasses,
      message: message,
      weighted: cfg.useClassWeights,
    );
  }

  // ============================================
  // Async helpers (do the lookups for you)
  // ============================================

  /// Reads the academy doc and extracts the graduation config snapshot.
  Future<AcademyGraduationConfig> loadAcademyConfig() async {
    try {
      final doc = await _collections.academy.get();
      if (!doc.exists) return const AcademyGraduationConfig();
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final rawThreshold = data['autoGraduationAttendances'];
      final threshold =
          rawThreshold is int && rawThreshold > 0 ? rawThreshold : null;
      return AcademyGraduationConfig(
        threshold: threshold,
        useClassWeights: data['useClassWeights'] == true,
      );
    } catch (_) {
      return const AcademyGraduationConfig();
    }
  }

  /// Returns the baseline count to subtract when computing "attendances since
  /// the last promotion" for [studentId] in [sportId]. If the student has
  /// never been promoted in this sport, returns 0 — every attendance counts.
  /// Otherwise returns the value that was the comparison snapshot at the
  /// time of their most recent promotion in this sport.
  ///
  /// Optionally accepts the student's full progression list so callers
  /// looping over many students can avoid re-querying per call.
  Future<int> getLastPromotionBaseline(
    String studentId, {
    SportId sportId = SportId.bjj,
    List<BeltProgression>? progressionsHint,
  }) async {
    final progressions = progressionsHint ?? await getByStudent(studentId);
    final forSport = progressions
        .where((p) => p.getSport() == sportId)
        .toList()
      ..sort((a, b) => b.promotionDate.compareTo(a.promotionDate));
    if (forSport.isEmpty) return 0;
    return forSport.first.baselineCount;
  }

  /// Sums Attendance.weight (defaulting to 1 for legacy docs) for a student.
  /// Use when [AcademyGraduationConfig.useClassWeights] is true.
  Future<int> getWeightedAttendanceCount(String studentId) async {
    final snap = await _collections.attendance
        .where('studentId', isEqualTo: studentId)
        .get();
    double total = 0;
    for (final d in snap.docs) {
      final data = d.data() as Map<String, dynamic>;
      final w = data['weight'];
      total += (w is num && w > 0) ? w.toDouble() : 1.0;
    }
    return total.round();
  }

  /// Convenience: resolves config, counts (weighted or not), reads the
  /// student's current grade per sport, and returns the eligibility.
  Future<EligibilityResult> checkEligibilityForStudent(
    String studentId, {
    SportId sportId = SportId.bjj,
    AcademyGraduationConfig? config,
  }) async {
    final cfg = config ?? await loadAcademyConfig();
    final studentDoc = await _collections.student(studentId).get();
    if (!studentDoc.exists) {
      return EligibilityResult(
        eligible: false,
        currentClasses: 0,
        requiredClasses: 0,
        missingClasses: 0,
        message: 'Aluno não encontrado',
        weighted: cfg.useClassWeights,
      );
    }
    final data = studentDoc.data() as Map<String, dynamic>;

    // Resolve current grade for this sport (multi-sport aware)
    String currentBelt;
    int currentStripes;
    final sportData = (data['sportData'] as Map?)?[sportId.value];
    if (sportId == SportId.bjj && sportData == null) {
      currentBelt = data['currentBelt'] ?? 'white';
      currentStripes = data['currentStripes'] ?? 0;
    } else {
      currentBelt = sportData?['currentGrade'] ?? 'white';
      currentStripes = sportData?['currentStripes'] ?? 0;
    }

    final category = data['category'] ?? 'adult';

    // System count: weighted if academy uses it, otherwise raw doc count.
    int systemCount;
    if (cfg.useClassWeights) {
      systemCount = await getWeightedAttendanceCount(studentId);
    } else {
      final attendSnap = await _collections.attendance
          .where('studentId', isEqualTo: studentId)
          .get();
      systemCount = attendSnap.size;
    }
    final initial = (data['initialAttendanceCount'] ?? 0) as int;
    final totalClasses = systemCount + initial;

    // Subtract the snapshot at the last promotion so we count only
    // attendances accumulated *since* that promotion. The mestre may have
    // chosen to wait past the threshold (e.g. promoted at 82 with target 75)
    // — those 7 extra do NOT carry over to the next graduation.
    final baseline = await getLastPromotionBaseline(
      studentId,
      sportId: sportId,
    );
    final sinceLastPromotion = (totalClasses - baseline).clamp(0, totalClasses);

    return checkEligibility(
      currentBelt: currentBelt,
      currentStripes: currentStripes,
      totalClasses: sinceLastPromotion,
      sportId: sportId,
      category: category,
      config: cfg,
    );
  }

  /// Batch helper: loads the config once, then resolves eligibility for every
  /// active student. Used by the admin students list to render the progress
  /// column / "Elegível" badge.
  Future<List<EligibilitySnapshotEntry>> getEligibilitySnapshot({
    SportId sportId = SportId.bjj,
  }) async {
    final cfg = await loadAcademyConfig();
    final snap = await _studentsRef.where('status', isEqualTo: 'active').get();

    // Pre-fetch the most recent promotion per student in one query, so the
    // per-student loop below doesn't trigger N progression reads.
    final progSnap = await _progressionsRef
        .where('sport', isEqualTo: sportId.value)
        .get();
    final baselineByStudent = <String, int>{};
    for (final p in progSnap.docs) {
      final bp = BeltProgression.fromFirestore(p);
      final existing = baselineByStudent[bp.studentId];
      // Keep the latest baseline only (sorted by promotionDate desc).
      if (existing == null) {
        baselineByStudent[bp.studentId] = bp.baselineCount;
      } else {
        // Re-evaluate: we sort the docs after collecting; here just keep
        // the highest baseline (last promotion has the biggest snapshot).
        baselineByStudent[bp.studentId] =
            bp.baselineCount > existing ? bp.baselineCount : existing;
      }
    }
    // Also include BJJ progressions without a sport field (legacy data).
    if (sportId == SportId.bjj) {
      final legacy = await _progressionsRef.get();
      for (final p in legacy.docs) {
        final data = p.data() as Map<String, dynamic>;
        if (data['sport'] != null) continue; // skip already-sport-tagged docs
        final bp = BeltProgression.fromFirestore(p);
        final existing = baselineByStudent[bp.studentId];
        if (existing == null || bp.baselineCount > existing) {
          baselineByStudent[bp.studentId] = bp.baselineCount;
        }
      }
    }

    final results = <EligibilitySnapshotEntry>[];
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;

      String currentBelt;
      int currentStripes;
      final sportData = (data['sportData'] as Map?)?[sportId.value];
      if (sportId == SportId.bjj && sportData == null) {
        currentBelt = data['currentBelt'] ?? 'white';
        currentStripes = data['currentStripes'] ?? 0;
      } else {
        currentBelt = sportData?['currentGrade'] ?? 'white';
        currentStripes = sportData?['currentStripes'] ?? 0;
      }
      final category = data['category'] ?? 'adult';

      int systemCount;
      if (cfg.useClassWeights) {
        systemCount = await getWeightedAttendanceCount(doc.id);
      } else {
        final ac = await _collections.attendance
            .where('studentId', isEqualTo: doc.id)
            .get();
        systemCount = ac.size;
      }
      final initial = (data['initialAttendanceCount'] ?? 0) as int;
      final total = systemCount + initial;
      final baseline = baselineByStudent[doc.id] ?? 0;
      final sinceLastPromotion = (total - baseline).clamp(0, total);

      final e = checkEligibility(
        currentBelt: currentBelt,
        currentStripes: currentStripes,
        totalClasses: sinceLastPromotion,
        sportId: sportId,
        category: category,
        config: cfg,
      );
      results.add(
        EligibilitySnapshotEntry(
          studentId: doc.id,
          eligible: e.eligible,
          currentClasses: e.currentClasses,
          requiredClasses: e.requiredClasses,
          missingClasses: e.missingClasses,
          weighted: e.weighted,
        ),
      );
    }
    return results;
  }

  // ============================================
  // Calculate Progress Percentage
  // ============================================
  double calculateProgress({
    required String currentBelt,
    required int currentStripes,
    required int totalClasses,
  }) {
    final requirements = stripeRequirements[currentBelt] ?? [0, 0, 0, 0];
    if (currentStripes >= requirements.length) return 1.0;

    final required = requirements[currentStripes];
    if (required == 0) return 0.0;

    return (totalClasses / required).clamp(0.0, 1.0);
  }

  // ============================================
  // Get Classes to Next Stripe
  // ============================================
  int getClassesToNextStripe({
    required String currentBelt,
    required int currentStripes,
    required int totalClasses,
  }) {
    final requirements = stripeRequirements[currentBelt] ?? [0, 0, 0, 0];
    if (currentStripes >= requirements.length) return 0;

    final required = requirements[currentStripes];
    return (required - totalClasses).clamp(0, required);
  }

  String _getBeltName(String belt, {SportId sportId = SportId.bjj}) {
    return getGradeLabel(sportId, belt);
  }

  // ============================================
  // Belt Label Helper (public, sport-aware)
  // ============================================
  String getBeltLabelFor(String belt, {SportId sportId = SportId.bjj}) => _getBeltName(belt, sportId: sportId);

  // ============================================
  // Belt Color Hex (sport-aware)
  // ============================================
  String getBeltColorHex(String belt, {SportId sportId = SportId.bjj}) {
    final color = getGradeColor(sportId, belt);
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  // ============================================
  // WRITE OPERATIONS
  // ============================================

  CollectionReference get _progressionsRef =>
      FirebaseService.firestore.collection('academies/$academyId/beltProgressions');

  CollectionReference get _studentsRef => _collections.students;
  CollectionReference get _achievementsRef => _collections.achievements;

  // ============================================
  // Get Progressions by Student
  // ============================================
  Future<List<BeltProgression>> getByStudent(String studentId) async {
    final query = await _progressionsRef
        .where('studentId', isEqualTo: studentId)
        .get();

    var progressions = query.docs.map((doc) => BeltProgression.fromFirestore(doc)).toList();
    progressions.sort((a, b) => b.promotionDate.compareTo(a.promotionDate));
    return progressions;
  }

  // ============================================
  // Get Progression by ID
  // ============================================
  Future<BeltProgression?> getById(String id) async {
    final doc = await _progressionsRef.doc(id).get();
    if (!doc.exists) return null;
    return BeltProgression.fromFirestore(doc);
  }

  // ============================================
  // Get Student Journey (timeline)
  // ============================================
  Future<Map<String, dynamic>> getStudentJourney(String studentId) async {
    final progressions = await getByStudent(studentId);

    // Get current student data
    final studentDoc = await _collections.student(studentId).get();
    final studentData = studentDoc.data() as Map<String, dynamic>?;

    return {
      'progressions': progressions,
      'currentBelt': studentData?['currentBelt'] ?? 'white',
      'currentStripes': studentData?['currentStripes'] ?? 0,
      'totalClasses': (studentData?['initialAttendanceCount'] ?? 0) +
          (studentData?['attendanceCount'] ?? 0),
    };
  }

  // ============================================
  // Promote Student (full promotion)
  // ============================================
  Future<BeltProgression> promote({
    required String studentId,
    required String studentName,
    required String newBelt,
    required int newStripes,
    required String promotedBy,
    required String promotedByName,
    String? notes,
    SportId sportId = SportId.bjj,
  }) async {
    // Get current student data
    final studentDoc = await _collections.student(studentId).get();
    final studentData = studentDoc.data() as Map<String, dynamic>;

    // Resolve current grade for this sport
    String currentBelt;
    int currentStripes;
    if (sportId == SportId.bjj && (studentData['sportData'] == null || (studentData['sportData'] as Map)['bjj'] == null)) {
      // Backward compat: use legacy fields
      currentBelt = studentData['currentBelt'] ?? 'white';
      currentStripes = studentData['currentStripes'] ?? 0;
    } else {
      final sd = (studentData['sportData'] as Map?)?[sportId.value];
      currentBelt = sd?['currentGrade'] ?? 'white';
      currentStripes = sd?['currentStripes'] ?? 0;
    }

    final totalClasses = (studentData['initialAttendanceCount'] ?? 0) +
        (studentData['attendanceCount'] ?? 0);

    // Snapshot the value that was compared against the academy threshold so
    // future checkEligibility calls can count "presenças desde a graduação"
    // instead of accumulating over the student's lifetime. When the academy
    // uses class weights, this is the weighted sum at promotion time.
    final config = await loadAcademyConfig();
    int effectiveCount;
    if (config.useClassWeights) {
      final systemCount = await getWeightedAttendanceCount(studentId);
      final initial = (studentData['initialAttendanceCount'] ?? 0) as int;
      effectiveCount = systemCount + initial;
    } else {
      effectiveCount = totalClasses;
    }

    final sportLabel = getSport(sportId).label;
    final gradeLabelStr = getGradeLabel(sportId, newBelt);

    // Create progression record
    final progressionRef = await _progressionsRef.add({
      'studentId': studentId,
      'previousBelt': currentBelt,
      'previousStripes': currentStripes,
      'newBelt': newBelt,
      'newStripes': newStripes,
      'promotionDate': FieldValue.serverTimestamp(),
      'totalClasses': totalClasses,
      'effectiveCountAtPromotion': effectiveCount,
      'promotedBy': promotedBy,
      'promotedByName': promotedByName,
      'notes': notes,
      'sport': sportId.value,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Update student — always update legacy fields for BJJ
    final updateData = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'sportData.${sportId.value}.currentGrade': newBelt,
      'sportData.${sportId.value}.currentStripes': newStripes,
    };
    if (sportId == SportId.bjj) {
      updateData['currentBelt'] = newBelt;
      updateData['currentStripes'] = newStripes;
    }
    await _collections.student(studentId).update(updateData);

    // Create achievement
    final isBeltChange = currentBelt != newBelt;
    await _achievementsRef.add({
      'studentId': studentId,
      'studentName': studentName,
      'type': isBeltChange ? 'graduation' : 'stripe',
      'title': isBeltChange
          ? 'Graduacao para $gradeLabelStr ($sportLabel)'
          : '$newStripes° Grau - $gradeLabelStr ($sportLabel)',
      'description': notes,
      'date': FieldValue.serverTimestamp(),
      'fromBelt': currentBelt,
      'toBelt': newBelt,
      'fromStripes': currentStripes,
      'toStripes': newStripes,
      'sport': sportId.value,
      'isPublic': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': promotedBy,
    });

    final doc = await progressionRef.get();
    return BeltProgression.fromFirestore(doc);
  }

  // ============================================
  // Add Stripe
  // ============================================
  Future<BeltProgression> addStripe({
    required String studentId,
    required String studentName,
    required String promotedBy,
    required String promotedByName,
    String? notes,
    SportId sportId = SportId.bjj,
    String category = 'adult',
  }) async {
    final studentDoc = await _collections.student(studentId).get();
    final studentData = studentDoc.data() as Map<String, dynamic>;

    // Resolve current grade for this sport
    String currentBelt;
    int currentStripes;
    if (sportId == SportId.bjj && (studentData['sportData'] == null || (studentData['sportData'] as Map)['bjj'] == null)) {
      currentBelt = studentData['currentBelt'] ?? 'white';
      currentStripes = studentData['currentStripes'] ?? 0;
    } else {
      final sd = (studentData['sportData'] as Map?)?[sportId.value];
      currentBelt = sd?['currentGrade'] ?? 'white';
      currentStripes = sd?['currentStripes'] ?? 0;
    }

    // Check max stripes for this sport/grade
    final gradeDef = getGradeDefinition(sportId, currentBelt);
    final maxStripes = gradeDef?.maxStripes ?? 4;

    if (currentStripes >= maxStripes) {
      throw Exception('Aluno já possui o máximo de graus. Use a promoção de faixa.');
    }

    return promote(
      studentId: studentId,
      studentName: studentName,
      newBelt: currentBelt,
      newStripes: currentStripes + 1,
      promotedBy: promotedBy,
      promotedByName: promotedByName,
      notes: notes,
      sportId: sportId,
    );
  }

  // ============================================
  // Change Belt
  // ============================================
  Future<BeltProgression> changeBelt({
    required String studentId,
    required String studentName,
    required String newBelt,
    required String promotedBy,
    required String promotedByName,
    String? notes,
    SportId sportId = SportId.bjj,
  }) async {
    return promote(
      studentId: studentId,
      studentName: studentName,
      newBelt: newBelt,
      newStripes: 0,
      promotedBy: promotedBy,
      promotedByName: promotedByName,
      notes: notes,
      sportId: sportId,
    );
  }

  // ============================================
  // Get Eligible Students
  // ============================================
  Future<List<Map<String, dynamic>>> getEligibleStudents() async {
    final snapshot = await _studentsRef.where('status', isEqualTo: 'active').get();
    final eligibleStudents = <Map<String, dynamic>>[];

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final currentBelt = data['currentBelt'] ?? 'white';
      final currentStripes = data['currentStripes'] ?? 0;
      final totalClasses = (data['initialAttendanceCount'] ?? 0) +
          (data['attendanceCount'] ?? 0);

      final eligibility = checkEligibility(
        currentBelt: currentBelt,
        currentStripes: currentStripes,
        totalClasses: totalClasses,
      );

      if (eligibility.eligible) {
        eligibleStudents.add({
          'id': doc.id,
          'fullName': data['fullName'],
          'currentBelt': currentBelt,
          'currentStripes': currentStripes,
          'totalClasses': totalClasses,
          'eligibility': eligibility,
        });
      }
    }

    return eligibleStudents;
  }

  // ============================================
  // Get Belt Distribution
  // ============================================
  Future<Map<String, int>> getBeltDistribution() async {
    final snapshot = await _studentsRef.where('status', isEqualTo: 'active').get();
    final distribution = <String, int>{};

    for (final belt in beltOrder) {
      distribution[belt] = 0;
    }

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final belt = data['currentBelt'] ?? 'white';
      distribution[belt] = (distribution[belt] ?? 0) + 1;
    }

    return distribution;
  }

  // ============================================
  // Get Recent Promotions
  // ============================================
  Future<List<BeltProgression>> getRecentPromotions({int limit = 10}) async {
    final snapshot = await _progressionsRef.get();
    var progressions = snapshot.docs.map((doc) => BeltProgression.fromFirestore(doc)).toList();
    progressions.sort((a, b) => b.promotionDate.compareTo(a.promotionDate));

    if (progressions.length > limit) {
      progressions = progressions.sublist(0, limit);
    }

    return progressions;
  }
}

// ============================================
// Factory Function
// ============================================
BeltProgressionService createBeltProgressionService(String academyId) {
  return BeltProgressionService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
BeltProgressionService get beltProgressionService =>
    BeltProgressionService(FirebaseService.academyId);
