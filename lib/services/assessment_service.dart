import 'package:cloud_firestore/cloud_firestore.dart';

import '../api/dto/student_dto.dart' as api;
import 'firebase_service.dart';

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

  factory Assessment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse scores from both formats:
    // Object format (web): {respeito: 4, disciplina: 3, ...}
    // Array format (legacy Flutter): [{category: 'respeito', score: 4}, ...]
    List<AssessmentScore> scoresList;
    final rawScores = data['scores'];
    if (rawScores is List) {
      scoresList = rawScores
          .map((s) => AssessmentScore.fromMap(s as Map<String, dynamic>))
          .toList();
    } else if (rawScores is Map) {
      scoresList = AssessmentCategory.values.map((cat) {
        final value = rawScores[cat.value];
        return AssessmentScore(
          category: cat,
          score: (value is num) ? value.toInt() : 3,
        );
      }).toList();
    } else {
      scoresList = [];
    }

    return Assessment(
      id: doc.id,
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      scores: scoresList,
      notes: data['notes'],
      assessedBy: data['evaluatedBy'] ?? data['assessedBy'] ?? '',
      assessedByName: data['evaluatedByName'] ?? data['assessedByName'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

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

/// Assessment Service - Multi-tenant assessment management
class AssessmentService {
  final String academyId;
  late final Collections _collections;

  AssessmentService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _assessmentsRef => _collections.assessments;

  // ============================================
  // Get Assessments by Student
  // ============================================
  Future<List<Assessment>> getByStudent(String studentId, {int? limit}) async {
    final query = await _assessmentsRef
        .where('studentId', isEqualTo: studentId)
        .get();

    var assessments = query.docs.map((doc) => Assessment.fromFirestore(doc)).toList();
    assessments.sort((a, b) => b.date.compareTo(a.date));

    if (limit != null && assessments.length > limit) {
      assessments = assessments.sublist(0, limit);
    }

    return assessments;
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
  Future<Assessment?> getById(String id) async {
    final doc = await _collections.assessment(id).get();
    if (!doc.exists) return null;
    return Assessment.fromFirestore(doc);
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
  Future<List<Assessment>> getRecent({int limit = 10}) async {
    final snapshot = await _assessmentsRef.get();
    var assessments = snapshot.docs.map((doc) => Assessment.fromFirestore(doc)).toList();
    assessments.sort((a, b) => b.date.compareTo(a.date));
    if (assessments.length > limit) {
      assessments = assessments.sublist(0, limit);
    }
    return assessments;
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
  }) async {
    // Store scores as object format for cross-app compatibility
    final scoresMap = <String, int>{};
    for (final s in scores) {
      scoresMap[s.category.value] = s.score;
    }

    final docRef = await _assessmentsRef.add({
      'studentId': studentId,
      'studentName': studentName,
      'date': Timestamp.fromDate(date ?? DateTime.now()),
      'scores': scoresMap,
      'notes': notes,
      'evaluatedBy': assessedBy,
      'evaluatedByName': assessedByName,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final doc = await docRef.get();
    return Assessment.fromFirestore(doc);
  }

  // ============================================
  // Update Assessment
  // ============================================
  Future<Assessment> update(String id, Map<String, dynamic> data) async {
    await _collections.assessment(id).update(data);
    final updated = await getById(id);
    return updated!;
  }

  // ============================================
  // Delete Assessment
  // ============================================
  Future<void> delete(String id) async {
    await _collections.assessment(id).delete();
  }
}

// ============================================
// Factory Function
// ============================================
AssessmentService createAssessmentService(String academyId) {
  return AssessmentService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
AssessmentService get assessmentService => AssessmentService(FirebaseService.academyId);
