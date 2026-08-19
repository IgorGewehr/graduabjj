import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/onboarding_providers.dart';
import '../../providers/portal_providers.dart';
import '../../services/analytics_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/onboarding/quiz_decision_bridge.dart';
import '../../widgets/onboarding/quiz_header.dart';
import '../../widgets/onboarding/quiz_skip_dialog.dart';
import '../../widgets/onboarding/steps/quiz_step_attendance.dart';
import '../../widgets/onboarding/steps/quiz_step_billing.dart';
import '../../widgets/onboarding/steps/quiz_step_extra_modules.dart';
import '../../widgets/onboarding/steps/quiz_step_gamification.dart';
import '../../widgets/onboarding/steps/quiz_step_graduation_rules.dart';
import '../../widgets/onboarding/steps/quiz_step_modalities.dart';
import '../../widgets/onboarding/steps/quiz_step_retention.dart';
import '../../widgets/onboarding/steps/quiz_step_sandbox.dart';
import '../../widgets/onboarding/steps/quiz_step_students.dart';
import '../../widgets/polish/polish.dart';

enum _WizardPhase {
  level1,
  bridge,
  level2,
}

/// Orquestrador do Onboarding Interativo & Quiz em 2 Níveis (`/admin/comece-aqui`)
class AdminOnboardingWizardScreen extends ConsumerStatefulWidget {
  const AdminOnboardingWizardScreen({super.key});

  @override
  ConsumerState<AdminOnboardingWizardScreen> createState() =>
      _AdminOnboardingWizardScreenState();
}

class _AdminOnboardingWizardScreenState
    extends ConsumerState<AdminOnboardingWizardScreen> {
  _WizardPhase _phase = _WizardPhase.level1;
  int _level1Step = 0;
  int _level2Step = 0;
  bool _startedLogged = false;

  static const int _totalLevel1Steps = 5;
  static const int _totalLevel2Steps = 4;

  void _nextLevel1Step() {
    if (_level1Step < _totalLevel1Steps - 1) {
      setState(() => _level1Step++);
    } else {
      setState(() => _phase = _WizardPhase.bridge);
    }
  }

  void _prevLevel1Step() {
    if (_level1Step > 0) {
      setState(() => _level1Step--);
    }
  }

  void _nextLevel2Step() {
    if (_level2Step < _totalLevel2Steps - 1) {
      setState(() => _level2Step++);
    } else {
      _finish(completedAll: true);
    }
  }

  void _prevLevel2Step() {
    if (_level2Step > 0) {
      setState(() => _level2Step--);
    } else {
      setState(() => _phase = _WizardPhase.bridge);
    }
  }

  Future<void> _markSeen() async {
    try {
      final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
      if (academyId == null) return;
      await SettingsService(academyId).markWizardSeen();
      ref.invalidate(academySettingsProvider);
    } catch (_) {
      // Best-effort
    }
  }

  Future<void> _exitWithSkipDialog() async {
    await QuizSkipDialog.show(
      context,
      onConfirmSkip: () async {
        await _markSeen();
        if (!mounted) return;
        context.go('/admin');
      },
    );
  }

  Future<void> _finish({bool completedAll = false}) async {
    unawaited(AnalyticsService.logWizardCompleted(
      profile: ref.read(academySettingsProvider).valueOrNull?.profile ?? 'fight',
    ));
    ref.invalidate(hasAttendanceExistProvider);
    ref.invalidate(hasStudentsExistProvider);
    ref.invalidate(classesProvider);
    ref.invalidate(academySettingsProvider);

    await _markSeen();
    if (!mounted) return;

    Celebration.confetti(context);
    await Future.delayed(const Duration(milliseconds: 700));
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

    if (!_startedLogged) {
      _startedLogged = true;
      unawaited(AnalyticsService.logWizardStarted(profile: settings.profile ?? 'fight'));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            if (_phase == _WizardPhase.level1)
              QuizHeader(
                currentStep: _level1Step + 1,
                totalSteps: _totalLevel1Steps,
                stageTitle: 'Nível 1 • Setup Essencial',
                onBack: _level1Step > 0 ? _prevLevel1Step : null,
                onSkip: _level1Step == _totalLevel1Steps - 1
                    ? _exitWithSkipDialog
                    : _nextLevel1Step,
                skipLabel: _level1Step == _totalLevel1Steps - 1 ? 'Sair' : 'Pular etapa',
              )
            else if (_phase == _WizardPhase.level2)
              QuizHeader(
                currentStep: _level2Step + 1,
                totalSteps: _totalLevel2Steps,
                stageTitle: 'Nível 2 • Superpoderes',
                onBack: _prevLevel2Step,
                onSkip: _level2Step == _totalLevel2Steps - 1
                    ? () => _finish(completedAll: false)
                    : _nextLevel2Step,
                skipLabel: _level2Step == _totalLevel2Steps - 1 ? 'Concluir' : 'Pular etapa',
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _buildCurrentContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentContent() {
    switch (_phase) {
      case _WizardPhase.level1:
        switch (_level1Step) {
          case 0:
            return QuizStepModalities(
              key: const ValueKey('l1_s0'),
              onNext: _nextLevel1Step,
            );
          case 1:
            return QuizStepBilling(
              key: const ValueKey('l1_s1'),
              onNext: _nextLevel1Step,
            );
          case 2:
            return QuizStepStudents(
              key: const ValueKey('l1_s2'),
              onNext: _nextLevel1Step,
            );
          case 3:
            return QuizStepAttendance(
              key: const ValueKey('l1_s3'),
              onNext: _nextLevel1Step,
            );
          case 4:
          default:
            return QuizStepSandbox(
              key: const ValueKey('l1_s4'),
              onNext: _nextLevel1Step,
            );
        }

      case _WizardPhase.bridge:
        return QuizDecisionBridge(
          key: const ValueKey('bridge'),
          onProceedToLevel2: () => setState(() {
            _phase = _WizardPhase.level2;
            _level2Step = 0;
          }),
          onGoToDashboard: () => _finish(completedAll: false),
        );

      case _WizardPhase.level2:
        switch (_level2Step) {
          case 0:
            return QuizStepRetention(
              key: const ValueKey('l2_s0'),
              onNext: _nextLevel2Step,
            );
          case 1:
            return QuizStepGamification(
              key: const ValueKey('l2_s1'),
              onNext: _nextLevel2Step,
            );
          case 2:
            return QuizStepGraduationRules(
              key: const ValueKey('l2_s2'),
              onNext: _nextLevel2Step,
            );
          case 3:
          default:
            return QuizStepExtraModules(
              key: const ValueKey('l2_s3'),
              onFinish: () => _finish(completedAll: true),
            );
        }
    }
  }
}
