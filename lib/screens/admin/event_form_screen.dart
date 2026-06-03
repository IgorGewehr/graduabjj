import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/academy_event.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../services/event_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/form/form_section.dart';
import '../../widgets/form/input_field.dart';
import '../../widgets/polish/polish.dart';

/// Create / edit a Jornal post (event, news or seminar).
///
/// When [eventId] is non-null the form loads the existing post via
/// [EventService.getById] and prefills every field. On save it routes to
/// [EventService.create] or [EventService.update], handles the cover upload,
/// optionally publishes, and (when checked) notifies students.
class AdminEventFormScreen extends ConsumerStatefulWidget {
  final String? eventId;

  const AdminEventFormScreen({super.key, this.eventId});

  @override
  ConsumerState<AdminEventFormScreen> createState() =>
      _AdminEventFormScreenState();
}

class _AdminEventFormScreenState extends ConsumerState<AdminEventFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _ctaUrl = TextEditingController();
  final _ctaLabel = TextEditingController();

  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  PostType _postType = PostType.event;
  bool _notify = false;
  bool _publish = false;

  // The post being edited (null while creating, or until the load completes).
  AcademyEvent? _existing;
  // Newly-picked cover pending upload on save.
  File? _pendingCover;
  // Cover already stored on the post being edited.
  String? _existingCoverUrl;

  bool _loading = false;
  bool _saving = false;

  // Unsaved-changes tracking (see physical_assessment_form_screen.dart). The
  // snapshot is captured after prefill and after a successful save.
  late String _savedSnapshot;

  bool get _isEditing => widget.eventId != null;

  String _snapshot() {
    return [
      _title.text,
      _description.text,
      _location.text,
      _ctaUrl.text,
      _ctaLabel.text,
      _startDate.toIso8601String(),
      _endDate?.toIso8601String() ?? '',
      _postType.name,
      _notify.toString(),
      _publish.toString(),
      _pendingCover?.path ?? '',
    ].join('|');
  }

  bool get _isDirty => _snapshot() != _savedSnapshot;

  @override
  void initState() {
    super.initState();
    _savedSnapshot = _snapshot();
    for (final c in <TextEditingController>[
      _title,
      _description,
      _location,
      _ctaUrl,
      _ctaLabel,
    ]) {
      c.addListener(_onChanged);
    }
    if (_isEditing) _load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _location.dispose();
    _ctaUrl.dispose();
    _ctaLabel.dispose();
    super.dispose();
  }

  EventService? _service() {
    final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
    if (academyId == null) return null;
    return EventService(academyId);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final service = _service();
      final event = await service?.getById(widget.eventId!);
      if (!mounted) return;
      if (event == null) {
        context.showError('Publicação não encontrada.');
        Navigator.of(context).pop();
        return;
      }
      _existing = event;
      _title.text = event.title;
      _description.text = event.description;
      _location.text = event.location ?? '';
      _ctaUrl.text = event.ctaUrl ?? '';
      _ctaLabel.text = event.ctaLabel ?? '';
      _startDate = event.startDate;
      _endDate = event.endDate;
      _postType = event.postType;
      _publish = event.isPublished;
      _existingCoverUrl = event.coverUrl;
      setState(() {
        _loading = false;
        _savedSnapshot = _snapshot();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      context.showError('Não foi possível carregar: $e');
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    setState(() {
      _startDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _startDate.hour,
        _startDate.minute,
      );
      // Keep the range valid.
      if (_endDate != null && _endDate!.isBefore(_startDate)) {
        _endDate = _startDate;
      }
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null) return;
    setState(() => _endDate = picked);
  }

  Future<void> _pickCover() async {
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
        imageQuality: 80,
        maxWidth: 1280,
      );
      if (picked == null) return;
      setState(() => _pendingCover = File(picked.path));
    } catch (e) {
      if (mounted) context.showError('Não foi possível obter a imagem: $e');
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar alterações?'),
        content: const Text(
          'Você tem alterações não salvas nesta publicação. Se sair agora, '
          'elas serão perdidas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continuar editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Descartar', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      context.showWarning('Confira os campos destacados.');
      return;
    }
    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      context.showWarning('A data final não pode ser anterior à inicial.');
      return;
    }

    final service = _service();
    if (service == null) {
      context.showError('Academia não encontrada.');
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final base = _existing;
      final event = AcademyEvent(
        id: base?.id ?? '',
        academyId: service.academyId,
        title: _title.text.trim(),
        slug: base?.slug ?? '',
        description: _description.text.trim(),
        coverUrl: base?.coverUrl,
        coverStoragePath: base?.coverStoragePath,
        startDate: _startDate,
        endDate: _endDate,
        location: _location.text.trim().isEmpty ? null : _location.text.trim(),
        ctaUrl: _ctaUrl.text.trim().isEmpty ? null : _ctaUrl.text.trim(),
        ctaLabel:
            _ctaLabel.text.trim().isEmpty ? null : _ctaLabel.text.trim(),
        isPublished: _publish,
        postType: _postType,
        sourceId: base?.sourceId,
        createdAt: base?.createdAt ?? now,
        updatedAt: now,
      );

      if (_isEditing) {
        final wasPublished = base?.isPublished ?? false;
        await service.update(widget.eventId!, event, cover: _pendingCover);
        // Newly toggled on -> publish (and notify only if checked).
        if (_publish && !wasPublished) {
          await service.publish(
            widget.eventId!,
            notify: _notify ? event.copyWith(id: widget.eventId!) : null,
          );
        }
      } else {
        await service.create(
          event,
          cover: _pendingCover,
          notify: _publish && _notify,
        );
      }

      if (!mounted) return;
      _savedSnapshot = _snapshot();
      ref.invalidate(journalAllProvider);
      context.showSuccess(
        _isEditing ? 'Publicação atualizada!' : 'Publicação salva!',
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        context.showError('Não foi possível salvar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final discard = await _confirmDiscard();
        if (!discard || !mounted) return;
        _savedSnapshot = _snapshot();
        navigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.surface,
          elevation: 0,
          title: Text(_isEditing ? 'Editar publicação' : 'Nova publicação'),
        ),
        body: _loading
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: PolishSkeleton.list(count: 4, itemHeight: 120),
              )
            : SafeArea(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                    children: [
                      _coverPicker().entrance(index: 0),
                      const SizedBox(height: 12),
                      FormSection(
                        title: 'Conteúdo',
                        icon: LucideIcons.fileText,
                        child: Column(
                          children: [
                            InputField(
                              controller: _title,
                              label: 'Título',
                              hintText: 'Ex.: Seminário com o mestre',
                              textCapitalization: TextCapitalization.sentences,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Informe um título'
                                  : null,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                            ),
                            const SizedBox(height: 12),
                            InputField(
                              controller: _description,
                              label: 'Descrição',
                              hintText: 'Detalhes da publicação…',
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Informe uma descrição'
                                  : null,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                            ),
                          ],
                        ),
                      ).entrance(index: 1),
                      const SizedBox(height: 12),
                      FormSection(
                        title: 'Tipo',
                        icon: LucideIcons.tag,
                        child: _typeSelector(),
                      ).entrance(index: 2),
                      const SizedBox(height: 12),
                      FormSection(
                        title: 'Quando e onde',
                        icon: LucideIcons.calendar,
                        child: Column(
                          children: [
                            _dateField(
                              label: 'Início',
                              value: _startDate,
                              onTap: _pickStartDate,
                            ),
                            const SizedBox(height: 12),
                            _dateField(
                              label: 'Fim (opcional)',
                              value: _endDate,
                              onTap: _pickEndDate,
                              onClear: _endDate == null
                                  ? null
                                  : () => setState(() => _endDate = null),
                            ),
                            const SizedBox(height: 12),
                            InputField(
                              controller: _location,
                              label: 'Local (opcional)',
                              hintText: 'Ex.: Tatame principal',
                              textCapitalization: TextCapitalization.sentences,
                            ),
                          ],
                        ),
                      ).entrance(index: 3),
                      const SizedBox(height: 12),
                      FormSection(
                        title: 'Botão de ação',
                        subtitle: 'Link opcional exibido na publicação',
                        icon: LucideIcons.link,
                        collapsible: true,
                        defaultCollapsed: true,
                        child: Column(
                          children: [
                            InputField(
                              controller: _ctaLabel,
                              label: 'Texto do botão',
                              hintText: 'Ex.: Inscreva-se',
                            ),
                            const SizedBox(height: 12),
                            InputField(
                              controller: _ctaUrl,
                              label: 'URL',
                              hintText: 'https://…',
                              keyboardType: TextInputType.url,
                            ),
                          ],
                        ),
                      ).entrance(index: 4),
                      const SizedBox(height: 12),
                      FormSection(
                        title: 'Publicação',
                        icon: LucideIcons.send,
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              activeThumbColor: AppTheme.primary,
                              title: const Text('Publicar agora'),
                              subtitle: const Text(
                                'Visível para os alunos no portal',
                              ),
                              value: _publish,
                              onChanged: (v) => setState(() => _publish = v),
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              activeColor: AppTheme.primary,
                              controlAffinity:
                                  ListTileControlAffinity.leading,
                              title: const Text('Notificar alunos ao publicar'),
                              value: _notify,
                              onChanged: (v) =>
                                  setState(() => _notify = v ?? false),
                            ),
                          ],
                        ),
                      ).entrance(index: 5),
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
                    borderRadius: BorderRadius.circular(12),
                  ),
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
                    : Text(_isEditing ? 'Salvar alterações' : 'Salvar'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverPicker() {
    final pending = _pendingCover;
    final hasExisting =
        _existingCoverUrl != null && _existingCoverUrl!.isNotEmpty;

    Widget preview;
    if (pending != null) {
      preview = Image.file(pending, fit: BoxFit.cover);
    } else if (hasExisting) {
      preview = AppCachedImage(imageUrl: _existingCoverUrl, fit: BoxFit.cover);
    } else {
      preview = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(LucideIcons.imagePlus, size: 32, color: AppTheme.textSecondary),
            SizedBox(height: 8),
            Text(
              'Adicionar capa',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: _pickCover,
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: preview,
              ),
            ),
            if (pending != null || hasExisting)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.edit3, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Trocar capa',
                        style: TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _typeLabel(PostType type) {
    switch (type) {
      case PostType.event:
        return 'Evento';
      case PostType.news:
        return 'Notícia';
      case PostType.seminar:
        return 'Seminário';
    }
  }

  Widget _typeSelector() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<PostType>(
        segments: PostType.values
            .map(
              (type) => ButtonSegment<PostType>(
                value: type,
                label: Text(_typeLabel(type)),
                icon: Text(type.emoji, style: const TextStyle(fontSize: 16)),
              ),
            )
            .toList(),
        selected: {_postType},
        showSelectedIcon: false,
        onSelectionChanged: (selection) =>
            setState(() => _postType = selection.first),
      ),
    );
  }

  Widget _dateField({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final text = value == null
        ? '—'
        : DateFormat("d 'de' MMM 'de' y", 'pt_BR').format(value);
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: onClear != null
              ? IconButton(
                  icon: const Icon(LucideIcons.x, size: 18),
                  onPressed: onClear,
                )
              : const Icon(LucideIcons.calendar, size: 18),
        ),
        child: Text(text, style: AppTheme.bodyMedium),
      ),
    );
  }
}
