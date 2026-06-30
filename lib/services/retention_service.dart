import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/student.dart';

/// Risk level classification
enum RiskLevel { low, medium, high, critical }

extension RiskLevelExtension on RiskLevel {
  String get label {
    switch (this) {
      case RiskLevel.low:
        return 'Baixo';
      case RiskLevel.medium:
        return 'Medio';
      case RiskLevel.high:
        return 'Alto';
      case RiskLevel.critical:
        return 'Critico';
    }
  }

  String get value {
    switch (this) {
      case RiskLevel.low:
        return 'low';
      case RiskLevel.medium:
        return 'medium';
      case RiskLevel.high:
        return 'high';
      case RiskLevel.critical:
        return 'critical';
    }
  }

  static RiskLevel fromString(String value) {
    switch (value) {
      case 'low':
        return RiskLevel.low;
      case 'medium':
        return RiskLevel.medium;
      case 'high':
        return RiskLevel.high;
      case 'critical':
        return RiskLevel.critical;
      default:
        return RiskLevel.low;
    }
  }
}

/// Auditoria (MED / produto): nível de consequência por inadimplência.
/// SEGURO POR PADRÃO — o máximo automático é 'warn' (apenas aviso). 'restrict'
/// NUNCA é aplicado automaticamente; só existe como rótulo para que produto
/// decida, futuramente e de forma explícita, plugar bloqueios. NENHUM consumidor
/// deste serviço deve negar check-in/reserva/acesso só por causa deste valor.
enum DelinquencyConsequence { none, warn, restrict }

extension DelinquencyConsequenceExtension on DelinquencyConsequence {
  String get value {
    switch (this) {
      case DelinquencyConsequence.none:
        return 'none';
      case DelinquencyConsequence.warn:
        return 'warn';
      case DelinquencyConsequence.restrict:
        return 'restrict';
    }
  }

  String get label {
    switch (this) {
      case DelinquencyConsequence.none:
        return 'Sem consequencia';
      case DelinquencyConsequence.warn:
        return 'Aviso';
      case DelinquencyConsequence.restrict:
        return 'Restricao';
    }
  }
}

/// Política de consequência por academia. SEGURA POR PADRÃO:
/// - [warnAfterDays]: a partir de quantos dias de atraso exibir um aviso.
/// - [restrictAfterDays]: a partir de quantos dias de atraso *seria* aplicada a
///   restrição — porém só tem efeito quando [allowAutoRestrict] for true
///   (default false). Enquanto false, o helper jamais retorna 'restrict'.
/// NOTA DE REVISÃO: habilitar [allowAutoRestrict] é decisão de produto e exige
/// wire-up explícito nas telas de check-in/reserva (outros arquivos/grupos).
class DelinquencyPolicy {
  final int warnAfterDays;
  final int restrictAfterDays;
  final bool allowAutoRestrict;

  const DelinquencyPolicy({
    this.warnAfterDays = 1,
    this.restrictAfterDays = 30,
    this.allowAutoRestrict = false, // seguro por padrão: nunca restringe sozinho
  });

  /// Constrói a política a partir do map de config da academia (ex.: doc da
  /// academia em Firestore). Campos ausentes caem no default seguro.
  factory DelinquencyPolicy.fromMap(Map<String, dynamic>? config) {
    if (config == null) return const DelinquencyPolicy();
    int asInt(dynamic v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    return DelinquencyPolicy(
      warnAfterDays: asInt(config['delinquencyWarnAfterDays'], 1),
      restrictAfterDays: asInt(config['delinquencyRestrictAfterDays'], 30),
      // só restringe se a academia EXPLICITAMENTE ligou a flag.
      allowAutoRestrict: config['delinquencyAllowAutoRestrict'] == true,
    );
  }
}

/// Risk Factor - a single factor contributing to a student's risk score
class RiskFactor {
  final String name;
  final String description;
  final int weight;
  final int score;
  final String details;

  RiskFactor({
    required this.name,
    required this.description,
    required this.weight,
    required this.score,
    required this.details,
  });
}

/// Student Risk Score - computed risk assessment for a single student
class StudentRiskScore {
  final String studentId;
  final String studentName;
  final int score;
  final RiskLevel level;
  final List<RiskFactor> factors;
  final DateTime? lastAttendance;
  final int daysSinceLastAttendance;
  final int overduePayments;
  final double attendanceTrend;
  final int monthsAtAcademy;

  StudentRiskScore({
    required this.studentId,
    required this.studentName,
    required this.score,
    required this.level,
    required this.factors,
    this.lastAttendance,
    required this.daysSinceLastAttendance,
    required this.overduePayments,
    required this.attendanceTrend,
    required this.monthsAtAcademy,
  });
}

/// Retention Metrics - aggregate metrics across all students
class RetentionMetrics {
  final int totalAtRisk;
  final double atRiskPercentage;
  final double averageFrequency;
  final double paymentComplianceRate;
  final Map<RiskLevel, int> distributionByRisk;

  RetentionMetrics({
    required this.totalAtRisk,
    required this.atRiskPercentage,
    required this.averageFrequency,
    required this.paymentComplianceRate,
    required this.distributionByRisk,
  });
}

/// Retention Service - Pure computation, no Firestore
class RetentionService {
  // ============================================
  // Calculate Risk Score for a Single Student
  // ============================================
  StudentRiskScore calculateStudentRisk(
    Student student,
    List<Map<String, dynamic>> attendanceRecords,
    List<Map<String, dynamic>> financials,
  ) {
    final now = DateTime.now();
    final factors = <RiskFactor>[];
    int totalScore = 0;

    // --- Factor 1: Attendance Decline (weight 40) ---
    final last15Days = now.subtract(const Duration(days: 15));
    final last30Days = now.subtract(const Duration(days: 30));

    final recentAttendance = attendanceRecords.where((a) {
      final date = _extractDate(a);
      return date != null && date.isAfter(last15Days);
    }).toList();

    final previousAttendance = attendanceRecords.where((a) {
      final date = _extractDate(a);
      return date != null &&
          date.isAfter(last30Days) &&
          !date.isAfter(last15Days);
    }).toList();

    final recentCount = recentAttendance.length;
    final previousCount = previousAttendance.length;

    int attendanceScore = 0;
    double attendanceTrend = 0;
    String attendanceDetails = '';

    if (previousCount > 0) {
      final changePercent =
          ((recentCount - previousCount) / previousCount) * 100;
      attendanceTrend = changePercent;

      if (changePercent <= -50) {
        attendanceScore = 40;
        attendanceDetails =
            'Queda de ${changePercent.abs().round()}% na frequencia ($previousCount -> $recentCount presencas)';
      } else if (changePercent <= -25) {
        attendanceScore = 25;
        attendanceDetails =
            'Queda de ${changePercent.abs().round()}% na frequencia ($previousCount -> $recentCount presencas)';
      } else if (changePercent < 0) {
        attendanceScore = 10;
        attendanceDetails =
            'Leve queda na frequencia ($previousCount -> $recentCount presencas)';
      } else {
        attendanceScore = 0;
        attendanceDetails =
            'Frequencia estavel ou em alta ($previousCount -> $recentCount presencas)';
      }
    } else if (recentCount == 0) {
      attendanceScore = 40;
      attendanceTrend = -100;
      attendanceDetails = 'Nenhuma presenca nos ultimos 30 dias';
    } else {
      attendanceScore = 0;
      attendanceTrend = 100;
      attendanceDetails =
          '$recentCount presencas nos ultimos 15 dias (sem historico anterior)';
    }

    factors.add(RiskFactor(
      name: 'Queda de Frequencia',
      description:
          'Comparacao de presencas nos ultimos 15 dias vs 15 dias anteriores',
      weight: 40,
      score: attendanceScore,
      details: attendanceDetails,
    ));
    totalScore += attendanceScore;

    // --- Factor 2: Inactivity (weight 30) ---
    final sortedAttendance = List<Map<String, dynamic>>.from(attendanceRecords);
    sortedAttendance.sort((a, b) {
      final dateA = _extractDate(a) ?? DateTime(2000);
      final dateB = _extractDate(b) ?? DateTime(2000);
      return dateB.compareTo(dateA);
    });

    final DateTime? lastAttendance = sortedAttendance.isNotEmpty
        ? _extractDate(sortedAttendance.first)
        : null;

    final int daysSinceLastAttendance = lastAttendance != null
        ? now.difference(lastAttendance).inDays
        : 999;

    int inactivityScore = 0;
    String inactivityDetails = '';

    if (daysSinceLastAttendance > 30) {
      inactivityScore = 30;
      inactivityDetails = '$daysSinceLastAttendance dias sem treinar';
    } else if (daysSinceLastAttendance > 14) {
      inactivityScore = 20;
      inactivityDetails = '$daysSinceLastAttendance dias sem treinar';
    } else if (daysSinceLastAttendance > 7) {
      inactivityScore = 10;
      inactivityDetails = '$daysSinceLastAttendance dias sem treinar';
    } else {
      inactivityScore = 0;
      inactivityDetails = lastAttendance != null
          ? 'Ultima presenca ha $daysSinceLastAttendance dia(s)'
          : 'Sem registros de presenca';
    }

    factors.add(RiskFactor(
      name: 'Inatividade',
      description: 'Dias desde a ultima presenca registrada',
      weight: 30,
      score: inactivityScore,
      details: inactivityDetails,
    ));
    totalScore += inactivityScore;

    // --- Factor 3: Overdue Payments (weight 20) ---
    // Auditoria (LOW): antes contava só status=='overdue', herdando o furo da
    // detecção (um doc com dueDate no passado e status 'pending' não entrava).
    // Agora usa a mesma regra canônica do model Payment.isOverdue: vencido =
    // dueDate no passado E status fora de {paid, cancelled}. Retrocompatível:
    // docs já marcados 'overdue' (com dueDate passada) continuam contando.
    final overdueFinancials =
        financials.where((f) => _isFinancialOverdue(f, now)).toList();
    final overdueCount = overdueFinancials.length;

    int paymentScore = 0;
    String paymentDetails = '';

    if (overdueCount > 2) {
      paymentScore = 20;
      paymentDetails = '$overdueCount pagamentos em atraso';
    } else if (overdueCount == 2) {
      paymentScore = 15;
      paymentDetails = '2 pagamentos em atraso';
    } else if (overdueCount == 1) {
      paymentScore = 10;
      paymentDetails = '1 pagamento em atraso';
    } else {
      paymentScore = 0;
      paymentDetails = 'Nenhum pagamento em atraso';
    }

    factors.add(RiskFactor(
      name: 'Pagamentos em Atraso',
      description: 'Quantidade de pagamentos vencidos',
      weight: 20,
      score: paymentScore,
      details: paymentDetails,
    ));
    totalScore += paymentScore;

    // --- Factor 4: Time at Academy (weight 10) ---
    final monthsAtAcademy = _differenceInMonths(now, student.startDate);

    int timeScore = 0;
    String timeDetails = '';

    if (monthsAtAcademy < 3) {
      timeScore = 10;
      timeDetails =
          '$monthsAtAcademy mes(es) na academia (periodo critico de adaptacao)';
    } else if (monthsAtAcademy < 6) {
      timeScore = 5;
      timeDetails = '$monthsAtAcademy meses na academia';
    } else {
      timeScore = 0;
      timeDetails = '$monthsAtAcademy meses na academia (veterano)';
    }

    factors.add(RiskFactor(
      name: 'Tempo na Academia',
      description: 'Alunos novos tem maior risco de evasao',
      weight: 10,
      score: timeScore,
      details: timeDetails,
    ));
    totalScore += timeScore;

    // --- Classify Risk Level ---
    final clampedScore = min(100, max(0, totalScore));
    RiskLevel level;

    if (clampedScore >= 75) {
      level = RiskLevel.critical;
    } else if (clampedScore >= 50) {
      level = RiskLevel.high;
    } else if (clampedScore >= 25) {
      level = RiskLevel.medium;
    } else {
      level = RiskLevel.low;
    }

    return StudentRiskScore(
      studentId: student.id,
      studentName: student.fullName,
      score: clampedScore,
      level: level,
      factors: factors,
      lastAttendance: lastAttendance,
      daysSinceLastAttendance: daysSinceLastAttendance,
      overduePayments: overdueCount,
      attendanceTrend: attendanceTrend,
      monthsAtAcademy: monthsAtAcademy,
    );
  }

  // ============================================
  // Delinquency Consequence (Auditoria MED / produto)
  // ============================================
  /// Retorna o NÍVEL de consequência por inadimplência de um aluno, derivado dos
  /// dias máximos de atraso entre seus financials e da [policy] da academia.
  ///
  /// SEGURO POR PADRÃO: o teto automático é 'warn'. 'restrict' só é retornado se
  /// [policy.allowAutoRestrict] estiver explicitamente ligado pela academia —
  /// caso contrário, mesmo com atraso alto, devolve 'warn'. Este helper APENAS
  /// classifica; não bloqueia nada. Para plugar bloqueio de check-in/reserva no
  /// futuro, o consumidor (telas de check-in/reserva — outros arquivos) deve
  /// checar `== DelinquencyConsequence.restrict` e então negar a ação. O wire-up
  /// do bloqueio é decisão de produto (revisar antes de habilitar).
  DelinquencyConsequence consequenceForStudent(
    List<Map<String, dynamic>> financials, {
    DelinquencyPolicy policy = const DelinquencyPolicy(),
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final days = maxDaysOverdue(financials, now: reference);
    return consequenceForDaysOverdue(days, policy: policy);
  }

  /// Mapeia dias de atraso -> consequência respeitando a política segura.
  DelinquencyConsequence consequenceForDaysOverdue(
    int daysOverdue, {
    DelinquencyPolicy policy = const DelinquencyPolicy(),
  }) {
    if (daysOverdue <= 0) return DelinquencyConsequence.none;

    // 'restrict' só quando a academia habilitou explicitamente. Enquanto a flag
    // estiver desligada (default), rebaixa para 'warn' — nunca bloqueia sozinho.
    if (policy.allowAutoRestrict && daysOverdue >= policy.restrictAfterDays) {
      return DelinquencyConsequence.restrict;
    }
    if (daysOverdue >= policy.warnAfterDays) {
      return DelinquencyConsequence.warn;
    }
    return DelinquencyConsequence.none;
  }

  /// Maior atraso (em dias) entre os financials vencidos do aluno. 0 se nenhum.
  int maxDaysOverdue(
    List<Map<String, dynamic>> financials, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    int worst = 0;
    for (final f in financials) {
      if (!_isFinancialOverdue(f, reference)) continue;
      final dueDate = _readDate(f, 'dueDate');
      if (dueDate == null) continue;
      final d = reference.difference(dueDate).inDays;
      if (d > worst) worst = d;
    }
    return worst;
  }

  // ============================================
  // Get At-Risk Students (all active students, sorted by score desc)
  // ============================================
  List<StudentRiskScore> getAtRiskStudents(
    List<Student> students,
    Map<String, List<Map<String, dynamic>>> attendanceMap,
    Map<String, List<Map<String, dynamic>>> financialsMap,
  ) {
    final activeStudents =
        students.where((s) => s.status == StudentStatus.active).toList();

    final riskScores = activeStudents.map((student) {
      final attendance = attendanceMap[student.id] ?? [];
      final financials = financialsMap[student.id] ?? [];
      return calculateStudentRisk(student, attendance, financials);
    }).toList();

    // Sort by score descending (highest risk first)
    riskScores.sort((a, b) => b.score.compareTo(a.score));

    return riskScores;
  }

  // ============================================
  // Get Retention Metrics
  // ============================================
  RetentionMetrics getRetentionMetrics(
    List<Student> students,
    List<StudentRiskScore> atRiskStudents,
  ) {
    final activeStudents =
        students.where((s) => s.status == StudentStatus.active).toList();
    final totalActive = activeStudents.length;

    // Total at risk (score >= 25)
    final atRiskList = atRiskStudents.where((s) => s.score >= 25).toList();
    final totalAtRisk = atRiskList.length;
    final atRiskPercentage =
        totalActive > 0 ? (totalAtRisk / totalActive) * 100 : 0.0;

    // Payment compliance (students with 0 overdue / total)
    final compliantStudents =
        atRiskStudents.where((s) => s.overduePayments == 0).toList();
    final paymentComplianceRate = totalActive > 0
        ? (compliantStudents.length / totalActive) * 100
        : 100.0;

    // Distribution by risk level
    final distributionByRisk = <RiskLevel, int>{
      RiskLevel.low: 0,
      RiskLevel.medium: 0,
      RiskLevel.high: 0,
      RiskLevel.critical: 0,
    };
    for (final s in atRiskStudents) {
      distributionByRisk[s.level] = (distributionByRisk[s.level] ?? 0) + 1;
    }

    // Average frequency: placeholder (the caller can compute from raw data)
    const averageFrequency = 0.0;

    return RetentionMetrics(
      totalAtRisk: totalAtRisk,
      atRiskPercentage: atRiskPercentage,
      averageFrequency: averageFrequency,
      paymentComplianceRate: paymentComplianceRate,
      distributionByRisk: distributionByRisk,
    );
  }

  // ============================================
  // Private Helpers
  // ============================================

  /// Extracts a DateTime from an attendance record map.
  /// Supports Timestamp, DateTime, and String values for the 'date' key.
  DateTime? _extractDate(Map<String, dynamic> record) {
    final raw = record['date'];
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  /// Lê um campo de data arbitrário (Timestamp/DateTime/String) de um map.
  DateTime? _readDate(Map<String, dynamic> record, String key) {
    final raw = record[key];
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is Timestamp) return raw.toDate();
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  /// Auditoria (LOW): regra canônica de "vencido" para um financial bruto (map),
  /// espelhando Payment.isOverdue — dueDate no passado E status fora de
  /// {paid, cancelled}. Mantém compat: se não houver dueDate mas o status já for
  /// 'overdue', conta como vencido (não perde dados legados pré-filtrados).
  bool _isFinancialOverdue(Map<String, dynamic> financial, DateTime now) {
    final status = (financial['status'] ?? '').toString();
    if (status == 'paid' || status == 'cancelled') return false;
    final dueDate = _readDate(financial, 'dueDate');
    if (dueDate != null) {
      return dueDate.isBefore(now);
    }
    // Fallback retrocompatível: docs sem dueDate mas já marcados 'overdue'.
    return status == 'overdue';
  }

  /// Calculates the difference in months between two dates.
  int _differenceInMonths(DateTime a, DateTime b) {
    return (a.year - b.year) * 12 + (a.month - b.month);
  }
}

// ============================================
// Factory Function
// ============================================
RetentionService createRetentionService() {
  return RetentionService();
}
