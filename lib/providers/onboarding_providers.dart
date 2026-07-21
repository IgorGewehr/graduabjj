import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/services.dart';
import 'auth_provider.dart';
import 'portal_providers.dart';

/// Providers compartilhados pelo funil de ativação (SPEC_ONBOARDING_2026-07.md)
/// — usados pelo `ActivationChecklist` (lib/widgets/onboarding/
/// activation_checklist.dart) E pelo gate do wizard `/admin/comece-aqui`
/// (lib/app.dart, Fatia 7). Extraídos pra cá (em vez de viverem duplicados em
/// cada widget) pra academia com o checklist E o gate ativos na mesma sessão
/// não disparar a mesma query Firestore duas vezes.

/// `true` se a academia já tem ao menos um aluno cadastrado.
final hasStudentsExistProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  final academyId = user?.academyId;
  if (academyId == null) return false;
  final snap = await Collections(academyId).students.limit(1).get();
  return snap.docs.isNotEmpty;
});

/// `true` se já existe ao menos um registro de presença na academia.
final hasAttendanceExistProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  final academyId = user?.academyId;
  if (academyId == null) return false;
  final snap = await Collections(academyId).attendance.limit(1).get();
  return snap.docs.isNotEmpty;
});

/// Estado do gate do wizard "Comece em 3 minutos" (SPEC_ONBOARDING_2026-07.md
/// §0.1). Espelha o `AppBootstrapStatus` do router (loading vs decidido) pra
/// o `redirect` do GoRouter nunca precisar "adivinhar" — ele só age quando o
/// estado já está resolvido.
enum WizardGateStatus {
  /// Alguma fonte (settings/turmas/alunos/presença) ainda está carregando —
  /// o router NÃO decide nada neste estado (evita bounce pro wizard depois
  /// que o dono já navegou pra outro lugar).
  loading,

  /// Academia genuinamente vazia (!hasClass && !hasStudent && !hasAttendance)
  /// e o dono nunca dispensou o wizard — mostra.
  show,

  /// Qualquer sinal de progresso já existe OU o dono já pulou antes — nunca
  /// mostra.
  hide,
}

/// Gate único do wizard — mesmos 3 sinais que o `ActivationChecklist` já
/// computa (`classesProvider`, [hasStudentsExistProvider],
/// [hasAttendanceExistProvider]) mais o dismissal persistido
/// (`AcademySettings.wizardSkippedAt`). Não inventa um mecanismo de gate novo:
/// o router só faz `ref.read` disto dentro do `redirect` já existente (mesmo
/// padrão do `appBootstrapProvider`).
final wizardGateStatusProvider = Provider<WizardGateStatus>((ref) {
  final settingsAsync = ref.watch(academySettingsProvider);
  final classesAsync = ref.watch(classesProvider);
  final studentsAsync = ref.watch(hasStudentsExistProvider);
  final attendanceAsync = ref.watch(hasAttendanceExistProvider);

  final anyLoading = settingsAsync.isLoading ||
      classesAsync.isLoading ||
      studentsAsync.isLoading ||
      attendanceAsync.isLoading;
  if (anyLoading) return WizardGateStatus.loading;

  final settings = settingsAsync.valueOrNull;
  // Sem settings confiáveis (erro/sem academia) → nunca força o wizard.
  if (settings == null ||
      classesAsync.hasError ||
      studentsAsync.hasError ||
      attendanceAsync.hasError) {
    return WizardGateStatus.hide;
  }

  if (settings.wizardSkippedAt != null) return WizardGateStatus.hide;

  final hasClass = (classesAsync.valueOrNull ?? const []).isNotEmpty;
  final hasStudent = studentsAsync.valueOrNull ?? false;
  final hasAttendance = attendanceAsync.valueOrNull ?? false;

  if (hasClass || hasStudent || hasAttendance) return WizardGateStatus.hide;
  return WizardGateStatus.show;
});
