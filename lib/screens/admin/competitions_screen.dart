import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../api/repositories.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/services.dart';
import '../portal/competition_detail_screen.dart';
import 'competitions/competition_card.dart';
import 'competitions/competition_form_sheet.dart';
import 'competitions/delete_confirmation_sheet.dart';
import 'competitions/enrollment_sheet.dart';
import 'competitions/trophy_showcase.dart';

/// Admin Competitions Screen - Fintech style matching webapp
class AdminCompetitionsScreen extends ConsumerStatefulWidget {
  const AdminCompetitionsScreen({super.key});

  @override
  ConsumerState<AdminCompetitionsScreen> createState() =>
      _AdminCompetitionsScreenState();
}

class _AdminCompetitionsScreenState
    extends ConsumerState<AdminCompetitionsScreen> {
  List<Competition> _upcomingCompetitions = [];
  List<Competition> _pastCompetitions = [];
  bool _isLoading = true;
  int _selectedTabIndex = 0;
  String? _academyId;

  final _tabs = ['Proximos', 'Passados'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadCompetitionsIfReady();
  }

  void _loadCompetitionsIfReady() {
    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser?.academyId != null &&
        _academyId != currentUser!.academyId) {
      _academyId = currentUser.academyId;
      _loadCompetitions();
    }
  }

  Future<void> _loadCompetitions() async {
    final academyId = _academyId;
    if (academyId == null) return;

    setState(() => _isLoading = true);

    try {
      ref.invalidate(tatami.tatamiCompetitionsLegacyProvider(academyId));
      final all = await ref
          .read(tatami.tatamiCompetitionsLegacyProvider(academyId).future);
      final now = DateTime.now();
      final upcoming =
          all.where((c) => !c.date.isBefore(now)).toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      final past =
          all.where((c) => c.date.isBefore(now)).toList()
            ..sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _upcomingCompetitions = upcoming;
        _pastCompetitions = past;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Competition> get _currentList =>
      _selectedTabIndex == 0 ? _upcomingCompetitions : _pastCompetitions;

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    if (currentUser?.academyId != null &&
        _academyId != currentUser!.academyId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _academyId = currentUser.academyId;
          _loadCompetitions();
        }
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadCompetitions,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(
              child: TrophyShowcase(
                upcomingCompetitions: _upcomingCompetitions,
                pastCompetitions: _pastCompetitions,
                onCompetitionTap: _navigateToDetail,
              ),
            ),
            SliverToBoxAdapter(child: _buildTabs()),
            _isLoading
                ? const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _currentList.isEmpty
                ? SliverFillRemaining(child: _buildEmptyState())
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final competition = _currentList[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: CompetitionCard(
                            competition: competition,
                            onTap: () => _navigateToDetail(competition),
                            onEdit: () => _openEditSheet(competition),
                            onDelete: () => _openDeleteSheet(competition),
                            onManageEnrollments: () =>
                                _openEnrollmentsSheet(competition),
                          ),
                        );
                      }, childCount: _currentList.length),
                    ),
                  ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: (currentUser?.isInstructor ?? false)
          ? FloatingActionButton.extended(
              onPressed: _openCreateSheet,
              backgroundColor: AppTheme.textPrimary,
              foregroundColor: Colors.white,
              icon: const Icon(LucideIcons.plus, size: 20),
              label: const Text('Novo Campeonato'),
            )
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Sub-widgets locais
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_upcomingCompetitions.length + _pastCompetitions.length} campeonatos',
              style: AppTheme.labelMedium.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadCompetitions,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.surface,
              foregroundColor: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.all(20),
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedTabIndex == index;
          final count = index == 0
              ? _upcomingCompetitions.length
              : _pastCompetitions.length;
          return GestureDetector(
            onTap: () => setState(() => _selectedTabIndex = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.textPrimary : AppTheme.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isSelected ? AppTheme.textPrimary : AppTheme.divider,
                ),
              ),
              child: Center(
                child: Text(
                  '${_tabs[index]} ($count)',
                  style: AppTheme.bodySmall.copyWith(
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(LucideIcons.trophy, size: 40, color: AppTheme.warning),
          ),
          const SizedBox(height: 16),
          Text(
            _selectedTabIndex == 0
                ? 'Nenhum campeonato agendado'
                : 'Nenhum campeonato passado',
            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Adicione novos campeonatos para comecar',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Navigation / sheet delegates
  // ---------------------------------------------------------------------------

  void _navigateToDetail(Competition competition) {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => CompetitionDetailScreen(
              competitionId: competition.id,
              isAdmin: true,
            ),
          ),
        )
        .then((_) => _loadCompetitions());
  }

  void _openCreateSheet() {
    if (_academyId == null) return;
    showCreateCompetitionSheet(
      context: context,
      ref: ref,
      academyId: _academyId!,
      onCreated: _loadCompetitions,
    );
  }

  void _openEditSheet(Competition competition) {
    if (_academyId == null) return;
    showEditCompetitionSheet(
      context: context,
      ref: ref,
      academyId: _academyId!,
      competition: competition,
      onUpdated: _loadCompetitions,
    );
  }

  void _openDeleteSheet(Competition competition) {
    if (_academyId == null) return;
    showDeleteCompetitionConfirmation(
      context: context,
      academyId: _academyId!,
      competition: competition,
      repo: ref.read(competitionRepoProvider),
      onDeleted: _loadCompetitions,
    );
  }

  void _openEnrollmentsSheet(Competition competition) {
    if (_academyId == null) return;
    showEnrollmentsSheet(
      context: context,
      academyId: _academyId!,
      competition: competition,
      competitionRepo: ref.read(competitionRepoProvider),
      studentRepo: ref.read(studentRepoProvider),
      onChanged: _loadCompetitions,
    );
  }
}
