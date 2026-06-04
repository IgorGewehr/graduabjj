import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/graduation_factors.dart';
import '../core/sports.dart';
import 'firebase_service.dart';
import 'skill_progress_service.dart';
import 'syllabus_service.dart';

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
  /// Per-sport, per-belt requirements: sportValue → {gradeId → classes}.
  /// Takes precedence over [threshold] when an entry exists for the
  /// student's sport + current belt.
  final Map<String, Map<String, int>> requirementsBySport;
  /// Política das técnicas do currículo (B2): 'informative' | 'required'.
  final String skillPolicy;
  /// % mínimo de técnicas dominadas quando [skillPolicy] == 'required'.
  final int minSkillPct;

  const AcademyGraduationConfig({
    this.threshold,
    this.useClassWeights = false,
    this.requirementsBySport = const {},
    this.skillPolicy = 'informative',
    this.minSkillPct = 80,
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

  // Requisitos compostos (B2). Preenchidos por checkEligibilityForStudent;
  // nulos no caminho puro (checkEligibility só usa presença).
  /// Técnicas dominadas / total cadastradas para a faixa atual (null = sem dado).
  final int? skillDone;
  final int? skillTotal;
  /// % dominado (0–100), ou null quando não há currículo.
  final double? skillPct;
  /// A política exige técnicas (`required`).
  final bool skillRequired;
  /// Requisito de técnicas atendido (true quando informativo ou sem currículo).
  final bool skillMet;
  /// Tempo-em-faixa em dias (informativo). Null se indeterminado.
  final int? daysInBelt;

  EligibilityResult({
    required this.eligible,
    this.nextBelt,
    this.nextStripes,
    required this.currentClasses,
    required this.requiredClasses,
    required this.missingClasses,
    required this.message,
    this.weighted = false,
    this.skillDone,
    this.skillTotal,
    this.skillPct,
    this.skillRequired = false,
    this.skillMet = true,
    this.daysInBelt,
  });

  EligibilityResult copyWith({
    bool? eligible,
    String? message,
    int? skillDone,
    int? skillTotal,
    double? skillPct,
    bool? skillRequired,
    bool? skillMet,
    int? daysInBelt,
  }) {
    return EligibilityResult(
      eligible: eligible ?? this.eligible,
      nextBelt: nextBelt,
      nextStripes: nextStripes,
      currentClasses: currentClasses,
      requiredClasses: requiredClasses,
      missingClasses: missingClasses,
      message: message ?? this.message,
      weighted: weighted,
      skillDone: skillDone ?? this.skillDone,
      skillTotal: skillTotal ?? this.skillTotal,
      skillPct: skillPct ?? this.skillPct,
      skillRequired: skillRequired ?? this.skillRequired,
      skillMet: skillMet ?? this.skillMet,
      daysInBelt: daysInBelt ?? this.daysInBelt,
    );
  }
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

    final grades = getGradesForSport(
      sportId,
      category: category,
      muaythaiVariant:
          sportId == SportId.muaythai ? resolveMuaythaiVariant(currentBelt) : null,
    );
    if (grades.isEmpty) return null;

    final currentGrade = grades.where((g) => g.id == currentBelt).firstOrNull;
    // Coral/red are above black — never reached automatically (manual only).
    if (currentGrade?.aboveBlack == true) return null;
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
      final nextGrade = grades[currentIndex + 1];
      // Don't auto-advance into above-black master ranks (coral/red).
      if (nextGrade.aboveBlack) return null;
      return {
        'belt': nextGrade.id,
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
    final perBelt = cfg.requirementsBySport[sportId.value]?[currentBelt];
    if (perBelt != null && perBelt > 0) {
      // Per-sport, per-belt configured requirement (applies to every degree
      // within the belt).
      requiredClasses = perBelt;
    } else if (cfg.threshold != null && cfg.threshold! > 0) {
      // Single global threshold for any belt/stripe transition.
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
        requirementsBySport:
            _parseRequirementsBySport(data['graduationRequirementsBySport']),
        skillPolicy:
            (data['graduationSkillPolicy'] as String?) ?? 'informative',
        minSkillPct: (data['graduationMinSkillPct'] as num?)?.toInt() ?? 80,
      );
    } catch (_) {
      return const AcademyGraduationConfig();
    }
  }

  /// Parses the nested {sportValue: {gradeId: classes}} map, dropping
  /// non-positive entries. Mirrors AcademySettings._parseRequirementsBySport.
  static Map<String, Map<String, int>> _parseRequirementsBySport(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, Map<String, int>>{};
    raw.forEach((sport, belts) {
      if (belts is Map) {
        final byBelt = <String, int>{};
        belts.forEach((belt, n) {
          if (n is num && n > 0) byBelt[belt.toString()] = n.toInt();
        });
        if (byBelt.isNotEmpty) out[sport.toString()] = byBelt;
      }
    });
    return out;
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

  /// Fatores de técnica (B2) da [gradeId] de [studentId] em [sportId]: lê o
  /// currículo da faixa + o progresso do aluno e aplica a política da academia.
  Future<GraduationSkillFactors> _skillFactorsForGrade(
    String studentId,
    SportId sportId,
    String gradeId,
    AcademyGraduationConfig cfg, {
    List<SyllabusTechnique>? techniquesHint,
  }) async {
    final techniques = techniquesHint ??
        await SyllabusService(academyId).getBySport(sportId.value);
    final gradeTechs = techniques.where((t) => t.gradeId == gradeId).toList();
    final progress = await SkillProgressService(academyId)
        .getByStudent(studentId, sport: sportId.value);
    final progMap = {for (final p in progress) p.techniqueId: p};
    final dominated = gradeTechs
        .where((t) => progMap[t.id]?.level.isMastered ?? false)
        .length;
    return computeSkillFactors(
      dominatedCount: dominated,
      totalForGrade: gradeTechs.length,
      policy: cfg.skillPolicy,
      minSkillPct: cfg.minSkillPct,
    );
  }

  /// Sums Attendance.weight (defaulting to 1 for legacy docs) for a student,
  /// filtered to [sportId] so a multi-sport student's progress isn't padded by
  /// other modalities (e.g. Muay Thai aulas must not count for BJJ). Legacy
  /// docs without a `sport` field are treated as BJJ for back-compat, mirroring
  /// the unweighted branch. Use when [AcademyGraduationConfig.useClassWeights]
  /// is true.
  Future<int> getWeightedAttendanceCount(
    String studentId, {
    required SportId sportId,
  }) async {
    final snap = await _collections.attendance
        .where('studentId', isEqualTo: studentId)
        .get();
    double total = 0;
    for (final d in snap.docs) {
      final data = d.data() as Map<String, dynamic>;
      final s = data['sport'];
      final matches = sportId == SportId.bjj
          ? (s == null || s == 'bjj')
          : (s == sportId.value);
      if (!matches) continue;
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
    // Attendances are filtered by sport so graduation in one modality doesn't
    // get padded by attendances of another (e.g. Muay Thai aulas don't count
    // for BJJ graduation). Legacy attendances without `sport` are treated as
    // BJJ for back-compat.
    int systemCount;
    if (cfg.useClassWeights) {
      systemCount = await getWeightedAttendanceCount(studentId, sportId: sportId);
    } else {
      Query attendQuery = _collections.attendance
          .where('studentId', isEqualTo: studentId);
      if (sportId == SportId.bjj) {
        // Include legacy docs without a sport field: query both 'bjj' and
        // null variants by counting in two queries.
        final bjjSnap = await attendQuery
            .where('sport', isEqualTo: 'bjj')
            .get();
        final legacySnap = await attendQuery
            .where('sport', isNull: true)
            .get();
        systemCount = bjjSnap.size + legacySnap.size;
      } else {
        final snap = await attendQuery
            .where('sport', isEqualTo: sportId.value)
            .get();
        systemCount = snap.size;
      }
    }
    final initial = (data['initialAttendanceCount'] ?? 0) as int;
    final totalClasses = systemCount + initial;

    // Subtract the snapshot at the last promotion so we count only
    // attendances accumulated *since* that promotion. The mestre may have
    // chosen to wait past the threshold (e.g. promoted at 82 with target 75)
    // — those 7 extra do NOT carry over to the next graduation.
    // Progressões (uma leitura) → baseline + data da última promoção no esporte.
    final progressions = await getByStudent(studentId);
    final forSport = progressions
        .where((p) => p.getSport() == sportId)
        .toList()
      ..sort((a, b) => b.promotionDate.compareTo(a.promotionDate));
    final baseline = forSport.isEmpty ? 0 : forSport.first.baselineCount;
    final lastPromoDate =
        forSport.isEmpty ? null : forSport.first.promotionDate;
    final sinceLastPromotion = (totalClasses - baseline).clamp(0, totalClasses);

    final base = checkEligibility(
      currentBelt: currentBelt,
      currentStripes: currentStripes,
      totalClasses: sinceLastPromotion,
      sportId: sportId,
      category: category,
      config: cfg,
    );

    // Requisitos compostos (B2): % de técnicas dominadas na faixa atual +
    // tempo-em-faixa. Bloqueia a elegibilidade só quando a política é 'required'.
    final factors = await _skillFactorsForGrade(studentId, sportId, currentBelt, cfg);
    final days = daysInBelt(
      lastPromotion: lastPromoDate,
      startDate: (data['startDate'] as Timestamp?)?.toDate(),
      now: DateTime.now(),
    );

    // Bloqueado por técnica = elegível por presença, mas política exige e não atingiu.
    final blockedBySkill = base.eligible && !factors.met;
    return base.copyWith(
      eligible: base.eligible && factors.met,
      message: blockedBySkill
          ? 'Faltam técnicas: ${factors.done}/${factors.total} dominadas '
              '(mín. ${cfg.minSkillPct}%)'
          : base.message,
      skillDone: factors.done,
      skillTotal: factors.total,
      skillPct: factors.pct,
      skillRequired: factors.required,
      skillMet: factors.met,
      daysInBelt: days,
    );
  }

  /// Batch helper: loads the config once, then resolves eligibility for every
  /// active student — each evaluated against THEIR OWN primary sport, not a
  /// single global sport. Students whose primary sport has no graduation ladder
  /// (e.g. musculação, boxe) get an empty entry (requiredClasses == 0) so the
  /// list renders no progress/badge for them. Used by the admin students list.
  Future<List<EligibilitySnapshotEntry>> getEligibilitySnapshot() async {
    final cfg = await loadAcademyConfig();
    // Cache de currículo por modalidade (só usado sob política 'required').
    final sylCache = <String, List<SyllabusTechnique>>{};
    final snap = await _studentsRef.where('status', isEqualTo: 'active').get();

    // Pre-fetch ALL promotions once, then index the latest baseline per
    // (student, sport) so the per-student loop doesn't trigger N reads.
    // Legacy progressions without a `sport` field are treated as BJJ.
    final progSnap = await _progressionsRef.get();
    final latestPromotion =
        <String, Map<String, ({DateTime date, int baseline})>>{};
    for (final p in progSnap.docs) {
      final bp = BeltProgression.fromFirestore(p);
      final sportVal = bp.sport ?? 'bjj';
      final bySport = latestPromotion.putIfAbsent(bp.studentId, () => {});
      final existing = bySport[sportVal];
      if (existing == null || bp.promotionDate.isAfter(existing.date)) {
        bySport[sportVal] = (date: bp.promotionDate, baseline: bp.baselineCount);
      }
    }

    final results = <EligibilitySnapshotEntry>[];
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final sportId = _primarySportFromData(data);

      // Sports without a graduation ladder never graduate — emit an empty
      // entry so the card shows no progress/badge for them.
      if (getSport(sportId).gradeSystem == GradeSystem.none) {
        results.add(EligibilitySnapshotEntry(
          studentId: doc.id,
          eligible: false,
          currentClasses: 0,
          requiredClasses: 0,
          missingClasses: 0,
          weighted: cfg.useClassWeights,
        ));
        continue;
      }

      // Current grade for the student's sport (legacy fields for BJJ).
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

      // Attendance count filtered to the student's sport (legacy null = BJJ),
      // matching checkEligibilityForStudent so the list and detail agree.
      int systemCount;
      if (cfg.useClassWeights) {
        systemCount = await getWeightedAttendanceCount(doc.id, sportId: sportId);
      } else {
        final ac = await _collections.attendance
            .where('studentId', isEqualTo: doc.id)
            .get();
        systemCount = ac.docs.where((d) {
          final s = (d.data() as Map<String, dynamic>)['sport'];
          return sportId == SportId.bjj
              ? (s == null || s == 'bjj')
              : s == sportId.value;
        }).length;
      }
      final initial = (data['initialAttendanceCount'] ?? 0) as int;
      final total = systemCount + initial;
      final baseline = latestPromotion[doc.id]?[sportId.value]?.baseline ?? 0;
      final sinceLastPromotion = (total - baseline).clamp(0, total);

      final e = checkEligibility(
        currentBelt: currentBelt,
        currentStripes: currentStripes,
        totalClasses: sinceLastPromotion,
        sportId: sportId,
        category: category,
        config: cfg,
      );
      // Política 'required': um aluno elegível por presença ainda precisa do
      // % mínimo de técnicas — alinha a lista ao detalhe e à auto-promoção.
      // O currículo por modalidade é lido uma vez e reaproveitado (cache).
      var eligible = e.eligible;
      if (eligible && cfg.skillPolicy == graduationSkillRequired) {
        sylCache[sportId.value] ??=
            await SyllabusService(academyId).getBySport(sportId.value);
        final f = await _skillFactorsForGrade(doc.id, sportId, currentBelt, cfg,
            techniquesHint: sylCache[sportId.value]);
        eligible = f.met;
      }
      results.add(
        EligibilitySnapshotEntry(
          studentId: doc.id,
          eligible: eligible,
          currentClasses: e.currentClasses,
          requiredClasses: e.requiredClasses,
          missingClasses: e.missingClasses,
          weighted: e.weighted,
        ),
      );
    }
    return results;
  }

  /// Resolves a student's primary sport from a raw Firestore doc map, mirroring
  /// Student.getPrimarySport(): `primarySport` field, else first of `sports`,
  /// else BJJ (back-compat for docs predating multi-sport).
  SportId _primarySportFromData(Map<String, dynamic> data) {
    final primary = data['primarySport'];
    if (primary is String && primary.isNotEmpty) {
      return SportId.fromString(primary);
    }
    final list = data['sports'];
    if (list is List && list.isNotEmpty) {
      return SportId.fromString(list.first.toString());
    }
    return SportId.bjj;
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
      final systemCount = await getWeightedAttendanceCount(studentId, sportId: sportId);
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
    final cfg = await loadAcademyConfig();
    final sylCache = <String, List<SyllabusTechnique>>{};

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      // Modalidade primária + faixa NAQUELE esporte (mesma regra do
      // Student.getGrade): pra não-BJJ a faixa vive em sportData; senão é a
      // legada currentBelt. Antes a elegibilidade era checada sempre como BJJ.
      final sportVal = (data['primarySport'] as String?) ??
          ((data['sports'] is List && (data['sports'] as List).isNotEmpty)
              ? (data['sports'] as List).first.toString()
              : 'bjj');
      final sportId = SportId.fromString(sportVal);
      final category = (data['category'] as String?) ?? 'adult';
      final sportData = (data['sportData'] as Map?)?[sportVal] as Map?;
      final useSportData = !(sportId == SportId.bjj && sportData == null);
      final beltFromSport =
          sportData == null ? null : sportData['currentGrade'];
      final stripesFromSport =
          sportData == null ? null : sportData['currentStripes'];
      final currentBelt = (useSportData ? beltFromSport : data['currentBelt']) ??
          data['currentBelt'] ??
          'white';
      final currentStripes =
          (useSportData ? stripesFromSport : data['currentStripes']) ??
              data['currentStripes'] ??
              0;
      final totalClasses = (data['initialAttendanceCount'] ?? 0) +
          (data['attendanceCount'] ?? 0);

      final eligibility = checkEligibility(
        currentBelt: currentBelt,
        currentStripes: currentStripes,
        totalClasses: totalClasses,
        sportId: sportId,
        category: category,
      );

      var isEligible = eligibility.eligible;
      // Política 'required': exige o % mínimo de técnicas além da presença.
      if (isEligible && cfg.skillPolicy == graduationSkillRequired) {
        sylCache[sportId.value] ??=
            await SyllabusService(academyId).getBySport(sportId.value);
        final f = await _skillFactorsForGrade(doc.id, sportId, currentBelt, cfg,
            techniquesHint: sylCache[sportId.value]);
        isEligible = f.met;
      }

      if (isEligible) {
        eligibleStudents.add({
          'id': doc.id,
          'fullName': data['fullName'],
          'currentBelt': currentBelt,
          'currentStripes': currentStripes,
          'totalClasses': totalClasses,
          'eligibility': eligibility,
          'sportId': sportVal,
          // Para notificar o aluno ("apto a graduar"); null se sem conta vinculada.
          'linkedUserId': data['linkedUserId'],
        });
      }
    }

    return eligibleStudents;
  }

  // ============================================
  // Get Belt Distribution
  // ============================================
  /// Distribuição de faixas SEGMENTADA por esporte: {sportValue: {beltId: count}}.
  /// Cada aluno entra na sua modalidade primária, com a faixa daquele esporte
  /// (sportData) — pra academia multi-esporte não misturar faixas de BJJ com
  /// braçadeiras de Muay Thai etc. num histograma só.
  Future<Map<String, Map<String, int>>> getBeltDistribution() async {
    final snapshot = await _studentsRef.where('status', isEqualTo: 'active').get();
    final bySport = <String, Map<String, int>>{};

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final sportVal = (data['primarySport'] as String?) ??
          ((data['sports'] is List && (data['sports'] as List).isNotEmpty)
              ? (data['sports'] as List).first.toString()
              : 'bjj');
      final sportData = (data['sportData'] as Map?)?[sportVal] as Map?;
      final useSportData = !(sportVal == 'bjj' && sportData == null);
      final beltFromSport =
          sportData == null ? null : sportData['currentGrade'];
      final belt = ((useSportData ? beltFromSport : data['currentBelt']) ??
          data['currentBelt'] ??
          'white') as String;
      final m = bySport[sportVal] ??= <String, int>{};
      m[belt] = (m[belt] ?? 0) + 1;
    }

    return bySport;
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
