import '../api/assessment_repo.dart';
import '../api/dto/student_dto.dart' as api;
import '../api/idempotency.dart';

/// Assessment Category
enum AssessmentCategory { respeito, disciplina, pontualidade, tecnica, esforco }

extension AssessmentCategoryExtension on AssessmentCategory {
  String get value {
    switch (this) {
      case AssessmentCategory.respeito:
        return 'respeito';
      case AssessmentCategory.disciplina:
        return 'disciplina';
      case AssessmentCategory.pontualidade:
        return 'pontualidade';
      case AssessmentCategory.tecnica:
        return 'tecnica';
      case AssessmentCategory.esforco:
        return 'esforco';
    }
  }

  String get label {
    switch (this) {
      case AssessmentCategory.respeito:
        return 'Respeito';
      case AssessmentCategory.disciplina:
        return 'Disciplina';
      case AssessmentCategory.pontualidade:
        return 'Pontualidade';
      case AssessmentCategory.tecnica:
        return 'Técnica';
      case AssessmentCategory.esforco:
        return 'Esforço';
    }
  }

  String get description {
    switch (this) {
      case AssessmentCategory.respeito:
        return 'Respeito aos colegas, professores e regras do tatame';
      case AssessmentCategory.disciplina:
        return 'Foco e atenção durante as aulas';
      case AssessmentCategory.pontualidade:
        return 'Chegada no horário e frequência';
      case AssessmentCategory.tecnica:
        return 'Evolução técnica e execução dos movimentos';
      case AssessmentCategory.esforco:
        return 'Dedicação e empenho durante os treinos';
    }
  }

  static AssessmentCategory fromString(String value) {
    switch (value) {
      case 'respeito':
        return AssessmentCategory.respeito;
      case 'disciplina':
        return AssessmentCategory.disciplina;
      case 'pontualidade':
        return AssessmentCategory.pontualidade;
      case 'tecnica':
        return AssessmentCategory.tecnica;
      case 'esforco':
        return AssessmentCategory.esforco;
      default:
        return AssessmentCategory.respeito;
    }
  }
}

/// Assessment Score Model
class AssessmentScore {
  final AssessmentCategory category;
  final int score; // 1-5

  AssessmentScore({required this.category, required this.score});

  factory AssessmentScore.fromMap(Map<String, dynamic> map) {
    return AssessmentScore(
      category: AssessmentCategoryExtension.fromString(map['category'] ?? 'respeito'),
      score: map['score'] ?? 3,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'category': category.value,
      'score': score,
    };
  }
}

/// Assessment Model
class Assessment {
  final String id;
  final String studentId;
  final String studentName;
  final DateTime date;
  final List<AssessmentScore> scores;
  final String? notes;
  final String assessedBy;
  final String assessedByName;
  final DateTime createdAt;

  Assessment({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.date,
    required this.scores,
    this.notes,
    required this.assessedBy,
    required this.assessedByName,
    required this.createdAt,
  });

  /// Adapter `ApiAssessment` → `Assessment` legacy.
  ///
  /// Notas:
  /// - `studentName`/`assessedByName` não vêm na resposta REST — default ''.
  /// - `scores` são derivados campo a campo de `ApiAssessmentScores`.
  factory Assessment.fromApi(api.ApiAssessment a) {
    final s = a.scores;
    return Assessment(
      id: a.id,
      studentId: a.studentId,
      studentName: '',
      date: a.date,
      scores: [
        AssessmentScore(category: AssessmentCategory.respeito, score: s.respeito),
        AssessmentScore(category: AssessmentCategory.disciplina, score: s.disciplina),
        AssessmentScore(category: AssessmentCategory.pontualidade, score: s.pontualidade),
        AssessmentScore(category: AssessmentCategory.tecnica, score: s.tecnica),
        AssessmentScore(category: AssessmentCategory.esforco, score: s.esforco),
      ],
      notes: a.notes,
      assessedBy: a.evaluatedByUid,
      assessedByName: '',
      createdAt: a.createdAt ?? a.date,
    );
  }

  // Computed properties
  double get averageScore {
    if (scores.isEmpty) return 0;
    final total = scores.fold<int>(0, (acc, s) => acc + s.score);
    return total / scores.length;
  }

  int? getScoreForCategory(AssessmentCategory category) {
    final score = scores.where((s) => s.category == category).firstOrNull;
    return score?.score;
  }
}

/// Assessment Service — wraps [AssessmentRemoteRepo] with the legacy
/// interface expected by screens. All Firestore calls have been removed.
class AssessmentService {
  final String academyId;
  final AssessmentRemoteRepo _repo;

  AssessmentService(this.academyId, this._repo);

  // ============================================
  // Get Assessments by Student
  // ============================================
  Future<List<Assessment>> getByStudent(String studentId, {int? limit}) async {
    final page = await _repo.getByStudent(
      academyId,
      studentId,
      limit: limit ?? 50,
    );
    return page.items.map(Assessment.fromApi).toList();
  }

  // ============================================
  // Get Latest Assessment
  // ============================================
  Future<Assessment?> getLatest(String studentId) async {
    final assessments = await getByStudent(studentId, limit: 1);
    return assessments.isNotEmpty ? assessments.first : null;
  }

  // ============================================
  // Get Assessment by ID
  // ============================================
  /// Fetches the full list and returns the matching item.
  /// The REST API does not expose a single-item GET for assessments, so we
  /// load the first page (limit 50) and search locally.
  Future<Assessment?> getById(String studentId, String id) async {
    final assessments = await getByStudent(studentId, limit: 50);
    return assessments.where((a) => a.id == id).firstOrNull;
  }

  // ============================================
  // Get Average Scores by Category
  // ============================================
  Future<Map<AssessmentCategory, double>> getAveragesByCategory(String studentId) async {
    final assessments = await getByStudent(studentId);
    if (assessments.isEmpty) {
      return {
        AssessmentCategory.respeito: 0,
        AssessmentCategory.disciplina: 0,
        AssessmentCategory.pontualidade: 0,
        AssessmentCategory.tecnica: 0,
        AssessmentCategory.esforco: 0,
      };
    }

    final totals = <AssessmentCategory, int>{};
    final counts = <AssessmentCategory, int>{};

    for (final assessment in assessments) {
      for (final score in assessment.scores) {
        totals[score.category] = (totals[score.category] ?? 0) + score.score;
        counts[score.category] = (counts[score.category] ?? 0) + 1;
      }
    }

    return {
      for (final category in AssessmentCategory.values)
        category: counts[category] != null && counts[category]! > 0
            ? totals[category]! / counts[category]!
            : 0,
    };
  }

  // ============================================
  // Get Overall Average
  // ============================================
  Future<double> getOverallAverage(String studentId) async {
    final averages = await getAveragesByCategory(studentId);
    final nonZero = averages.values.where((v) => v > 0).toList();
    if (nonZero.isEmpty) return 0;
    return nonZero.reduce((a, b) => a + b) / nonZero.length;
  }

  // ============================================
  // Get Assessments by Date Range
  // ============================================
  Future<List<Assessment>> getByDateRange(
    String studentId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final assessments = await getByStudent(studentId);
    return assessments.where((a) =>
        a.date.isAfter(startDate.subtract(const Duration(days: 1))) &&
        a.date.isBefore(endDate.add(const Duration(days: 1)))
    ).toList();
  }

  // ============================================
  // Get Recent Assessments (all students)
  // ============================================
  /// NOTE: The Tatami API requires a studentId — there is no academy-wide
  /// "recent assessments" endpoint. This method is kept for API compatibility
  /// but returns an empty list. Callers that need per-student recents should
  /// call [getByStudent] directly.
  Future<List<Assessment>> getRecent({int limit = 10}) async {
    return const [];
  }

  // ============================================
  // Get Evolution Data (for charts)
  // ============================================
  Future<Map<String, dynamic>> getEvolution(String studentId, {int count = 5}) async {
    final assessments = await getByStudent(studentId, limit: count);
    if (assessments.isEmpty) {
      return {
        'labels': <String>[],
        'datasets': <Map<String, dynamic>>[],
        'averages': <String, double>{},
      };
    }

    final labels = AssessmentCategory.values.map((c) => c.label).toList();
    final datasets = <Map<String, dynamic>>[];
    final averages = <String, double>{};

    for (final assessment in assessments.reversed) {
      final scores = <String, int>{};
      for (final score in assessment.scores) {
        scores[score.category.value] = score.score;
      }
      datasets.add({
        'date': assessment.date.toIso8601String(),
        'scores': scores,
      });
    }

    // Calculate averages
    for (final category in AssessmentCategory.values) {
      final categoryScores = assessments
          .expand((a) => a.scores)
          .where((s) => s.category == category)
          .map((s) => s.score);
      if (categoryScores.isNotEmpty) {
        averages[category.value] = categoryScores.reduce((a, b) => a + b) / categoryScores.length;
      }
    }

    return {
      'labels': labels,
      'datasets': datasets,
      'averages': averages,
    };
  }

  // ============================================
  // Calculate Overall Score
  // ============================================
  double calculateOverallScore(List<AssessmentScore> scores) {
    if (scores.isEmpty) return 0;
    final total = scores.fold<int>(0, (acc, s) => acc + s.score);
    return total / scores.length;
  }

  // ============================================
  // Get Performance Level
  // ============================================
  Map<String, String> getPerformanceLevel(double overallScore) {
    if (overallScore >= 4.5) {
      return {'level': 'excelente', 'label': 'Excelente', 'color': '#22c55e'};
    } else if (overallScore >= 4) {
      return {'level': 'muito_bom', 'label': 'Muito Bom', 'color': '#84cc16'};
    } else if (overallScore >= 3) {
      return {'level': 'bom', 'label': 'Bom', 'color': '#eab308'};
    } else if (overallScore >= 2) {
      return {'level': 'regular', 'label': 'Regular', 'color': '#f97316'};
    } else {
      return {'level': 'precisa_melhorar', 'label': 'Precisa Melhorar', 'color': '#ef4444'};
    }
  }

  // ============================================
  // WRITE OPERATIONS
  // ============================================

  // ============================================
  // Create Assessment
  // ============================================
  Future<Assessment> create({
    required String studentId,
    required String studentName,
    required List<AssessmentScore> scores,
    required String assessedBy,
    required String assessedByName,
    DateTime? date,
    String? notes,
    IdempotencyKey? idempotencyKey,
  }) async {
    final req = api.CreateAssessmentRequest(
      date: date ?? DateTime.now(),
      notes: notes,
      scores: api.ApiAssessmentScores(
        respeito: scores.firstWhere((s) => s.category == AssessmentCategory.respeito, orElse: () => AssessmentScore(category: AssessmentCategory.respeito, score: 3)).score,
        disciplina: scores.firstWhere((s) => s.category == AssessmentCategory.disciplina, orElse: () => AssessmentScore(category: AssessmentCategory.disciplina, score: 3)).score,
        pontualidade: scores.firstWhere((s) => s.category == AssessmentCategory.pontualidade, orElse: () => AssessmentScore(category: AssessmentCategory.pontualidade, score: 3)).score,
        tecnica: scores.firstWhere((s) => s.category == AssessmentCategory.tecnica, orElse: () => AssessmentScore(category: AssessmentCategory.tecnica, score: 3)).score,
        esforco: scores.firstWhere((s) => s.category == AssessmentCategory.esforco, orElse: () => AssessmentScore(category: AssessmentCategory.esforco, score: 3)).score,
      ),
    );

    final apiAssessment = await _repo.create(
      academyId,
      studentId,
      req,
      idempotencyKey: idempotencyKey,
    );
    return Assessment.fromApi(apiAssessment);
  }

  // ============================================
  // Update Assessment
  // ============================================
  Future<Assessment> update(
    String studentId,
    String assessmentId,
    Map<String, dynamic> data,
  ) async {
    final apiAssessment = await _repo.update(
      academyId,
      studentId,
      assessmentId,
      data,
    );
    return Assessment.fromApi(apiAssessment);
  }

  // ============================================
  // Delete Assessment
  // ============================================
  Future<void> delete(String studentId, String assessmentId) async {
    await _repo.delete(academyId, studentId, assessmentId);
  }
}

// ============================================
// Factory Function
// ============================================
AssessmentService createAssessmentService(
  String academyId,
  AssessmentRemoteRepo repo,
) {
  return AssessmentService(academyId, repo);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
/// NOTE: This getter requires a repo instance and cannot be used as a simple
/// top-level getter anymore. Callers should use [assessmentRepoProvider] +
/// [createAssessmentService] or access [assessmentRepoProvider] directly.
///
/// Kept for source compatibility — throws if called; migrate to
/// ref.read(assessmentRepoProvider).
AssessmentService get assessmentService =>
    throw UnsupportedError(
      'assessmentService getter removed — use assessmentRepoProvider via Riverpod '
      'or pass AssessmentRemoteRepo explicitly to createAssessmentService().',
    );
