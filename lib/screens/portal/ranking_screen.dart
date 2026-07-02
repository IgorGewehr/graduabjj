import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/brand_tokens.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/ranking_entry.dart';
import '../../models/student.dart';
import '../../providers/portal_providers.dart';
import '../../providers/ranking_providers.dart';
import '../../providers/student_provider.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/feature_disabled_state.dart';
import '../../widgets/polish/polish.dart';

/// Student-facing attendance leaderboard. Pick an audience (Geral / Adulto /
/// Kids) + period and see who trained the most. Each row links to that
/// student's public profile.
class RankingScreen extends ConsumerStatefulWidget {
  /// When true, the screen is opened from the ADMIN/professor side: the
  /// student-visibility gate (rankingVisibleToStudents) is bypassed — staff
  /// always see the ranking of THEIR students — the title reflects the staff
  /// view, and a row tap opens the admin student detail instead of the portal
  /// public profile.
  final bool forStaff;

  /// When true, renders only the body (no Scaffold/AppBar) so it can be embedded
  /// as a tab inside another screen (e.g. the admin SOCIAL screen). The caller
  /// provides the surrounding Scaffold and background.
  final bool embedded;
  const RankingScreen({
    super.key,
    this.forStaff = false,
    this.embedded = false,
  });

  @override
  ConsumerState<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends ConsumerState<RankingScreen> {
  RankingCategory _category = RankingCategory.general;
  RankingPeriod _period = RankingPeriod.week;
  // Selected modality (null until the user picks). Only relevant for academies
  // that train more than one sport — keeps each modality's ranking separate.
  SportId? _selectedSport;

  @override
  Widget build(BuildContext context) {
    // Staff (admin/professor) ALWAYS see the ranking of their students — the
    // rankingVisibleToStudents gate only governs the student portal. Defense in
    // depth for the portal: even reached via deep link / stale nav, the ranking
    // stays hidden when the academy disabled student visibility. Loading/null
    // resolves to true so it shows by default for legacy academies.
    final rankingVisible = widget.forStaff ||
        ref.watch(
          academySettingsProvider.select(
            (s) => s.valueOrNull?.rankingVisibleToStudents ?? true,
          ),
        );

    // Embutido (aba de outra tela): só o corpo, sem Scaffold/AppBar — o pai já
    // fornece o fundo bone e a barra.
    if (widget.embedded) {
      return !rankingVisible ? const _RankingUnavailableState() : _buildContent();
    }

    return Scaffold(
      // Fundo bone (igual à Galera) pros cards brancos do leaderboard aparecerem.
      backgroundColor: const Color(0xFFF4F3EF),
      appBar: AppBar(
        title: Text(widget.forStaff ? 'Ranking dos Alunos' : 'Ranking de Turmas'),
      ),
      body: !rankingVisible
          ? const _RankingUnavailableState()
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    // The academy's modalities, derived from its classes. A sport selector only
    // appears for multi-modality academies; otherwise the ranking is over the
    // single sport (sport filter stays null = all, which is equivalent).
    final classes = ref.watch(classesProvider).valueOrNull ?? const [];
    var academySports = (<SportId>{for (final c in classes) c.getSport()}
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index)));

    // Aluno (não-staff) vê SÓ a(s) modalidade(s) e a categoria (adulto/kids) em
    // que ele está. Staff (admin/professor) continua vendo tudo e escolhendo.
    final isStudentView = !widget.forStaff;
    final student =
        isStudentView ? ref.watch(currentStudentProvider).valueOrNull : null;
    var effectiveCategory = _category;
    if (student != null) {
      final studentSports = student.getSports().toSet();
      final mine = academySports.where(studentSports.contains).toList();
      academySports = mine.isNotEmpty ? mine : student.getSports();
      effectiveCategory = student.category == StudentCategory.kids
          ? RankingCategory.kids
          : RankingCategory.adult;
    }

    final showSportSelector = academySports.length > 1;
    // Staff com 1 modalidade usa sport=null (= todas, equivalente). O aluno
    // SEMPRE escopa numa modalidade dele (nunca "todas"), mesmo sem seletor.
    final SportId? activeSport = academySports.isEmpty
        ? null
        : (showSportSelector || isStudentView)
            ? ((_selectedSport != null &&
                    academySports.contains(_selectedSport))
                ? _selectedSport
                : academySports.first)
            : null;

    return Column(
      children: [
        if (showSportSelector)
          _SportSelector(
            sports: academySports,
            selected: activeSport!,
            onChanged: (s) => setState(() => _selectedSport = s),
          ),
        _RankingHeader(
          category: effectiveCategory,
          period: _period,
          onCategoryChanged: (c) => setState(() => _category = c),
          onPeriodChanged: (p) => setState(() => _period = p),
          // Aluno: categoria travada na dele (sem seletor); só staff escolhe.
          showCategorySelector: widget.forStaff,
        ),
        // Sub-meta do meio da tabela (§2.3 U-shape) — só na visão do ALUNO e
        // só quando ele está no terço central do ranking. Renderiza
        // SizedBox.shrink() fora dessas condições (invisível por padrão).
        if (isStudentView && student != null)
          _MyPositionCard(
            myStudentId: student.id,
            rankingKey: (
              category: effectiveCategory,
              period: _period,
              sport: activeSport?.value,
            ),
          ),
        Expanded(child: _buildLeaderboard(activeSport, effectiveCategory)),
      ],
    );
  }

  Widget _buildLeaderboard(SportId? sport, RankingCategory category) {
    final key = (category: category, period: _period, sport: sport?.value);
    final rankingAsync = ref.watch(classRankingProvider(key));

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: () async {
        HapticFeedback.mediumImpact();
        ref.invalidate(classRankingProvider(key));
      },
      child: rankingAsync.when(
        loading: () => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: PolishSkeleton.list(count: 6, itemHeight: 68),
        ),
        error: (_, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            _RankingMessageState(
              icon: LucideIcons.alertCircle,
              message: 'Nao foi possivel carregar o ranking.\nPuxe para atualizar.',
            ),
          ],
        ),
        data: (entries) {
          if (entries.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 100),
                PolishedEmptyState(
                  icon: LucideIcons.trophy,
                  title: 'Nenhuma presença registrada',
                  subtitle: 'Treine no período para aparecer no ranking.',
                ),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final entry = entries[i];
              return _RankingTile(
                entry: entry,
                onTap: () => context.push(
                  widget.forStaff
                      ? '/admin/alunos/${entry.studentId}'
                      : '/portal/profile/${entry.studentId}',
                ),
              ).entrance(index: i);
            },
          );
        },
      ),
    );
  }
}

/// Horizontal modality picker — one ranking per sport for multi-sport academies.
class _SportSelector extends StatelessWidget {
  final List<SportId> sports;
  final SportId selected;
  final ValueChanged<SportId> onChanged;

  const _SportSelector({
    required this.sports,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      color: AppTheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final s in sports) ...[
              ChoiceChip(
                label: Text(getSport(s).label),
                selected: s == selected,
                showCheckmark: false,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  onChanged(s);
                },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sticky header: audience (Geral / Adulto / Kids) + period segmented controls.
class _RankingHeader extends StatelessWidget {
  final RankingCategory category;
  final RankingPeriod period;
  final ValueChanged<RankingCategory> onCategoryChanged;
  final ValueChanged<RankingPeriod> onPeriodChanged;
  final bool showCategorySelector;

  const _RankingHeader({
    required this.category,
    required this.period,
    required this.onCategoryChanged,
    required this.onPeriodChanged,
    this.showCategorySelector = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Audience segmented control — só staff escolhe; o aluno tem a
          // categoria travada na dele, então o seletor fica escondido.
          if (showCategorySelector) ...[
            SegmentedButton<RankingCategory>(
              segments: const [
                ButtonSegment(
                  value: RankingCategory.general,
                  label: Text('Geral'),
                ),
                ButtonSegment(
                  value: RankingCategory.adult,
                  label: Text('Adulto'),
                ),
                ButtonSegment(
                  value: RankingCategory.kids,
                  label: Text('Kids'),
                ),
              ],
              selected: {category},
              showSelectedIcon: false,
              onSelectionChanged: (set) {
                HapticFeedback.selectionClick();
                onCategoryChanged(set.first);
              },
            ),
            const SizedBox(height: 12),
          ],
          // Period segmented control
          SegmentedButton<RankingPeriod>(
            segments: const [
              ButtonSegment(
                value: RankingPeriod.week,
                label: Text('7 Dias'),
              ),
              ButtonSegment(
                value: RankingPeriod.month,
                label: Text('30 Dias'),
              ),
            ],
            selected: {period},
            showSelectedIcon: false,
            onSelectionChanged: (set) {
              HapticFeedback.selectionClick();
              onPeriodChanged(set.first);
            },
          ),
        ],
      ),
    );
  }
}

/// One leaderboard row (fighter aesthetic): big tabular rank numeral (líder em
/// vermelho), avatar, name, training count. Sem medalha laranja/dourada.
class _RankingTile extends StatelessWidget {
  final RankingEntry entry;
  final VoidCallback onTap;

  const _RankingTile({required this.entry, required this.onTap});

  static const _ink = Color(0xFF0A0A0A);
  static const _red = Color(0xFFE0301E);
  static const _smoke = Color(0xFF6E6E68);

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final leader = entry.rank == 1;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _ink.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Text(
                '${entry.rank}',
                style: TextStyle(
                  fontSize: 23,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: leader ? _red : _ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Hero(
              tag: 'profile-avatar-${entry.studentId}',
              child: AppCachedAvatar(
                imageUrl: entry.photoUrl,
                radius: 20,
                backgroundColor: _ink.withValues(alpha: 0.06),
                foregroundColor: _ink,
                child: Text(
                  _initials(entry.studentName),
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.studentName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w800, color: _ink),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${entry.attendanceCount}',
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                fontFeatures: [FontFeature.tabularFigures()],
                color: _ink,
              ),
            ),
            const SizedBox(width: 4),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('treinos',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, color: _smoke)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card "VOCÊ" — sub-meta para o MEIO da tabela (visão do aluno).
///
/// Base científica (docs/b2c/PESQUISA_PSICOLOGIA_RETENCAO_RIVAIS_2026-07.md
/// §2.3, efeito curvilíneo/U-shape): motivação é maior no TOPO e no FUNDO do
/// ranking — a desmotivação mora no meio. A correção de design (P6) é dar a
/// quem está no meio UMA sub-meta mais próxima que a posição global.
///
/// Regras de exibição (fora delas o widget é invisível — SizedBox.shrink):
/// - tabela com >= 8 entries (ranking pequeno não tem "meio");
/// - posição > 3 (topo NUNCA vê — seria redundante);
/// - posição entre 25% e 75% da tabela (o terço central da curva U).
///
/// A sub-meta é a distância pro próximo colocado: como o desempate do
/// [RankingService] é presença-mais-recente DESC, EMPATAR em treinos já sobe —
/// então o alvo é `max(1, diff)` presenças. Nunca vira push (§2.3: "nunca push
/// de posição"); é só um lembrete silencioso de que a próxima posição está a
/// poucos treinos.
class _MyPositionCard extends ConsumerWidget {
  final String myStudentId;
  final ({RankingCategory category, RankingPeriod period, String? sport})
      rankingKey;

  const _MyPositionCard({
    required this.myStudentId,
    required this.rankingKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mesma family key da lista — zero fetch extra, e o pull-to-refresh da
    // lista invalida este card junto.
    final entries = ref.watch(classRankingProvider(rankingKey)).valueOrNull;
    if (entries == null || entries.length < 8) return const SizedBox.shrink();

    final idx = entries.indexWhere((e) => e.studentId == myStudentId);
    if (idx <= 0) return const SizedBox.shrink(); // fora do ranking ou líder
    final me = entries[idx];
    final fraction = me.rank / entries.length;
    if (me.rank <= 3 || fraction < 0.25 || fraction > 0.75) {
      return const SizedBox.shrink();
    }

    // Distância pro próximo: empate + presença mais recente já desempata a
    // favor de quem acabou de treinar, então o alvo mínimo é 1 presença.
    final above = entries[idx - 1];
    final needed = (above.attendanceCount - me.attendanceCount).clamp(1, 9999);
    final subGoal = needed == 1
        ? 'A 1 presença de subir uma posição'
        : 'A $needed presenças de subir uma posição';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.ink.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          // Posição atual — numeral tabular no padrão das linhas da tabela.
          Text(
            '${me.rank}º',
            style: const TextStyle(
              fontSize: 23,
              height: 1.0,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              fontFeatures: Brand.tabular,
              color: Brand.ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VOCÊ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                    color: Brand.blood,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subGoal,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    fontFeatures: Brand.tabular,
                    color: Brand.ink,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${me.attendanceCount}',
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              fontFeatures: Brand.tabular,
              color: Brand.ink,
            ),
          ),
          const SizedBox(width: 4),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'treinos',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Brand.ash,
              ),
            ),
          ),
        ],
      ),
    ).entrance();
  }
}

/// Shown when the academy turned off the student-facing ranking. Guards against
/// deep links or stale navigation reaching a leaderboard that should be hidden.
class _RankingUnavailableState extends StatelessWidget {
  const _RankingUnavailableState();

  @override
  Widget build(BuildContext context) {
    return const FeatureDisabledState(
      icon: LucideIcons.medal,
      title: 'Ranking indisponível',
      subtitle: 'Sua academia não está usando o Ranking de Turmas.',
    );
  }
}

/// Centered icon + message used for empty / error / unavailable states.
class _RankingMessageState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _RankingMessageState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppTheme.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
