import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/body_composition.dart';
import '../../core/feedback_utils.dart';
import '../../core/measurement_input.dart';
import '../../core/theme.dart';
// PhysicalAssessment/AssessmentPhoto come via the service barrel below.
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../services/photo_upload_service.dart';
import '../../services/physical_assessment_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/form/form_section.dart';
import '../../widgets/form/input_field.dart';

/// Form to create/edit a physical assessment. Pop returns `true` when an
/// assessment was saved. Evolution photos (Fase 2) are shown only when
/// [allowPhotos] is true (adults only — minors are excluded to avoid
/// app-store UGC/minor issues and LGPD concerns).
class PhysicalAssessmentFormScreen extends ConsumerStatefulWidget {
  final String academyId;
  final String studentId;
  final String studentName;

  /// Whether the evolution-photos section is shown. Pass `true` only for
  /// adult students.
  final bool allowPhotos;

  /// Student sex/age — used to estimate body fat % from skinfolds (Pollock).
  /// Null when unknown; the estimate is simply hidden.
  final Sex? studentSex;
  final int? studentAge;

  /// When set, the form edits this assessment instead of creating a new one.
  final PhysicalAssessment? existing;

  const PhysicalAssessmentFormScreen({
    super.key,
    required this.academyId,
    required this.studentId,
    required this.studentName,
    this.allowPhotos = false,
    this.studentSex,
    this.studentAge,
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
  // Skinfold sites (mm). Includes the Jackson-Pollock 3-site sets for both
  // sexes: men = chest+abdominal+thigh, women = triceps+suprailiac+thigh.
  static const Map<String, String> _skinfoldLabels = {
    'triceps': 'Tríceps', 'chest': 'Peitoral', 'subscapular': 'Subescapular',
    'suprailiac': 'Supra-ilíaca', 'abdominal': 'Abdominal', 'thigh': 'Coxa',
  };
  static const Map<String, String> _goals = {
    'hipertrofia': 'Hipertrofia', 'emagrecimento': 'Emagrecimento',
    'condicionamento': 'Condicionamento', 'manutencao': 'Manutenção',
  };

  // Evolution photo angles (Fase 2). Order is the display order.
  static const List<String> _photoAngles = ['front', 'side', 'back'];
  static const Map<String, String> _photoLabels = {
    'front': 'Frente', 'side': 'Lado', 'back': 'Costas',
  };

  final _picker = ImagePicker();
  // Photos already saved on the assessment, keyed by angle.
  final Map<String, AssessmentPhoto> _existingPhotos = {};
  // Newly-picked photos pending upload on save, keyed by angle (override
  // existing for the same angle).
  final Map<String, File> _pendingPhotos = {};
  // Storage paths of existing photos the user removed — deleted on save.
  final Set<String> _photosToDelete = {};

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
  final _formKey = GlobalKey<FormState>();

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
      for (final p in e.photos) {
        _existingPhotos[p.angle] = p;
      }
    }
    // IMC ao vivo conforme peso/altura mudam.
    _weight.addListener(_onChanged);
    _height.addListener(_onChanged);
    // % gordura estimada (Pollock) ao vivo conforme as dobras mudam.
    for (final c in _skinfolds.values) {
      c.addListener(_onChanged);
    }
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

  double? _parse(TextEditingController c) => parseDecimalInput(c.text);

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

  /// % gordura estimada pelas dobras (Jackson-Pollock 3 dobras). Null quando
  /// faltam sexo, idade ou alguma das 3 dobras do protocolo.
  double? get _pollockFat {
    final sex = widget.studentSex;
    final age = widget.studentAge;
    if (sex == null || age == null) return null;
    return pollockBodyFatPct(
      isMale: sex == Sex.male,
      age: age,
      skinfolds: _collect(_skinfolds),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? true)) {
      context.showWarning('Confira os campos destacados.');
      return;
    }
    final w = _parse(_weight);
    final h = _parse(_height);
    // Avaliação totalmente vazia não faz sentido salvar.
    if (w == null &&
        h == null &&
        _parse(_bodyFat) == null &&
        _collect(_girths).isEmpty &&
        _collect(_skinfolds).isEmpty &&
        _existingPhotos.isEmpty &&
        _pendingPhotos.isEmpty) {
      context.showWarning('Preencha ao menos uma medida ou foto.');
      return;
    }

    setState(() => _saving = true);
    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      // Upload pending photos and assemble the list; `toDelete` collects the
      // storage paths of replaced/removed objects to clean up ONLY after the
      // Firestore write succeeds (so a failed write never orphans the doc).
      final toDelete = <String>{};
      final photos = await _resolvePhotos(toDelete);
      // Derive fat/lean mass when weight + % gordura are both known.
      final bodyFat = _parse(_bodyFat);
      final split = (w != null && bodyFat != null)
          ? bodyMassSplit(weightKg: w, bodyFatPct: bodyFat)
          : null;
      final assessment = PhysicalAssessment(
        id: widget.existing?.id ?? '',
        studentId: widget.studentId,
        studentName: widget.studentName,
        date: _date,
        weightKg: w,
        heightCm: h,
        bodyFatPct: bodyFat,
        leanMassKg: split?.leanMassKg,
        fatMassKg: split?.fatMassKg,
        measurements: _collect(_girths),
        skinfolds: _collect(_skinfolds),
        photos: photos,
        goal: _goal,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        // Preserva quem fez a avaliação original ao editar; no create usa o
        // usuário logado.
        assessedBy: widget.existing?.assessedBy ?? (user?.id ?? ''),
        assessedByName:
            widget.existing?.assessedByName ?? (user?.displayName ?? ''),
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
      );

      final service = PhysicalAssessmentService(widget.academyId);
      if (_isEditing) {
        await service.update(widget.existing!.id, assessment);
      } else {
        await service.create(assessment);
      }
      // Doc saved — now safe to delete orphaned storage objects (best-effort;
      // a leaked object is harmless, a deleted-but-still-referenced one is not).
      if (toDelete.isNotEmpty) {
        final uploadService = PhotoUploadService();
        for (final path in toDelete) {
          try {
            await uploadService.deleteAssessmentPhoto(storagePath: path);
          } catch (_) {/* orphan cleanup is non-critical */}
        }
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

  /// Uploads pending photos and assembles the final photo list. Existing
  /// photos are kept as-is unless replaced/removed. Storage paths of
  /// replaced/removed objects are added to [outToDelete]; the caller deletes
  /// them only after the Firestore write succeeds.
  Future<List<AssessmentPhoto>> _resolvePhotos(Set<String> outToDelete) async {
    // Photos section hidden (non-adult) — never touch existing photos.
    if (!widget.allowPhotos) return widget.existing?.photos ?? const [];

    outToDelete.addAll(_photosToDelete);
    final uploadService = PhotoUploadService();
    final result = <AssessmentPhoto>[];

    for (final angle in _photoAngles) {
      final pending = _pendingPhotos[angle];
      if (pending != null) {
        final old = _existingPhotos[angle];
        if (old != null && old.storagePath.isNotEmpty) {
          outToDelete.add(old.storagePath);
        }
        final up = await uploadService.uploadAssessmentPhoto(
          academyId: widget.academyId,
          studentId: widget.studentId,
          imageFile: pending,
          angle: angle,
        );
        result.add(AssessmentPhoto(
          url: up.url,
          storagePath: up.storagePath,
          angle: angle,
          takenAt: _date,
        ));
      } else if (_existingPhotos.containsKey(angle)) {
        result.add(_existingPhotos[angle]!);
      }
    }
    return result;
  }

  Future<void> _pickPhoto(String angle) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.image),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1080,
      );
      if (picked == null) return;
      setState(() => _pendingPhotos[angle] = File(picked.path));
    } catch (e) {
      if (mounted) context.showError('Não foi possível obter a imagem: $e');
    }
  }

  void _removePhoto(String angle) {
    setState(() {
      _pendingPhotos.remove(angle);
      final old = _existingPhotos.remove(angle);
      if (old != null && old.storagePath.isNotEmpty) {
        _photosToDelete.add(old.storagePath);
      }
    });
  }

  Widget _buildPhotoSection() {
    return FormSection(
      title: 'Fotos de evolução',
      subtitle: 'Frente, lado e costas — opcional, privadas',
      icon: LucideIcons.camera,
      badge: 'Opcional',
      collapsible: true,
      defaultCollapsed: true,
      child: Row(
        children: [
          for (final angle in _photoAngles) ...[
            Expanded(child: _photoSlot(angle)),
            if (angle != _photoAngles.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _photoSlot(String angle) {
    final pending = _pendingPhotos[angle];
    final existing = _existingPhotos[angle];
    final hasPhoto = pending != null || existing != null;

    Widget preview;
    if (pending != null) {
      preview = Image.file(pending, fit: BoxFit.cover);
    } else if (existing != null) {
      preview = AppCachedImage(imageUrl: existing.url, fit: BoxFit.cover);
    } else {
      preview = const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_photoLabels[angle]!, style: AppTheme.labelSmall),
        const SizedBox(height: 4),
        AspectRatio(
          aspectRatio: 3 / 4,
          child: InkWell(
            onTap: () => _pickPhoto(angle),
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: hasPhoto
                        ? preview
                        : const Center(
                            child: Icon(LucideIcons.plus,
                                color: AppTheme.textSecondary),
                          ),
                  ),
                ),
                if (hasPhoto)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: () => _removePhoto(angle),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.x,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
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
        child: Form(
          key: _formKey,
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
                    _num(_weight, 'Peso', 'kg', min: 20, max: 300),
                    _num(_height, 'Altura', 'cm', min: 50, max: 250),
                  ]),
                  const SizedBox(height: 12),
                  FormRow(children: [
                    // max alinhado ao teto sanitário do cálculo de Pollock (75)
                    // para a estimativa nunca preencher um valor que o campo
                    // depois rejeita.
                    _num(_bodyFat, '% Gordura', '%', min: 1, max: 75),
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
                            _girthLabels[PhysicalAssessment.girthKeys[i]]!, 'cm',
                            min: 5, max: 250),
                        if (i + 1 < PhysicalAssessment.girthKeys.length)
                          _num(
                              _girths[PhysicalAssessment.girthKeys[i + 1]]!,
                              _girthLabels[PhysicalAssessment.girthKeys[i + 1]]!,
                              'cm', min: 5, max: 250)
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
                      child: _num(_skinfolds[k]!, _skinfoldLabels[k]!, 'mm',
                          min: 1, max: 100),
                    ),
                  _pollockBox(),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Fotos de evolução (somente adultos)
            if (widget.allowPhotos) ...[
              _buildPhotoSection(),
              const SizedBox(height: 12),
            ],

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

  /// Live "% gordura estimada (Pollock)" helper shown under the skinfolds.
  /// Guides the user when sex/age/sites are missing, and offers to copy the
  /// estimate into the % Gordura field.
  Widget _pollockBox() {
    final sex = widget.studentSex;
    final age = widget.studentAge;

    Widget shell(Widget child, {Color? bg}) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bg ?? AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: child,
        );

    final hintStyle =
        AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary);

    if (sex == null) {
      return shell(Row(children: [
        const Icon(LucideIcons.info, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Defina o sexo do aluno no cadastro para estimar a % de gordura '
            'pelas dobras.',
            style: hintStyle,
          ),
        ),
      ]));
    }
    if (age == null) {
      return shell(Row(children: [
        const Icon(LucideIcons.info, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Informe a data de nascimento do aluno para estimar a % de '
            'gordura pelas dobras.',
            style: hintStyle,
          ),
        ),
      ]));
    }

    final fat = _pollockFat;
    if (fat == null) {
      final sites = pollock3Sites(isMale: sex == Sex.male)
          .map((k) => _skinfoldLabels[k] ?? k)
          .join(', ');
      return shell(Row(children: [
        const Icon(LucideIcons.info, size: 14, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Preencha as 3 dobras do protocolo (${sex.label}): $sites.',
            style: hintStyle,
          ),
        ),
      ]));
    }

    return shell(
      bg: AppTheme.primary.withValues(alpha: 0.08),
      Row(
        children: [
          const Icon(LucideIcons.calculator, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '% gordura estimada (Pollock 3 dobras): '
              '${_fmt(double.parse(fat.toStringAsFixed(1)))}%',
              style: AppTheme.bodySmall.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () {
              _bodyFat.text = _fmt(double.parse(fat.toStringAsFixed(1)));
              setState(() {});
              context.showSuccess('% Gordura preenchida com a estimativa.');
            },
            child: const Text('Usar'),
          ),
        ],
      ),
    );
  }

  Widget _num(TextEditingController c, String label, String unit,
      {double? min, double? max}) {
    return InputField(
      controller: c,
      label: label,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      validator: (v) =>
          validateOptionalMeasure(v, label: label, min: min, max: max),
      autovalidateMode: AutovalidateMode.onUserInteraction,
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
