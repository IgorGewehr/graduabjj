// Providers Riverpod de nível domínio para a migração graduabjj→Tatami.
//
// Estes providers consomem os *RemoteRepo de lib/api/repositories.dart e
// expõem o resultado de uma forma que telas/widgets podem consumir
// diretamente. Eles NÃO substituem ainda os providers legacy (currentUserProvider,
// studentsProvider, etc.) — telas só vão trocar para estes via PR de
// wiring específico, atrás da feature flag correspondente.
//
// A convenção é: cada provider lê a flag e, quando false, lança
// StateError. Isso garante que esquecer de checar a flag explode cedo
// no canary em vez de silenciosamente bater no BE de staging em prod.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dto/identity_dto.dart';
import 'dto/student_dto.dart';
import 'feature_flags.dart';
import 'repositories.dart';

class TatamiFlagDisabledError extends StateError {
  TatamiFlagDisabledError(String flag)
      : super('Tatami flag "$flag" is disabled. Toggle in Remote Config '
            'before consuming the corresponding *TatamiProvider.');
}

void _requireFlag(bool enabled, String flagName) {
  if (!enabled) throw TatamiFlagDisabledError(flagName);
}

// ---------------------------------------------------------------------------
// Identity (Sprint 1)
// ---------------------------------------------------------------------------

/// Carrega `/v1/me` quando a flag `useTatamiIdentity` está ligada.
/// Cacheado pela vida do provider — invalidar via `ref.invalidate(...)`
/// quando o usuário atualizar perfil.
final currentTatamiUserProvider =
    FutureProvider<CurrentUserResponse>((ref) async {
  _requireFlag(
    ref.watch(tatamiFlagsProvider).useTatamiIdentity,
    'useTatamiIdentity',
  );
  return ref.watch(identityRepoProvider).getMe();
});

// ---------------------------------------------------------------------------
// Student reads (Sprint 2)
// ---------------------------------------------------------------------------

/// Lista paginada de alunos para uma academia. `.family` aceita
/// (academyId, filter) como par.
///
/// Uso na tela:
/// ```dart
/// final asyncPage = ref.watch(tatamiStudentsProvider(
///   StudentsQuery(academyId: aid, filter: filter),
/// ));
/// ```
final tatamiStudentsProvider = FutureProvider.family<StudentsPage, StudentsQuery>(
  (ref, q) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiReads,
      'useTatamiReads',
    );
    return ref
        .watch(studentRepoProvider)
        .list(q.academyId, filter: q.filter);
  },
);

class StudentsQuery {
  const StudentsQuery({required this.academyId, this.filter = const StudentFilter()});

  final String academyId;
  final StudentFilter filter;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StudentsQuery &&
          other.academyId == academyId &&
          other.filter.status == filter.status &&
          other.filter.belt == filter.belt &&
          other.filter.category == filter.category &&
          other.filter.q == filter.q &&
          other.filter.sport == filter.sport &&
          other.filter.limit == filter.limit &&
          other.filter.cursor == filter.cursor);

  @override
  int get hashCode => Object.hash(
        academyId,
        filter.status,
        filter.belt,
        filter.category,
        filter.q,
        filter.sport,
        filter.limit,
        filter.cursor,
      );
}

/// KPIs do dashboard. Sprint 2.
final tatamiStudentStatsProvider =
    FutureProvider.family<ApiStudentStats, String>(
  (ref, academyId) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiReads,
      'useTatamiReads',
    );
    return ref.watch(studentRepoProvider).getStats(academyId);
  },
);

/// Eligibility de graduação por aluno. Sprint 2.
final tatamiStudentEligibilityProvider =
    FutureProvider.family<ApiEligibilityView, _StudentRef>(
  (ref, r) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiReads,
      'useTatamiReads',
    );
    return ref.watch(studentRepoProvider).getEligibility(r.academyId, r.studentId);
  },
);

/// Detalhe completo de um aluno (header + perfil). Sprint 2.
final tatamiStudentByIdProvider =
    FutureProvider.family<ApiStudent, _StudentRef>(
  (ref, r) async {
    _requireFlag(
      ref.watch(tatamiFlagsProvider).useTatamiReads,
      'useTatamiReads',
    );
    return ref.watch(studentRepoProvider).getById(r.academyId, r.studentId);
  },
);

class _StudentRef {
  const _StudentRef(this.academyId, this.studentId);
  final String academyId;
  final String studentId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _StudentRef &&
          other.academyId == academyId &&
          other.studentId == studentId);

  @override
  int get hashCode => Object.hash(academyId, studentId);
}

/// Construtor público de _StudentRef. O record interno é mantido privado
/// para evitar criar 5 classes públicas de chave; um único factory function
/// resolve.
StudentRef studentRef(String academyId, String studentId) =>
    StudentRef._(academyId, studentId);

class StudentRef {
  const StudentRef._(this.academyId, this.studentId);
  final String academyId;
  final String studentId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StudentRef &&
          other.academyId == academyId &&
          other.studentId == studentId);

  @override
  int get hashCode => Object.hash(academyId, studentId);
}
