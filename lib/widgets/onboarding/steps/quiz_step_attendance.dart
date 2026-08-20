import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/portal_providers.dart';
import '../../../services/settings_service.dart';
import '../../polish/polish.dart';
import '../quiz_card_option.dart';

/// Passo de Método de Presença & Check-in no Quiz
class QuizStepAttendance extends ConsumerStatefulWidget {
  final VoidCallback onNext;

  const QuizStepAttendance({
    super.key,
    required this.onNext,
  });

  @override
  ConsumerState<QuizStepAttendance> createState() => _QuizStepAttendanceState();
}

enum _AttendanceMethod { teacherApp, qrTatame, turnstile }

class _QuizStepAttendanceState extends ConsumerState<QuizStepAttendance> {
  _AttendanceMethod _method = _AttendanceMethod.teacherApp;
  String _vendor = 'control_id';
  bool _blockOnOverdue = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(academySettingsProvider).valueOrNull;
    if (settings != null) {
      if (settings.accessControlEnabled) {
        _method = _AttendanceMethod.turnstile;
        if (settings.accessControlVendor.isNotEmpty) {
          _vendor = settings.accessControlVendor;
        }
        _blockOnOverdue = settings.accessControlBlockOnOverdue;
      } else if (settings.studentCheckinEnabled || settings.musculacaoSelfCheckin) {
        _method = _AttendanceMethod.qrTatame;
      } else {
        _method = _AttendanceMethod.teacherApp;
      }
    }
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
      if (academyId != null) {
        final service = SettingsService(academyId);
        switch (_method) {
          case _AttendanceMethod.teacherApp:
            await service.updateAttendanceCheckinMethod(
              studentCheckinEnabled: false,
              musculacaoCheckinMode: 'manual',
            );
            break;
          case _AttendanceMethod.qrTatame:
            await service.updateAttendanceCheckinMethod(
              studentCheckinEnabled: true,
              musculacaoCheckinMode: 'qr',
            );
            break;
          case _AttendanceMethod.turnstile:
            await service.updateAccessControl(
              enabled: true,
              vendor: _vendor,
              blockOnOverdue: _blockOnOverdue,
            );
            break;
        }
        ref.invalidate(academySettingsProvider);
      }
      widget.onNext();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar preferência de presença: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendors = [
      (id: 'control_id', name: 'Control iD (Facial/Digital)'),
      (id: 'henry', name: 'Henry'),
      (id: 'intelbras', name: 'Intelbras'),
      (id: 'topdata', name: 'Topdata'),
      (id: 'kiosk', name: 'Totem Kiosk (Tablet)'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Como será feita a chamada?',
                style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Escolha como seus alunos confirmarão a presença nos treinos.',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ).entrance(),
          const SizedBox(height: 20),
          QuizCardOption(
            title: 'Chamada pelo App do Professor',
            subtitle: 'Você ou seus instrutores tocam no nome dos alunos que chegaram.',
            badgeText: 'Mais Prático',
            badgeColor: AppTheme.success,
            icon: LucideIcons.clipboardCheck,
            isSelected: _method == _AttendanceMethod.teacherApp,
            onTap: () => setState(() => _method = _AttendanceMethod.teacherApp),
          ),
          QuizCardOption(
            title: 'QR Code no Tatame / Recepção',
            subtitle: 'O aluno aponta a câmera do celular para o QR Code e dá check-in sozinho.',
            badgeText: 'Sem Filas',
            badgeColor: AppTheme.info,
            icon: LucideIcons.qrCode,
            isSelected: _method == _AttendanceMethod.qrTatame,
            onTap: () => setState(() => _method = _AttendanceMethod.qrTatame),
          ),
          QuizCardOption(
            title: 'Catraca Eletrônica / Acesso',
            subtitle: 'Integração direta com catracas (Control iD, Henry, Intelbras, Topdata).',
            icon: LucideIcons.shieldCheck,
            isSelected: _method == _AttendanceMethod.turnstile,
            onTap: () => setState(() => _method = _AttendanceMethod.turnstile),
          ),
          if (_method == _AttendanceMethod.turnstile) ...[
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
                  Row(
                    children: [
                      const Icon(LucideIcons.scanFace, color: AppTheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Configuração da Catraca',
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Marca / Fabricante do seu equipamento:',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: vendors.map((v) {
                      final isSelected = _vendor == v.id;
                      return ChoiceChip(
                        label: Text(v.name),
                        selected: isSelected,
                        selectedColor: AppTheme.textPrimary,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : AppTheme.textPrimary,
                        ),
                        onSelected: (_) => setState(() => _vendor = v.id),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Checkbox(
                        value: _blockOnOverdue,
                        activeColor: AppTheme.textPrimary,
                        onChanged: (val) => setState(() => _blockOnOverdue = val ?? false),
                      ),
                      Expanded(
                        child: Text(
                          'Bloquear giro de alunos inadimplentes',
                          style: AppTheme.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/admin/catracas'),
                      icon: const Icon(LucideIcons.settings, size: 16),
                      label: const Text('Cadastrar IP / Dispositivo Agora'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: const BorderSide(color: AppTheme.textPrimary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Você também pode continuar o quiz e cadastrar os aparelhos depois em Configurações > Catracas.',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
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
