import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../models/training_video.dart';
import '../../models/workout_plan.dart' show WorkoutAudience;
import '../../providers/auth_provider.dart';
import '../../services/services.dart';
import '../../widgets/common/sport_chip.dart';

/// Admin list of training videos + entry point to the form.
class TrainingVideosScreen extends ConsumerStatefulWidget {
  const TrainingVideosScreen({super.key});

  @override
  ConsumerState<TrainingVideosScreen> createState() =>
      _TrainingVideosScreenState();
}

class _TrainingVideosScreenState extends ConsumerState<TrainingVideosScreen> {
  bool _loading = true;
  List<TrainingVideo> _videos = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _videos = await TrainingVideoService(FirebaseService.academyId).listAll();
    } catch (_) {
      _videos = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openForm([TrainingVideo? video]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TrainingVideoFormScreen(video: video)),
    );
    if (changed == true) _load();
  }

  String _audienceLabel(TrainingVideo v) {
    switch (v.audience) {
      case WorkoutAudience.academy:
        return 'Toda a academia';
      case WorkoutAudience.sport:
        return v.sport == null
            ? 'Por modalidade'
            : sports[v.sportId]?.label ?? 'Modalidade';
      case WorkoutAudience.students:
        return '${v.assignedStudentIds.length} aluno(s)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Videos'),
        backgroundColor: AppTheme.surface,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Novo video'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _videos.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: _videos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final v = _videos[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openForm(v),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                v.source == VideoSource.upload
                                    ? Icons.movie_outlined
                                    : Icons.link,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v.title,
                                      style: AppTheme.bodyLarge.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _audienceLabel(v),
                                      style: AppTheme.labelSmall.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (v.sportId != null) SportChip(sportId: v.sportId!),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_outlined,
                size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(
              'Nenhum video ainda.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              'Cole um link (YouTube/Vimeo) ou suba um arquivo.',
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Form
// ============================================================

class TrainingVideoFormScreen extends ConsumerStatefulWidget {
  final TrainingVideo? video;
  const TrainingVideoFormScreen({super.key, this.video});

  @override
  ConsumerState<TrainingVideoFormScreen> createState() =>
      _TrainingVideoFormScreenState();
}

class _TrainingVideoFormScreenState
    extends ConsumerState<TrainingVideoFormScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  SportId? _sport;
  WorkoutAudience _audience = WorkoutAudience.academy;
  final Set<String> _assignedIds = {};
  VideoSource _source = VideoSource.link;
  File? _pickedFile;
  String? _pickedName;
  List<Student> _allStudents = [];
  bool _saving = false;

  bool get _isEditing => widget.video != null;

  @override
  void initState() {
    super.initState();
    final v = widget.video;
    if (v != null) {
      _titleCtrl.text = v.title;
      _descCtrl.text = v.description ?? '';
      _sport = v.sportId;
      _audience = v.audience;
      _assignedIds.addAll(v.assignedStudentIds);
      _source = v.source;
      if (v.source == VideoSource.link) _urlCtrl.text = v.url;
    }
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      _allStudents = await StudentService(FirebaseService.academyId).getActive();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final x = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 15),
    );
    if (x != null) {
      setState(() {
        _pickedFile = File(x.path);
        _pickedName = x.name;
      });
    }
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      context.showError('Informe um titulo.');
      return;
    }
    if (_audience == WorkoutAudience.students && _assignedIds.isEmpty) {
      context.showError('Selecione ao menos um aluno.');
      return;
    }

    String url;
    String? storagePath;
    if (_source == VideoSource.link) {
      url = _urlCtrl.text.trim();
      if (url.isEmpty || Uri.tryParse(url)?.hasScheme != true) {
        context.showError('Informe um link valido (https://...).');
        return;
      }
      storagePath = null;
    } else {
      // upload
      if (_pickedFile == null &&
          _isEditing &&
          widget.video!.source == VideoSource.upload) {
        // Keep the existing uploaded file.
        url = widget.video!.url;
        storagePath = widget.video!.storagePath;
      } else if (_pickedFile != null) {
        url = ''; // set after upload
        storagePath = null;
      } else {
        context.showError('Selecione um arquivo de video.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final service = TrainingVideoService(FirebaseService.academyId);

      if (_source == VideoSource.upload && _pickedFile != null) {
        final uploaded = await service.uploadVideoFile(_pickedFile!);
        url = uploaded.url;
        storagePath = uploaded.path;
      }

      final user = await ref.read(currentUserProvider.future);
      final video = TrainingVideo(
        id: widget.video?.id ?? '',
        title: _titleCtrl.text.trim(),
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        sport: _sport?.value,
        audience: _audience,
        assignedStudentIds: _assignedIds.toList(),
        source: _source,
        url: url,
        storagePath: storagePath,
        createdBy: widget.video?.createdBy ?? user?.id ?? '',
        createdByName: widget.video?.createdByName ?? user?.displayName ?? '',
      );

      if (_isEditing) {
        await service.update(widget.video!.id, video);
      } else {
        await service.create(video);
        if (_audience == WorkoutAudience.students) {
          await _notifyAssignedStudents(title: video.title);
        }
      }
      if (!mounted) return;
      context.showSuccess('Video salvo!');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) context.showError('Erro ao salvar o video.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir video?'),
        content: const Text('Esta acao nao pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Excluir', style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await TrainingVideoService(FirebaseService.academyId)
          .delete(widget.video!);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) context.showError('Erro ao excluir.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar video' : 'Novo video'),
        backgroundColor: AppTheme.surface,
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Excluir',
              icon: Icon(Icons.delete_outline, color: AppTheme.error),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Titulo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Descricao (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          _buildSourcePicker(),
          const SizedBox(height: 16),
          _buildSportPicker(),
          const SizedBox(height: 16),
          _buildAudiencePicker(),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salvar video'),
            ),
          ),
        ],
      ),
    );
  }

  /// Best-effort notification to each assigned student who has a linked app
  /// account. Used when a video is created for specific students.
  Future<void> _notifyAssignedStudents({required String title}) async {
    try {
      final dispatcher = NotificationDispatcher(FirebaseService.academyId);
      final byId = {for (final s in _allStudents) s.id: s};
      for (final id in _assignedIds) {
        final uid = byId[id]?.linkedUserId;
        if (uid != null && uid.isNotEmpty) {
          await dispatcher.notifyNewContent(
            userId: uid,
            title: title,
            isVideo: true,
            actionUrl: '/portal/videos',
          );
        }
      }
    } catch (_) {
      // Notifications are best-effort; never block the save.
    }
  }

  Widget _buildSourcePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Origem do video',
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Link'),
              selected: _source == VideoSource.link,
              onSelected: (_) => setState(() => _source = VideoSource.link),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Upload'),
              selected: _source == VideoSource.upload,
              onSelected: (_) => setState(() => _source = VideoSource.upload),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_source == VideoSource.link)
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Link do video',
              hintText: 'https://youtube.com/watch?v=...',
              border: OutlineInputBorder(),
            ),
          )
        else
          _buildUploadPicker(),
      ],
    );
  }

  Widget _buildUploadPicker() {
    final hasExisting = _isEditing &&
        widget.video!.source == VideoSource.upload &&
        _pickedFile == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _pickVideo,
          icon: const Icon(Icons.video_call_outlined),
          label: Text(_pickedFile == null
              ? 'Selecionar video'
              : 'Trocar video'),
        ),
        const SizedBox(height: 6),
        Text(
          _pickedName != null
              ? 'Selecionado: $_pickedName'
              : hasExisting
                  ? 'Video atual mantido (selecione para trocar).'
                  : 'Nenhum video selecionado.',
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
        ),
        Text(
          'Maximo 15 min. O envio pode levar alguns minutos.',
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildSportPicker() {
    return DropdownButtonFormField<SportId?>(
      initialValue: _sport,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Modalidade',
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem<SportId?>(
          value: null,
          child: Text('Qualquer modalidade'),
        ),
        ...sportOptions.map(
          (s) => DropdownMenuItem<SportId?>(
            value: s,
            child: Text(sports[s]?.label ?? s.value),
          ),
        ),
      ],
      onChanged: (v) => setState(() => _sport = v),
    );
  }

  Widget _buildAudiencePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quem recebe',
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            _audienceChip(WorkoutAudience.academy, 'Toda a academia'),
            _audienceChip(WorkoutAudience.sport, 'Por modalidade'),
            _audienceChip(WorkoutAudience.students, 'Alunos especificos'),
          ],
        ),
        if (_audience == WorkoutAudience.students) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickStudents,
            icon: const Icon(Icons.people_outline),
            label: Text('Selecionar alunos (${_assignedIds.length})'),
          ),
        ],
      ],
    );
  }

  Widget _audienceChip(WorkoutAudience a, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _audience == a,
      onSelected: (_) => setState(() => _audience = a),
    );
  }

  Future<void> _pickStudents() async {
    final selected = Set<String>.from(_assignedIds);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.9,
              builder: (ctx, scroll) {
                return Column(
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      'Selecionar alunos',
                      style: AppTheme.titleMedium
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        controller: scroll,
                        itemCount: _allStudents.length,
                        itemBuilder: (ctx, i) {
                          final s = _allStudents[i];
                          return CheckboxListTile(
                            value: selected.contains(s.id),
                            title: Text(s.fullName),
                            onChanged: (v) => setSheet(() {
                              if (v == true) {
                                selected.add(s.id);
                              } else {
                                selected.remove(s.id);
                              }
                            }),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text('Confirmar (${selected.length})'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
    setState(() {
      _assignedIds
        ..clear()
        ..addAll(selected);
    });
  }
}
