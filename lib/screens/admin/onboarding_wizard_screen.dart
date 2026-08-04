import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/academy.dart' show AcademyProfile, AcademyProfileExtension;
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/join_request_providers.dart';
import '../../providers/onboarding_providers.dart';
import '../../providers/portal_providers.dart';
import '../../services/analytics_service.dart';
import '../../services/services.dart';
import '../../services/team_service.dart';
import '../../widgets/form/input_field.dart';
import '../../widgets/onboarding/billing_activation_step.dart';
import '../../widgets/onboarding/quick_create_class_form.dart';
import '../../widgets/polish/polish.dart';
import 'attendance_screen.dart';

/// Wizard "Comece em 3 minutos" — `/admin/comece-aqui`
/// (SPEC_ONBOARDING_2026-07.md §0.1/§1.1, Fatia 7). Só aparece pra academias
/// GENUINAMENTE vazias (gate em lib/app.dart via [wizardGateStatusProvider]) —
/// uma academia com qualquer progresso prévio nunca cai aqui. "Menos é mais":
/// cada passo tem 1 ação primária óbvia e, exceto onde a spec proíbe
/// explicitamente (W1 fight/hybrid — turma é pré-requisito mecânico), um link
/// de dispensa discreto.
///
/// FIGHT/HYBRID (hybrid segue fight integralmente, core/academy_vocab.dart):
///   0 'class'      → cria a turma de hoje (QuickCreateClassForm)
///   1 'students'    → matricula quem já é aluno OU cadastra rápido
///   2 'billing'     → BillingActivationStep embutido (o aha)
///   3 'attendance'  → 1ª chamada, pré-filtrada na turma criada
///
/// FITNESS (sem turma/sem faixa por design):
///   0 'invite'  → compartilha o código único da academia
///   1 'billing' → BillingActivationStep embutido
///   2 'done'    → tela informativa ("check-in já está ativo")
class AdminOnboardingWizardScreen extends ConsumerStatefulWidget {
  const AdminOnboardingWizardScreen({super.key});

  @override
  ConsumerState<AdminOnboardingWizardScreen> createState() =>
      _AdminOnboardingWizardScreenState();
}

class _AdminOnboardingWizardScreenState
    extends ConsumerState<AdminOnboardingWizardScreen> {
  int _stepIndex = 0;
  String? _createdClassId;
  bool _startedLogged = false;

  AcademyProfile get _profile => AcademyProfileExtension.fromString(
        ref.read(academySettingsProvider).valueOrNull?.profile,
      );

  String _stepIdFor(bool isFitness, int index) {
    if (isFitness) return const ['invite', 'billing', 'done'][index];
    return const ['class', 'students', 'billing', 'attendance'][index];
  }

  void _goToStep(int index) {
    final profile = _profile;
    setState(() => _stepIndex = index);
    unawaited(AnalyticsService.logWizardStepViewed(
      step: _stepIdFor(profile == AcademyProfile.fitness, index),
      profile: profile.value,
    ));
  }

  void _logSkip(String step) {
    unawaited(AnalyticsService.logWizardStepSkipped(
      step: step,
      profile: _profile.value,
    ));
  }

  /// Escrita idempotente que fecha o gate pra sempre (dono já viu o wizard,
  /// seja por dispensa explícita ou por conclusão natural) — mesmo campo
  /// (`wizardSkippedAt`) que [wizardGateStatusProvider] olha.
  Future<void> _markSeen() async {
    try {
      final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
      if (academyId == null) return;
      await SettingsService(academyId).markWizardSeen();
      ref.invalidate(academySettingsProvider);
    } catch (_) {
      // Best-effort — não bloquear a saída do wizard por causa disso.
    }
  }

  /// Link global de dispensa (chrome do wizard) — sai do fluxo INTEIRO,
  /// diferente dos "pular" por-passo (que só avançam pro próximo passo).
  Future<void> _exitWizard() async {
    final profile = _profile;
    unawaited(AnalyticsService.logWizardAbandoned(
      lastStep: _stepIdFor(profile == AcademyProfile.fitness, _stepIndex),
      profile: profile.value,
    ));
    await _markSeen();
    if (!mounted) return;
    context.go('/admin');
  }

  Future<void> _finish() async {
    final profile = _profile;
    unawaited(AnalyticsService.logWizardCompleted(profile: profile.value));
    // W4 (fight/hybrid) pode ter marcado presença via AttendanceService
    // direto (fora de qualquer provider) — sem isto o checklist mostraria
    // "Registre a 1ª presença" como pendente mesmo logo depois de concluída.
    ref.invalidate(hasAttendanceExistProvider);
    await _markSeen();
    if (!mounted) return;
    Celebration.confetti(context);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    context.go('/admin');
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(academySettingsProvider);
    final settings = settingsAsync.valueOrNull;
    if (settings == null) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final profile = AcademyProfileExtension.fromString(settings.profile);
    final isFitness = profile == AcademyProfile.fitness;

    // Dispara `wizard_started` + o 1º `wizard_step_viewed` uma única vez, no
    // primeiro build em que o perfil já está disponível (garantido pelo gate
    // do router: só chega aqui depois de academySettingsProvider resolver).
    if (!_startedLogged) {
      _startedLogged = true;
      unawaited(AnalyticsService.logWizardStarted(profile: profile.value));
      unawaited(AnalyticsService.logWizardStepViewed(
        step: _stepIdFor(isFitness, _stepIndex),
        profile: profile.value,
      ));
    }

    // Tela final da fitness é puramente informativa — sem barra de progresso
    // nem link de dispensa (não há mais nada a "pular").
    if (isFitness && _stepIndex == 2) {
      return _FitnessDoneScreen(onFinish: _finish);
    }

    final totalSteps = isFitness ? 2 : 4;
    final progress = (_stepIndex + 1) / totalSteps;

    String? trailingLabel;
    VoidCallback? onTrailing;
    if (isFitness) {
      if (_stepIndex == 0) {
        trailingLabel = 'Pular';
        onTrailing = _exitWizard;
      }
      // step 1 (billing) já tem seu próprio "Agora não" — sem chrome extra.
    } else {
      if (_stepIndex == 1) {
        trailingLabel = 'Pular';
        onTrailing = _exitWizard;
      } else if (_stepIndex == 3) {
        // Último passo: "Concluir" ocupa o lugar do "Pular" — finalizar É a
        // saída natural daqui, com ou sem presença marcada (spec §1.1: "Ao
        // concluir (ou pular)").
        trailingLabel = 'Concluir';
        onTrailing = _finish;
      }
      // step 2 (billing) já tem seu próprio "Agora não" — sem chrome extra.
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _WizardTopBar(
              progress: progress,
              trailingLabel: trailingLabel,
              onTrailing: onTrailing,
            ),
            Expanded(child: _buildStep(isFitness)),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(bool isFitness) {
    if (isFitness) {
      switch (_stepIndex) {
        case 0:
          return _InviteStepBody(onManualDone: () => _goToStep(1));
        case 1:
        default:
          return BillingActivationStep(
            source: 'wizard',
            onDone: (activated) {
              if (!activated) _logSkip('billing');
              _goToStep(2);
            },
          );
      }
    }

    switch (_stepIndex) {
      case 0:
        return _ClassStepBody(
          onCreated: (created) {
            _createdClassId = created.id;
            _goToStep(1);
          },
        );
      case 1:
        return _StudentsStepBody(
          classId: _createdClassId!,
          onNext: () => _goToStep(2),
          onSkip: () {
            _logSkip('students');
            _goToStep(2);
          },
        );
      case 2:
        return BillingActivationStep(
          source: 'wizard',
          onDone: (activated) {
            if (!activated) _logSkip('billing');
            _goToStep(3);
          },
        );
      case 3:
      default:
        return AdminAttendanceScreen(
          initialClassId: _createdClassId,
          wizardBannerText: 'Toque no nome de quem chegou.',
        );
    }
  }
}

/// Chrome comum a todo passo (SPEC §1.1): barra de progresso fina no topo +
/// (quando aplicável) 1 link secundário discreto no canto.
class _WizardTopBar extends StatelessWidget {
  final double progress;
  final String? trailingLabel;
  final VoidCallback? onTrailing;

  const _WizardTopBar({
    required this.progress,
    this.trailingLabel,
    this.onTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 40,
            child: Align(
              alignment: Alignment.centerRight,
              child: trailingLabel == null
                  ? null
                  : TextButton(
                      onPressed: onTrailing,
                      child: Text(
                        trailingLabel!,
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
          ),
          AnimatedProgressBar(
            value: progress,
            minHeight: 5,
            color: AppTheme.primary,
            backgroundColor: AppTheme.surfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// W1 fight/hybrid — "Crie sua turma de hoje". Só a copy muda em relação ao
/// bottom sheet de `attendance_screen.dart`; a lógica (nome + "mais opções" +
/// salvar) vive inteira em [QuickCreateClassForm].
class _ClassStepBody extends StatelessWidget {
  final void Function(BJJClass created) onCreated;

  const _ClassStepBody({required this.onCreated});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Crie sua turma de hoje',
            style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Só o nome — dá pra editar tudo depois.',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          QuickCreateClassForm(
            // Gate do wizard exige !hasStudent pra chegar aqui — nunca há
            // aluno pré-existente nesta etapa (a matrícula é o passo W2).
            students: const [],
            analyticsSource: 'wizard',
            nameHint: 'Ex.: Turma das 19h',
            submitLabel: 'Criar e continuar',
            onCreated: (created) async => onCreated(created),
          ),
        ],
      ),
    );
  }
}

/// W2 fight/hybrid — "Quem treina hoje?". Duas variantes conforme a base já
/// tenha alunos sem turma ou não (spec §1.1).
class _StudentsStepBody extends ConsumerStatefulWidget {
  final String classId;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _StudentsStepBody({
    required this.classId,
    required this.onNext,
    required this.onSkip,
  });

  @override
  ConsumerState<_StudentsStepBody> createState() => _StudentsStepBodyState();
}

class _StudentsStepBodyState extends ConsumerState<_StudentsStepBody> {
  bool _loading = true;
  List<Student> _existing = const [];
  final Set<String> _selected = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
    if (academyId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final students = await StudentService(academyId).getActive();
      if (!mounted) return;
      setState(() {
        _existing = students;
        _selected
          ..clear()
          ..addAll(students.map((s) => s.id));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
      if (academyId != null && _selected.isNotEmpty) {
        await ClassService(academyId).addStudents(
          widget.classId,
          _selected.toList(),
        );
        ref.invalidate(hasStudentsExistProvider);
        // A turma criada no W1 já está em cache com `studentIds: []` (ver
        // QuickCreateClassForm) — sem isto o checklist mostraria "matricule
        // seus alunos" como pendente mesmo logo depois de matriculá-los.
        ref.invalidate(classesProvider);
      }
      widget.onNext();
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_existing.isEmpty) {
      return _QuickAddLoop(
        classId: widget.classId,
        onDone: widget.onNext,
        onSkip: widget.onSkip,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quem treina hoje?',
            style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Marque quem já é seu aluno — o resto você adiciona depois.',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          ..._existing.map(
            (s) => CheckboxListTile(
              value: _selected.contains(s.id),
              onChanged: (v) => setState(() {
                if (v ?? false) {
                  _selected.add(s.id);
                } else {
                  _selected.remove(s.id);
                }
              }),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                s.fullName,
                style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Continuar'),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _saving ? null : widget.onSkip,
              child: Text(
                'Pular, adiciono depois',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cadastro rápido em loop — Nome + telefone, sem escolha de modalidade
/// (zero-decisão: fight/hybrid grava `bjj`, fitness grava `musculacao`, mesmo
/// default que `auth_provider.dart` usa ao criar a conta da academia).
/// Compartilhado por W2 fight/hybrid (sem alunos ainda) e pelo modo manual do
/// W1 fitness ("Prefiro cadastrar eu mesmo") — [classId] nulo pula a
/// matrícula em turma (fitness não tem turma).
class _QuickAddLoop extends ConsumerStatefulWidget {
  final String? classId;
  final VoidCallback onDone;
  final VoidCallback onSkip;

  const _QuickAddLoop({
    this.classId,
    required this.onDone,
    required this.onSkip,
  });

  @override
  ConsumerState<_QuickAddLoop> createState() => _QuickAddLoopState();
}

class _QuickAddLoopState extends ConsumerState<_QuickAddLoop> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final List<Student> _added = [];
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      context.showWarning('Informe o nome do aluno');
      return;
    }

    setState(() => _saving = true);
    try {
      final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
      if (academyId == null) return;
      final settings = ref.read(academySettingsProvider).valueOrNull;
      final profile = AcademyProfileExtension.fromString(settings?.profile);
      final sports = profile == AcademyProfile.fitness
          ? const [SportId.musculacao]
          : const [SportId.bjj];

      final student = await StudentService(academyId).quickCreate(
        fullName: name,
        sports: sports,
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
      );

      if (widget.classId != null) {
        await ClassService(academyId).addStudent(widget.classId!, student.id);
        ref.invalidate(classesProvider);
      }
      ref.invalidate(hasStudentsExistProvider);

      if (!mounted) return;
      setState(() {
        _added.add(student);
        _nameController.clear();
        _phoneController.clear();
      });
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quem treina hoje?',
            style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Cadastre rapidinho — o resto você edita depois.',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 20),
          InputField(
            controller: _nameController,
            label: 'Nome',
            hintText: 'Nome do aluno',
            prefixIcon: LucideIcons.user,
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          PhoneInput(controller: _phoneController, label: 'Telefone (opcional)'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _add,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.userPlus, size: 18),
              label: const Text('Adicionar mais'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: BorderSide(color: AppTheme.divider),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          if (_added.isNotEmpty) ...[
            const SizedBox(height: 16),
            ..._added.map(
              (s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(LucideIcons.checkCircle, size: 16, color: AppTheme.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(s.fullName, style: AppTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          if (_added.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : widget.onDone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.textPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Continuar'),
              ),
            ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _saving ? null : widget.onSkip,
              child: Text(
                'Pular, adiciono depois',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// W1 fitness — "Convide quem já treina com você". Mostra o código único
/// (gera automaticamente se a academia ainda não tem um) com botão de
/// compartilhar; "Prefiro cadastrar eu mesmo" troca pro mesmo loop de
/// cadastro rápido do fight/hybrid, sem turma.
class _InviteStepBody extends ConsumerStatefulWidget {
  final VoidCallback onManualDone;

  const _InviteStepBody({required this.onManualDone});

  @override
  ConsumerState<_InviteStepBody> createState() => _InviteStepBodyState();
}

class _InviteStepBodyState extends ConsumerState<_InviteStepBody> {
  bool _manualMode = false;
  bool _generating = false;
  bool _autoGenerateTried = false;

  Future<void> _generateCode(String academyId) async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      await TeamService().rotateAcademyJoinCode(academyId);
    } catch (_) {
      if (mounted) context.showError('Não foi possível gerar o código.');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_manualMode) {
      return _QuickAddLoop(
        onDone: widget.onManualDone,
        onSkip: widget.onManualDone,
      );
    }

    final academyId = ref.watch(currentUserProvider).valueOrNull?.academyId ?? '';
    final codeAsync = ref.watch(academyJoinCodeProvider);
    final code = codeAsync.valueOrNull;

    // Academia nova quase certamente não tem código ainda — gera sozinho 1x
    // (mesma CF que o botão "Gerar" de join_requests_screen.dart chama),
    // pra não obrigar o dono a um tap extra num passo que já é "zero-decisão".
    if (!_autoGenerateTried &&
        !_generating &&
        academyId.isNotEmpty &&
        codeAsync.hasValue &&
        (code == null || code.isEmpty)) {
      _autoGenerateTried = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _generateCode(academyId));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Convide seus alunos',
            style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Compartilhe o código — eles se cadastram sozinhos e você só aprova.',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                Text(
                  'Código da academia',
                  style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 10),
                if (code == null || code.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        code,
                        style: AppTheme.headlineSmall.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 5,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Copiar',
                        icon: const Icon(LucideIcons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          context.showSuccess('Código copiado!');
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (code == null || code.isEmpty)
                  ? null
                  : () => Share.share(
                        'Entra na minha academia pelo app! Use o código: $code',
                      ),
              icon: const Icon(LucideIcons.share2, size: 18),
              label: const Text('Compartilhar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () => setState(() => _manualMode = true),
              child: Text(
                'Prefiro cadastrar eu mesmo',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tela final da fitness — puramente informativa (spec §1.1): o check-in do
/// aluno já nasce ligado (`studentCheckinEnabled` default `true`,
/// `auth_provider.dart`), então não há toggle nenhum aqui.
class _FitnessDoneScreen extends StatelessWidget {
  final VoidCallback onFinish;

  const _FitnessDoneScreen({required this.onFinish});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(LucideIcons.checkCircle2, size: 48, color: AppTheme.success),
              ),
              const SizedBox(height: 24),
              Text(
                'Pronto! O check-in já está ativo',
                textAlign: TextAlign.center,
                style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                'Assim que forem aprovados, seus alunos tocam em CHECK-IN no '
                'app deles — não precisa configurar mais nada.',
                textAlign: TextAlign.center,
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: AppTheme.textPrimary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.checkCircle, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'CHECK-IN',
                      style: AppTheme.bodyMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onFinish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.textPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Ir para o Painel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
