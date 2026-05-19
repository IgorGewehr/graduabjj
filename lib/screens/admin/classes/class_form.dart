// Bottom-sheet form for creating and editing a BJJClass.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/dto/class_dto.dart' as api;
import '../../../api/repositories.dart';
import '../../../core/feedback_utils.dart';
import '../../../core/sports.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/portal_providers.dart';
import '../../../services/services.dart';
import 'class_helpers.dart';
import 'class_widgets.dart';

/// Shows a bottom-sheet to CREATE a new class.
/// [onCreated] is called after successful save so the parent can reload.
void showCreateClassSheet(
  BuildContext context,
  WidgetRef ref, {
  required VoidCallback onCreated,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ClassFormSheet(ref: ref, onSaved: onCreated),
  );
}

/// Shows a bottom-sheet to EDIT an existing class.
/// [onUpdated] is called after successful save.
void showEditClassSheet(
  BuildContext context,
  WidgetRef ref,
  BJJClass cls, {
  required VoidCallback onUpdated,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ClassFormSheet(ref: ref, existingClass: cls, onSaved: onUpdated),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _ClassFormSheet extends StatefulWidget {
  final WidgetRef ref;
  final BJJClass? existingClass;
  final VoidCallback onSaved;

  const _ClassFormSheet({
    required this.ref,
    this.existingClass,
    required this.onSaved,
  });

  @override
  State<_ClassFormSheet> createState() => _ClassFormSheetState();
}

class _ClassFormSheetState extends State<_ClassFormSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _instructorController;
  late final TextEditingController _maxStudentsController;
  late final TextEditingController _weightController;

  late StudentCategory? _selectedCategory;
  late SportId _selectedSport;
  late List<ScheduleEntry> _scheduleEntries;
  late bool _useClassWeights;
  bool _isSaving = false;

  bool get _isEditing => widget.existingClass != null;

  @override
  void initState() {
    super.initState();
    final cls = widget.existingClass;
    _nameController = TextEditingController(text: cls?.name ?? '');
    _descriptionController = TextEditingController(text: cls?.description ?? '');
    _instructorController = TextEditingController(text: cls?.instructorName ?? '');
    _maxStudentsController = TextEditingController(
      text: cls?.maxStudents?.toString() ?? '',
    );
    _weightController = TextEditingController(
      text: (cls?.weight ?? 1).toString(),
    );
    _selectedCategory = cls?.category;
    _selectedSport = cls?.getSport() ?? SportId.bjj;
    _useClassWeights =
        widget.ref.read(academySettingsProvider).valueOrNull?.useClassWeights ??
        false;

    if (cls != null && cls.schedule.isNotEmpty) {
      _scheduleEntries = cls.schedule
          .map(
            (s) => ScheduleEntry(
              dayOfWeek: s.dayOfWeek,
              startTime: s.startTime,
              endTime: s.endTime,
            ),
          )
          .toList();
    } else {
      _scheduleEntries = [
        ScheduleEntry(dayOfWeek: 1, startTime: '19:00', endTime: '20:30'),
      ];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _instructorController.dispose();
    _maxStudentsController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.isEmpty) {
      context.showWarning('Nome e obrigatorio');
      return;
    }
    setState(() => _isSaving = true);

    try {
      final currentUser = widget.ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) return;

      final academyId = currentUser!.academyId!;
      final repo = widget.ref.read(classRepoProvider);

      // Map ScheduleEntry → ApiScheduleEntry
      final apiSchedule = _scheduleEntries
          .map(
            (e) => api.ApiScheduleEntry(
              dayOfWeek: e.dayOfWeek,
              startTime: e.startTime,
              endTime: e.endTime,
            ),
          )
          .toList();

      // Map StudentCategory? → ApiClassCategory
      api.ApiClassCategory toApiCategory(StudentCategory? cat) {
        switch (cat) {
          case StudentCategory.kids:
            return api.ApiClassCategory.kids;
          case StudentCategory.adult:
            return api.ApiClassCategory.adult;
          default:
            return api.ApiClassCategory.mixed;
        }
      }

      if (_isEditing) {
        // Build weight string: only set when useClassWeights is on and != 1
        String? weightStr;
        if (_useClassWeights) {
          final w = double.tryParse(_weightController.text) ?? 1.0;
          if (w != 1.0) weightStr = w.toStringAsFixed(3);
        }

        final req = api.UpdateClassRequest(
          name: _nameController.text,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          category: toApiCategory(_selectedCategory),
          sport: _selectedSport.value,
          instructorName: _instructorController.text.isEmpty
              ? null
              : _instructorController.text,
          maxStudents: _maxStudentsController.text.isEmpty
              ? null
              : int.tryParse(_maxStudentsController.text),
          weight: weightStr,
          schedule: apiSchedule,
        );
        await repo.update(academyId, widget.existingClass!.id, req);
      } else {
        // Build weight string for creation
        String? weightStr;
        if (_useClassWeights) {
          final w = double.tryParse(_weightController.text) ?? 1.0;
          if (w != 1.0) weightStr = w.toStringAsFixed(3);
        }

        final req = api.CreateClassRequest(
          name: _nameController.text,
          description: _descriptionController.text.isEmpty
              ? null
              : _descriptionController.text,
          category: toApiCategory(_selectedCategory),
          sport: _selectedSport.value,
          instructorName: _instructorController.text.isEmpty
              ? null
              : _instructorController.text,
          maxStudents: _maxStudentsController.text.isEmpty
              ? null
              : int.tryParse(_maxStudentsController.text),
          weight: weightStr,
          schedule: apiSchedule,
        );
        await repo.create(academyId, req);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        context.showError('Erro: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _isEditing ? LucideIcons.pencil : LucideIcons.users,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _isEditing ? 'Editar Turma' : 'Nova Turma',
                style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Scrollable fields
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ModernTextField(
                    controller: _nameController,
                    label: 'Nome da Turma',
                    hint: 'Ex: Turma Iniciante',
                    icon: LucideIcons.users,
                  ),
                  const SizedBox(height: 16),
                  ModernTextField(
                    controller: _descriptionController,
                    label: 'Descricao (opcional)',
                    hint: 'Breve descricao da turma',
                    icon: LucideIcons.fileText,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Categoria',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: DropdownButtonFormField<StudentCategory>(
                      value: _selectedCategory,
                      items: StudentCategory.values.map((cat) {
                        return DropdownMenuItem(
                          value: cat,
                          child: Text(cat.label),
                        );
                      }).toList(),
                      onChanged: (value) =>
                          setState(() => _selectedCategory = value),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      dropdownColor: AppTheme.surface,
                      hint: const Text('Selecione a categoria'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Esporte',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: DropdownButtonFormField<SportId>(
                      value: _selectedSport,
                      items: sportOptions.map((sportId) {
                        final sport = getSport(sportId);
                        return DropdownMenuItem(
                          value: sportId,
                          child: Row(
                            children: [
                              Icon(
                                sport.icon,
                                size: 18,
                                color: sportChipColors[sportId],
                              ),
                              const SizedBox(width: 8),
                              Text(sport.label),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedSport = value);
                        }
                      },
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      dropdownColor: AppTheme.surface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ModernTextField(
                    controller: _instructorController,
                    label: 'Instrutor (opcional)',
                    hint: 'Nome do instrutor',
                    icon: LucideIcons.userCircle,
                  ),
                  const SizedBox(height: 16),
                  ModernTextField(
                    controller: _maxStudentsController,
                    label: 'Maximo de Alunos (opcional)',
                    hint: 'Ex: 20',
                    icon: LucideIcons.users,
                    keyboardType: TextInputType.number,
                  ),
                  if (_useClassWeights) ...[
                    const SizedBox(height: 16),
                    ModernTextField(
                      controller: _weightController,
                      label: 'Peso da turma',
                      hint: '1 = padrao. Ex: aula particular = 2',
                      icon: LucideIcons.scale,
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Horarios',
                    style: AppTheme.titleSmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._scheduleEntries.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final schedule = entry.value;
                    return ScheduleEntryRow(
                      schedule: schedule,
                      canRemove: _scheduleEntries.length > 1,
                      onChanged: () => setState(() {}),
                      onRemove: () =>
                          setState(() => _scheduleEntries.removeAt(idx)),
                      dialogContext: context,
                    );
                  }),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _scheduleEntries.add(
                          ScheduleEntry(
                            dayOfWeek: 1,
                            startTime: '19:00',
                            endTime: '20:30',
                          ),
                        );
                      });
                    },
                    icon: Icon(LucideIcons.plus, size: 18),
                    label: const Text('Adicionar Horario'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isEditing ? LucideIcons.save : LucideIcons.plus,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(_isEditing ? 'Salvar' : 'Criar Turma'),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
