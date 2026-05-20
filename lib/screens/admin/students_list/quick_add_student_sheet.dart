import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/dto/student_dto.dart'
    show CreateStudentRequest, ApiStudentCategoryX, ApiBeltX;
import '../../../api/repositories.dart';
import '../../../core/feedback_utils.dart';
import '../../../core/sports.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../providers/auth_provider.dart' show currentUserProvider;
import '../../../providers/selected_academy_provider.dart';
import '../../../services/services.dart';

/// Cadastro rápido de aluno. Pede apenas Nome + Modalidades (+ categoria
/// opcional) e usa `StudentRemoteRepo.create` via Tatami para gravar —
/// a primeira modalidade selecionada vira primária. Inclui link para o
/// cadastro completo (form de várias abas) se o admin precisar dos campos extras.
class QuickAddStudentSheet extends ConsumerStatefulWidget {
  final void Function(Student) onCreated;

  const QuickAddStudentSheet({super.key, required this.onCreated});

  @override
  ConsumerState<QuickAddStudentSheet> createState() =>
      _QuickAddStudentSheetState();
}

class _QuickAddStudentSheetState extends ConsumerState<QuickAddStudentSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  StudentCategory _category = StudentCategory.adult;
  final Set<SportId> _selectedSports = {};
  SportId? _primarySport;
  bool _isSaving = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _toggleSport(SportId sport) {
    setState(() {
      if (_selectedSports.contains(sport)) {
        _selectedSports.remove(sport);
        if (_primarySport == sport) {
          _primarySport = _selectedSports.isNotEmpty
              ? _selectedSports.first
              : null;
        }
      } else {
        _selectedSports.add(sport);
        _primarySport ??= sport;
      }
      _errorText = null;
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = 'Informe o nome do aluno');
      return;
    }
    if (_selectedSports.isEmpty) {
      setState(() => _errorText = 'Selecione pelo menos uma modalidade');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      final academyId = ref.read(selectedAcademyIdProvider) ?? '';
      final repo = ref.read(studentRepoProvider);

      final orderedSports = [
        _primarySport ?? _selectedSports.first,
        ..._selectedSports.where((s) => s != _primarySport),
      ];
      final primary = orderedSports.first;

      // Seed the primary sport's initial grade (lowest for this category).
      final grades = getGradesForSport(primary, category: _category.value);
      final firstGradeId = grades.isNotEmpty ? grades.first.id : 'white';

      // Build sportData map for all selected sports.
      final sportData = <String, dynamic>{};
      for (final sport in orderedSports) {
        final sg = getGradesForSport(sport, category: _category.value);
        final defaultGrade = sg.isNotEmpty ? sg.first.id : 'white';
        sportData[sport.value] = {
          'currentGrade': defaultGrade,
          'currentStripes': 0,
        };
      }

      final phone = _phoneController.text.trim();
      final apiStudent = await repo.create(
        academyId,
        CreateStudentRequest(
          fullName: name,
          phone: phone.isEmpty ? null : phone,
          category: ApiStudentCategoryX.fromWire(_category.value),
          currentBelt: ApiBeltX.fromWire(firstGradeId),
          currentStripes: 0,
          primarySport: primary.value,
          sportsList: orderedSports.map((s) => s.value).toList(),
          sportData: sportData,
        ),
      );
      final student = Student.fromApi(apiStudent);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onCreated(student);
      context.showSuccess('Aluno cadastrado!');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorText = 'Erro: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      LucideIcons.userPlus,
                      color: AppTheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Cadastro rápido',
                          style: AppTheme.titleMedium.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Apenas nome e modalidade — edite o resto depois',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Nome completo *',
                  hintText: 'Ex: Maria da Silva',
                  prefixIcon: Icon(
                    LucideIcons.user,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.divider),
                  ),
                ),
                onChanged: (_) {
                  if (_errorText != null) setState(() => _errorText = null);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Telefone (opcional)',
                  hintText: '(11) 99999-9999',
                  prefixIcon: Icon(
                    LucideIcons.phone,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.divider),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Categoria',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: StudentCategory.values.map((cat) {
                  final isSelected = _category == cat;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _category = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primary.withValues(alpha: 0.1)
                                : AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.divider,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Text(
                            cat.label,
                            textAlign: TextAlign.center,
                            style: AppTheme.bodyMedium.copyWith(
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Modalidades *',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_primarySport != null)
                    Text(
                      '· Principal: ${sports[_primarySport!]!.label}',
                      style: AppTheme.labelSmall.copyWith(
                        color:
                            sportChipColors[_primarySport!] ??
                            AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: sportOptions.map((sportId) {
                  final isSelected = _selectedSports.contains(sportId);
                  final isPrimary = _primarySport == sportId;
                  return _buildSportPickerChip(sportId, isSelected, isPrimary);
                }).toList(),
              ),
              if (_selectedSports.length > 1) ...[
                const SizedBox(height: 8),
                Text(
                  'Toque novamente em uma modalidade selecionada para defini-la como principal.',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.alertCircle,
                        color: AppTheme.error,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorText!,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.textPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.userPlus, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Cadastrar aluno',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () {
                          Navigator.pop(context);
                          context.go('/admin/alunos/novo');
                        },
                  icon: const Icon(LucideIcons.fileText, size: 16),
                  label: const Text('Cadastro completo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSportPickerChip(
    SportId sportId,
    bool isSelected,
    bool isPrimary,
  ) {
    final sport = sports[sportId]!;
    final accent = sportChipColors[sportId] ?? AppTheme.textPrimary;
    return GestureDetector(
      onTap: () {
        if (isSelected && !isPrimary) {
          setState(() => _primarySport = sportId);
        } else {
          _toggleSport(sportId);
        }
      },
      onLongPress: () {
        if (isSelected) _toggleSport(sportId);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: isPrimary ? 0.18 : 0.1)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? accent : AppTheme.divider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              sport.icon,
              size: 14,
              color: isSelected ? accent : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              sport.label,
              style: AppTheme.bodySmall.copyWith(
                color: isSelected ? accent : AppTheme.textPrimary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (isPrimary) ...[
              const SizedBox(width: 6),
              Icon(LucideIcons.star, size: 12, color: accent),
            ],
          ],
        ),
      ),
    );
  }
}
