import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/physical_assessment.dart';
import '../../providers/auth_provider.dart';
import '../../services/physical_assessment_service.dart';
import '../../widgets/form/form_section.dart';
import '../../widgets/form/input_field.dart';

/// Form to create/edit a physical assessment (Fase 1 — measurements only;
/// photos come in Fase 2). Pop returns `true` when an assessment was saved.
class PhysicalAssessmentFormScreen extends ConsumerStatefulWidget {
  final String academyId;
  final String studentId;
  final String studentName;

  /// When set, the form edits this assessment instead of creating a new one.
  final PhysicalAssessment? existing;

  const PhysicalAssessmentFormScreen({
    super.key,
    required this.academyId,
    required this.studentId,
    required this.studentName,
    this.existing,
  });

  @override
  ConsumerState<PhysicalAssessmentFormScreen> createState() =>
      _PhysicalAssessmentFormScreenState();
}

class _PhysicalAssessmentFormScreenState
    extends ConsumerState<PhysicalAssessmentFormScreen> {
  // pt-BR girth labels for PhysicalAssessment.girthKeys.
  static const Map<String, String> _girthLabels = {
    'neck': 'Pescoço', 'shoulder': 'Ombro', 'chest': 'Tórax', 'waist': 'Cintura',
    'abdomen': 'Abdômen', 'hip': 'Quadril', 'armR': 'Braço D', 'armL': 'Braço E',
    'forearmR': 'Antebraço D', 'forearmL': 'Antebraço E', 'thighR': 'Coxa D',
    'thighL': 'Coxa E', 'calfR': 'Panturrilha D', 'calfL': 'Panturrilha E',
  };
  static const Map<String, String> _skinfoldLabels = {
    'triceps': 'Tríceps', 'subscapular': 'Subescapular', 'suprailiac': 'Supra-ilíaca',
    'abdominal': 'Abdominal', 'thigh': 'Coxa',
  };
  static const Map<String, String> _goals = {
    'hipertrofia': 'Hipertrofia', 'emagrecimento': 'Emagrecimento',
    'condicionamento': 'Condicionamento', 'manutencao': 'Manutenção',
  };

  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _bodyFat = TextEditingController();
  final _notes = TextEditingController();
  final Map<String, TextEditingController> _girths = {
    for (final k in PhysicalAssessment.girthKeys) k: TextEditingController(),
  };
  late final Map<String, TextEditingController> _skinfolds = {
    for (final k in _skinfoldLabels.keys) k: TextEditingController(),
  };

  late DateTime _date;
  String? _goal;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e?.date ?? DateTime.now();
    _goal = e?.goal;
    if (e != null) {
      if (e.weightKg != null) _weight.text = _fmt(e.weightKg!);
      if (e.heightCm != null) _height.text = _fmt(e.heightCm!);
      if (e.bodyFatPct != null) _bodyFat.text = _fmt(e.bodyFatPct!);
      _notes.text = e.notes ?? '';
      e.measurements.forEach((k, v) => _girths[k]?.text = _fmt(v));
      e.skinfolds.forEach((k, v) => _skinfolds[k]?.text = _fmt(v));
    }
    // IMC ao vivo conforme peso/altura mudam.
    _weight.addListener(_onChanged);
    _height.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _weight.dispose();
    _height.dispose();
    _bodyFat.dispose();
    _notes.dispose();
    for (final c in _girths.values) {
      c.dispose();
    }
    for (final c in _skinfolds.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  double? _parse(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Map<String, double> _collect(Map<String, TextEditingController> src) {
    final out = <String, double>{};
    src.forEach((k, c) {
      final v = _parse(c);
      if (v != null) out[k] = v;
    });
    return out;
  }

  double? get _bmiPreview {
    final w = _parse(_weight), h = _parse(_height);
    if (w == null || h == null || h == 0) return null;
    final m = h / 100.0;
    return w / (m * m);
  }

  Future<void> _save() async {
    final w = _parse(_weight);
    final h = _parse(_height);
    // Avaliação totalmente vazia não faz sentido salvar.
    if (w == null &&
        h == null &&
        _parse(_bodyFat) == null &&
        _collect(_girths).isEmpty &&
        _collect(_skinfolds).isEmpty) {
      context.showWarning('Preencha ao menos uma medida.');
      return;
    }

    setState(() => _saving = true);
    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      final assessment = PhysicalAssessment(
        id: widget.existing?.id ?? '',
        studentId: widget.studentId,
        studentName: widget.studentName,
        date: _date,
        weightKg: w,
        heightCm: h,
        bodyFatPct: _parse(_bodyFat),
        measurements: _collect(_girths),
        skinfolds: _collect(_skinfolds),
        photos: widget.existing?.photos ?? const [],
        goal: _goal,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        assessedBy: user?.id ?? '',
        assessedByName: user?.displayName ?? '',
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      );

      final service = PhysicalAssessmentService(widget.academyId);
      if (_isEditing) {
        await service.update(widget.existing!.id, assessment);
      } else {
        await service.create(assessment);
      }
      if (!mounted) return;
      context.showSuccess(
          _isEditing ? 'Avaliação atualizada!' : 'Avaliação registrada!');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        context.showError('Não foi possível salvar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bmi = _bmiPreview;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        title: Text(_isEditing ? 'Editar avaliação' : 'Nova avaliação'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            // Aluno + data
            FormSection(
              title: widget.studentName,
              icon: LucideIcons.user,
              child: Column(
                children: [
                  InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Data da avaliação',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(LucideIcons.calendar, size: 18),
                      ),
                      child: Text(
                        '${_date.day.toString().padLeft(2, '0')}/'
                        '${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                        style: AppTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Básico + IMC
            FormSection(
              title: 'Peso e composição',
              icon: LucideIcons.scale,
              child: Column(
                children: [
                  FormRow(children: [
                    _num(_weight, 'Peso', 'kg'),
                    _num(_height, 'Altura', 'cm'),
                  ]),
                  const SizedBox(height: 12),
                  FormRow(children: [
                    _num(_bodyFat, '% Gordura', '%'),
                    _ImcBox(bmi: bmi),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Perimetria (opcional, recolhível)
            FormSection(
              title: 'Medidas (perimetria)',
              subtitle: 'Circunferências em cm — opcional',
              icon: LucideIcons.ruler,
              badge: 'Opcional',
              collapsible: true,
              defaultCollapsed: true,
              child: Column(
                children: [
                  for (var i = 0; i < PhysicalAssessment.girthKeys.length; i += 2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FormRow(children: [
                        _num(_girths[PhysicalAssessment.girthKeys[i]]!,
                            _girthLabels[PhysicalAssessment.girthKeys[i]]!, 'cm'),
                        if (i + 1 < PhysicalAssessment.girthKeys.length)
                          _num(
                              _girths[PhysicalAssessment.girthKeys[i + 1]]!,
                              _girthLabels[PhysicalAssessment.girthKeys[i + 1]]!,
                              'cm')
                        else
                          const SizedBox(),
                      ]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Dobras cutâneas (opcional, recolhível)
            FormSection(
              title: 'Dobras cutâneas',
              subtitle: 'Em mm — opcional',
              icon: LucideIcons.minimize2,
              badge: 'Opcional',
              collapsible: true,
              defaultCollapsed: true,
              child: Column(
                children: [
                  for (final k in _skinfoldLabels.keys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _num(_skinfolds[k]!, _skinfoldLabels[k]!, 'mm'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Meta + notas
            FormSection(
              title: 'Objetivo e observações',
              icon: LucideIcons.target,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String?>(
                    value: _goal,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Objetivo',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      ..._goals.entries.map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          )),
                    ],
                    onChanged: (v) => setState(() => _goal = v),
                  ),
                  const SizedBox(height: 12),
                  InputField(
                    controller: _notes,
                    label: 'Observações',
                    hintText: 'Ex.: avaliação inicial, lesão no ombro…',
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(_isEditing ? 'Salvar alterações' : 'Salvar avaliação'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _num(TextEditingController c, String label, String unit) {
    return InputField(
      controller: c,
      label: label,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      suffix: Text(unit, style: AppTheme.labelSmall.copyWith(
        color: AppTheme.textSecondary,
      )),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2010),
      lastDate: DateTime.now(),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) setState(() => _date = picked);
  }
}

/// Read-only IMC box that mirrors the look of an [InputField] value.
class _ImcBox extends StatelessWidget {
  final double? bmi;
  const _ImcBox({this.bmi});

  @override
  Widget build(BuildContext context) {
    final b = bmi;
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'IMC',
        border: OutlineInputBorder(),
      ),
      child: Text(
        b == null ? '—' : b.toStringAsFixed(1),
        style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
