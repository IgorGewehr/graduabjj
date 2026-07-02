import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import '../polish/polish.dart';

/// Checklist de ativação do admin: um cartão "Comece por aqui" que guia o dono
/// da academia pelos primeiros passos de configuração. Cada passo é derivado do
/// ESTADO REAL da academia (turmas, planos, Mercado Pago, alunos, presença,
/// perfil) — então um passo só aparece como concluído quando de fato foi feito.
///
/// O componente some sozinho quando tudo está pronto (100%) ou quando o estado
/// ainda não pôde ser carregado, para nunca poluir o dashboard de uma academia
/// já madura.
///
/// Uso (o dashboard apenas monta, sem parâmetros):
/// ```dart
/// const ActivationChecklist(),
/// ```
class ActivationChecklist extends ConsumerStatefulWidget {
  const ActivationChecklist({super.key});

  @override
  ConsumerState<ActivationChecklist> createState() =>
      _ActivationChecklistState();
}

class _ActivationChecklistState extends ConsumerState<ActivationChecklist> {
  // Expandir/retrair PERSISTE no device (SharedPreferences): quem retraiu o
  // checklist uma vez não quer vê-lo aberto de novo a cada visita ao
  // dashboard — ele só reabre se o professor tocar de novo.
  static const _prefsKey = 'activation_checklist_expanded';
  static const _hiddenKey = 'activation_checklist_hidden';
  bool _expanded = true;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getBool(_prefsKey);
      final hidden = prefs.getBool(_hiddenKey) ?? false;
      if (!mounted) return;
      setState(() {
        if (saved != null) _expanded = saved;
        _hidden = hidden;
      });
    });
  }

  /// "Não mostrar mais": academia madura não precisa do guia — some de vez
  /// (persistido no device; os passos continuam acessíveis via Configurações).
  void _hideForever() {
    setState(() => _hidden = true);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_hiddenKey, true));
  }

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_prefsKey, _expanded));
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final settingsAsync = ref.watch(academySettingsProvider);
    final classesAsync = ref.watch(classesProvider);
    final plansAsync = ref.watch(activePlansProvider);
    final studentsAsync = ref.watch(_activationStudentsExistProvider);
    final attendanceAsync = ref.watch(_activationAttendanceExistProvider);

    // Qualquer fonte ainda carregando → esqueleto discreto (mantém o lugar do
    // cartão sem "pular" o layout do dashboard).
    final anyLoading = settingsAsync.isLoading ||
        classesAsync.isLoading ||
        plansAsync.isLoading ||
        studentsAsync.isLoading ||
        attendanceAsync.isLoading;
    if (anyLoading) {
      return const _ChecklistSkeleton();
    }

    // Sem dados confiáveis (erro de fetch / sem academia) → não mostrar um
    // onboarding quebrado. Some.
    final settings = settingsAsync.valueOrNull;
    if (settings == null ||
        classesAsync.hasError ||
        plansAsync.hasError ||
        studentsAsync.hasError ||
        attendanceAsync.hasError) {
      return const SizedBox.shrink();
    }

    final hasProfile = settings.name.trim().isNotEmpty &&
        (settings.logoUrl?.trim().isNotEmpty ?? false);
    final hasClass = (classesAsync.valueOrNull ?? const []).isNotEmpty;
    final hasPlan = (plansAsync.valueOrNull ?? const []).isNotEmpty;
    final mpConnected = settings.mpConnected;
    final hasStudent = studentsAsync.valueOrNull ?? false;
    final hasAttendance = attendanceAsync.valueOrNull ?? false;
    final dismissed = settings.onboardingDismissedSteps;

    final allSteps = <_ActivationStep>[
      _ActivationStep(
        id: 'profile',
        icon: LucideIcons.building2,
        title: 'Perfil da academia',
        subtitle: 'Adicione nome e logo da sua academia',
        route: '/admin/configuracoes',
        done: hasProfile,
      ),
      _ActivationStep(
        id: 'class',
        icon: LucideIcons.calendarClock,
        title: 'Crie sua 1ª turma',
        subtitle: 'Defina horários e dias de treino',
        route: '/admin/turmas',
        done: hasClass,
      ),
      _ActivationStep(
        id: 'plan',
        icon: LucideIcons.creditCard,
        title: 'Planos e mensalidade',
        subtitle: 'Configure os valores da sua academia',
        route: '/admin/financeiro',
        done: hasPlan,
      ),
      _ActivationStep(
        id: 'mp',
        icon: LucideIcons.wallet,
        title: 'Conecte o Mercado Pago',
        subtitle: 'Receba pagamentos online direto no app',
        // Rota PRECISA: Settings → aba Financeiro → scroll + destaque no card.
        route: '/admin/configuracoes?feature=payments',
        done: mpConnected,
        recommended: true,
        dismissible: true, // opcional → pode ser dispensado
      ),
      _ActivationStep(
        id: 'students',
        icon: LucideIcons.userPlus,
        title: 'Cadastre seus alunos',
        subtitle: 'Adicione alunos e gere o código de acesso de cada um',
        route: '/admin/alunos',
        done: hasStudent,
      ),
      _ActivationStep(
        id: 'attendance',
        icon: LucideIcons.qrCode,
        title: 'Registre a 1ª presença',
        subtitle: 'Faça a primeira chamada de treino',
        route: '/admin/chamada',
        done: hasAttendance,
      ),
    ];

    // Passos dispensados pelo dono somem e não contam.
    final steps =
        allSteps.where((s) => !dismissed.contains(s.id)).toList(growable: false);

    final total = steps.length;
    final doneCount = steps.where((s) => s.done).length;

    // Tudo concluído (ou tudo que sobrou foi dispensado) → some.
    if (total == 0 || doneCount >= total) return const SizedBox.shrink();

    final progress = doneCount / total;

    Future<void> dismissStep(String id) async {
      await ref.read(settingsServiceProvider)?.dismissOnboardingStep(id);
      ref.invalidate(academySettingsProvider);
    }

    return PolishCard(
      elevated: true,
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabeçalho (toca p/ expandir/retrair) ──────────────────────
          Pressable(
            onTap: _toggleExpanded,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    LucideIcons.sparkles,
                    size: 20,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Comece por aqui',
                        style: AppTheme.titleMedium.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$doneCount de $total concluídos',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Chevron de expandir/retrair.
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: PolishMotion.fast,
                  child: const Icon(
                    LucideIcons.chevronDown,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // ── Progresso (sempre visível, mesmo retraído) ────────────────
          AnimatedProgressBar(
            value: progress,
            minHeight: 8,
            color: AppTheme.success,
            backgroundColor: AppTheme.surfaceVariant,
          ),
          // ── Passos (só quando expandido) ──────────────────────────────
          AnimatedSize(
            duration: PolishMotion.normal,
            curve: PolishMotion.entrance,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      for (final step in steps)
                        _ActivationStepTile(
                          step: step,
                          onTap: () => context.go(step.route),
                          onDismiss: step.dismissible && !step.done
                              ? () => dismissStep(step.id)
                              : null,
                        ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Pressable(
                          onTap: _hideForever,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 4),
                            child: Text(
                              'Não mostrar mais',
                              style: AppTheme.bodySmall.copyWith(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Um passo do checklist (dados derivados + apresentação).
class _ActivationStep {
  /// Id estável (usado para persistir "dispensado").
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final bool done;

  /// Marca o passo como "Recomendado" (badge) quando ainda pendente.
  final bool recommended;

  /// Pode ser dispensado pelo dono ("não vou usar") — passos opcionais.
  final bool dismissible;

  const _ActivationStep({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.done,
    this.recommended = false,
    this.dismissible = false,
  });
}

/// Linha tocável de um passo: ícone tintado, título/subtítulo e, à direita, um
/// check verde (feito) ou uma seta (pendente). Passos feitos ficam esmaecidos e
/// com o título riscado.
class _ActivationStepTile extends StatelessWidget {
  final _ActivationStep step;
  final VoidCallback onTap;

  /// Quando não-nulo, o passo pode ser dispensado (mostra um "×" discreto).
  final VoidCallback? onDismiss;

  const _ActivationStepTile({
    required this.step,
    required this.onTap,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final done = step.done;
    final iconColor = done ? AppTheme.success : AppTheme.primary;
    final tint = done ? AppTheme.success : AppTheme.primary;

    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // Ícone do passo num círculo tintado.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: done ? 0.10 : 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(step.icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            // Título + subtítulo (esmaecidos quando feito).
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          step.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            color: done
                                ? AppTheme.textSecondary
                                : AppTheme.textPrimary,
                            decoration:
                                done ? TextDecoration.lineThrough : null,
                            decorationColor: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      if (step.recommended && !done) ...[
                        const SizedBox(width: 8),
                        const _RecommendedBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // "Dispensar" (× discreto) para passos opcionais pendentes.
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Dispensar',
                icon: const Icon(LucideIcons.x,
                    size: 16, color: AppTheme.textSecondary),
              ),
            // Estado: check verde (feito) ou seta (pendente).
            _TrailingIndicator(done: done),
          ],
        ),
      ),
    );
  }
}

/// Indicador à direita do passo: medalha de concluído ou seta de "vá fazer".
class _TrailingIndicator extends StatelessWidget {
  final bool done;

  const _TrailingIndicator({required this.done});

  @override
  Widget build(BuildContext context) {
    if (done) {
      return Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          color: AppTheme.success,
          shape: BoxShape.circle,
        ),
        child: const Icon(LucideIcons.check, size: 16, color: Colors.white),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        LucideIcons.arrowRight,
        size: 16,
        color: AppTheme.textSecondary,
      ),
    );
  }
}

/// Pequeno selo "Recomendado".
class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Recomendado',
        style: AppTheme.labelSmall.copyWith(
          color: AppTheme.info,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Esqueleto exibido enquanto as fontes de dados resolvem.
class _ChecklistSkeleton extends StatelessWidget {
  const _ChecklistSkeleton();

  @override
  Widget build(BuildContext context) {
    return PolishCard(
      elevated: true,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PolishSkeleton.shimmer(
            child: Row(
              children: [
                PolishSkeleton.avatar(size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PolishSkeleton.bar(width: 160, height: 16),
                      const SizedBox(height: 8),
                      PolishSkeleton.bar(width: 220, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PolishSkeleton.shimmer(
            child: PolishSkeleton.bar(height: 8, radius: 999),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 3; i++) ...[
            PolishSkeleton.shimmer(
              child: Row(
                children: [
                  PolishSkeleton.avatar(size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PolishSkeleton.bar(width: 140, height: 13),
                        const SizedBox(height: 6),
                        PolishSkeleton.bar(width: 200, height: 11),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (i < 2) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Providers de derivação leve (existência), próprios deste componente.
//
// Para os passos "Convide alunos" e "1ª presença" basta saber se existe ao
// menos um documento — então usamos uma query limit(1) em vez de varrer a
// coleção. Os demais passos reusam providers já existentes (academySettings,
// classes, activePlans).
// ───────────────────────────────────────────────────────────────────────────

/// `true` se a academia já tem ao menos um aluno cadastrado.
final _activationStudentsExistProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  final academyId = user?.academyId;
  if (academyId == null) return false;
  final snap = await Collections(academyId).students.limit(1).get();
  return snap.docs.isNotEmpty;
});

/// `true` se já existe ao menos um registro de presença na academia.
final _activationAttendanceExistProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  final academyId = user?.academyId;
  if (academyId == null) return false;
  final snap = await Collections(academyId).attendance.limit(1).get();
  return snap.docs.isNotEmpty;
});
