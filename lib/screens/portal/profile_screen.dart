import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/feedback_utils.dart';
import '../../core/formatters.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../models/user.dart';
import '../../providers/providers.dart';
import '../../services/firebase_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/common/animated_belt.dart';
import '../../widgets/common/belt_badge.dart';
import '../../widgets/common/delete_account_helper.dart';
import '../../widgets/common/profile_photo_picker.dart';
import '../../widgets/polish/polish.dart';
import '../../widgets/skeletons/skeletons.dart';

// =============================================================================
// Tokens anti-slop (consistentes com o hub do Lutador / fighter_theme).
// Bone + cards brancos + tinta ink + UM acento vermelho. A COR DA FAIXA
// (AppTheme.getBeltColor) só representa faixa real — nunca cromática de UI.
// =============================================================================
class _T {
  _T._();
  static const bone = Color(0xFFF4F3EF);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0A0A0A);
  static const blood = Color(0xFFE0301E);
  static const smoke = Color(0xFF6E6E68);
  static const ash = Color(0xFF9A9A93);
  static const hair = Color(0x14000000); // 8% ink hairline
  static const List<FontFeature> tab = [FontFeature.tabularFigures()];
}

TextStyle _eyebrow(Color c, double s) => TextStyle(
      color: c,
      fontSize: s,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.4,
    );

/// Profile Screen - Redesigned in the Fighter style (bone canvas, white cards,
/// ink/red, tabular numerals). Keeps all existing functionality.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) {
          return _buildEmptyState();
        }

        // Total de treinos = presenças no sistema (chamada + autocheck-in) +
        // a base histórica lançada manualmente pela academia
        // (initialAttendanceCount). É o mesmo número exibido no perfil público
        // (student.totalAttendanceCount); a contagem antiga ignorava a base
        // histórica, então treinos anteriores ao sistema não apareciam.
        final totalTreinos = student.totalAttendanceCount;
        final plansAsync = ref.watch(studentPlansProvider(student.id));
        final startDate = student.jiujitsuStartDate ?? student.startDate;
        final trainingTime = _formatTrainingTime(startDate);

        return Container(
          color: _T.bone,
          child: RefreshIndicator(
            color: _T.blood,
            backgroundColor: _T.card,
            onRefresh: () async {
              HapticFeedback.mediumImpact();
              ref.invalidate(currentStudentProvider);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Identity header — avatar (editable) + name + faixa + status
                  _HeroHeader(student: student).fadeInQuick(),

                  const SizedBox(height: 14),

                  // Graduation showcase — animated belt(s) per sport
                  _GraduationCard(student: student),

                  const SizedBox(height: 14),

                  // Stats — presenças + tempo de treino
                  _StatsRow(
                    totalTreinos: totalTreinos,
                    trainingTime: trainingTime,
                  ),

                  const SizedBox(height: 14),

                  // Quick Actions
                  _QuickActions(
                    onTimeline: () => context.go('/portal/linha-do-tempo'),
                  ),

                  const SizedBox(height: 26),

                  // Academy-managed section
                  _SectionHeader(title: 'GERENCIADO PELA ACADEMIA'),
                  const SizedBox(height: 10),
                  _InfoCard(
                    children: [
                      _InfoRow(
                        label: 'Inicio',
                        value:
                            DateFormat('dd/MM/yyyy').format(student.startDate),
                      ),
                      _InfoRow(
                        label: 'Status',
                        value: student.status.label,
                        valueColor:
                            AppTheme.getStatusColor(student.status.value),
                      ),
                      if ((plansAsync.valueOrNull ?? []).isNotEmpty)
                        _InfoRow(
                          label:
                              'Plano${(plansAsync.valueOrNull ?? []).length > 1 ? 's' : ''}',
                          value: (plansAsync.valueOrNull ?? [])
                              .map((p) => p.name)
                              .join(', '),
                        ),
                    ],
                  ),

                  const SizedBox(height: 26),

                  // My Data section
                  _SectionHeader(title: 'MEUS DADOS'),
                  const SizedBox(height: 10),
                  _InfoCard(
                    children: [
                      _DataTile(
                        icon: LucideIcons.dumbbell,
                        title: 'Modalidades',
                        subtitle: _getSportsSummary(student),
                        isSubtitleEmpty: false,
                        onTap: () =>
                            context.go('/portal/minhas-modalidades'),
                      ),
                      _DataTile(
                        icon: LucideIcons.user,
                        title: 'Dados Pessoais',
                        subtitle: _getPersonalDataSummary(student),
                        isSubtitleEmpty: _isPersonalDataEmpty(student),
                        onTap: () =>
                            _showEditPersonalDataSheet(context, ref, student),
                      ),
                      _DataTile(
                        icon: LucideIcons.mapPin,
                        title: 'Endereco',
                        subtitle: _getAddressSummary(student),
                        isSubtitleEmpty: student.address == null ||
                            !_hasAddress(student.address!),
                        onTap: () =>
                            _showEditAddressSheet(context, ref, student),
                      ),
                      _DataTile(
                        icon: LucideIcons.heartPulse,
                        title: 'Saude e Emergencia',
                        subtitle: _getHealthEmergencySummary(student),
                        isSubtitleEmpty: _isHealthDataEmpty(student) &&
                            student.emergencyContact == null,
                        onTap: () => _showEditHealthAndEmergencySheet(
                          context,
                          ref,
                          student,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 26),

                  // Preferences
                  _SectionHeader(title: 'PREFERENCIAS'),
                  const SizedBox(height: 10),
                  _PrivacyToggle(
                    value: student.isProfilePublic,
                    onChanged: (value) =>
                        _updatePrivacy(context, ref, student, value),
                  ),

                  const SizedBox(height: 26),

                  // Academies
                  _AcademiesSection(),

                  const SizedBox(height: 26),

                  // Account
                  _AccountSection(),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        );
      },
      loading: () => _buildLoadingState(),
      error: (_, _) => _buildEmptyState(),
    );
  }

  // ============================================
  // HELPERS
  // ============================================

  String _formatTrainingTime(DateTime startDate) {
    final now = DateTime.now();
    final difference = now.difference(startDate);
    final months = difference.inDays ~/ 30;

    if (months >= 12) {
      final years = months ~/ 12;
      final remainingMonths = months % 12;
      if (remainingMonths > 0) {
        return '${years}a ${remainingMonths}m';
      }
      return '$years ano${years > 1 ? 's' : ''}';
    } else if (months > 0) {
      return '$months mes${months > 1 ? 'es' : ''}';
    } else {
      final days = difference.inDays;
      return '$days dia${days != 1 ? 's' : ''}';
    }
  }

  String _getSportsSummary(Student student) {
    final sports = student.getSports();
    final names = sports.map((s) => getSport(s).labelShort).join(' · ');
    final count = sports.length == 1 ? '1 modalidade' : '${sports.length} modalidades';
    return '$count · $names';
  }

  String _getPersonalDataSummary(Student student) {
    final parts = <String>[];
    if (student.phone != null && student.phone!.isNotEmpty) {
      parts.add(formatPhone(student.phone));
    }
    if (student.email != null && student.email!.isNotEmpty) {
      parts.add(student.email!);
    }
    if (student.nickname != null && student.nickname!.isNotEmpty) {
      parts.add(student.nickname!);
    }
    if (parts.isEmpty) return 'Nenhum dado';
    return parts.join(', ');
  }

  String _getAddressSummary(Student student) {
    if (student.address == null || !_hasAddress(student.address!)) {
      return 'Nenhum endereco cadastrado';
    }
    final city = student.address!.city;
    final state = student.address!.state;
    if (city.isNotEmpty && state.isNotEmpty) {
      return '$city - $state';
    }
    if (city.isNotEmpty) return city;
    return student.address!.street;
  }

  String _getHealthEmergencySummary(Student student) {
    final parts = <String>[];
    if (student.bloodType != null && student.bloodType!.isNotEmpty) {
      parts.add('Tipo ${student.bloodType}');
    }
    if (student.emergencyContact != null &&
        student.emergencyContact!.name.isNotEmpty) {
      parts.add(student.emergencyContact!.name);
    }
    if (parts.isEmpty) return 'Nenhum dado';
    return parts.join(', ');
  }

  bool _isPersonalDataEmpty(Student student) {
    return (student.nickname == null || student.nickname!.isEmpty) &&
        student.birthDate == null &&
        (student.phone == null || student.phone!.isEmpty) &&
        (student.email == null || student.email!.isEmpty) &&
        (student.cpf == null || student.cpf!.isEmpty) &&
        (student.rg == null || student.rg!.isEmpty) &&
        student.weight == null;
  }

  bool _isHealthDataEmpty(Student student) {
    return (student.bloodType == null || student.bloodType!.isEmpty) &&
        (student.allergies == null || student.allergies!.isEmpty) &&
        (student.healthNotes == null || student.healthNotes!.isEmpty);
  }

  bool _hasAddress(Address address) {
    return address.street.isNotEmpty || address.city.isNotEmpty;
  }

  // ============================================
  // ACTIONS
  // ============================================

  Future<void> _updatePrivacy(
    BuildContext context,
    WidgetRef ref,
    Student student,
    bool value,
  ) async {
    try {
      final studentService = ref.read(studentServiceProvider);
      if (studentService == null) return;

      await studentService.update(student.id, {'isProfilePublic': value});
      ref.invalidate(currentStudentProvider);

      if (context.mounted) {
        context.showSuccess(
          value ? 'Perfil agora e publico' : 'Perfil agora e privado',
        );
      }
    } catch (e) {
      if (context.mounted) {
        context.showError('Erro ao atualizar: $e');
      }
    }
  }

  void _showEditPersonalDataSheet(
    BuildContext context,
    WidgetRef ref,
    Student student,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditPersonalDataSheet(
        student: student,
        onSave: (data) async {
          final studentService = ref.read(studentServiceProvider);
          if (studentService == null) return;
          await studentService.update(student.id, data);
          ref.invalidate(currentStudentProvider);
        },
      ),
    );
  }

  void _showEditAddressSheet(
    BuildContext context,
    WidgetRef ref,
    Student student,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditAddressSheet(
        student: student,
        onSave: (data) async {
          final studentService = ref.read(studentServiceProvider);
          if (studentService == null) return;
          await studentService.update(student.id, data);
          ref.invalidate(currentStudentProvider);
        },
      ),
    );
  }

  void _showEditHealthAndEmergencySheet(
    BuildContext context,
    WidgetRef ref,
    Student student,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditHealthAndEmergencySheet(
        student: student,
        onSave: (data) async {
          final studentService = ref.read(studentServiceProvider);
          if (studentService == null) return;
          await studentService.update(student.id, data);
          ref.invalidate(currentStudentProvider);
        },
      ),
    );
  }

  // ============================================
  // LOADING & EMPTY STATES
  // ============================================

  Widget _buildLoadingState() {
    return Container(
      color: _T.bone,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          children: const [
            SizedBox(height: 8),
            // Avatar shimmer
            SkeletonAvatar(size: 72),
            SizedBox(height: 20),
            // Stats shimmer
            SkeletonStats(count: 2, height: 80),
            SizedBox(height: 24),
            // Card shimmer
            SkeletonCard(
              height: 150,
              showAvatar: false,
              padding: EdgeInsets.all(16),
            ),
            SizedBox(height: 12),
            SkeletonCard(height: 80, showAvatar: true),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      color: _T.bone,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 60),
            Center(
              child: Column(
                children: [
                  Icon(LucideIcons.userX, size: 44, color: _T.ash),
                  const SizedBox(height: 14),
                  Text(
                    'PERFIL NAO ENCONTRADO',
                    style: _eyebrow(_T.ink, 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sua conta nao esta vinculada a um aluno',
                    style: const TextStyle(
                      color: _T.smoke,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            // Account section always visible for account deletion
            _AccountSection(),
          ],
        ),
      ),
    );
  }
}

// ============================================
// NEW WIDGETS
// ============================================

/// Identity header — editable avatar + name (ALL-CAPS) + faixa + status pill.
/// Left-aligned credential, consistent with the Lutador hub header.
class _HeroHeader extends ConsumerWidget {
  final Student student;

  const _HeroHeader({required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fall back to the authoritative academy context when the selected-academy
    // provider hasn't settled (null) — otherwise the upload path would be
    // academies//students/... and Storage denies it.
    final academyId =
        ref.watch(selectedAcademyIdProvider) ?? FirebaseService.academyId;

    final primarySport = student.getPrimarySport();
    final grade = student.getGrade(primarySport);
    final belt = grade?.currentGrade ?? student.currentBelt;
    final stripes = grade?.currentStripes ?? student.currentStripes;
    final beltColor = AppTheme.getBeltColor(belt);
    final definition = getSport(primarySport);
    final hasBelt = definition.gradeSystem != GradeSystem.none;

    final name = (student.nickname != null && student.nickname!.isNotEmpty)
        ? student.nickname!
        : student.fullName;
    final gradeLabel = getGradeLabel(primarySport, belt);
    final stripeLabel = stripes > 0
        ? ' · ${stripes == 1 ? '1º grau' : '$stripesº grau'}'
        : '';

    return _WhiteCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Editable avatar — keeps full upload/crop functionality.
          ProfilePhotoPicker(
            academyId: academyId,
            studentId: student.id,
            photoUrl: student.photoUrl,
            fullName: student.fullName,
            currentBelt: student.currentBelt,
            editable: true,
            size: 72.0,
            onPhotoUpdated: () {
              ref.invalidate(currentStudentProvider);
            },
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _T.ink,
                    fontSize: 21,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    if (hasBelt) ...[
                      _MiniBelt(beltColor: beltColor, stripes: stripes),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        hasBelt ? '$gradeLabel$stripeLabel' : definition.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _T.smoke,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Status pill — uses the academy status color (semantic, not a
                // belt color), kept compact and rectangular.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.getStatusBackgroundColor(
                      student.status.value,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    student.status.label.toUpperCase(),
                    style: _eyebrow(
                      AppTheme.getStatusColor(student.status.value),
                      10,
                    ),
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

/// Small belt swatch with a tip block + stripes — mirrors the Lutador hub.
class _MiniBelt extends StatelessWidget {
  const _MiniBelt({required this.beltColor, required this.stripes});
  final Color beltColor;
  final int stripes;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 14,
      decoration: BoxDecoration(
        color: beltColor,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: _T.hair),
      ),
      alignment: Alignment.centerRight,
      child: Container(
        width: 11,
        height: 14,
        decoration: const BoxDecoration(
          color: _T.ink,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(3),
            bottomRight: Radius.circular(3),
          ),
        ),
        child: stripes > 0
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  stripes.clamp(0, 4),
                  (_) => Container(
                    width: 1.4,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 0.6),
                    color: Colors.white,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// Graduation showcase — animated belt(s) per sport in a white card.
class _GraduationCard extends ConsumerWidget {
  final Student student;

  const _GraduationCard({required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve graduation per sport. getGrade returns the per-sport grade;
    // multimodal students show one belt per graded sport. Presence-only sports
    // (GradeSystem.none — boxe/MMA/musculação) have no graduation and render as
    // a plain chip instead of a meaningless "Branca" belt.
    final primarySport = student.getPrimarySport();
    final muaythaiVariant =
        ref.watch(academySettingsProvider).valueOrNull?.muaythaiGradeSystem;

    // Order: primary sport first, then the rest, deduplicated.
    final sportsList = <SportId>[
      primarySport,
      ...student.getSports().where((s) => s != primarySport),
    ];

    return _WhiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(width: 14, height: 2, color: _T.blood),
              const SizedBox(width: 8),
              Text('GRADUACAO', style: _eyebrow(_T.ink, 12)),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < sportsList.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _SportGrade(
              sport: sportsList[i],
              grade: student.getGrade(sportsList[i]),
              muaythaiVariant: muaythaiVariant,
              isPrimary: i == 0,
            ),
          ],
        ],
      ),
    );
  }
}

/// Renders a single sport's graduation in the hero.
///
/// Graded sports (BJJ belts, Muay Thai armbands, …) show the [AnimatedBelt]
/// plus a label naming the grade. Presence-only sports (GradeSystem.none —
/// boxe/MMA/musculação) have no graduation, so we omit the belt entirely and
/// show only a chip with the sport name to avoid a meaningless "Branca" belt.
class _SportGrade extends StatelessWidget {
  final SportId sport;
  final ({String currentGrade, int currentStripes})? grade;
  final String? muaythaiVariant;
  final bool isPrimary;

  const _SportGrade({
    required this.sport,
    required this.grade,
    required this.muaythaiVariant,
    required this.isPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final definition = getSport(sport);

    // Presence-only sports have no belt/grade ladder — render just the name.
    if (definition.gradeSystem == GradeSystem.none) {
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
            Text(
              definition.label.toUpperCase(),
              style: _eyebrow(_T.ink, 12),
            ),
          ],
        ),
      );
    }

    final gradeId = grade?.currentGrade ?? 'white';
    final stripes = grade?.currentStripes ?? 0;

    return Column(
      children: [
        AnimatedBelt(
          belt: gradeId,
          stripes: stripes,
          sportId: sport,
          muaythaiVariant: muaythaiVariant,
          size: isPrimary ? BeltSize.large : BeltSize.small,
          highlight: isPrimary,
        ),
        // Name the grade for every sport except primary BJJ, where the belt
        // color already reads as the grade.
        if (!(isPrimary && sport == SportId.bjj)) ...[
          const SizedBox(height: 8),
          Text(
            isPrimary
                ? getGradeLabel(sport, gradeId).toUpperCase()
                : '${definition.label}: ${getGradeLabel(sport, gradeId)}'
                    .toUpperCase(),
            textAlign: TextAlign.center,
            style: _eyebrow(_T.smoke, isPrimary ? 12 : 11),
          ),
        ],
      ],
    );
  }
}

/// Stats row — presenças (count-up) + tempo de treino, fighter instrument
/// style: big w900 tabular numerals + micro-caps labels.
class _StatsRow extends StatelessWidget {
  final int totalTreinos;
  final String trainingTime;

  const _StatsRow({required this.totalTreinos, required this.trainingTime});

  @override
  Widget build(BuildContext context) {
    return _WhiteCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                AnimatedCountUp(
                  value: totalTreinos,
                  style: const TextStyle(
                    color: _T.ink,
                    fontSize: 30,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    fontFeatures: _T.tab,
                  ),
                ),
                const SizedBox(height: 6),
                Text('PRESENCAS', style: _eyebrow(_T.smoke, 10)),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: _T.hair),
          Expanded(
            child: Column(
              children: [
                Text(
                  trainingTime,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _T.ink,
                    fontSize: 30,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    fontFeatures: _T.tab,
                  ),
                ),
                const SizedBox(height: 6),
                Text('DE TREINO', style: _eyebrow(_T.smoke, 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// White card base — fighter surface: white, radius 16, decided hairline.
class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _T.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.hair),
      ),
      child: child,
    );
  }
}

/// Quick Actions — Timeline chip.
/// Chip 'EDITAR PERFIL' removido: duplicava o tile 'Dados Pessoais' em
/// MEUS DADOS, que já abre _showEditPersonalDataSheet (decisão do dono:
/// sem funções repetidas na mesma tela).
class _QuickActions extends StatelessWidget {
  final VoidCallback onTimeline;

  const _QuickActions({required this.onTimeline});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: _QuickActionChip(
        icon: LucideIcons.history,
        label: 'LINHA DO TEMPO',
        onTap: onTimeline,
        filled: false,
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : _T.ink;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: filled ? _T.ink : _T.card,
          borderRadius: BorderRadius.circular(12),
          border: filled ? null : Border.all(color: _T.hair),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Data Tile — Navigable collapsed tile for "Meus Dados" section
class _DataTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSubtitleEmpty;
  final VoidCallback onTap;

  const _DataTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSubtitleEmpty,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Leading icon
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _T.bone,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _T.hair),
              ),
              child: Icon(icon, size: 18, color: _T.ink),
            ),
            const SizedBox(width: 12),
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _T.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isSubtitleEmpty ? _T.ash : _T.smoke,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Trailing chevron
            const Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: _T.ash,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// KEPT WIDGETS (unchanged)
// ============================================

/// Section Header
class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 14, height: 2, color: _T.blood),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: _eyebrow(_T.ink, 13))),
      ],
    );
  }
}

/// Info Card container
class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final filteredChildren = children.where((c) => c is! SizedBox).toList();

    return Container(
      decoration: BoxDecoration(
        color: _T.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.hair),
      ),
      child: Column(
        children: [
          for (int i = 0; i < filteredChildren.length; i++) ...[
            filteredChildren[i],
            if (i < filteredChildren.length - 1)
              Divider(height: 1, thickness: 1, color: _T.hair),
          ],
        ],
      ),
    );
  }
}

/// Info Row
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label.toUpperCase(),
              style: _eyebrow(_T.smoke, 11),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? _T.ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Privacy Toggle
class _PrivacyToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PrivacyToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _T.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.hair),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _T.bone,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _T.hair),
            ),
            child: Icon(
              value ? LucideIcons.eye : LucideIcons.eyeOff,
              size: 18,
              color: _T.ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Perfil publico',
                  style: TextStyle(
                    color: _T.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Outros alunos podem ver seu perfil',
                  style: TextStyle(
                    color: _T.smoke,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: _T.blood,
            activeTrackColor: _T.blood.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

// ============================================
// EDIT SHEETS
// ============================================

/// Edit Personal Data Sheet
class _EditPersonalDataSheet extends StatefulWidget {
  final Student student;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _EditPersonalDataSheet({required this.student, required this.onSave});

  @override
  State<_EditPersonalDataSheet> createState() => _EditPersonalDataSheetState();
}

class _EditPersonalDataSheetState extends State<_EditPersonalDataSheet> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _cpfController;
  late final TextEditingController _rgController;
  late final TextEditingController _weightController;
  DateTime? _birthDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.student.nickname);
    _phoneController =
        TextEditingController(text: formatPhone(widget.student.phone));
    _emailController = TextEditingController(text: widget.student.email);
    _cpfController =
        TextEditingController(text: formatCpfCnpj(widget.student.cpf));
    _rgController = TextEditingController(text: widget.student.rg);
    _weightController = TextEditingController(
      text: widget.student.weight?.toString(),
    );
    _birthDate = widget.student.birthDate;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _cpfController.dispose();
    _rgController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await widget.onSave({
        'nickname': _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : onlyDigits(_phoneController.text),
        // Email NÃO é persistido aqui: alterá-lo só no doc divergiria do
        // Firebase Auth (login). Campo é somente leitura na UI; a troca de
        // email de login é feita pela recepção/admin.
        'cpf': _cpfController.text.trim().isEmpty
            ? null
            : onlyDigits(_cpfController.text),
        'rg': _rgController.text.trim().isEmpty
            ? null
            : _rgController.text.trim(),
        'weight': _weightController.text.trim().isEmpty
            ? null
            : double.tryParse(_weightController.text.trim()),
        'birthDate': _birthDate,
      });
      if (mounted) {
        context.showSuccess('Dados atualizados!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _EditSheet(
      title: 'Dados Pessoais',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        _SheetTextField(
          label: 'Apelido',
          controller: _nicknameController,
          hint: 'Como gostaria de ser chamado',
        ),
        _SheetDateField(
          label: 'Data de nascimento',
          value: _birthDate,
          onChanged: (d) => setState(() => _birthDate = d),
        ),
        _SheetTextField(
          label: 'Telefone',
          controller: _phoneController,
          hint: '(00) 00000-0000',
          keyboardType: TextInputType.phone,
          inputFormatters: [PhoneInputFormatter()],
        ),
        _SheetTextField(
          label: 'Email',
          controller: _emailController,
          hint: 'seu@email.com',
          keyboardType: TextInputType.emailAddress,
          readOnly: true,
          helperText:
              'Para alterar o email de login, contate a recepção.',
        ),
        _SheetTextField(
          label: 'CPF',
          controller: _cpfController,
          hint: '000.000.000-00',
          keyboardType: TextInputType.number,
          inputFormatters: [CpfCnpjInputFormatter()],
        ),
        _SheetTextField(
          label: 'RG',
          controller: _rgController,
          hint: 'Numero do RG',
        ),
        _SheetTextField(
          label: 'Peso (kg)',
          controller: _weightController,
          hint: 'Ex: 75.5',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
    );
  }
}

/// Edit Address Sheet
class _EditAddressSheet extends StatefulWidget {
  final Student student;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _EditAddressSheet({required this.student, required this.onSave});

  @override
  State<_EditAddressSheet> createState() => _EditAddressSheetState();
}

class _EditAddressSheetState extends State<_EditAddressSheet> {
  late final TextEditingController _zipCodeController;
  late final TextEditingController _streetController;
  late final TextEditingController _numberController;
  late final TextEditingController _complementController;
  late final TextEditingController _neighborhoodController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final address = widget.student.address;
    _zipCodeController = TextEditingController(text: address?.zipCode);
    _streetController = TextEditingController(text: address?.street);
    _numberController = TextEditingController(text: address?.number);
    _complementController = TextEditingController(text: address?.complement);
    _neighborhoodController = TextEditingController(
      text: address?.neighborhood,
    );
    _cityController = TextEditingController(text: address?.city);
    _stateController = TextEditingController(text: address?.state);
  }

  @override
  void dispose() {
    _zipCodeController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final hasData =
          _streetController.text.trim().isNotEmpty ||
          _cityController.text.trim().isNotEmpty;
      await widget.onSave({
        'address': hasData
            ? {
                'zipCode': _zipCodeController.text.trim(),
                'street': _streetController.text.trim(),
                'number': _numberController.text.trim(),
                'complement': _complementController.text.trim().isEmpty
                    ? null
                    : _complementController.text.trim(),
                'neighborhood': _neighborhoodController.text.trim(),
                'city': _cityController.text.trim(),
                'state': _stateController.text.trim(),
              }
            : null,
      });
      if (mounted) {
        context.showSuccess('Endereco atualizado!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _EditSheet(
      title: 'Endereco',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        _SheetTextField(
          label: 'CEP',
          controller: _zipCodeController,
          hint: '00000-000',
          keyboardType: TextInputType.number,
        ),
        _SheetTextField(
          label: 'Rua',
          controller: _streetController,
          hint: 'Nome da rua',
        ),
        _SheetTextField(
          label: 'Numero',
          controller: _numberController,
          hint: '123',
          keyboardType: TextInputType.number,
        ),
        _SheetTextField(
          label: 'Complemento',
          controller: _complementController,
          hint: 'Apto, bloco...',
        ),
        _SheetTextField(
          label: 'Bairro',
          controller: _neighborhoodController,
          hint: 'Nome do bairro',
        ),
        _SheetTextField(
          label: 'Cidade',
          controller: _cityController,
          hint: 'Nome da cidade',
        ),
        _SheetTextField(
          label: 'Estado',
          controller: _stateController,
          hint: 'UF',
        ),
      ],
    );
  }
}

/// Combined Edit Health & Emergency Contact Sheet
class _EditHealthAndEmergencySheet extends StatefulWidget {
  final Student student;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const _EditHealthAndEmergencySheet({
    required this.student,
    required this.onSave,
  });

  @override
  State<_EditHealthAndEmergencySheet> createState() =>
      _EditHealthAndEmergencySheetState();
}

class _EditHealthAndEmergencySheetState
    extends State<_EditHealthAndEmergencySheet> {
  // Health controllers
  late final TextEditingController _bloodTypeController;
  late final TextEditingController _allergiesController;
  late final TextEditingController _healthNotesController;
  // Emergency controllers
  late final TextEditingController _emergencyNameController;
  late final TextEditingController _emergencyPhoneController;
  late final TextEditingController _emergencyRelationshipController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _bloodTypeController = TextEditingController(
      text: widget.student.bloodType,
    );
    _allergiesController = TextEditingController(
      text: widget.student.allergies?.join(', '),
    );
    _healthNotesController = TextEditingController(
      text: widget.student.healthNotes,
    );
    _emergencyNameController = TextEditingController(
      text: widget.student.emergencyContact?.name,
    );
    _emergencyPhoneController = TextEditingController(
      text: formatPhone(widget.student.emergencyContact?.phone),
    );
    _emergencyRelationshipController = TextEditingController(
      text: widget.student.emergencyContact?.relationship,
    );
  }

  @override
  void dispose() {
    _bloodTypeController.dispose();
    _allergiesController.dispose();
    _healthNotesController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _emergencyRelationshipController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final allergiesText = _allergiesController.text.trim();
      final hasEmergencyData =
          _emergencyNameController.text.trim().isNotEmpty ||
          _emergencyPhoneController.text.trim().isNotEmpty;

      await widget.onSave({
        'bloodType': _bloodTypeController.text.trim().isEmpty
            ? null
            : _bloodTypeController.text.trim(),
        'allergies': allergiesText.isEmpty
            ? null
            : allergiesText
                  .split(',')
                  .map((a) => a.trim())
                  .where((a) => a.isNotEmpty)
                  .toList(),
        'healthNotes': _healthNotesController.text.trim().isEmpty
            ? null
            : _healthNotesController.text.trim(),
        'emergencyContact': hasEmergencyData
            ? {
                'name': _emergencyNameController.text.trim(),
                'phone': onlyDigits(_emergencyPhoneController.text),
                'relationship': _emergencyRelationshipController.text.trim(),
              }
            : null,
      });
      if (mounted) {
        context.showSuccess('Dados atualizados!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _EditSheet(
      title: 'Saude e Emergencia',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        // Health section label
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'SAUDE',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        _SheetTextField(
          label: 'Tipo sanguineo',
          controller: _bloodTypeController,
          hint: 'Ex: A+, O-, AB+',
        ),
        _SheetTextField(
          label: 'Alergias',
          controller: _allergiesController,
          hint: 'Separe por virgula',
        ),
        _SheetTextField(
          label: 'Observacoes',
          controller: _healthNotesController,
          hint: 'Lesoes, medicamentos...',
          maxLines: 3,
        ),
        // Emergency section label
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: Text(
            'CONTATO DE EMERGENCIA',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        _SheetTextField(
          label: 'Nome',
          controller: _emergencyNameController,
          hint: 'Nome do contato',
        ),
        _SheetTextField(
          label: 'Telefone',
          controller: _emergencyPhoneController,
          hint: '(00) 00000-0000',
          keyboardType: TextInputType.phone,
          inputFormatters: [PhoneInputFormatter()],
        ),
        _SheetTextField(
          label: 'Parentesco',
          controller: _emergencyRelationshipController,
          hint: 'Ex: Mae, Pai, Conjuge',
        ),
      ],
    );
  }
}

// ============================================
// SHARED SHEET COMPONENTS
// ============================================

/// Base Edit Sheet
class _EditSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool isSaving;
  final VoidCallback onSave;

  const _EditSheet({
    required this.title,
    required this.children,
    required this.isSaving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppTheme.titleLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Form
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
            // Save Button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(top: BorderSide(color: AppTheme.divider)),
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: LoadingButton(
                    isLoading: isSaving,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onSave();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Salvar',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet Text Field
class _SheetTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;
  final String? helperText;

  const _SheetTextField({
    required this.label,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.readOnly = false,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.labelMedium.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            readOnly: readOnly,
            enableInteractiveSelection: !readOnly,
            style: AppTheme.bodyMedium.copyWith(
              color: readOnly ? AppTheme.textSecondary : null,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textDisabled,
              ),
              helperText: helperText,
              helperMaxLines: 2,
              helperStyle: AppTheme.labelSmall.copyWith(
                color: AppTheme.textSecondary,
              ),
              filled: true,
              fillColor: readOnly
                  ? AppTheme.surfaceVariant.withValues(alpha: 0.25)
                  : AppTheme.surfaceVariant.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sheet Date Field
class _SheetDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const _SheetDateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.labelMedium.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    value ??
                    DateTime.now().subtract(const Duration(days: 365 * 20)),
                firstDate: DateTime(1940),
                lastDate: DateTime.now(),
              );
              if (picked != null) onChanged(picked);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value != null
                          ? DateFormat('dd/MM/yyyy').format(value!)
                          : 'Selecionar data',
                      style: AppTheme.bodyMedium.copyWith(
                        color: value != null
                            ? AppTheme.textPrimary
                            : AppTheme.textDisabled,
                      ),
                    ),
                  ),
                  Icon(
                    LucideIcons.calendar,
                    size: 18,
                    color: AppTheme.textSecondary,
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
// ACADEMIES SECTION (Multi-Academy Support)
// ============================================

/// Academies Section - Shows linked academies for multi-academy users
class _AcademiesSection extends ConsumerWidget {
  const _AcademiesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMultiple = ref.watch(hasMultipleAcademiesProvider);
    final academiesAsync = ref.watch(userAcademiesInfoProvider);
    final selectedId = ref.watch(selectedAcademyIdProvider);
    final mapping = ref.watch(userAcademyMappingProvider).valueOrNull;
    final primaryId = mapping?.primaryAcademyId;

    // Only show section if user has academies (show even for single academy)
    return academiesAsync.when(
      data: (academies) {
        if (academies.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sem onEdit: 'GERENCIAR ACADEMIAS' abaixo já é a via única para
            // '/portal/academias' (decisão do dono: sem funções repetidas na mesma tela).
            _SectionHeader(title: 'MINHAS ACADEMIAS'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: _T.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _T.hair),
              ),
              child: Column(
                children: [
                  for (int i = 0; i < academies.length; i++) ...[
                    _AcademyTile(
                      academy: academies[i],
                      isSelected: academies[i].id == selectedId,
                      isPrimary: academies[i].id == primaryId,
                      onTap: hasMultiple
                          ? () => ref
                                .read(selectedAcademyProvider.notifier)
                                .selectAcademy(academies[i].id)
                          : null,
                    ),
                    if (i < academies.length - 1)
                      Divider(height: 1, thickness: 1, color: _T.hair),
                  ],
                ],
              ),
            ),
            if (hasMultiple) ...[
              const SizedBox(height: 12),
              Pressable(
                onTap: () => context.push('/portal/academias'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _T.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _T.hair),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        LucideIcons.settings,
                        size: 14,
                        color: _T.ink,
                      ),
                      const SizedBox(width: 8),
                      Text('GERENCIAR ACADEMIAS', style: _eyebrow(_T.ink, 11)),
                      const SizedBox(width: 4),
                      const Icon(
                        LucideIcons.chevronRight,
                        size: 14,
                        color: _T.ash,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

/// Academy Tile for the academies list
class _AcademyTile extends StatelessWidget {
  final AcademyInfo academy;
  final bool isSelected;
  final bool isPrimary;
  final VoidCallback? onTap;

  const _AcademyTile({
    required this.academy,
    required this.isSelected,
    required this.isPrimary,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Logo
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: academy.logoUrl == null ? _T.ink : null,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: academy.logoUrl != null
                  ? AppCachedImage(
                      imageUrl: academy.logoUrl,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorIcon: _buildDefaultLogo(),
                    )
                  : _buildDefaultLogo(),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          academy.name,
                          style: TextStyle(
                            color: _T.ink,
                            fontSize: 14.5,
                            fontWeight:
                                isSelected ? FontWeight.w800 : FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isPrimary) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _T.ink,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PRINCIPAL',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    academy.role.label,
                    style: const TextStyle(
                      color: _T.smoke,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Selected indicator
            if (isSelected)
              Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: _T.ink,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.check,
                  size: 13,
                  color: Colors.white,
                ),
              )
            else if (onTap != null)
              const Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: _T.ash,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultLogo() {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _T.ink,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          academy.name.isNotEmpty ? academy.name[0].toUpperCase() : 'A',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Account section with delete account option
class _AccountSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: 'CONTA'),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: _T.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _T.hair),
          ),
          child: Column(
            children: [
              // Change password
              _AccountTile(
                icon: LucideIcons.lock,
                title: 'Trocar senha',
                onTap: () => _showChangePasswordDialog(context, ref),
              ),
              Divider(height: 1, thickness: 1, color: _T.hair),
              // Redeem instructor code (for users invited as instructor in
              // another academy — they enter the 8-char code here)
              _AccountTile(
                icon: LucideIcons.key,
                title: 'Resgatar código de equipe',
                onTap: () => context.push('/codigo-equipe'),
              ),
              Divider(height: 1, thickness: 1, color: _T.hair),
              // Legal links
              _AccountTile(
                icon: LucideIcons.fileText,
                title: 'Termos de Uso',
                onTap: () => _openUrl(AppConstants.termsOfServiceUrl),
              ),
              Divider(height: 1, thickness: 1, color: _T.hair),
              _AccountTile(
                icon: LucideIcons.shield,
                title: 'Politica de Privacidade',
                onTap: () => _openUrl(AppConstants.privacyPolicyUrl),
              ),
              Divider(height: 1, thickness: 1, color: _T.hair),
              // Notification preferences — acima do logout (LGPD)
              _AccountTile(
                icon: LucideIcons.bell,
                title: 'Notificacoes',
                onTap: () =>
                    context.push('/portal/preferencias-notificacoes'),
              ),
              Divider(height: 1, thickness: 1, color: _T.hair),
              // Logout — sair da conta (acima do excluir conta)
              _AccountTile(
                icon: LucideIcons.logOut,
                title: 'Sair',
                onTap: () => ref.read(authServiceProvider).signOut(),
              ),
              Divider(height: 1, thickness: 1, color: _T.hair),
              // Delete account
              _AccountTile(
                icon: LucideIcons.trash2,
                title: 'Excluir minha conta',
                isDestructive: true,
                onTap: () => DeleteAccountHelper.showConfirmation(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        onSubmit: (current, next) async {
          final authService = ref.read(authServiceProvider);
          await authService.updatePassword(
            currentPassword: current,
            newPassword: next,
          );
        },
      ),
    );
  }
}

/// Dialog that asks for current password + new password + confirmation, then
/// triggers reauth + update. Validates new password length and confirmation
/// match client-side; Firebase errors (`wrong-password`,
/// `requires-recent-login`, etc.) are surfaced inline.
class _ChangePasswordDialog extends StatefulWidget {
  final Future<void> Function(String currentPassword, String newPassword)
  onSubmit;

  const _ChangePasswordDialog({required this.onSubmit});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _saving = false;
  bool _success = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cur = _currentController.text;
    final next = _newController.text;
    final conf = _confirmController.text;

    if (cur.isEmpty) {
      setState(() => _error = 'Informe sua senha atual.');
      return;
    }
    if (next.length < 6) {
      setState(
        () => _error = 'A nova senha precisa ter pelo menos 6 caracteres.',
      );
      return;
    }
    if (next != conf) {
      setState(() => _error = 'A confirmacao nao bate com a nova senha.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(cur, next);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _success = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _mapError(e);
      });
    }
  }

  String _mapError(Object e) {
    final s = e.toString();
    if (s.contains('wrong-password') || s.contains('invalid-credential')) {
      return 'Senha atual incorreta.';
    }
    if (s.contains('requires-recent-login')) {
      return 'Por seguranca, saia e entre novamente antes de trocar a senha.';
    }
    if (s.contains('weak-password')) {
      return 'Senha muito fraca. Use ao menos 6 caracteres.';
    }
    return 'Erro ao trocar a senha. Tente novamente.';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_success ? 'Senha atualizada' : 'Trocar senha'),
      content: _success
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.checkCircle,
                  color: AppTheme.success,
                  size: 36,
                ),
                const SizedBox(height: 12),
                Text(
                  'Sua senha foi alterada com sucesso.',
                  style: AppTheme.bodyMedium,
                ),
              ],
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _currentController,
                    obscureText: !_showCurrent,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      labelText: 'Senha atual',
                      prefixIcon: const Icon(LucideIcons.lock, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showCurrent ? LucideIcons.eyeOff : LucideIcons.eye,
                          size: 18,
                        ),
                        onPressed: () =>
                            setState(() => _showCurrent = !_showCurrent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newController,
                    obscureText: !_showNew,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      labelText: 'Nova senha',
                      prefixIcon: const Icon(LucideIcons.key, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showNew ? LucideIcons.eyeOff : LucideIcons.eye,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _showNew = !_showNew),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmController,
                    obscureText: !_showNew,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Confirmar nova senha',
                      prefixIcon: Icon(LucideIcons.key, size: 18),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      actions: _success
          ? [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ]
          : [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text('Salvar'),
              ),
            ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isDestructive;

  const _AccountTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? _T.blood : _T.ink;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: isDestructive
                  ? _T.blood.withValues(alpha: 0.5)
                  : _T.ash,
            ),
          ],
        ),
      ),
    );
  }
}
