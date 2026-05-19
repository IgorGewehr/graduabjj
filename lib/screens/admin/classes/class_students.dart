// Bottom-sheet for managing students enrolled in a BJJClass.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/repositories.dart';
import '../../../core/feedback_utils.dart';
import '../../../core/sports.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/services.dart';
import '../../../widgets/cached_image.dart';
import '../../../widgets/common/grade_display.dart';
import '../../../widgets/common/sport_chip.dart';
import 'class_widgets.dart';

/// Opens the manage-students bottom-sheet for [bjjClass].
/// [onChanged] is called when the enrollment set was modified.
void showManageStudentsSheet(
  BuildContext context,
  BJJClass bjjClass, {
  required VoidCallback onChanged,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) =>
        ManageStudentsSheet(bjjClass: bjjClass, onChanged: onChanged),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class ManageStudentsSheet extends ConsumerStatefulWidget {
  final BJJClass bjjClass;
  final VoidCallback onChanged;

  const ManageStudentsSheet({
    super.key,
    required this.bjjClass,
    required this.onChanged,
  });

  @override
  ConsumerState<ManageStudentsSheet> createState() =>
      _ManageStudentsSheetState();
}

class _ManageStudentsSheetState extends ConsumerState<ManageStudentsSheet> {
  bool _isLoading = true;
  bool _hasChanges = false;
  List<Student> _students = [];
  Set<String> _enrolledIds = {};
  final Set<String> _pendingIds = {};
  String _searchQuery = '';
  bool _showOnlyEnrolled = false;

  @override
  void initState() {
    super.initState();
    _enrolledIds = widget.bjjClass.studentIds.toSet();
    _load();
  }

  Future<void> _load() async {
    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      if (currentUser?.academyId == null) {
        setState(() => _isLoading = false);
        return;
      }
      final service = StudentService(currentUser!.academyId!);
      final students = await service.getAll();

      // Order: enrolled first, then students who already practice this sport,
      // then everyone else — alphabetical inside each group.
      final classSport = widget.bjjClass.getSport();
      students.sort((a, b) {
        final aEnrolled = _enrolledIds.contains(a.id) ? 0 : 1;
        final bEnrolled = _enrolledIds.contains(b.id) ? 0 : 1;
        if (aEnrolled != bEnrolled) return aEnrolled.compareTo(bEnrolled);
        final aMatchesSport = a.getSports().contains(classSport) ? 0 : 1;
        final bMatchesSport = b.getSports().contains(classSport) ? 0 : 1;
        if (aMatchesSport != bMatchesSport) {
          return aMatchesSport.compareTo(bMatchesSport);
        }
        return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      });

      setState(() {
        _students = students;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  List<Student> get _visibleStudents {
    Iterable<Student> base = _students;
    if (_showOnlyEnrolled) {
      base = base.where((s) => _enrolledIds.contains(s.id));
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      base = base.where(
        (s) =>
            s.fullName.toLowerCase().contains(q) ||
            (s.nickname?.toLowerCase().contains(q) ?? false),
      );
    }
    return base.toList();
  }

  Future<void> _toggle(Student student) async {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId == null) return;
    if (_pendingIds.contains(student.id)) return;

    final wasEnrolled = _enrolledIds.contains(student.id);
    setState(() {
      _pendingIds.add(student.id);
      if (wasEnrolled) {
        _enrolledIds.remove(student.id);
      } else {
        _enrolledIds.add(student.id);
      }
    });

    try {
      final academyId = currentUser!.academyId!;
      final repo = ref.read(classRepoProvider);
      if (wasEnrolled) {
        await repo.removeStudent(academyId, widget.bjjClass.id, student.id);
      } else {
        await repo.addStudent(academyId, widget.bjjClass.id, student.id);
      }
      _hasChanges = true;
      if (mounted) setState(() => _pendingIds.remove(student.id));
    } catch (e) {
      if (mounted) {
        setState(() {
          _pendingIds.remove(student.id);
          if (wasEnrolled) {
            _enrolledIds.add(student.id);
          } else {
            _enrolledIds.remove(student.id);
          }
        });
        context.showError('Erro: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cls = widget.bjjClass;
    final classSport = cls.getSport();
    final sportDef = sports[classSport]!;
    final accent = sportChipColors[classSport] ?? AppTheme.primary;
    final maxedOut =
        cls.maxStudents != null && _enrolledIds.length >= cls.maxStudents!;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
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
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(sportDef.icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cls.name,
                      style: AppTheme.titleMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        SportChip(sportId: classSport),
                        const SizedBox(width: 8),
                        Text(
                          '${_enrolledIds.length}${cls.maxStudents != null ? '/${cls.maxStudents}' : ''} alunos',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  if (_hasChanges) widget.onChanged();
                  Navigator.pop(context);
                },
                icon: const Icon(LucideIcons.x, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Search
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Buscar aluno...',
                hintStyle: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textDisabled,
                ),
                prefixIcon: Icon(
                  LucideIcons.search,
                  color: AppTheme.textSecondary,
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Filter chips + full / over-capacity badge
          Row(
            children: [
              ToggleChip(
                label: 'Todos (${_students.length})',
                selected: !_showOnlyEnrolled,
                onTap: () => setState(() => _showOnlyEnrolled = false),
              ),
              const SizedBox(width: 8),
              ToggleChip(
                label: 'Matriculados (${_enrolledIds.length})',
                selected: _showOnlyEnrolled,
                onTap: () => setState(() => _showOnlyEnrolled = true),
              ),
              const Spacer(),
              if (maxedOut)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Lotada',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Student list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _visibleStudents.isEmpty
                ? Center(
                    child: Text(
                      _showOnlyEnrolled
                          ? 'Nenhum aluno matriculado'
                          : 'Nenhum aluno encontrado',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _visibleStudents.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final s = _visibleStudents[i];
                      final isEnrolled = _enrolledIds.contains(s.id);
                      final isPending = _pendingIds.contains(s.id);
                      final practicesSport =
                          s.getSports().contains(classSport);
                      final blockedByCap = !isEnrolled && maxedOut;
                      return _StudentRow(
                        student: s,
                        classSport: classSport,
                        enrolled: isEnrolled,
                        pending: isPending,
                        practicesSport: practicesSport,
                        disabled: blockedByCap,
                        onTap: blockedByCap ? null : () => _toggle(s),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Student Row ─────────────────────────────────────────────────────────────

class _StudentRow extends StatelessWidget {
  final Student student;
  final SportId classSport;
  final bool enrolled;
  final bool pending;
  final bool practicesSport;
  final bool disabled;
  final VoidCallback? onTap;

  const _StudentRow({
    required this.student,
    required this.classSport,
    required this.enrolled,
    required this.pending,
    required this.practicesSport,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primarySport = student.getPrimarySport();
    final grade = student.getGrade(primarySport);
    final accent = sportChipColors[classSport] ?? AppTheme.primary;

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: enrolled
                ? accent.withValues(alpha: 0.06)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enrolled ? accent : AppTheme.divider,
              width: enrolled ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: student.photoUrl != null
                    ? AppCachedImage(
                        imageUrl: student.photoUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(10),
                      )
                    : Center(
                        child: Text(
                          student.displayName[0].toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      student.fullName,
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (grade != null)
                          GradeDisplay(
                            sportId: primarySport,
                            grade: grade.currentGrade,
                            stripes: grade.currentStripes,
                            size: GradeDisplaySize.small,
                          ),
                        SportChip(sportId: primarySport),
                        if (practicesSport && primarySport != classSport)
                          SportChip(sportId: classSport),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 28,
                height: 28,
                child: pending
                    ? const Padding(
                        padding: EdgeInsets.all(4),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        enrolled
                            ? LucideIcons.checkCircle2
                            : LucideIcons.circle,
                        color: enrolled ? accent : AppTheme.textDisabled,
                        size: 26,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
