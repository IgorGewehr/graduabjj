import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/competition_photo.dart';
import '../../models/fighter_profile.dart';
import '../../models/public_student_profile.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_providers.dart';
import '../../providers/portal_providers.dart';
import '../../providers/ranking_providers.dart';
import '../../services/achievement_service.dart' show Achievement, AchievementType;
import '../../services/competition_service.dart' show CompetitionResult;
import '../../widgets/cached_image.dart';
import '../../widgets/common/animated_belt.dart';
import '../../widgets/common/belt_badge.dart';
import '../../widgets/common/grade_badge.dart';
import '../../widgets/competitions/photo_card.dart';
import '../../widgets/competitions/photo_fullscreen_viewer.dart';
import '../../widgets/polish/polish.dart';

// =============================================================================
// Tokens anti-slop (consistentes com o hub do Lutador / perfil próprio).
// Bone + cards brancos + tinta ink + UM acento vermelho. A COR DA FAIXA
// (getGradeColor) só representa faixa real.
// =============================================================================
class _T {
  _T._();
  static const bone = Color(0xFFF4F3EF);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0A0A0A);
  static const blood = Color(0xFFE0301E);
  static const smoke = Color(0xFF6E6E68);
  static const ash = Color(0xFF9A9A93);
  static const hair = Color(0x14000000);
  static const List<FontFeature> tab = [FontFeature.tabularFigures()];
}

TextStyle _eyebrow(Color c, double s) => TextStyle(
      color: c,
      fontSize: s,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
    );

/// Read-only public profile of a student, viewed from inside the portal.
///
/// Resolves the academy from the current user, then composes the student's
/// timeline, competition results and photos via [publicStudentProfileProvider].
/// Strictly read-only: no edit/mutation affordances are exposed here.
class PublicProfileScreen extends ConsumerStatefulWidget {
  final String studentId;

  const PublicProfileScreen({super.key, required this.studentId});

  @override
  ConsumerState<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final academyId =
        ref.watch(currentUserProvider).valueOrNull?.academyId;

    return Scaffold(
      backgroundColor: _T.bone,
      appBar: AppBar(
        title: Text('PERFIL', style: _eyebrow(_T.ink, 15)),
        centerTitle: false,
        backgroundColor: _T.bone,
        foregroundColor: _T.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _T.ink),
      ),
      body: academyId == null
          ? _buildMessage(
              icon: LucideIcons.userX,
              title: 'Perfil nao disponivel',
            )
          : _buildBody(academyId),
    );
  }

  Widget _buildBody(String academyId) {
    final profileAsync = ref.watch(
      publicStudentProfileProvider(
        (academyId: academyId, studentId: widget.studentId),
      ),
    );

    return profileAsync.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          PolishSkeleton.header(avatarSize: 64),
          const SizedBox(height: 16),
          Expanded(
            child: PolishSkeleton.list(count: 4, showAvatar: false),
          ),
        ],
      ),
      error: (e, st) => _buildMessage(
        icon: LucideIcons.alertTriangle,
        title: 'Erro ao carregar',
        subtitle: 'Nao foi possivel carregar este perfil',
      ),
      data: (profile) {
        if (profile == null) {
          // Sem ficha na academia do viewer — caso típico: AMIGO de OUTRA
          // academia (navegado pelo auth uid, que não é studentId local). Cai
          // na vitrine pública pura do espelho fighterProfiles/{uid}, sem exigir
          // o student doc da academia do viewer.
          return _buildShowcaseOnly();
        }
        // MESMA ACADEMIA: perfil de colega é SEMPRE liberado. Este provider
        // resolve na academia do VIEWER (publicStudentProfileProvider), então
        // se chegou aqui o alvo é da mesma academia — você treina com ele, vê a
        // evolução dele. A flag isProfilePublic só gateia a exposição EXTERNA/web
        // (fora do app), nunca os colegas de tatame.
        return _buildProfile(profile);
      },
    );
  }

  Widget _buildProfile(PublicStudentProfile profile) {
    final Student student = profile.student;
    final List<Achievement> achievements = profile.achievements;
    final List<CompetitionResult> results = profile.competitionResults;
    final List<CompetitionPhoto> photos = profile.photos;

    // VITRINE MATERIALIZADA — lê o espelho `fighterProfiles/{uid}` (1 read),
    // nunca a attendance privada da academia do dono. O id de navegação é o
    // studentId (doc do aluno); o mirror é chaveado pelo auth uid, que vem em
    // `linkedUserId`. Cai de volta no studentId quando o aluno não tem usuário
    // vinculado (setups antigos em que doc.id == uid).
    final String uid = (student.linkedUserId != null &&
            student.linkedUserId!.isNotEmpty)
        ? student.linkedUserId!
        : widget.studentId;
    final FighterProfile? showcase =
        ref.watch(fighterShowcaseProvider(uid)).valueOrNull;

    final bool hasGraduations =
        showcase != null && showcase.graduations.isNotEmpty;
    final bool hasCompetitions =
        showcase != null && showcase.competitions.isNotEmpty;
    final int medalCount = showcase != null && showcase.medals.total > 0
        ? showcase.medals.total
        : results.length;

    return Column(
      children: [
        _ProfileHeader(
          student: student,
          medalCount: medalCount,
          showcase: showcase,
        ).fadeInQuick(),
        Material(
          color: _T.bone,
          child: TabBar(
            controller: _tabController,
            labelColor: _T.ink,
            unselectedLabelColor: _T.smoke,
            indicatorColor: _T.blood,
            indicatorWeight: 2.5,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: _T.hair,
            labelStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
            tabs: const [
              Tab(text: 'GRADUACOES'),
              Tab(text: 'COMPETICOES'),
              Tab(text: 'FOTOS'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Vitrine materializada quando existe; senão a linha do tempo
              // clássica (mesma academia do visitante) como fallback.
              hasGraduations
                  ? _GraduationsTab(graduations: showcase.graduations)
                  : _TimelineTab(achievements: achievements),
              hasCompetitions
                  ? _CompetitionMarksTab(
                      marks: showcase.competitions,
                      medals: showcase.medals,
                    )
                  : _CompetitionsTab(results: results),
              _PhotosTab(photos: photos),
            ],
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // VITRINE-ONLY — amigo cross-academy: não há student doc na academia do
  // viewer, então renderiza direto do espelho fighterProfiles/{uid} (o id de
  // navegação É o auth uid do lutador). Header enxuto + as mesmas abas de
  // graduações/competições da vitrine.
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildShowcaseOnly() {
    final fpAsync = ref.watch(fighterShowcaseProvider(widget.studentId));
    return fpAsync.when(
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          PolishSkeleton.header(avatarSize: 64),
          const SizedBox(height: 16),
          Expanded(child: PolishSkeleton.list(count: 4, showAvatar: false)),
        ],
      ),
      error: (_, _) => _buildMessage(
        icon: LucideIcons.alertTriangle,
        title: 'Erro ao carregar',
        subtitle: 'Nao foi possivel carregar este perfil',
      ),
      data: (fp) {
        if (fp == null) {
          return _buildMessage(
            icon: LucideIcons.userX,
            title: 'Perfil nao disponivel',
          );
        }
        return _buildFighterShowcase(fp);
      },
    );
  }

  Widget _buildFighterShowcase(FighterProfile fp) {
    return Column(
      children: [
        _showcaseHeader(fp),
        Material(
          color: _T.bone,
          child: TabBar(
            controller: _tabController,
            labelColor: _T.ink,
            unselectedLabelColor: _T.smoke,
            indicatorColor: _T.blood,
            indicatorWeight: 2.5,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: _T.hair,
            labelStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6),
            unselectedLabelStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6),
            tabs: const [
              Tab(text: 'GRADUACOES'),
              Tab(text: 'COMPETICOES'),
              Tab(text: 'FOTOS'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              fp.graduations.isNotEmpty
                  ? _GraduationsTab(graduations: fp.graduations)
                  : _buildMessage(
                      icon: LucideIcons.award,
                      title: 'Sem graduacoes ainda'),
              fp.competitions.isNotEmpty
                  ? _CompetitionMarksTab(
                      marks: fp.competitions, medals: fp.medals)
                  : _buildMessage(
                      icon: LucideIcons.trophy,
                      title: 'Sem competicoes ainda'),
              _buildMessage(icon: LucideIcons.image, title: 'Sem fotos'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _showcaseHeader(FighterProfile fp) {
    final sport = SportId.fromString(fp.sport);
    final beltColor = AppTheme.getBeltColor(fp.belt);
    final gradeLabel = getGradeLabel(sport, fp.belt).toUpperCase();
    final onBelt = beltColor.computeLuminance() > 0.6 ? _T.ink : Colors.white;
    final parts = fp.name.trim().split(RegExp(r'\s+'));
    final initials = parts.isEmpty || parts.first.isEmpty
        ? '?'
        : (parts.length == 1
            ? parts.first[0].toUpperCase()
            : (parts.first[0] + parts.last[0]).toUpperCase());
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.hair),
      ),
      child: Column(
        children: [
          // Belt-ring avatar — same pattern as _ProfileHeader.
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: beltColor, width: 2.5),
            ),
            child: AppCachedAvatar(
              imageUrl: fp.photoUrl,
              radius: 35,
              backgroundColor: beltColor,
              foregroundColor: onBelt,
              child: Text(
                initials,
                style: TextStyle(
                  color: onBelt,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(fp.name.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _T.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(
            fp.academyName != null && fp.academyName!.isNotEmpty
                ? '$gradeLabel · ${fp.academyName}'
                : gradeLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: _T.smoke,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _showcaseStat('${fp.currentStreak}', 'SEMANAS'),
              _statDivider(),
              _showcaseStat('${fp.recordStreak}', 'RECORDE'),
              _statDivider(),
              _showcaseStat('${fp.totalTrainings}', 'TREINOS'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _showcaseStat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: _T.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: _T.smoke,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
          ],
        ),
      );

  Widget _statDivider() =>
      Container(width: 1, height: 28, color: _T.hair);

  Widget _buildMessage({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppTheme.textDisabled),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================
// Header
// ============================================
class _ProfileHeader extends ConsumerWidget {
  final Student student;
  final int medalCount;

  /// Vitrine materializada (espelho). Quando presente, o cartel de stats vira
  /// STREAK · RECORDE · TREINOS (o "número de KOs" do lutador). Sem ela, mantém
  /// o cartel clássico TREINOS · MEDALHAS.
  final FighterProfile? showcase;

  const _ProfileHeader({
    required this.student,
    required this.medalCount,
    this.showcase,
  });

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sport = student.getPrimarySport();
    final grade = student.getGrade(sport);
    final primaryDef = getSport(sport);
    final primaryIsGraded = primaryDef.gradeSystem != GradeSystem.none;
    final age = student.age;
    final beltColor = grade != null
        ? AppTheme.getBeltColor(grade.currentGrade)
        : _T.ink;
    final muaythaiVariant =
        ref.watch(academySettingsProvider).valueOrNull?.muaythaiGradeSystem;

    // Esportes SECUNDÁRIOS (todos menos o principal), na ordem declarada.
    // O espelho SAFE já projeta sports/primarySport/sportData, então o
    // visitante tem o dado — o header só passa a consumi-lo.
    final secondarySports =
        student.getSports().where((s) => s != sport).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        children: [
          // Identity card — avatar + name + faixa
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _T.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _T.hair),
            ),
            child: Column(
              children: [
                Hero(
                  tag: 'profile-avatar-${student.id}',
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: beltColor, width: 2.5),
                    ),
                    child: AppCachedAvatar(
                      imageUrl: student.photoUrl,
                      radius: 40,
                      backgroundColor: _T.bone,
                      foregroundColor: _T.ink,
                      child: Text(
                        _initials(student.fullName),
                        style: const TextStyle(
                          color: _T.ink,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        student.displayName.toUpperCase(),
                        style: const TextStyle(
                          color: _T.ink,
                          fontSize: 21,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!student.isProfilePublic) ...[
                      const SizedBox(width: 6),
                      const Icon(LucideIcons.lock, size: 15, color: _T.ash),
                    ],
                  ],
                ),
                if (age != null) ...[
                  const SizedBox(height: 4),
                  Text('$age ANOS', style: _eyebrow(_T.smoke, 11)),
                ],
                const SizedBox(height: 14),
                // Esporte PRINCIPAL em destaque. Esportes graduados mostram o
                // AnimatedBelt grande (morph tocado uma vez ao abrir, na escada
                // de cor do próprio esporte). Esportes presence-only
                // (boxe/MMA/musculação, GradeSystem.none) não têm faixa: em vez
                // de sumir o bloco, renderiza um chip de modalidade.
                if (primaryIsGraded) ...[
                  AnimatedBelt(
                    belt: grade?.currentGrade ?? 'white',
                    stripes: grade?.currentStripes ?? 0,
                    sportId: sport,
                    muaythaiVariant: muaythaiVariant,
                    size: BeltSize.large,
                    highlight: true,
                  ),
                  if (sport != SportId.bjj) ...[
                    const SizedBox(height: 8),
                    GradeBadge(
                      sportId: sport,
                      grade: grade?.currentGrade ?? 'white',
                      stripes: grade?.currentStripes ?? 0,
                    ),
                  ],
                ] else
                  _ModalityChip(sport: sport),
                // Strip compacto de mini-belts dos esportes secundários.
                if (secondarySports.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _SecondarySportsStrip(
                    student: student,
                    sports: secondarySports,
                    muaythaiVariant: muaythaiVariant,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Stats — fighter instrument style. Com vitrine: STREAK (acento
          // sangue) · RECORDE · TREINOS. Sem: TREINOS · MEDALHAS (clássico).
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: _T.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _T.hair),
            ),
            child: showcase != null
                ? Row(
                    children: [
                      Expanded(
                        child: _StatItem(
                          value: showcase!.currentStreak,
                          label: 'SEMANAS',
                          accent: true,
                        ),
                      ),
                      Container(width: 1, height: 40, color: _T.hair),
                      Expanded(
                        child: _StatItem(
                          value: showcase!.recordStreak,
                          label: 'RECORDE',
                        ),
                      ),
                      Container(width: 1, height: 40, color: _T.hair),
                      Expanded(
                        child: _StatItem(
                          value: showcase!.totalTrainings,
                          label: 'TREINOS',
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _StatItem(
                          value: student.totalAttendanceCount,
                          label: 'TREINOS',
                        ),
                      ),
                      Container(width: 1, height: 40, color: _T.hair),
                      Expanded(
                        child: _StatItem(value: medalCount, label: 'MEDALHAS'),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final num value;
  final String label;
  final bool accent;

  const _StatItem({
    required this.value,
    required this.label,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedCountUp(
          value: value,
          style: TextStyle(
            color: accent ? _T.blood : _T.ink,
            fontSize: 30,
            height: 1.0,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            fontFeatures: _T.tab,
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: _eyebrow(_T.smoke, 10)),
      ],
    );
  }
}

/// Chip de modalidade para o esporte PRINCIPAL quando ele é presence-only
/// (GradeSystem.none — boxe/MMA/musculação): não há escada de faixa, então em
/// vez de sumir o bloco de graduação mostramos só o nome do esporte. Espelha o
/// `_SportGrade`/`GradeSystem.none` do perfil próprio.
class _ModalityChip extends StatelessWidget {
  final SportId sport;

  const _ModalityChip({required this.sport});

  @override
  Widget build(BuildContext context) {
    final definition = getSport(sport);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _T.bone,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _T.hair),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(definition.icon, size: 16, color: _T.smoke),
          const SizedBox(width: 8),
          Text(definition.label.toUpperCase(), style: _eyebrow(_T.ink, 12)),
        ],
      ),
    );
  }
}

/// Strip compacto dos esportes SECUNDÁRIOS, abaixo do herói do principal. Cada
/// esporte graduado vira um mini-belt (AnimatedBelt small na escada do próprio
/// esporte); presence-only vira ícone de modalidade. Lê `getGrade(sport)` do
/// espelho SAFE (sportData já projetado). Read-only.
class _SecondarySportsStrip extends StatelessWidget {
  final Student student;
  final List<SportId> sports;
  final String? muaythaiVariant;

  const _SecondarySportsStrip({
    required this.student,
    required this.sports,
    required this.muaythaiVariant,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Container(height: 1, color: _T.hair)),
            const SizedBox(width: 10),
            Text('TAMBEM TREINA', style: _eyebrow(_T.ash, 10)),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: _T.hair)),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final s in sports)
              _SecondarySportTile(
                sport: s,
                grade: student.getGrade(s),
                muaythaiVariant: muaythaiVariant,
              ),
          ],
        ),
      ],
    );
  }
}

class _SecondarySportTile extends StatelessWidget {
  final SportId sport;
  final ({String currentGrade, int currentStripes})? grade;
  final String? muaythaiVariant;

  const _SecondarySportTile({
    required this.sport,
    required this.grade,
    required this.muaythaiVariant,
  });

  @override
  Widget build(BuildContext context) {
    final def = getSport(sport);
    final isGraded = def.gradeSystem != GradeSystem.none;
    final gradeId = grade?.currentGrade ?? 'white';
    final stripes = grade?.currentStripes ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _T.bone,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _T.hair),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(def.labelShort.toUpperCase(), style: _eyebrow(_T.smoke, 9.5)),
          const SizedBox(height: 8),
          if (isGraded)
            AnimatedBelt(
              belt: gradeId,
              stripes: stripes,
              sportId: sport,
              muaythaiVariant: muaythaiVariant,
              size: BeltSize.small,
              highlight: false,
            )
          else
            Icon(def.icon, size: 20, color: _T.ink),
          if (isGraded) ...[
            const SizedBox(height: 6),
            Text(
              getGradeLabel(sport, gradeId).toUpperCase(),
              style: _eyebrow(_T.ash, 9),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================
// Timeline tab — achievements grouped by year (newest first)
// ============================================
class _TimelineTab extends StatelessWidget {
  final List<Achievement> achievements;

  const _TimelineTab({required this.achievements});

  @override
  Widget build(BuildContext context) {
    if (achievements.isEmpty) {
      return const _EmptyState(
        icon: LucideIcons.clock,
        message: 'Sem registros ainda',
      );
    }

    // Group by year, newest year first.
    final byYear = <int, List<Achievement>>{};
    for (final a in achievements) {
      byYear.putIfAbsent(a.year, () => []).add(a);
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemCount: years.length,
      itemBuilder: (context, index) {
        final year = years[index];
        final items = byYear[year]!
          ..sort((a, b) => b.date.compareTo(a.date));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 8, bottom: 12),
              child: Row(
                children: [
                  Container(width: 14, height: 2, color: _T.blood),
                  const SizedBox(width: 8),
                  Text(
                    year.toString(),
                    style: const TextStyle(
                      color: _T.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      fontFeatures: _T.tab,
                    ),
                  ),
                ],
              ),
            ),
            ...items.map((a) => _AchievementTile(achievement: a)),
          ],
        ).entrance(index: index);
      },
    );
  }
}

/// Achievement tile reproducing the timeline_screen.dart visual language:
/// a coloured icon circle, title, optional description, a belt indicator on
/// graduations (with sport badge) or a position badge on competitions.
class _AchievementTile extends StatelessWidget {
  final Achievement achievement;

  const _AchievementTile({required this.achievement});

  SportId get _sport => achievement.sport != null
      ? SportId.fromString(achievement.sport!)
      : SportId.bjj;

  Color _beltColor(String belt) {
    final c = getGradeColor(_sport, belt);
    return c.computeLuminance() > 0.85 ? const Color(0xFF9CA3AF) : c;
  }

  // Fighter palette: ink-on-bone with a single blood accent. Graduations keep
  // the sacred belt color; everything else stays ink (with blood reserved for
  // competition/streak highlights). No medal gold/orange, no rainbow.
  ({IconData icon, Color color, Color bg}) _ink(IconData icon) =>
      (icon: icon, color: _T.ink, bg: _T.bone);
  ({IconData icon, Color color, Color bg}) _blood(IconData icon) =>
      (icon: icon, color: _T.blood, bg: _T.blood.withValues(alpha: 0.10));

  ({IconData icon, Color color, Color bg}) get _config {
    switch (achievement.type) {
      case AchievementType.graduation:
        final c = _beltColor(achievement.toBelt ?? 'white');
        return (
          icon: LucideIcons.award,
          color: c,
          bg: c.withValues(alpha: 0.15),
        );
      case AchievementType.stripe:
        return _ink(LucideIcons.star);
      case AchievementType.competition:
        return _blood(LucideIcons.trophy);
      case AchievementType.milestone:
        return _ink(LucideIcons.target);
      case AchievementType.attendanceStreak:
        return _blood(LucideIcons.flame);
      case AchievementType.rankingPosition:
        return _ink(LucideIcons.trophy);
      case AchievementType.trainingPr:
        return _ink(LucideIcons.trendingUp);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final isGraduation = achievement.type == AchievementType.graduation;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: config.bg,
              shape: BoxShape.circle,
              border: Border.all(color: config.color, width: 2.5),
            ),
            child: Icon(config.icon, size: 20, color: config.color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _T.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _T.hair),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          achievement.title,
                          style: const TextStyle(
                            color: _T.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      // Sport badge on graduation entries (when the
                      // achievement exposes a sport).
                      if (isGraduation && achievement.sport != null)
                        _SportChip(sport: _sport),
                    ],
                  ),
                  if (achievement.description != null &&
                      achievement.description!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      achievement.description!,
                      style: const TextStyle(
                        color: _T.smoke,
                        fontSize: 13,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  if (isGraduation && achievement.toBelt != null) ...[
                    const SizedBox(height: 12),
                    _BeltIndicator(
                      belt: achievement.toBelt!,
                      sport: _sport,
                    ),
                  ],
                  if (achievement.type == AchievementType.competition &&
                      achievement.position != null) ...[
                    const SizedBox(height: 12),
                    _PositionBadge(position: achievement.position!.name),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.calendar,
                        size: 13,
                        color: _T.ash,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat("d 'de' MMMM 'de' yyyy", 'pt_BR')
                            .format(achievement.date),
                        style: const TextStyle(
                          color: _T.smoke,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SportChip extends StatelessWidget {
  final SportId sport;

  const _SportChip({required this.sport});

  @override
  Widget build(BuildContext context) {
    final label = sports[sport]?.labelShort ?? sport.value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _T.bone,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _T.hair),
      ),
      child: Text(label.toUpperCase(), style: _eyebrow(_T.ink, 10)),
    );
  }
}

/// Selo "AUTO" para marcos AUTO-DECLARADOS (source 'auto') — distingue da
/// graduação/competição VERIFICADA pela academia (sem selo = autoridade). Estilo
/// fighter: contorno discreto em tinta cinza, all-caps, sem cor de medalha.
class _AutoBadge extends StatelessWidget {
  const _AutoBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _T.bone,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _T.hair),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.userCheck, size: 10, color: _T.ash),
          const SizedBox(width: 4),
          Text('AUTO', style: _eyebrow(_T.ash, 9)),
        ],
      ),
    );
  }
}

class _BeltIndicator extends StatelessWidget {
  final String belt;
  final SportId sport;

  const _BeltIndicator({required this.belt, required this.sport});

  @override
  Widget build(BuildContext context) {
    final c = getGradeColor(sport, belt);
    final beltColor =
        c.computeLuminance() > 0.85 ? const Color(0xFF9CA3AF) : c;
    final label = getGradeLabel(sport, belt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: beltColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: beltColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 8,
            decoration: BoxDecoration(
              color: beltColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Faixa $label',
            style: AppTheme.bodySmall.copyWith(
              fontWeight: FontWeight.w600,
              color: beltColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionBadge extends StatelessWidget {
  final String position;

  const _PositionBadge({required this.position});

  @override
  Widget build(BuildContext context) {
    final String label;
    final IconData icon;
    switch (position) {
      case 'gold':
        label = 'Ouro';
        icon = LucideIcons.medal;
        break;
      case 'silver':
        label = 'Prata';
        icon = LucideIcons.medal;
        break;
      case 'bronze':
        label = 'Bronze';
        icon = LucideIcons.medal;
        break;
      default:
        label = 'Participante';
        icon = LucideIcons.award;
    }
    // Podium is the highlight → blood accent; participation stays neutral ink.
    final isPodium = position == 'gold' ||
        position == 'silver' ||
        position == 'bronze';
    final color = isPodium ? _T.blood : _T.ink;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label.toUpperCase(), style: _eyebrow(color, 11)),
        ],
      ),
    );
  }
}

// ============================================
// Competicoes tab
// ============================================
class _CompetitionsTab extends StatelessWidget {
  final List<CompetitionResult> results;

  const _CompetitionsTab({required this.results});

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const _EmptyState(
        icon: LucideIcons.trophy,
        message: 'Sem competicoes registradas',
      );
    }

    final sorted = [...results]..sort((a, b) => b.date.compareTo(a.date));

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemCount: sorted.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _ResultTile(result: sorted[index]).entrance(index: index),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final CompetitionResult result;

  const _ResultTile({required this.result});

  ({IconData icon, Color color, String label}) get _medal {
    switch (result.position) {
      case 'gold':
        return (icon: LucideIcons.medal, color: _T.blood, label: 'OURO');
      case 'silver':
        return (icon: LucideIcons.medal, color: _T.blood, label: 'PRATA');
      case 'bronze':
        return (icon: LucideIcons.medal, color: _T.blood, label: 'BRONZE');
      default:
        return (icon: LucideIcons.award, color: _T.ink, label: 'PARTICIPACAO');
    }
  }

  @override
  Widget build(BuildContext context) {
    final medal = _medal;
    final details = [
      result.beltCategory,
      result.weightCategory,
      result.modality,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' • ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _T.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _T.hair),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: medal.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: medal.color.withValues(alpha: 0.25)),
            ),
            child: Icon(medal.icon, size: 22, color: medal.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(medal.label, style: _eyebrow(medal.color, 10)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  result.competitionName,
                  style: const TextStyle(
                    color: _T.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    details,
                    style: const TextStyle(
                      color: _T.smoke,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  DateFormat("d 'de' MMM 'de' yyyy", 'pt_BR')
                      .format(result.date),
                  style: const TextStyle(
                    color: _T.ash,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// VITRINE — Graduacoes (esforco por bloco)
// ============================================
/// Timeline de graduacoes materializada do espelho. Cada marco (grau OU faixa)
/// carrega o "training block" do Strava colado: NN TREINOS · MM MESES ATE AQUI
/// (delta ja computado pelo dono). Cor so no indicador da faixa real; numeros
/// em tinta neutra.
class _GraduationsTab extends StatelessWidget {
  final List<FighterGraduation> graduations;

  const _GraduationsTab({required this.graduations});

  @override
  Widget build(BuildContext context) {
    if (graduations.isEmpty) {
      return const _EmptyState(
        icon: LucideIcons.award,
        message: 'Sem graduacoes ainda',
      );
    }

    // Ja vem desc (mais recente primeiro) do espelho.
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemCount: graduations.length,
      itemBuilder: (context, index) =>
          _GraduationMarkTile(grad: graduations[index]).entrance(index: index),
    );
  }
}

class _GraduationMarkTile extends StatelessWidget {
  final FighterGraduation grad;

  const _GraduationMarkTile({required this.grad});

  SportId get _sport => SportId.fromString(grad.sport);

  Color get _beltColor {
    final c = getGradeColor(_sport, grad.belt);
    return c.computeLuminance() > 0.85 ? const Color(0xFF9CA3AF) : c;
  }

  String get _title {
    final label = getGradeLabel(_sport, grad.belt).toUpperCase();
    if (grad.isBeltChange) return 'FAIXA $label';
    if (grad.stripes > 0) return '${grad.stripes}º GRAU $label';
    return label;
  }

  /// Linha de esforco. Trata legado: quando o delta de presencas e <= 0 (docs
  /// antigos sem `totalClasses`), omite a contagem e mostra so o tempo.
  String get _effort {
    final unit = grad.weighted ? 'PONTOS' : 'TREINOS';
    final mLabel = grad.monthsToReach == 1 ? 'MES' : 'MESES';
    final tReach = grad.trainingsToReach;
    if (tReach != null && tReach > 0) {
      return '$tReach $unit · ${grad.monthsToReach} $mLabel ATE AQUI';
    }
    return '${grad.monthsToReach} $mLabel ATE AQUI';
  }

  @override
  Widget build(BuildContext context) {
    final beltColor = _beltColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: beltColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: beltColor, width: 2.5),
            ),
            child: Icon(LucideIcons.award, size: 20, color: beltColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _T.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _T.hair),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _title,
                          style: const TextStyle(
                            color: _T.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (grad.source == 'auto') ...[
                        const _AutoBadge(),
                        const SizedBox(width: 6),
                      ],
                      _SportChip(sport: _sport),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Barra na cor real da faixa (unico uso de cor de faixa).
                  Container(
                    width: 28,
                    height: 8,
                    decoration: BoxDecoration(
                      color: beltColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // "Training block" — esforco do bloco, em tinta neutra.
                  Text(_effort, style: _eyebrow(_T.smoke, 11)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.calendar,
                        size: 13,
                        color: _T.ash,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat("d 'de' MMMM 'de' yyyy", 'pt_BR')
                            .format(grad.date),
                        style: const TextStyle(
                          color: _T.smoke,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// VITRINE — Competicoes (cartel + estrada entre marcos)
// ============================================
/// Cartel estilo BoxRec (OURO/PRATA/BRONZE tabular) + lista desc com a "estrada"
/// entre competicoes: DESDE A ULTIMA: N TREINOS · M MESES · +K GRAUS. Tudo lido
/// do espelho materializado — zero attendance privada.
class _CompetitionMarksTab extends StatelessWidget {
  final List<FighterCompetitionMark> marks;
  final MedalCount medals;

  const _CompetitionMarksTab({required this.marks, required this.medals});

  @override
  Widget build(BuildContext context) {
    if (marks.isEmpty) {
      return const _EmptyState(
        icon: LucideIcons.trophy,
        message: 'Sem competicoes registradas',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemCount: marks.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _MedalCartel(medals: medals).fadeInQuick();
        }
        final i = index - 1;
        return _CompetitionMarkTile(
          mark: marks[i],
          // Ultima posicao da lista desc = a competicao mais antiga = estreia.
          isDebut: i == marks.length - 1,
        ).entrance(index: i);
      },
    );
  }
}

class _MedalCartel extends StatelessWidget {
  final MedalCount medals;

  const _MedalCartel({required this.medals});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: _T.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.hair),
      ),
      child: Row(
        children: [
          Expanded(child: _CartelItem(value: medals.gold, label: 'OURO')),
          Container(width: 1, height: 40, color: _T.hair),
          Expanded(child: _CartelItem(value: medals.silver, label: 'PRATA')),
          Container(width: 1, height: 40, color: _T.hair),
          Expanded(child: _CartelItem(value: medals.bronze, label: 'BRONZE')),
        ],
      ),
    );
  }
}

class _CartelItem extends StatelessWidget {
  final int value;
  final String label;

  const _CartelItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.medal, size: 14, color: _T.blood),
            const SizedBox(width: 6),
            AnimatedCountUp(
              value: value,
              style: const TextStyle(
                color: _T.ink,
                fontSize: 26,
                height: 1.0,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                fontFeatures: _T.tab,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(label, style: _eyebrow(_T.smoke, 10)),
      ],
    );
  }
}

class _CompetitionMarkTile extends StatelessWidget {
  final FighterCompetitionMark mark;
  final bool isDebut;

  const _CompetitionMarkTile({required this.mark, required this.isDebut});

  ({IconData icon, Color color, String label}) get _medal {
    switch (mark.position) {
      case 'gold':
        return (icon: LucideIcons.medal, color: _T.blood, label: 'OURO');
      case 'silver':
        return (icon: LucideIcons.medal, color: _T.blood, label: 'PRATA');
      case 'bronze':
        return (icon: LucideIcons.medal, color: _T.blood, label: 'BRONZE');
      default:
        return (icon: LucideIcons.award, color: _T.ink, label: 'PARTICIPACAO');
    }
  }

  /// A "estrada pro campeonato": evolucao acumulada desde a comp anterior. Na
  /// estreia, vira o totalizador da caminhada ate a 1a competicao.
  String get _road {
    final mLabel = mark.monthsSincePrev == 1 ? 'MES' : 'MESES';
    if (isDebut) {
      final cum = mark.cumulativeTrainings;
      return cum != null
          ? 'ESTREIA: $cum TREINOS · ${mark.monthsSincePrev} $mLabel DE CAMINHADA'
          : 'ESTREIA: ${mark.monthsSincePrev} $mLabel DE CAMINHADA';
    }
    final since = mark.trainingsSincePrev;
    final parts = <String>[
      if (since != null) '$since TREINOS',
      '${mark.monthsSincePrev} $mLabel',
    ];
    if (mark.gradesSincePrev > 0) {
      final gLabel = mark.gradesSincePrev == 1 ? 'GRAU' : 'GRAUS';
      parts.add('+${mark.gradesSincePrev} $gLabel');
    }
    return 'DESDE A ULTIMA: ${parts.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) {
    final medal = _medal;
    final details = [
      mark.beltCategory,
      mark.weightCategory,
      mark.modality,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' • ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _T.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _T.hair),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: medal.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: medal.color.withValues(alpha: 0.25)),
                  ),
                  child: Icon(medal.icon, size: 22, color: medal.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(medal.label, style: _eyebrow(medal.color, 10)),
                          if (mark.source == 'auto') ...[
                            const SizedBox(width: 8),
                            const _AutoBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mark.name,
                        style: const TextStyle(
                          color: _T.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          details,
                          style: const TextStyle(
                            color: _T.smoke,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        DateFormat("d 'de' MMM 'de' yyyy", 'pt_BR')
                            .format(mark.date),
                        style: const TextStyle(
                          color: _T.ash,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // A estrada — acento sangue, numeros tabulares.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: _T.blood.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _road,
                style: const TextStyle(
                  color: _T.blood,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  fontFeatures: _T.tab,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Fotos tab — 2-column grid, reuses PhotoCard + fullscreen viewer
// ============================================
class _PhotosTab extends StatelessWidget {
  final List<CompetitionPhoto> photos;

  const _PhotosTab({required this.photos});

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return const _EmptyState(
        icon: LucideIcons.image,
        message: 'Nenhuma foto',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        return PhotoCard(
          photo: photo,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PhotoFullscreenViewer(
                  photos: photos,
                  initialIndex: index,
                ),
              ),
            );
          },
        ).entrance(index: index);
      },
    );
  }
}

// ============================================
// Shared empty state
// ============================================
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return PolishedEmptyState(icon: icon, title: message);
  }
}
