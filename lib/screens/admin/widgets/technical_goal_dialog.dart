import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/brand_tokens.dart';
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../services/services.dart';

/// Resultado do dialog de meta técnica.
enum TechnicalGoalResult { saved, completed }

/// Dialog de META TÉCNICA de curto prazo (protocolo anti-"blue belt blues",
/// §6.3 arma 1) — o professor define 1 meta de habilidade de 4-6 semanas e o
/// aluno a vê como missão ativa no hub dele.
///
/// É O MESMO dialog na ficha do aluno e no radar de retenção (blues playbook):
/// mesma escrita, mesma voz. Grava `activeGoal` no doc do aluno via update()
/// parcial (staff-only pelas rules; o aluno apenas lê).
///
/// Retorna [TechnicalGoalResult.saved] ao salvar/editar,
/// [TechnicalGoalResult.completed] ao concluir (FieldValue.delete) e `null`
/// se o professor cancelou. Os snackbars de sucesso já são exibidos aqui —
/// o chamador só precisa recarregar o aluno quando o retorno for não-nulo.
Future<TechnicalGoalResult?> showTechnicalGoalDialog(
  BuildContext context, {
  required String studentId,
  required String studentName,
  StudentGoal? current,
  required String staffName,
}) async {
  final result = await showDialog<TechnicalGoalResult>(
    context: context,
    builder: (_) => _TechnicalGoalDialog(
      studentId: studentId,
      studentName: studentName,
      current: current,
      staffName: staffName,
    ),
  );
  if (result != null && context.mounted) {
    context.showSuccess(
      result == TechnicalGoalResult.completed
          ? 'Meta concluída 👊'
          : 'Meta salva — vira missão no app do aluno',
    );
  }
  return result;
}

class _TechnicalGoalDialog extends StatefulWidget {
  const _TechnicalGoalDialog({
    required this.studentId,
    required this.studentName,
    required this.current,
    required this.staffName,
  });

  final String studentId;
  final String studentName;
  final StudentGoal? current;
  final String staffName;

  @override
  State<_TechnicalGoalDialog> createState() => _TechnicalGoalDialogState();
}

class _TechnicalGoalDialogState extends State<_TechnicalGoalDialog> {
  late final TextEditingController _textCtrl =
      TextEditingController(text: widget.current?.text ?? '');

  /// Prazo escolhido (null = sem prazo).
  DateTime? _until;

  /// 4 ou 6 quando um chip de semanas está ativo; null = sem prazo ou data
  /// customizada do date picker.
  int? _presetWeeks;

  bool _busy = false;

  bool get _isEditing => widget.current != null;

  @override
  void initState() {
    super.initState();
    // Meta existente com prazo entra como data customizada (o chip de data
    // mostra o dia exato — não "reencaixa" em 4/6 semanas).
    _until = widget.current?.until;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _selectNoDeadline() => setState(() {
        _until = null;
        _presetWeeks = null;
      });

  void _selectWeeks(int weeks) => setState(() {
        _presetWeeks = weeks;
        _until = DateTime.now().add(Duration(days: weeks * 7));
      });

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = now.add(const Duration(days: 1));
    var initial = _until ?? now.add(const Duration(days: 28));
    if (initial.isBefore(first)) initial = first;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Prazo da meta',
    );
    if (picked != null && mounted) {
      setState(() {
        _until = picked;
        _presetWeeks = null;
      });
    }
  }

  Future<void> _save() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await StudentService(FirebaseService.academyId)
          .update(widget.studentId, {
        'activeGoal': {
          'text': text,
          'until': _until != null ? Timestamp.fromDate(_until!) : null,
          'setByName': widget.staffName,
          'setAt': FieldValue.serverTimestamp(),
        },
      });
      if (mounted) Navigator.pop(context, TechnicalGoalResult.saved);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        context.showError('Não deu pra salvar a meta');
      }
    }
  }

  Future<void> _complete() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await StudentService(FirebaseService.academyId)
          .update(widget.studentId, {'activeGoal': FieldValue.delete()});
      if (mounted) Navigator.pop(context, TechnicalGoalResult.completed);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        context.showError('Não deu pra concluir a meta');
      }
    }
  }

  Widget _deadlineChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return ChoiceChip(
      avatar: icon != null
          ? Icon(icon, size: 14, color: selected ? Colors.white : Brand.ink)
          : null,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        color: selected ? Colors.white : Brand.ink,
      ),
      selected: selected,
      selectedColor: Brand.ink,
      visualDensity: VisualDensity.compact,
      onSelected: _busy ? null : (_) => onTap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _textCtrl.text.trim().isNotEmpty && !_busy;
    final customSelected = _until != null && _presetWeeks == null;

    return AlertDialog(
      backgroundColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Meta técnica',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            widget.studentName,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Brand.ash,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _textCtrl,
              autofocus: !_isEditing,
              enabled: !_busy,
              maxLength: 100,
              minLines: 1,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Ex.: Finalizar 3x da guarda fechada',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'PRAZO (OPCIONAL)',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: Brand.ash,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _deadlineChip(
                  label: 'SEM PRAZO',
                  selected: _until == null,
                  onTap: _selectNoDeadline,
                ),
                _deadlineChip(
                  label: '4 SEMANAS',
                  selected: _presetWeeks == 4,
                  onTap: () => _selectWeeks(4),
                ),
                _deadlineChip(
                  label: '6 SEMANAS',
                  selected: _presetWeeks == 6,
                  onTap: () => _selectWeeks(6),
                ),
                _deadlineChip(
                  icon: LucideIcons.calendar,
                  label: customSelected
                      ? DateFormat('dd/MM/yy').format(_until!)
                      : 'DATA',
                  selected: customSelected,
                  onTap: _pickDate,
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (_isEditing)
          TextButton.icon(
            onPressed: _busy ? null : _complete,
            icon: const Icon(LucideIcons.checkCircle2,
                size: 16, color: AppTheme.success),
            label: const Text(
              'CONCLUIR',
              style: TextStyle(
                color: AppTheme.success,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text(
            'CANCELAR',
            style: TextStyle(color: Brand.ash, fontWeight: FontWeight.w800),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Brand.blood),
          onPressed: canSave ? _save : null,
          child: Text(
            _isEditing ? 'SALVAR' : 'DEFINIR META',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}
