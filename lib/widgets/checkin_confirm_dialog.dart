import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme.dart';
import '../models/checkin.dart';
import '../models/student.dart';
import '../services/class_service.dart';

/// Dialog for admin to review and confirm check-ins
class CheckinConfirmDialog extends StatefulWidget {
  final BJJClass selectedClass;
  final List<Checkin> checkins;
  final List<Student> allStudents;
  final Future<void> Function(String checkinId) onRemoveCheckin;
  final Future<void> Function(Student student) onAddManualCheckin;
  final Future<void> Function(List<String> checkinIds) onConfirmCheckins;
  final bool isConfirming;
  final bool isRemoving;
  final bool isAdding;

  const CheckinConfirmDialog({
    super.key,
    required this.selectedClass,
    required this.checkins,
    required this.allStudents,
    required this.onRemoveCheckin,
    required this.onAddManualCheckin,
    required this.onConfirmCheckins,
    this.isConfirming = false,
    this.isRemoving = false,
    this.isAdding = false,
  });

  @override
  State<CheckinConfirmDialog> createState() => _CheckinConfirmDialogState();
}

class _CheckinConfirmDialogState extends State<CheckinConfirmDialog> {
  final _searchController = TextEditingController();
  String _sortBy = 'time';
  bool _showAddStudent = false;
  String? _removingId;
  String? _addingStudentId;

  List<Checkin> get _filteredCheckins {
    var result = List<Checkin>.from(widget.checkins);

    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      final term = _searchController.text.toLowerCase();
      result = result.where((c) => c.studentName.toLowerCase().contains(term)).toList();
    }

    // Apply sort
    switch (_sortBy) {
      case 'name-asc':
        result.sort((a, b) => a.studentName.compareTo(b.studentName));
        break;
      case 'name-desc':
        result.sort((a, b) => b.studentName.compareTo(a.studentName));
        break;
      case 'time':
      default:
        result.sort((a, b) => a.checkinTime.compareTo(b.checkinTime));
        break;
    }

    return result;
  }

  List<Student> get _studentsWithoutCheckin {
    final checkinStudentIds = widget.checkins.map((c) => c.studentId).toSet();

    var eligible = widget.allStudents.where((s) =>
        widget.selectedClass.studentIds.contains(s.id) &&
        !checkinStudentIds.contains(s.id) &&
        s.status == StudentStatus.active).toList();

    if (_showAddStudent && _searchController.text.isNotEmpty) {
      final term = _searchController.text.toLowerCase();
      eligible = eligible.where((s) =>
          s.fullName.toLowerCase().contains(term) ||
          (s.nickname?.toLowerCase().contains(term) ?? false)).toList();
    }

    eligible.sort((a, b) => a.fullName.compareTo(b.fullName));
    return eligible;
  }

  Future<void> _handleRemoveCheckin(String checkinId) async {
    setState(() => _removingId = checkinId);
    try {
      await widget.onRemoveCheckin(checkinId);
    } finally {
      if (mounted) {
        setState(() => _removingId = null);
      }
    }
  }

  Future<void> _handleAddManualCheckin(Student student) async {
    setState(() => _addingStudentId = student.id);
    try {
      await widget.onAddManualCheckin(student);
    } finally {
      if (mounted) {
        setState(() => _addingStudentId = null);
      }
    }
  }

  Future<void> _handleConfirm() async {
    final checkinIds = _filteredCheckins.map((c) => c.id).toList();
    await widget.onConfirmCheckins(checkinIds);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _buildHeader(),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search and Sort
                    _buildSearchAndSort(),
                    const SizedBox(height: 16),

                    // Content based on mode
                    if (_showAddStudent)
                      _buildAddStudentList()
                    else
                      _buildCheckinList(),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Footer
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.how_to_reg, color: AppTheme.success, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Check-ins - ${widget.selectedClass.name}',
                  style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${widget.checkins.length} aluno${widget.checkins.length != 1 ? 's' : ''} '
                  'fez${widget.checkins.length != 1 ? 'eram' : ''} check-in',
                  style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndSort() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: _showAddStudent
                      ? 'Buscar aluno para adicionar...'
                      : 'Buscar aluno...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppTheme.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppTheme.divider),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        if (!_showAddStudent) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              _SortChip(
                label: 'A-Z',
                isSelected: _sortBy == 'name-asc',
                onTap: () => setState(() => _sortBy = 'name-asc'),
              ),
              const SizedBox(width: 8),
              _SortChip(
                label: 'Z-A',
                isSelected: _sortBy == 'name-desc',
                onTap: () => setState(() => _sortBy = 'name-desc'),
              ),
              const SizedBox(width: 8),
              _SortChip(
                label: 'Horario',
                icon: Icons.access_time,
                isSelected: _sortBy == 'time',
                onTap: () => setState(() => _sortBy = 'time'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildCheckinList() {
    final checkins = _filteredCheckins;

    if (checkins.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            _searchController.text.isNotEmpty
                ? 'Nenhum check-in encontrado'
                : 'Nenhum check-in pendente',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return Column(
      children: [
        ...checkins.map((checkin) => _CheckinItem(
              checkin: checkin,
              isRemoving: _removingId == checkin.id,
              onRemove: () => _handleRemoveCheckin(checkin.id),
              disabled: widget.isRemoving && _removingId != checkin.id,
            )),

        // Add student button
        if (_studentsWithoutCheckin.isNotEmpty)
          TextButton.icon(
            onPressed: () => setState(() {
              _showAddStudent = true;
              _searchController.clear();
            }),
            icon: const Icon(Icons.person_add, size: 18),
            label: const Text('Adicionar aluno'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
            ),
          ),
      ],
    );
  }

  Widget _buildAddStudentList() {
    final students = _studentsWithoutCheckin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => setState(() {
            _showAddStudent = false;
            _searchController.clear();
          }),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Voltar para lista de check-ins'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Selecione um aluno para adicionar:',
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 12),

        if (students.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                _searchController.text.isNotEmpty
                    ? 'Nenhum aluno encontrado'
                    : 'Todos os alunos ja fizeram check-in',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ),
          )
        else
          ...students.map((student) => _StudentItem(
                student: student,
                isAdding: _addingStudentId == student.id,
                onAdd: () => _handleAddManualCheckin(student),
                disabled: widget.isAdding && _addingStudentId != student.id,
              )),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: widget.isConfirming || _filteredCheckins.isEmpty
                ? null
                : _handleConfirm,
            icon: widget.isConfirming
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check, size: 18),
            label: Text(widget.isConfirming
                ? 'Confirmando...'
                : 'Confirmar Lista (${_filteredCheckins.length})'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sort chip widget
class _SortChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: isSelected ? Colors.white : AppTheme.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: AppTheme.labelSmall.copyWith(
                color: isSelected ? Colors.white : AppTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Checkin item widget
class _CheckinItem extends StatelessWidget {
  final Checkin checkin;
  final bool isRemoving;
  final VoidCallback onRemove;
  final bool disabled;

  const _CheckinItem({
    required this.checkin,
    required this.isRemoving,
    required this.onRemove,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.check, size: 16, color: AppTheme.success),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    checkin.studentName,
                    style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 12, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('HH:mm').format(checkin.checkinTime),
                        style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: isRemoving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.close, size: 18, color: AppTheme.error),
              onPressed: disabled ? null : onRemove,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

/// Student item widget
class _StudentItem extends StatelessWidget {
  final Student student;
  final bool isAdding;
  final VoidCallback onAdd;
  final bool disabled;

  const _StudentItem({
    required this.student,
    required this.isAdding,
    required this.onAdd,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: InkWell(
        onTap: disabled ? null : onAdd,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.nickname ?? student.fullName.split(' ').first,
                      style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      student.fullName,
                      style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isAdding ? AppTheme.success : AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: isAdding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(Icons.person_add, size: 16, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
