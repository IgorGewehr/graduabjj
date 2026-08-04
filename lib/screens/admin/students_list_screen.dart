import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../core/brand_tokens.dart';
import '../../core/feedback_utils.dart';
import '../../core/responsive.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/join_request_providers.dart';
import '../../providers/portal_providers.dart';
import '../../services/analytics_service.dart';
import '../../services/services.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/common/academy_page_header.dart';
import '../../widgets/common/grade_display.dart';
import '../../widgets/common/sport_chip.dart';
import '../../widgets/polish/polish.dart';

/// Students List Screen - Fintech style matching webapp
class StudentsListScreen extends ConsumerStatefulWidget {
  const StudentsListScreen({super.key});

  @override
  ConsumerState<StudentsListScreen> createState() => _StudentsListScreenState();
}

class _StudentsListScreenState extends ConsumerState<StudentsListScreen> {
  List<Student> _students = [];
  List<Student> _filteredStudents = [];
  bool _isLoading = true;

  // Filters
  String _searchQuery = '';
  StudentStatus? _statusFilter;
  StudentCategory? _categoryFilter;
  SportId? _sportFilter;
  String? _beltFilter;
  bool? _accountFilter; // null=all, true=linked, false=unlinked
  // Retenção (§3.3): null=off; 7/14/30 = "sem treinar há N+ dias".
  // Usa retention.lastAttendanceDate (CF); aluno sem NENHUMA presença conhecida
  // só entra na banda 30+ (não polui 7/14 antes do backfill rodar).
  int? _inactivityFilter;
  String _sortBy = 'name';

  // Auto-graduation snapshot (only loaded when feature is on)
  Map<String, EligibilitySnapshotEntry> _eligibilityByStudent = {};

  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);

    try {
      // Source the academy from the authenticated user (single source of truth),
      // NOT the mutable global static FirebaseService.academyId (which could be
      // stale/'default' and silently query the wrong/empty academy → "0 alunos").
      final user = await ref.read(currentUserProvider.future);
      final academyId = user?.academyId ?? FirebaseService.academyId;

      final service = StudentService(academyId);
      final students = await service.getAll();

      // PERFORMANCE: mostra a lista IMEDIATAMENTE (getAll é 1 query, rápido). A
      // eligibility (badges de graduação) é CARA — N+1 sobre presenças/syllabus
      // por aluno (15-30s p/ 100+ alunos) — e NÃO pode BLOQUEAR a lista. Carrega
      // em background e preenche os badges quando pronto (a lista aparece na hora
      // em vez de travar a tela sem feedback útil).
      if (!mounted) return;
      setState(() {
        _students = students;
        _applyFilters();
        _isLoading = false;
      });

      final settings = ref.read(academySettingsProvider).valueOrNull;
      if (settings?.autoGraduationEnabled == true) {
        unawaited(_loadEligibilityInBackground(academyId));
      }
    } catch (e) {
      // Surface the failure instead of masquerading as "0 alunos".
      debugPrint(
        '[StudentsList] load failed (academy=${FirebaseService.academyId}): $e',
      );
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Carrega a snapshot de elegibilidade de graduação em BACKGROUND (não bloqueia
  /// a lista). Atualiza os badges quando pronto; falha silenciosa (badges apenas
  /// não aparecem).
  Future<void> _loadEligibilityInBackground(String academyId) async {
    try {
      final snapshot =
          await BeltProgressionService(academyId).getEligibilitySnapshot();
      if (!mounted) return;
      setState(() {
        _eligibilityByStudent = {for (final e in snapshot) e.studentId: e};
        _applyFilters();
      });
    } catch (e) {
      debugPrint('[StudentsList] eligibility (background) failed: $e');
    }
  }

  void _applyFilters() {
    var filtered = _students.toList();

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered
          .where(
            (s) =>
                s.fullName.toLowerCase().contains(query) ||
                (s.nickname?.toLowerCase().contains(query) ?? false) ||
                (s.email?.toLowerCase().contains(query) ?? false),
          )
          .toList();
    }

    // Status filter
    if (_statusFilter != null) {
      filtered = filtered.where((s) => s.status == _statusFilter).toList();
    } else {
      // Sem filtro explícito: ex-alunos TRANSFERIDOS não poluem o roster ativo.
      // Eles continuam acessíveis (com todo o histórico) ao selecionar o filtro
      // "Transferido" — que já aparece porque o sheet itera StudentStatus.values.
      filtered = filtered
          .where((s) => s.status != StudentStatus.transferred)
          .toList();
    }

    // Category filter
    if (_categoryFilter != null) {
      filtered = filtered.where((s) => s.category == _categoryFilter).toList();
    }

    // Sport filter — student must practice this modality
    if (_sportFilter != null) {
      filtered = filtered
          .where((s) => s.getSports().contains(_sportFilter))
          .toList();
    }

    // Belt filter — sport-aware. If a sport is selected, match the grade
    // for that sport; otherwise fall back to the legacy BJJ field for backward
    // compatibility with single-sport academies.
    if (_beltFilter != null) {
      filtered = filtered.where((s) {
        final sport = _sportFilter ?? s.getPrimarySport();
        final grade = s.getGrade(sport);
        return grade?.currentGrade == _beltFilter;
      }).toList();
    }

    // Account filter
    if (_accountFilter != null) {
      if (_accountFilter!) {
        filtered = filtered
            .where((s) => s.linkedUserId != null && s.linkedUserId!.isNotEmpty)
            .toList();
      } else {
        filtered = filtered
            .where((s) => s.linkedUserId == null || s.linkedUserId!.isEmpty)
            .toList();
      }
    }

    // Inactivity filter (Retenção §3.3) — só faz sentido para alunos ativos.
    if (_inactivityFilter != null) {
      final n = _inactivityFilter!;
      filtered = filtered.where((s) {
        if (s.status != StudentStatus.active) return false;
        final days = s.daysSinceLastAttendance;
        if (days == null) return n >= 30; // nunca treinou → só na banda 30+
        return days >= n;
      }).toList();
    }

    // Sorting
    switch (_sortBy) {
      case 'name':
        filtered.sort((a, b) => a.fullName.compareTo(b.fullName));
        break;
      case 'attendance':
        filtered.sort(
          (a, b) => b.totalAttendanceCount.compareTo(a.totalAttendanceCount),
        );
        break;
      case 'belt':
        filtered.sort((a, b) {
          final sportA = _sportFilter ?? a.getPrimarySport();
          final sportB = _sportFilter ?? b.getPrimarySport();
          final gradeA = a.getGrade(sportA)?.currentGrade ?? 'white';
          final gradeB = b.getGrade(sportB)?.currentGrade ?? 'white';
          final gradesA = getGradesForSport(
            sportA,
            category: a.category.value,
            muaythaiVariant: sportA == SportId.muaythai
                ? resolveMuaythaiVariant(gradeA)
                : null,
          );
          final gradesB = getGradesForSport(
            sportB,
            category: b.category.value,
            muaythaiVariant: sportB == SportId.muaythai
                ? resolveMuaythaiVariant(gradeB)
                : null,
          );
          final aIndex = gradesA.indexWhere((g) => g.id == gradeA);
          final bIndex = gradesB.indexWhere((g) => g.id == gradeB);
          if (aIndex != bIndex) return bIndex.compareTo(aIndex);
          final stripesA = a.getGrade(sportA)?.currentStripes ?? 0;
          final stripesB = b.getGrade(sportB)?.currentStripes ?? 0;
          return stripesB.compareTo(stripesA);
        });
        break;
      case 'eligible_first':
        // Eligible students float to the top, then closest-to-eligible by
        // progress fraction, then alphabetical as tiebreaker.
        filtered.sort((a, b) {
          final ea = _eligibilityByStudent[a.id];
          final eb = _eligibilityByStudent[b.id];
          final ael = ea?.eligible == true ? 1 : 0;
          final bel = eb?.eligible == true ? 1 : 0;
          if (ael != bel) return bel - ael;
          final aProg = (ea != null && ea.requiredClasses > 0)
              ? ea.currentClasses / ea.requiredClasses
              : 0.0;
          final bProg = (eb != null && eb.requiredClasses > 0)
              ? eb.currentClasses / eb.requiredClasses
              : 0.0;
          if (aProg != bProg) return bProg.compareTo(aProg);
          return a.fullName.compareTo(b.fullName);
        });
        break;
    }

    setState(() => _filteredStudents = filtered);
  }

  bool _hasActiveFilters() {
    return _statusFilter != null ||
        _categoryFilter != null ||
        _sportFilter != null ||
        _beltFilter != null ||
        _accountFilter != null ||
        _inactivityFilter != null;
  }

  void _clearFilters() {
    setState(() {
      _statusFilter = null;
      _categoryFilter = null;
      _sportFilter = null;
      _beltFilter = null;
      _accountFilter = null;
      _inactivityFilter = null;
      _applyFilters();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Master switch (mesmo campo que gateia o botão de check-in do próprio
    // aluno em lutador_hub_screen.dart) — decide se a ação "Marcar presença
    // de hoje" aparece nos cards abaixo. `select` evita rebuild da tela
    // inteira quando outros campos de AcademySettings mudam.
    final musculacaoEnabled = ref.watch(
      academySettingsProvider.select(
        (s) => s.valueOrNull?.musculacaoEnabled ?? true,
      ),
    );
    return Scaffold(
      backgroundColor: AppTheme.background,
      // ContentBounded: no-op no mobile; no desktop centraliza e limita a lista
      // em 1200px (evita a tabela esticada edge-to-edge numa janela larga).
      body: ContentBounded(
        child: RefreshIndicator(
          onRefresh: _loadStudents,
          child: CustomScrollView(
            slivers: [
              // Multi-academy aware header — shows current academy + switcher
              SliverToBoxAdapter(
                child: AcademyPageHeader(
                  icon: LucideIcons.users,
                  title: 'Alunos',
                  description: '${_students.length} alunos cadastrados',
                  actions: [
                    IconButton(
                      onPressed: _exportStudents,
                      icon: const Icon(Icons.download, size: 20),
                      tooltip: 'Exportar CSV',
                    ),
                    IconButton(
                      onPressed: _loadStudents,
                      icon: const Icon(LucideIcons.refreshCw, size: 20),
                      tooltip: 'Atualizar',
                    ),
                  ],
                ),
              ),

              // Solicitações de entrada (self-onboarding) — destaque verde.
              SliverToBoxAdapter(child: _buildRequestsButton()),

              // Search and filters
              SliverToBoxAdapter(child: _buildSearchAndFilters()),
              SliverToBoxAdapter(child: _buildInactivityChips()),

              // Active filter chips
              if (_hasActiveFilters())
                SliverToBoxAdapter(child: _buildActiveFilterChips()),

              // Student list
              _isLoading
                  ? SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      sliver: SliverToBoxAdapter(
                        // scrollable:false: SliverToBoxAdapter dá altura
                        // infinita ao filho — ListView scrollável aqui quebra
                        // o layout da tela inteira (viewport unbounded).
                        child: PolishSkeleton.list(
                            count: 6, itemHeight: 88, scrollable: false),
                      ),
                    )
                  : _filteredStudents.isEmpty
                  ? SliverFillRemaining(child: _buildEmptyState())
                  : _buildStudentSliverList(musculacaoEnabled),

              // Bottom padding
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showQuickAddSheet,
        backgroundColor: AppTheme.textPrimary,
        child: const Icon(LucideIcons.userPlus, color: Colors.white),
      ),
    );
  }

  Future<void> _exportStudents() async {
    if (_students.isEmpty) {
      context.showError('Nenhum aluno para exportar.');
      return;
    }
    try {
      final csv = StudentExportService(
        FirebaseService.academyId,
      ).buildCsv(_students);
      final bytes = Uint8List.fromList(utf8.encode(csv));
      final fileName =
          'alunos_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
      final path = await FilePicker.saveFile(
        dialogTitle: 'Exportar alunos',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
        bytes: bytes,
      );
      if (!mounted) return;
      if (path != null) {
        context.showSuccess('${_students.length} alunos exportados.');
      }
    } catch (_) {
      if (mounted) context.showError('Erro ao exportar.');
    }
  }

  /// Chips rápidos de inatividade (Retenção §3.3) — 1 toque para achar quem
  /// está esfriando, sem abrir o sheet de filtros.
  Widget _buildInactivityChips() {
    Widget chip(int days) {
      final selected = _inactivityFilter == days;
      return GestureDetector(
        onTap: () {
          setState(() {
            _inactivityFilter = selected ? null : days;
            _applyFilters();
          });
        },
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Brand.blood : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Brand.blood : AppTheme.divider,
            ),
          ),
          child: Text(
            '$days+ dias',
            style: AppTheme.labelSmall.copyWith(
              color: selected ? Colors.white : AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Row(
        children: [
          Text(
            'SEM TREINAR HÁ',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textDisabled,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 10),
          chip(7),
          chip(14),
          chip(30),
        ],
      ),
    );
  }

  /// Botão de destaque para as SOLICITAÇÕES de entrada. Verde e proeminente
  /// quando há pendências ("Solicitações (N)"); discreto quando não há (mas
  /// ainda leva à tela pra ver/compartilhar o código da academia).
  Widget _buildRequestsButton() {
    final count = ref.watch(pendingJoinRequestsCountProvider);
    final has = count > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Material(
        color: has ? AppTheme.success : AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/admin/alunos/solicitacoes'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: has ? null : Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                Icon(
                  has ? LucideIcons.userCheck : LucideIcons.ticket,
                  size: 20,
                  color: has ? Colors.white : AppTheme.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    has
                        ? 'Solicitações de entrada'
                        : 'Código da academia & solicitações',
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: has ? Colors.white : AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (has)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: AppTheme.labelMedium.copyWith(
                        color: AppTheme.success,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  Icon(LucideIcons.chevronRight,
                      size: 18, color: AppTheme.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          // Search field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: TextField(
                controller: _searchController,
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
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            LucideIcons.x,
                            color: AppTheme.textSecondary,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                              _applyFilters();
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                    _applyFilters();
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Filter button
          GestureDetector(
            onTap: _showFilterBottomSheet,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _hasActiveFilters()
                    ? AppTheme.primary
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hasActiveFilters()
                      ? AppTheme.primary
                      : AppTheme.divider,
                ),
              ),
              child: Icon(
                LucideIcons.sliders,
                size: 20,
                color: _hasActiveFilters()
                    ? Colors.white
                    : AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          if (_statusFilter != null)
            _FilterChip(
              label: _statusFilter!.label,
              onRemove: () {
                setState(() {
                  _statusFilter = null;
                  _applyFilters();
                });
              },
            ),
          if (_categoryFilter != null)
            _FilterChip(
              label: _categoryFilter!.label,
              onRemove: () {
                setState(() {
                  _categoryFilter = null;
                  _applyFilters();
                });
              },
            ),
          if (_sportFilter != null)
            _FilterChip(
              label: sports[_sportFilter]!.label,
              onRemove: () {
                setState(() {
                  _sportFilter = null;
                  // Belt selection only makes sense within a sport — reset it.
                  _beltFilter = null;
                  _applyFilters();
                });
              },
            ),
          if (_beltFilter != null)
            _FilterChip(
              label:
                  'Faixa ${getGradeLabel(_sportFilter ?? SportId.bjj, _beltFilter!)}',
              onRemove: () {
                setState(() {
                  _beltFilter = null;
                  _applyFilters();
                });
              },
            ),
          if (_accountFilter != null)
            _FilterChip(
              label: _accountFilter! ? 'Com conta' : 'Sem conta',
              onRemove: () {
                setState(() {
                  _accountFilter = null;
                  _applyFilters();
                });
              },
            ),
          if (_inactivityFilter != null)
            _FilterChip(
              label: 'Sem treinar $_inactivityFilter+ dias',
              onRemove: () {
                setState(() {
                  _inactivityFilter = null;
                  _applyFilters();
                });
              },
            ),
          GestureDetector(
            onTap: _clearFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Limpar',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentSliverList(bool musculacaoEnabled) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final student = _filteredStudents[index];
          return _StudentCard(
            student: student,
            eligibility: _eligibilityByStudent[student.id],
            musculacaoEnabled: musculacaoEnabled,
            onTap: () => context.go('/admin/alunos/${student.id}'),
          ).entrance(index: index);
        }, childCount: _filteredStudents.length),
      ),
    );
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FilterBottomSheet(
        statusFilter: _statusFilter,
        categoryFilter: _categoryFilter,
        sportFilter: _sportFilter,
        beltFilter: _beltFilter,
        accountFilter: _accountFilter,
        sortBy: _sortBy,
        muaythaiVariant:
            ref
                .read(academySettingsProvider)
                .valueOrNull
                ?.muaythaiGradeSystem ??
            muaythaiVariantCbmt,
        onApply: (status, category, sport, belt, account, sort) {
          setState(() {
            _statusFilter = status;
            _categoryFilter = category;
            _sportFilter = sport;
            _beltFilter = belt;
            _accountFilter = account;
            _sortBy = sort;
            _applyFilters();
          });
          Navigator.pop(context);
        },
        onClear: () {
          setState(() {
            _statusFilter = null;
            _categoryFilter = null;
            _sportFilter = null;
            _beltFilter = null;
            _accountFilter = null;
            _sortBy = 'name';
            _applyFilters();
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showQuickAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _QuickAddStudentSheet(
        muaythaiVariant:
            ref
                .read(academySettingsProvider)
                .valueOrNull
                ?.muaythaiGradeSystem ??
            muaythaiVariantCbmt,
        onCreated: (student) {
          // Genuine win — a new student joined the academy.
          if (mounted) Celebration.confetti(context);
          // Refresh list with the new student.
          _loadStudents();
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasFilters = _hasActiveFilters();
    return PolishedEmptyState(
      icon: LucideIcons.users,
      title: hasFilters ? 'Nenhum aluno encontrado' : 'Nenhum aluno cadastrado',
      subtitle: hasFilters
          ? 'Tente ajustar os filtros'
          : 'Adicione o primeiro aluno da academia',
      actionLabel: hasFilters ? null : 'Cadastrar Aluno',
      onAction: hasFilters ? null : () => context.go('/admin/alunos/novo'),
    );
  }
}

/// Filter chip widget
class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _FilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Icon(LucideIcons.x, size: 14, color: AppTheme.primary),
          ),
        ],
      ),
    );
  }
}

/// Student Card Widget - Fintech style
class _StudentCard extends StatelessWidget {
  final Student student;
  final VoidCallback? onTap;

  /// Optional eligibility snapshot from the academy-wide auto-graduation
  /// computation. When non-null and `requiredClasses > 0`, the card renders
  /// a progress bar (current/required) and an "Elegível" badge.
  final EligibilitySnapshotEntry? eligibility;

  /// Master switch da academia (AcademySettings.musculacaoEnabled) — parte
  /// do gate da ação "Marcar presença de hoje" (a outra parte é o próprio
  /// aluno ter ≥1 modalidade sem-faixa, calculado abaixo).
  final bool musculacaoEnabled;

  const _StudentCard({
    required this.student,
    this.onTap,
    this.eligibility,
    this.musculacaoEnabled = false,
  });

  /// Modalidades sem-faixa (GradeSystem.none — musculação/boxe/MMA) que este
  /// aluno pratica. Espelha o gate do botão de check-in do próprio aluno em
  /// lutador_hub_screen.dart (`checkinIsAvailable`), sem a exigência de
  /// `musculacaoCheckinMode == 'button'`: a ação da recepção é justamente a
  /// via alternativa pra quem NÃO usa o app, então vale em qualquer modo.
  List<SportId> get _gradelessSports => student
      .getSports()
      .where((s) => getSport(s).gradeSystem == GradeSystem.none)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final showEligibility =
        eligibility != null && eligibility!.requiredClasses > 0;
    final gradelessSports = _gradelessSports;
    final showStaffCheckin = musculacaoEnabled && gradelessSports.isNotEmpty;
    return Pressable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(
          children: [
            // Avatar
            _buildAvatar(),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          student.fullName,
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showEligibility && eligibility!.eligible)
                        _buildEligibleBadge(),
                      if (student.status != StudentStatus.active)
                        _buildStatusBadge(),
                      // Risco de churn (Retenção §3.3): só high/critical, e só
                      // para ativos — discreto, não polui quem está ok.
                      if (student.status == StudentStatus.active &&
                          (student.retention?.riskLevel == 'high' ||
                              student.retention?.riskLevel == 'critical'))
                        _buildRiskBadge(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildPrimaryGrade(),
                      const SizedBox(width: 8),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.textDisabled,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${student.totalAttendanceCount} presencas',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        student.category.label,
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (showEligibility) _buildProgressRow(),
                  _buildSportChipsRow(),
                ],
              ),
            ),

            if (showStaffCheckin) ...[
              const SizedBox(width: 4),
              _StaffCheckinAction(
                student: student,
                gradelessSports: gradelessSports,
              ),
            ],
            const SizedBox(width: 8),
            Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEligibleBadge() {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.warningLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.zap, size: 10, color: AppTheme.warning),
          const SizedBox(width: 4),
          Text(
            'Elegivel',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.warning,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow() {
    final e = eligibility!;
    final progress = (e.currentClasses / e.requiredClasses).clamp(0.0, 1.0);
    final unit = e.weighted ? 'pts' : 'aulas';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: AppTheme.surfaceVariant,
                valueColor: AlwaysStoppedAnimation(
                  e.eligible ? AppTheme.warning : AppTheme.info,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${e.currentClasses}/${e.requiredClasses} $unit',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final primarySport = student.getPrimarySport();
    final grade = student.getGrade(primarySport);
    final gradeId = grade?.currentGrade ?? 'white';
    final sportColor = sportChipColors[primarySport] ?? AppTheme.textSecondary;
    final avatarColor = _getGradeColor(primarySport, gradeId);
    final isLightAvatar = _isLightGrade(gradeId);

    return Hero(
      tag: 'student-avatar-${student.id}',
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: avatarColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sportColor, width: 2),
        ),
        child: student.photoUrl != null
            ? AppCachedImage(
                imageUrl: student.photoUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(10),
              )
            : Center(
                child: Text(
                  student.displayName[0].toUpperCase(),
                  style: TextStyle(
                    color: isLightAvatar ? Colors.black87 : Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildPrimaryGrade() {
    final primarySport = student.getPrimarySport();
    final grade = student.getGrade(primarySport);
    if (grade == null) return const SizedBox.shrink();
    return GradeDisplay(
      sportId: primarySport,
      grade: grade.currentGrade,
      stripes: grade.currentStripes,
      size: GradeDisplaySize.small,
    );
  }

  Widget _buildSportChipsRow() {
    final sports = student.getSports();
    if (sports.isEmpty) return const SizedBox.shrink();
    final primary = student.getPrimarySport();
    // Primary first, then the rest (cap at 4 visible, "+N" for overflow).
    final ordered = [primary, ...sports.where((s) => s != primary)];
    const maxVisible = 4;
    final visible = ordered.take(maxVisible).toList();
    final overflow = ordered.length - visible.length;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final s in visible) SportChip(sportId: s),
          if (overflow > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '+$overflow',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  height: 1,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Badge de risco de churn — ponto blood + dias sem treinar. Mesmo molde
  /// visual do badge de status.
  Widget _buildRiskBadge() {
    final critical = student.retention?.riskLevel == 'critical';
    final color = critical ? Brand.blood : AppTheme.warning;
    final days = student.daysSinceLastAttendance;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            days != null ? '${days}d' : 'esfriando',
            style: AppTheme.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    Color color;
    switch (student.status) {
      case StudentStatus.injured:
        color = AppTheme.warning;
        break;
      case StudentStatus.inactive:
        color = AppTheme.textSecondary;
        break;
      case StudentStatus.suspended:
        color = AppTheme.error;
        break;
      default:
        color = AppTheme.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        student.status.label,
        style: AppTheme.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Color _getGradeColor(SportId sport, String gradeId) {
    return getGradeColor(sport, gradeId);
  }

  bool _isLightGrade(String gradeId) {
    const lightGrades = {'white', 'yellow', 'orange'};
    return lightGrades.contains(gradeId.split('-').first);
  }
}

/// Ação discreta da recepção: "Marcar presença de hoje" pra um aluno SEM app
/// numa modalidade sem-turma (musculação/boxe/MMA). Só renderizada pelo
/// _StudentCard quando o gate (musculacaoEnabled + ≥1 modalidade sem-faixa)
/// passa. 1 modalidade → toque direto; ≥2 → mini-seletor num bottom sheet
/// (mesma UX de escolha do botão de check-in do próprio aluno em
/// lutador_hub_screen.dart `_CheckinButtonCard`).
///
/// A escrita (AttendanceService.markStaffScheduleLessPresence) usa o MESMO
/// doc-id determinístico da Cloud Function `selfCheckin` — nunca duplica com
/// um check-in que o aluno já tenha feito hoje pelo próprio app.
class _StaffCheckinAction extends ConsumerStatefulWidget {
  final Student student;
  final List<SportId> gradelessSports;

  const _StaffCheckinAction({
    required this.student,
    required this.gradelessSports,
  });

  @override
  ConsumerState<_StaffCheckinAction> createState() =>
      _StaffCheckinActionState();
}

class _StaffCheckinActionState extends ConsumerState<_StaffCheckinAction> {
  bool _busy = false;

  Future<void> _handleTap() async {
    if (_busy) return;
    final sports = widget.gradelessSports;
    final chosen = sports.length == 1 ? sports.single : await _pickSport();
    if (chosen != null) await _markPresence(chosen);
  }

  /// Mini-seletor quando o aluno pratica ≥2 modalidades sem-faixa.
  Future<SportId?> _pickSport() {
    final sports = widget.gradelessSports;
    return showModalBottomSheet<SportId>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Presença de hoje — ${widget.student.fullName}',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final s in sports)
                ListTile(
                  leading: Icon(getSport(s).icon, color: AppTheme.textPrimary),
                  title: Text(getSport(s).label),
                  onTap: () => Navigator.pop(sheetContext, s),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _markPresence(SportId sport) async {
    setState(() => _busy = true);
    try {
      final user = await ref.read(currentUserProvider.future);
      if (user == null) {
        if (mounted) context.showError('Sessão inválida — entre novamente.');
        return;
      }
      await AttendanceService(FirebaseService.academyId)
          .markStaffScheduleLessPresence(
        studentId: widget.student.id,
        studentName: widget.student.fullName,
        sport: sport.value,
        className: getSport(sport).label,
        verifiedBy: user.id,
        verifiedByName: user.displayName,
      );
      unawaited(AnalyticsService.logCheckinScanned(kind: 'staff'));
      if (!mounted) return;
      context.showSuccess('Presença registrada: ${widget.student.fullName}');
    } on AttendanceAlreadyMarkedException {
      if (mounted) {
        context.showError(
          '${widget.student.fullName} já tem presença hoje nesta modalidade.',
        );
      }
    } catch (_) {
      if (mounted) context.showError('Erro ao marcar presença.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Marcar presença de hoje',
      child: Pressable(
        onTap: _busy ? null : _handleTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: _busy
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.success,
                  ),
                )
              : Icon(LucideIcons.userCheck, size: 16, color: AppTheme.success),
        ),
      ),
    );
  }
}

/// Filter Bottom Sheet
class _FilterBottomSheet extends StatefulWidget {
  final StudentStatus? statusFilter;
  final StudentCategory? categoryFilter;
  final SportId? sportFilter;
  final String? beltFilter;
  final bool? accountFilter;
  final String sortBy;
  final String muaythaiVariant;
  final Function(
    StudentStatus?,
    StudentCategory?,
    SportId?,
    String?,
    bool?,
    String,
  )
  onApply;
  final VoidCallback onClear;

  const _FilterBottomSheet({
    required this.statusFilter,
    required this.categoryFilter,
    required this.sportFilter,
    required this.beltFilter,
    required this.accountFilter,
    required this.sortBy,
    required this.muaythaiVariant,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<_FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<_FilterBottomSheet> {
  late StudentStatus? _status;
  late StudentCategory? _category;
  late SportId? _sport;
  late String? _belt;
  late bool? _account;
  late String _sort;

  @override
  void initState() {
    super.initState();
    _status = widget.statusFilter;
    _category = widget.categoryFilter;
    _sport = widget.sportFilter;
    _belt = widget.beltFilter;
    _account = widget.accountFilter;
    _sort = widget.sortBy;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
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

            // Title
            Text(
              'Filtros',
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),

            // Status filter
            _buildSectionTitle('Status'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: StudentStatus.values.map((status) {
                final isSelected = _status == status;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _status = isSelected ? null : status),
                  child: _buildChip(status.label, isSelected),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Category filter
            _buildSectionTitle('Categoria'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: StudentCategory.values.map((category) {
                final isSelected = _category == category;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _category = isSelected ? null : category),
                  child: _buildChip(category.label, isSelected),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Sport filter
            _buildSectionTitle('Modalidade'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sportOptions.map((sportId) {
                final isSelected = _sport == sportId;
                return GestureDetector(
                  onTap: () => setState(() {
                    if (isSelected) {
                      _sport = null;
                    } else {
                      _sport = sportId;
                    }
                    // Belt is tied to sport — clear when sport changes.
                    _belt = null;
                  }),
                  child: _buildSportFilterChip(sportId, isSelected),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Belt filter — grades depend on selected sport (defaults to BJJ).
            _buildSectionTitle(
              'Faixa${_sport != null ? ' · ${sports[_sport]!.labelShort}' : ''}',
            ),
            Builder(
              builder: (_) {
                final activeSport = _sport ?? SportId.bjj;
                final categoryValue = _category?.value ?? 'adult';
                final grades = getGradesForSport(
                  activeSport,
                  category: categoryValue,
                  muaythaiVariant: activeSport == SportId.muaythai
                      ? widget.muaythaiVariant
                      : null,
                );
                if (grades.isEmpty) {
                  return Text(
                    'Esta modalidade não usa graduação.',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: grades.map((g) {
                    final isSelected = _belt == g.id;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _belt = isSelected ? null : g.id),
                      child: _buildChip(g.label, isSelected),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 20),

            // Account filter
            _buildSectionTitle('Conta'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [(true, 'Com conta'), (false, 'Sem conta')].map((item) {
                final isSelected = _account == item.$1;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _account = isSelected ? null : item.$1),
                  child: _buildChip(item.$2, isSelected),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // Sort by
            _buildSectionTitle('Ordenar por'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  [
                    ('name', 'Nome'),
                    ('attendance', 'Presencas'),
                    ('belt', 'Faixa'),
                    ('eligible_first', 'Elegiveis primeiro'),
                  ].map((item) {
                    final isSelected = _sort == item.$1;
                    return GestureDetector(
                      onTap: () => setState(() => _sort = item.$1),
                      child: _buildChip(item.$2, isSelected),
                    );
                  }).toList(),
            ),
            const SizedBox(height: 32),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onClear,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: AppTheme.divider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Limpar',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => widget.onApply(
                      _status,
                      _category,
                      _sport,
                      _belt,
                      _account,
                      _sort,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.textPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Aplicar',
                      style: AppTheme.bodyMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: AppTheme.bodyMedium.copyWith(
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildChip(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.textPrimary : AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? AppTheme.textPrimary : AppTheme.divider,
        ),
      ),
      child: Text(
        label,
        style: AppTheme.bodySmall.copyWith(
          color: isSelected ? Colors.white : AppTheme.textPrimary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSportFilterChip(SportId sportId, bool isSelected) {
    final sport = sports[sportId]!;
    final accent = sportChipColors[sportId] ?? AppTheme.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? accent.withValues(alpha: 0.12) : AppTheme.surface,
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
        ],
      ),
    );
  }
}

/// Cadastro rápido de aluno. Pede apenas Nome + Modalidades (+ categoria
/// opcional) e usa `StudentService.quickCreate` para gravar — a primeira
/// modalidade selecionada vira primária. Inclui link para o cadastro
/// completo (form de várias abas) se o admin precisar dos campos extras.
class _QuickAddStudentSheet extends StatefulWidget {
  final void Function(Student) onCreated;
  final String muaythaiVariant;

  const _QuickAddStudentSheet({
    required this.onCreated,
    required this.muaythaiVariant,
  });

  @override
  State<_QuickAddStudentSheet> createState() => _QuickAddStudentSheetState();
}

class _QuickAddStudentSheetState extends State<_QuickAddStudentSheet> {
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
      final service = StudentService(FirebaseService.academyId);
      final orderedSports = [
        _primarySport ?? _selectedSports.first,
        ..._selectedSports.where((s) => s != _primarySport),
      ];
      final student = await service.quickCreate(
        fullName: name,
        sports: orderedSports,
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        category: _category,
        muaythaiVariant: widget.muaythaiVariant,
      );
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
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(LucideIcons.userPlus, size: 18),
                            const SizedBox(width: 8),
                            const Text(
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
        // Tap unselected → adds. Tap selected non-primary → makes primary.
        // Long-press → removes.
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
