import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/sports.dart';
import '../../../core/theme.dart';
import '../../../models/academy.dart';
import '../../../models/student.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/join_request_providers.dart';
import '../../../providers/onboarding_providers.dart';
import '../../../providers/portal_providers.dart';
import '../../../services/student_service.dart';
import '../../../services/team_service.dart';
import '../../form/input_field.dart';
import '../../polish/polish.dart';
import '../quiz_card_option.dart';

/// Passo 3 do Nível 1: Entrada dos Alunos (Código de Convite ou Cadastro Rápido)
class QuizStepStudents extends ConsumerStatefulWidget {
  final VoidCallback onNext;

  const QuizStepStudents({
    super.key,
    required this.onNext,
  });

  @override
  ConsumerState<QuizStepStudents> createState() => _QuizStepStudentsState();
}

enum _StudentEntryMode { inviteCode, manualAdd }

class _QuizStepStudentsState extends ConsumerState<QuizStepStudents> {
  _StudentEntryMode _mode = _StudentEntryMode.inviteCode;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final List<Student> _addedStudents = [];
  bool _saving = false;
  bool _generatingCode = false;
  bool _autoGenerateCodeTried = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _generateCode(String academyId) async {
    if (_generatingCode) return;
    setState(() => _generatingCode = true);
    try {
      await TeamService().rotateAcademyJoinCode(academyId);
      ref.invalidate(academyJoinCodeProvider);
    } catch (_) {
      // Best-effort
    } finally {
      if (mounted) setState(() => _generatingCode = false);
    }
  }

  Future<void> _addStudentManual() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o nome do aluno')),
      );
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
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      );

      ref.invalidate(hasStudentsExistProvider);

      if (mounted) {
        setState(() {
          _addedStudents.add(student);
          _nameController.clear();
          _phoneController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao cadastrar aluno: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final academyId = ref.watch(currentUserProvider).valueOrNull?.academyId ?? '';
    final codeAsync = ref.watch(academyJoinCodeProvider);
    final code = codeAsync.valueOrNull;

    if (!_autoGenerateCodeTried &&
        !_generatingCode &&
        academyId.isNotEmpty &&
        codeAsync.hasValue &&
        (code == null || code.isEmpty)) {
      _autoGenerateCodeTried = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _generateCode(academyId));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Como prefere colocar seus alunos?',
                style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Eles podem se cadastrar pelo link ou você pode adicionar agora.',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ).entrance(),
          const SizedBox(height: 20),
          QuizCardOption(
            title: 'Auto-cadastro por Código / WhatsApp',
            subtitle: 'Envie o código da academia no grupo. Os alunos entram e você só aprova.',
            badgeText: 'Mais Fácil',
            badgeColor: AppTheme.success,
            icon: LucideIcons.send,
            isSelected: _mode == _StudentEntryMode.inviteCode,
            onTap: () => setState(() => _mode = _StudentEntryMode.inviteCode),
          ),
          if (_mode == _StudentEntryMode.inviteCode) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                children: [
                  Text(
                    'CÓDIGO DE ENTRADA DA ACADEMIA',
                    style: AppTheme.labelSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),
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
                          style: AppTheme.headlineLarge.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Copiar código',
                          icon: const Icon(LucideIcons.copy, size: 20),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Código copiado com sucesso!')),
                            );
                          },
                        ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: (code == null || code.isEmpty)
                          ? null
                          : () {
                              final academyName = ref.read(academySettingsProvider).valueOrNull?.name ?? 'nossa academia';
                              final message = '🥋 *Convite da $academyName*\n\n'
                                  'Fala pessoal! O aplicativo oficial da nossa academia já está disponível para você acompanhar suas presenças, graduações e treinos.\n\n'
                                  '📲 *1. Baixe o app oficial:*\n'
                                  '🤖 *Android (Google Play):*\n'
                                  'https://play.google.com/store/apps/details?id=com.tensorroot.graduabjj\n\n'
                                  '🍎 *iPhone (App Store):*\n'
                                  'https://apps.apple.com/app/graduabjj/id6742323719\n\n'
                                  '🔑 *2. Nosso Código de Acesso:*\n'
                                  '*$code*\n\n'
                                  '👉 *Como entrar:*\n'
                                  '• Baixe e abra o app\n'
                                  '• Toque em "Entrar com Código"\n'
                                  '• Digite o código *$code* para entrar na nossa turma!';
                              Share.share(message);
                            },
                      icon: const Icon(LucideIcons.share2, size: 18),
                      label: const Text('Compartilhar no WhatsApp'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: const BorderSide(color: AppTheme.textPrimary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          QuizCardOption(
            title: 'Cadastrar manualmente meus alunos',
            subtitle: 'Adicione o nome dos seus primeiros alunos agora mesmo.',
            icon: LucideIcons.userPlus,
            isSelected: _mode == _StudentEntryMode.manualAdd,
            onTap: () => setState(() => _mode = _StudentEntryMode.manualAdd),
          ),
          if (_mode == _StudentEntryMode.manualAdd) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InputField(
                    controller: _nameController,
                    label: 'Nome do Aluno',
                    hintText: 'Ex.: Carlos Gracie',
                    prefixIcon: LucideIcons.user,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 10),
                  InputField(
                    controller: _phoneController,
                    label: 'Telefone / WhatsApp (Opcional)',
                    hintText: '(00) 00000-0000',
                    prefixIcon: LucideIcons.phone,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _addStudentManual,
                      icon: const Icon(LucideIcons.plus, size: 18),
                      label: const Text('Adicionar Aluno'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: const BorderSide(color: AppTheme.textPrimary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  if (_addedStudents.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Alunos adicionados (${_addedStudents.length}):',
                      style: AppTheme.labelSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ..._addedStudents.map(
                      (s) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.checkCircle2, size: 16, color: AppTheme.success),
                            const SizedBox(width: 8),
                            Text(s.fullName, style: AppTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text(
                'Continuar',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
