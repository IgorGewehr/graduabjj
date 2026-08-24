import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/student.dart';
import '../services/firebase_service.dart';
import '../services/retention_contact_service.dart';
import '../services/student_service.dart';

/// Providers da Retenção 2.0 — leem os campos PERSISTIDOS (`retention.*`,
/// gravados pela CF onAttendanceWrite + job diário) e a subcoleção
/// `retentionContacts`. ZERO varredura de payments/attendance no client:
/// o motor de risco agora é server-side.
///
/// Contratos reusados pelo dashboard (bloco RADAR §6):
/// - [retentionStudentsProvider]
/// - [retentionMonthStatsProvider]
/// - [latestSnapshotProvider]

/// Serviço de contatos de reengajamento (academy-scoped).
final retentionContactServiceProvider = Provider<RetentionContactService>((ref) {
  return RetentionContactService(FirebaseService.academyId);
});

/// Alunos ATIVOS ordenados por risco: riskScore desc (null por último),
/// tie-break daysSinceLastAttendance desc (null por último).
///
/// Leitura instantânea — só a coleção students (o `retention.*` vem embutido
/// no doc do aluno). riskScore null = job diário ainda não rodou (fallback de
/// agrupamento por inatividade fica na tela).
final retentionStudentsProvider = FutureProvider<List<Student>>((ref) async {
  final service = StudentService(FirebaseService.academyId);
  final students = await service.getActive();

  int riskOf(Student s) => s.retention?.riskScore ?? -1;
  int daysOf(Student s) => s.daysSinceLastAttendance ?? -1;

  students.sort((a, b) {
    final byRisk = riskOf(b).compareTo(riskOf(a));
    if (byRisk != 0) return byRisk;
    return daysOf(b).compareTo(daysOf(a));
  });
  return students;
});

/// REGRA DO RADAR (feedback do dono, jul/2026): a atenção do professor é para
/// quem TAVA TREINANDO e está esfriando — NÃO para quem nunca engatou (nunca
/// treinou, ou meia dúzia de aulas na vida). Nunca-engatou é problema de
/// ATIVAÇÃO, não de churn — e poluía o radar inteiro (academia com alunos
/// legados sem presença nascia "100% crítica").
///
/// Elegível ao radar de esfriamento:
/// 1. Já treinou de verdade: presença conhecida E >=8 presenças na vida.
/// 2. Tinha hábito recente (>=3 semanas treinadas nas últimas 8 OU >=4
///    presenças nos últimos 30d) e está esfriando (4 semanas recentes < 4
///    anteriores, OU >=7 dias parado); OU
/// 3. É fiel de longa data (>=20 presenças) que parou de vez há 14–90 dias
///    (>90 dias não é "esfriando", é ex-aluno — outro funil).
bool isCoolingAthlete(Student s) {
  final r = s.retention;
  if (r == null) {
    final days = s.daysSinceLastAttendance;
    return days == null || days >= 7;
  }

  // 1. Alunos com risco computado pelo backend (crítico/alto/médio ou blues)
  if (r.riskLevel == 'critical' || r.riskLevel == 'high' || r.riskLevel == 'medium') {
    return true;
  }
  if (r.riskScore != null && r.riskScore! >= 25) {
    return true;
  }
  if (r.bluesRisk == true) return true;

  final days = s.daysSinceLastAttendance;
  // 2. Alunos sem treino recente (7+ dias) ou sem nenhuma presença
  if (days == null || days >= 7) return true;

  // 3. Queda de hábito nas últimas semanas
  final weeks = s.last8WeeksBuckets(DateTime.now());
  final trainedWeeks = weeks.where((w) => w > 0).length;
  final hadRecentHabit = trainedWeeks >= 3 || r.attendanceLast30d >= 4;

  if (hadRecentHabit) {
    final older = weeks.sublist(0, 4).fold<int>(0, (a, b) => a + b);
    final recent = weeks.sublist(4).fold<int>(0, (a, b) => a + b);
    return recent < older || days >= 7;
  }

  return s.totalAttendanceCount >= 20 && days >= 14 && days <= 90;
}

/// Métrica de recuperação do mês corrente para o header
/// "De N contatados este mês, M voltaram".
class RetentionMonthStats {
  /// StudentIds DISTINTOS contatados desde o início do mês.
  final int contacted;

  /// Contatos do mês já fechados como 'recovered' pelo job diário.
  final int recovered;

  const RetentionMonthStats({required this.contacted, required this.recovered});

  static const zero = RetentionMonthStats(contacted: 0, recovered: 0);
}

/// Contatos do mês corrente → { contatados distintos, recuperados }.
/// Qualquer erro (rules, offline) degrada para zeros — a tela nunca quebra
/// por causa do header.
final retentionMonthStatsProvider =
    FutureProvider<RetentionMonthStats>((ref) async {
  final service = ref.watch(retentionContactServiceProvider);
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  try {
    final contacts = await service.listSince(monthStart);
    final contactedIds = <String>{};
    final recoveredIds = <String>{};
    for (final c in contacts) {
      if (c.studentId.isEmpty) continue;
      contactedIds.add(c.studentId);
      if (c.isRecovered) recoveredIds.add(c.studentId);
    }
    return RetentionMonthStats(
      contacted: contactedIds.length,
      recovered: recoveredIds.length,
    );
  } catch (_) {
    return RetentionMonthStats.zero;
  }
});

/// StudentIds com contato 'pending' (em aberto, aguardando outcome do job).
/// Gate do chip "sugerir inativar": não sugerir enquanto há contato em aberto.
/// Erro → set vazio (o chip some, nunca sugere errado).
final retentionPendingContactIdsProvider =
    FutureProvider<Set<String>>((ref) async {
  final service = ref.watch(retentionContactServiceProvider);
  try {
    return await service.pendingContactStudentIds();
  } catch (_) {
    return const <String>{};
  }
});

/// Histórico de contatos de UM aluno (mais recentes primeiro, limit 20).
/// Usado pelo expandir do card e pelo check anti-assédio do WhatsApp.
final studentRetentionContactsProvider =
    FutureProvider.family<List<RetentionContact>, String>((ref, studentId) async {
  final service = ref.watch(retentionContactServiceProvider);
  try {
    return await service.listForStudent(studentId, limit: 20);
  } catch (_) {
    return const [];
  }
});

/// Último snapshot diário agregado (`retentionSnapshots/{YYYY-MM-DD}`) —
/// tendência p/ header e bloco RADAR do dashboard. Null = job nunca rodou.
///
/// Campos: atRisk{critical,high,medium}, activeStudents, churnedThisMonth,
/// avgWeeklyAttendance, contactsMade, recoveredAfterContact, computedAt.
final latestSnapshotProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  try {
    final snap = await Collections(FirebaseService.academyId)
        .academy
        .collection('retentionSnapshots')
        .orderBy(FieldPath.documentId, descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final data = Map<String, dynamic>.from(snap.docs.first.data());
    data['id'] = snap.docs.first.id;
    return data;
  } catch (_) {
    return null;
  }
});
