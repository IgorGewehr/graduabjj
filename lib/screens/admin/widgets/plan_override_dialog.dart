import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../services/services.dart';

/// Edita o valor e o dia de vencimento de UM aluno dentro de um plano.
/// Devolve `true` se algo foi gravado (o chamador recarrega).
///
/// Mesmo contrato dos diálogos que já existem em student_detail_screen e
/// paying_students_screen (valor igual ao do plano ⇒ remove o override em vez
/// de gravar um "personalizado" fantasma), mas com validação visível — lá um
/// valor inválido simplesmente não fazia nada — e gravando só o que mudou.
/// Permissão: `plans` só aceita escrita de admin (firestore.rules), quem
/// chama é responsável por não abrir isto para outro papel.
Future<bool> showPlanOverrideDialog(
  BuildContext context, {
  required Plan plan,
  required String studentId,
  required String studentName,
}) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => _PlanOverrideDialog(
      plan: plan,
      studentId: studentId,
      studentName: studentName,
    ),
  );
  return changed == true;
}

class _PlanOverrideDialog extends StatefulWidget {
  final Plan plan;
  final String studentId;
  final String studentName;

  const _PlanOverrideDialog({
    required this.plan,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<_PlanOverrideDialog> createState() => _PlanOverrideDialogState();
}

class _PlanOverrideDialogState extends State<_PlanOverrideDialog> {
  late final TextEditingController _valueController;
  late final TextEditingController _dueDayController;
  String? _valueError;
  String? _dueDayError;
  String? _saveError;
  bool _saving = false;

  Plan get _plan => widget.plan;
  String get _id => widget.studentId;

  @override
  void initState() {
    super.initState();
    _valueController = TextEditingController(
      text: _plan.getStudentValue(_id).toStringAsFixed(2),
    );
    _dueDayController = TextEditingController(
      text: _plan.getStudentDueDay(_id).toString(),
    );
  }

  @override
  void dispose() {
    _valueController.dispose();
    _dueDayController.dispose();
    super.dispose();
  }

  /// Roda [action] com o botão travado e fecha como "alterado" se der certo;
  /// em erro mantém o diálogo aberto com a mensagem (não perde o que foi
  /// digitado).
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = 'Não foi possível salvar. Tente novamente.';
        });
      }
    }
  }

  Future<void> _save() async {
    final value = double.tryParse(_valueController.text.replaceAll(',', '.'));
    final dueDay = int.tryParse(_dueDayController.text.trim());
    setState(() {
      _valueError = (value == null || value <= 0)
          ? 'Informe um valor maior que zero'
          : null;
      _dueDayError = (dueDay == null || dueDay < 1 || dueDay > 31)
          ? 'Informe um dia de 1 a 31'
          : null;
    });
    if (_valueError != null || _dueDayError != null) return;

    final valueChanged =
        (value! - _plan.getStudentValue(_id)).abs() >= 0.005;
    final dueDayChanged = dueDay! != _plan.getStudentDueDay(_id);
    if (!valueChanged && !dueDayChanged) {
      Navigator.of(context).pop(false);
      return;
    }

    final service = PlanService(FirebaseService.academyId);
    await _run(() async {
      if (valueChanged) {
        // Comparado ao valor POR PERÍODO (trimestral/semestral não são o
        // monthlyValue) — senão ficaria um customValues fantasma.
        if ((value - _plan.effectivePeriodValue).abs() < 0.005) {
          await service.removeCustomValue(_plan.id, _id);
        } else {
          await service.setCustomValue(_plan.id, _id, value);
        }
      }
      if (dueDayChanged) {
        if (dueDay == _plan.defaultDueDay) {
          await service.removeCustomDueDay(_plan.id, _id);
        } else {
          await service.setCustomDueDay(_plan.id, _id, dueDay);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomValue = _plan.customValues.containsKey(_id);
    final hasCustomDueDay = _plan.customDueDays.containsKey(_id);

    return AlertDialog(
      title: Text(widget.studentName),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Valor padrão do plano: ${_plan.formattedValue}',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _valueController,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Valor do aluno',
                prefixText: 'R\$ ',
                errorText: _valueError,
                border: const OutlineInputBorder(),
              ),
            ),
            if (hasCustomValue)
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => _run(
                        () => PlanService(
                          FirebaseService.academyId,
                        ).removeCustomValue(_plan.id, _id),
                      ),
                icon: const Icon(LucideIcons.rotateCcw, size: 16),
                label: const Text('Restaurar valor do plano'),
              ),
            const SizedBox(height: 16),
            Text(
              'Vencimento padrão do plano: dia ${_plan.defaultDueDay}',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _dueDayController,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Dia de vencimento',
                hintText: '1-31',
                errorText: _dueDayError,
                border: const OutlineInputBorder(),
              ),
            ),
            if (hasCustomDueDay)
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => _run(
                        () => PlanService(
                          FirebaseService.academyId,
                        ).removeCustomDueDay(_plan.id, _id),
                      ),
                icon: const Icon(LucideIcons.rotateCcw, size: 16),
                label: const Text('Restaurar vencimento do plano'),
              ),
            if (_saveError != null) ...[
              const SizedBox(height: 12),
              Text(
                _saveError!,
                style: AppTheme.bodySmall.copyWith(color: AppTheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Salvar'),
        ),
      ],
    );
  }
}
