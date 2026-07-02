import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../models/checkin.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import '../../services/checkin_service.dart';
import '../../widgets/polish/polish.dart';

// ---------------------------------------------------------------------------
// Fighter palette (local to this screen — não toca o theme compartilhado).
// ---------------------------------------------------------------------------
const Color _kBone = Color(0xFFF4F3EF); // canvas
const Color _kCard = Color(0xFFFFFFFF); // card surface
const Color _kInk = Color(0xFF0A0A0A); // tinta principal
const Color _kInk2 = Color(0xFF6E6E68); // texto secundário
const Color _kRed = Color(0xFFE0301E); // único acento
const Color _kHair = Color(0xFFE7E5DF); // hairline / divisória

const List<FontFeature> _kTab = [FontFeature.tabularFigures()];

/// Valida "HH:mm" tolerando lixo de dados ("", "19", "19:00:00", não-numérico).
/// Sem isso, `int.parse` cru dentro de [isInCheckinWindow] /
/// [getTimeUntilCheckinOpens] derruba o build inteiro (tela branca).
bool _isValidHhmm(String t) {
  final p = t.split(':');
  if (p.length < 2) return false;
  final h = int.tryParse(p[0].trim());
  final m = int.tryParse(p[1].trim());
  return h != null && m != null && h >= 0 && h <= 23 && m >= 0 && m <= 59;
}

/// Normaliza para "HH:mm" para exibição; devolve cru se não der pra normalizar.
String _displayTime(String t) {
  final p = t.split(':');
  if (p.length < 2) return t;
  final h = int.tryParse(p[0].trim());
  final m = int.tryParse(p[1].trim());
  if (h == null || m == null) return t;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Schedule Screen - Horarios das Aulas / Meus Treinos
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  bool _isCreatingCheckin = false;

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final settingsAsync = ref.watch(academySettingsProvider);
    final currentStudent = ref.watch(currentStudentProvider).valueOrNull;

    final studentId = currentStudent?.id ?? currentUser?.studentId;
    final academyId = currentUser?.academyId;

    if (studentId == null || academyId == null) {
      return _Canvas(
        child: _StateBlock(
          icon: LucideIcons.userX,
          title: 'ALUNO NÃO ENCONTRADO',
          message: 'Não foi possível identificar seu cadastro nesta academia.',
        ),
      );
    }

    final checkinEnabled =
        settingsAsync.valueOrNull?.studentCheckinEnabled ?? false;

    final classesAsync = ref.watch(
      _enrolledClassesProvider(
        _EnrolledClassesParams(academyId: academyId, studentId: studentId),
      ),
    );

    final studentCheckinsAsync = checkinEnabled
        ? ref.watch(studentPendingCheckinsProvider(studentId))
        : const AsyncValue<List<Checkin>>.data([]);

    return _Canvas(
      child: RefreshIndicator(
        color: _kRed,
        backgroundColor: _kCard,
        onRefresh: () async {
          HapticFeedback.mediumImpact();
          ref.invalidate(
            _enrolledClassesProvider(
              _EnrolledClassesParams(
                academyId: academyId,
                studentId: studentId,
              ),
            ),
          );
          if (checkinEnabled) {
            ref.invalidate(studentPendingCheckinsProvider(studentId));
          }
        },
        child: classesAsync.when(
          loading: () => _buildLoadingState(),
          error: (e, _) => _buildErrorState(),
          data: (result) {
            // Toda a montagem síncrona (parse de horários, agrupamento por dia)
            // roda aqui dentro. Um único schedule com horário sujo lançava
            // exceção e deixava a tela BRANCA — agora isso vira estado de erro
            // visível em vez de nada.
            try {
              final studentCheckins = studentCheckinsAsync.valueOrNull ?? [];

              // result.visible = turmas matriculadas (se houver) ou TODAS as
              // turmas ativas da academia como fallback. Garante que alunos com
              // presença mas sem matrícula formal vejam o schedule completo.
              final classes = result.visible;

              // Multi-sport: derive the distinct sports the student actually
              // has classes in (legacy null == 'bjj' via getSport()). With more
              // than one, expose a per-sport filter so BJJ and Muay Thai aren't
              // jumbled in one date-only list. Single-sport students see the
              // unchanged screen (filter hides itself).
              final classSports = <SportId>[];
              for (final c in classes) {
                final s = c.getSport();
                if (!classSports.contains(s)) classSports.add(s);
              }
              final multiSport = classSports.length > 1;

              SportId? selectedSport;
              if (multiSport) {
                final primary =
                    currentStudent?.getPrimarySport() ?? SportId.bjj;
                selectedSport =
                    ref.watch(selectedSportProvider('schedule')) ??
                    (classSports.contains(primary)
                        ? primary
                        : classSports.first);
              }

              // Sport filter: compute the filtered list, but if it comes out
              // empty (e.g. stale provider state from a previous session), fall
              // back to showing ALL classes so the screen never goes blank just
              // because a sport was previously selected that no longer exists.
              final filteredBySport = selectedSport == null
                  ? classes
                  : classes
                        .where((c) => c.getSport() == selectedSport)
                        .toList();
              final visibleClasses = (selectedSport != null &&
                      filteredBySport.isEmpty)
                  ? classes
                  : filteredBySport;
              // If we fell back, clear the effective sport so the filter chip
              // doesn't mislead the user.
              final effectiveSport =
                  (selectedSport != null && filteredBySport.isEmpty)
                      ? null
                      : selectedSport;

              final upcoming = _buildUpcomingSchedules(
                visibleClasses,
                studentCheckins,
                checkinEnabled,
              );
              return _buildContent(
                classes: classes,
                upcoming: upcoming,
                hasAcademyClasses: result.allClasses.isNotEmpty,
                studentId: studentId,
                studentName: currentStudent?.fullName ?? 'Aluno',
                checkinEnabled: checkinEnabled,
                multiSport: multiSport,
                classSports: classSports,
                selectedSport: effectiveSport,
              );
            } catch (_) {
              return _buildErrorState();
            }
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ content

  Widget _buildContent({
    required List<BJJClass> classes,
    required List<UpcomingSchedule> upcoming,
    required bool hasAcademyClasses,
    required String studentId,
    required String studentName,
    required bool checkinEnabled,
    required bool multiSport,
    required List<SportId> classSports,
    required SportId? selectedSport,
  }) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Header(),
          const SizedBox(height: 16),

          const _AcademyIndicator(),

          if (checkinEnabled) ...[
            _CheckinBanner(onScan: () => context.push('/portal/scan')),
            const SizedBox(height: 16),
          ],

          // Per-sport filter (multi-sport students only). Rendered above the
          // empty state so a student whose selected sport has no upcoming
          // classes can still switch to another sport.
          if (multiSport && selectedSport != null) ...[
            _SportFilter(
              sports: classSports,
              selected: selectedSport,
              onSelected: (s) => ref
                  .read(selectedSportProvider('schedule').notifier)
                  .state = s,
            ),
            const SizedBox(height: 16),
          ],

          // Empty-state real: a academia não tem turma cadastrada nenhuma.
          // (classes.isEmpty com fallback ativo significa o mesmo que
          // !hasAcademyClasses, mas usamos a flag direta para clareza.)
          if (!hasAcademyClasses)
            _StateBlock(
              icon: LucideIcons.calendarOff,
              title: 'NENHUMA TURMA CADASTRADA',
              message: 'Esta academia ainda não possui turmas configuradas.',
            )
          else if (upcoming.isEmpty)
            _StateBlock(
              icon: LucideIcons.calendarClock,
              title: 'SEM AULAS PROGRAMADAS',
              message: multiSport
                  ? 'Nenhuma aula deste esporte nos próximos 7 dias.'
                  : 'Nenhuma aula nos próximos 7 dias.',
            )
          else
            ..._buildSchedulesByDay(
              upcoming,
              studentId,
              studentName,
              checkinEnabled,
              multiSport,
            ),

          if (checkinEnabled && hasAcademyClasses) ...[
            const SizedBox(height: 20),
            const _Legend(),
          ],
        ],
      ),
    );
  }

  // ----------------------------------------------------------- data assembly

  List<UpcomingSchedule> _buildUpcomingSchedules(
    List<BJJClass> classes,
    List<Checkin> studentCheckins,
    bool checkinEnabled,
  ) {
    final now = DateTime.now();
    final schedules = <UpcomingSchedule>[];

    for (int i = 0; i < 7; i++) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: i));
      final dayOfWeek = date.weekday % 7; // 0-6 (0 = domingo)

      for (final bjjClass in classes) {
        final classSchedules = bjjClass.schedule
            .where((s) => s.dayOfWeek == dayOfWeek)
            .toList();

        for (final schedule in classSchedules) {
          final isToday = i == 0;

          // GUARDA CRÍTICA: só chama os helpers de janela quando o horário é
          // um "HH:mm" válido. Horário sujo -> sem janela/contagem, mas a aula
          // continua aparecendo na grade.
          final validTimes =
              _isValidHhmm(schedule.startTime) &&
              _isValidHhmm(schedule.endTime);

          final inWindow =
              isToday &&
              validTimes &&
              isInCheckinWindow(
                startTime: schedule.startTime,
                endTime: schedule.endTime,
                date: date,
              );

          final timeUntilWindow = (isToday && validTimes)
              ? getTimeUntilCheckinOpens(
                  startTime: schedule.startTime,
                  date: date,
                )
              : null;

          final hasCheckin = studentCheckins.any(
            (c) =>
                c.classId == bjjClass.id &&
                c.scheduleDate.year == date.year &&
                c.scheduleDate.month == date.month &&
                c.scheduleDate.day == date.day,
          );

          schedules.add(
            UpcomingSchedule(
              bjjClass: bjjClass,
              date: date,
              dayOfWeek: dayOfWeek,
              startTime: schedule.startTime,
              endTime: schedule.endTime,
              isToday: isToday,
              inWindow: inWindow,
              timeUntilWindow: timeUntilWindow,
              hasCheckin: hasCheckin,
            ),
          );
        }
      }
    }

    schedules.sort((a, b) {
      final dateCompare = a.date.compareTo(b.date);
      if (dateCompare != 0) return dateCompare;
      return a.startTime.compareTo(b.startTime);
    });

    return schedules;
  }

  List<Widget> _buildSchedulesByDay(
    List<UpcomingSchedule> schedules,
    String studentId,
    String studentName,
    bool checkinEnabled,
    bool multiSport,
  ) {
    final widgets = <Widget>[];
    final groupedByDate = <String, List<UpcomingSchedule>>{};

    for (final schedule in schedules) {
      final key = DateFormat('yyyy-MM-dd').format(schedule.date);
      groupedByDate.putIfAbsent(key, () => []).add(schedule);
    }

    var animIndex = 0;
    var firstGroup = true;
    for (final entry in groupedByDate.entries) {
      final dateSchedules = entry.value;
      final isToday = dateSchedules.first.isToday;

      widgets.add(
        Padding(
          padding: EdgeInsets.only(top: firstGroup ? 0 : 18, bottom: 10),
          child: _DayLabel(
            date: dateSchedules.first.date,
            isToday: isToday,
          ),
        ).fadeInQuick(),
      );
      firstGroup = false;

      for (final schedule in dateSchedules) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ScheduleCard(
              schedule: schedule,
              checkinEnabled: checkinEnabled,
              isCreating: _isCreatingCheckin,
              showSportBadge: multiSport,
              onCheckin: () => _handleCheckin(schedule, studentId, studentName),
            ).entrance(index: animIndex),
          ),
        );
        animIndex++;
      }
    }

    return widgets;
  }

  // ------------------------------------------------------------------ actions

  Future<void> _handleCheckin(
    UpcomingSchedule schedule,
    String studentId,
    String studentName,
  ) async {
    if (_isCreatingCheckin) return;

    HapticFeedback.selectionClick();
    setState(() => _isCreatingCheckin = true);

    try {
      final actions = ref.read(checkinActionsProvider.notifier);
      await actions.createCheckin(
        studentId: studentId,
        studentName: studentName,
        classId: schedule.bjjClass.id,
        className: schedule.bjjClass.name,
        scheduleStartTime: schedule.startTime,
        scheduleEndTime: schedule.endTime,
        scheduleDayOfWeek: schedule.dayOfWeek,
      );

      if (mounted) {
        HapticFeedback.heavyImpact();
        Celebration.confetti(context);
        context.showSuccess('Check-in realizado com sucesso!');
        ref.invalidate(studentPendingCheckinsProvider(studentId));
      }
    } catch (e) {
      if (mounted) {
        context.showError(e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingCheckin = false);
      }
    }
  }

  // ------------------------------------------------------------------- states

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Header(),
          const SizedBox(height: 16),
          // scrollable:false é OBRIGATÓRIO aqui: dentro de Column em
          // SingleChildScrollView o ListView interno recebe altura infinita →
          // "Vertical viewport was given unbounded height" → a TELA INTEIRA
          // falhava o layout e ficava em branco (e o render object quebrado
          // envenenava os frames do app todo enquanto a branch vivia no shell).
          PolishSkeleton.list(count: 4, itemHeight: 96, scrollable: false),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Header(),
          const SizedBox(height: 24),
          _StateBlock(
            icon: LucideIcons.alertTriangle,
            title: 'ERRO AO CARREGAR',
            message:
                'Não foi possível carregar seus horários. Puxe para baixo para tentar novamente.',
            accent: _kRed,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Chrome / building blocks
// ===========================================================================

/// Fundo bone que cobre toda a área (cards brancos respiram sobre ele).
class _Canvas extends StatelessWidget {
  final Widget child;
  const _Canvas({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(color: _kBone, child: child);
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HORÁRIOS',
          style: const TextStyle(
            color: _kInk,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'PRÓXIMOS 7 DIAS',
          style: const TextStyle(
            color: _kInk2,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _DayLabel extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  const _DayLabel({required this.date, required this.isToday});

  String _label() {
    if (isToday) return 'HOJE';
    try {
      return DateFormat("EEEE, d 'DE' MMM", 'pt_BR').format(date).toUpperCase();
    } catch (_) {
      return DateFormat('EEE, d/MM').format(date).toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (isToday) ...[
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: _kRed,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Text(
          _label(),
          style: TextStyle(
            color: isToday ? _kRed : _kInk2,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _CheckinBanner extends StatelessWidget {
  final VoidCallback onScan;
  const _CheckinBanner({required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kHair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.info, size: 16, color: _kInk2),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Check-in liberado de 30 min antes do início até 1h após o fim da aula.',
                  style: const TextStyle(
                    color: _kInk2,
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(LucideIcons.qrCode, size: 16),
              label: const Text('ESCANEAR QR DA AULA'),
              style: FilledButton.styleFrom(
                backgroundColor: _kInk,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 20,
      runSpacing: 8,
      children: const [
        _LegendItem(
          icon: LucideIcons.zap,
          color: _kRed,
          label: 'Check-in disponível',
        ),
        _LegendItem(
          icon: LucideIcons.checkCircle2,
          color: _kInk,
          label: 'Check-in realizado',
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  const _LegendItem({
    required this.icon,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: _kInk2,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Filtro por esporte (só aluno multi-esporte). Segmentos all-caps no estilo
/// fighter — sem cores de esporte/faixa, apenas ink/red/bone.
class _SportFilter extends StatelessWidget {
  final List<SportId> sports;
  final SportId selected;
  final ValueChanged<SportId> onSelected;
  const _SportFilter({
    required this.sports,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var i = 0; i < sports.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _SportFilterChip(
              label: getSport(sports[i]).label.toUpperCase(),
              selected: sports[i] == selected,
              onTap: () {
                if (sports[i] != selected) {
                  HapticFeedback.selectionClick();
                  onSelected(sports[i]);
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _SportFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SportFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _kInk : _kCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? _kInk : _kHair),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _kInk2,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

/// Selo de esporte no card (aluno multi-esporte). Neutro — ink2 sobre bone,
/// sem cor de esporte/faixa.
class _SportBadge extends StatelessWidget {
  final SportId sport;
  const _SportBadge({required this.sport});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: _kBone,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _kHair),
      ),
      child: Text(
        getSport(sport).label.toUpperCase(),
        style: const TextStyle(
          color: _kInk2,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

/// Estado de vazio/erro genérico no estilo fighter.
class _StateBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color accent;
  const _StateBlock({
    required this.icon,
    required this.title,
    required this.message,
    this.accent = _kInk,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kHair),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 26, color: accent),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _kInk,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _kInk2,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ).fadeInQuick();
  }
}

// ===========================================================================
// Schedule card
// ===========================================================================

class _ScheduleCard extends StatelessWidget {
  final UpcomingSchedule schedule;
  final bool checkinEnabled;
  final bool isCreating;
  final bool showSportBadge;
  final VoidCallback onCheckin;

  const _ScheduleCard({
    required this.schedule,
    required this.checkinEnabled,
    required this.isCreating,
    required this.showSportBadge,
    required this.onCheckin,
  });

  @override
  Widget build(BuildContext context) {
    final showCheckin = checkinEnabled && schedule.isToday;
    final active = schedule.inWindow && !schedule.hasCheckin;

    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? _kRed.withValues(alpha: 0.45) : _kHair,
          width: active ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TimeBlock(
                  start: _displayTime(schedule.startTime),
                  end: _displayTime(schedule.endTime),
                  active: active,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showSportBadge) ...[
                        _SportBadge(sport: schedule.bjjClass.getSport()),
                        const SizedBox(height: 5),
                      ],
                      Text(
                        schedule.bjjClass.name,
                        style: const TextStyle(
                          color: _kInk,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      if (schedule.bjjClass.instructorName != null &&
                          schedule.bjjClass.instructorName!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(
                              LucideIcons.user,
                              size: 12,
                              color: _kInk2,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                schedule.bjjClass.instructorName!,
                                style: const TextStyle(
                                  color: _kInk2,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showCheckin) _buildCheckinSection(),
        ],
      ),
    );
  }

  Widget _buildCheckinSection() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kHair)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: _checkinChild(),
    );
  }

  Widget _checkinChild() {
    if (schedule.hasCheckin) {
      return Row(
        children: const [
          Icon(LucideIcons.checkCircle2, size: 16, color: _kInk),
          SizedBox(width: 8),
          Text(
            'PRESENÇA CONFIRMADA',
            style: TextStyle(
              color: _kInk,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      );
    }

    if (schedule.inWindow) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: isCreating ? null : onCheckin,
          icon: isCreating
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(LucideIcons.zap, size: 16),
          label: Text(isCreating ? 'AGUARDE...' : 'MARCAR PRESENÇA'),
          style: FilledButton.styleFrom(
            backgroundColor: _kRed,
            foregroundColor: Colors.white,
            disabledBackgroundColor: _kRed.withValues(alpha: 0.5),
            disabledForegroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
      );
    }

    if (schedule.timeUntilWindow != null) {
      final hours = schedule.timeUntilWindow!['hours'] ?? 0;
      final minutes = schedule.timeUntilWindow!['minutes'] ?? 0;
      final timeText = hours > 0 ? '${hours}h ${minutes}min' : '${minutes}min';

      return Row(
        children: [
          const Icon(LucideIcons.clock, size: 14, color: _kInk2),
          const SizedBox(width: 7),
          Text(
            'Check-in abre em ',
            style: const TextStyle(
              color: _kInk2,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            timeText,
            style: const TextStyle(
              color: _kInk,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              fontFeatures: _kTab,
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

/// Bloco de horário à esquerda do card (numerais tabulares).
class _TimeBlock extends StatelessWidget {
  final String start;
  final String end;
  final bool active;
  const _TimeBlock({
    required this.start,
    required this.end,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? _kRed : _kInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: active ? _kRed.withValues(alpha: 0.06) : _kBone,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? _kRed.withValues(alpha: 0.25) : _kHair,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            start,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              fontFeatures: _kTab,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 3),
          Container(width: 14, height: 1, color: _kHair),
          const SizedBox(height: 3),
          Text(
            end,
            style: const TextStyle(
              color: _kInk2,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFeatures: _kTab,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Data models
// ===========================================================================

class UpcomingSchedule {
  final BJJClass bjjClass;
  final DateTime date;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final bool isToday;
  final bool inWindow;
  final Map<String, int>? timeUntilWindow;
  final bool hasCheckin;

  UpcomingSchedule({
    required this.bjjClass,
    required this.date,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.isToday,
    required this.inWindow,
    this.timeUntilWindow,
    required this.hasCheckin,
  });
}

// ===========================================================================
// Enrolled classes provider
// ===========================================================================

class _EnrolledClassesParams {
  final String academyId;
  final String studentId;

  _EnrolledClassesParams({required this.academyId, required this.studentId});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _EnrolledClassesParams) return false;
    return academyId == other.academyId && studentId == other.studentId;
  }

  @override
  int get hashCode => Object.hash(academyId, studentId);
}

/// Resultado do provider: [visible] é o que a tela exibe (turmas matriculadas
/// se houver alguma, senão TODAS as turmas ativas da academia). [allClasses]
/// contém sempre o total da academia — usado para o empty-state real.
/// [isEnrolled] indica se [visible] é subconjunto (enrollment) ou fallback.
class _ClassesResult {
  final List<BJJClass> visible;
  final List<BJJClass> allClasses;
  final bool isEnrolled;

  const _ClassesResult({
    required this.visible,
    required this.allClasses,
    required this.isEnrolled,
  });
}

final _enrolledClassesProvider =
    FutureProvider.family<_ClassesResult, _EnrolledClassesParams>((
      ref,
      params,
    ) async {
      final classService = ClassService(params.academyId);
      final allClasses = await classService.list();

      final enrolled = allClasses
          .where((c) => c.studentIds.contains(params.studentId))
          .toList();

      return _ClassesResult(
        visible: enrolled.isNotEmpty ? enrolled : allClasses,
        allClasses: allClasses,
        isEnrolled: enrolled.isNotEmpty,
      );
    });

/// Indicador de academia para usuários multi-academia.
class _AcademyIndicator extends ConsumerWidget {
  const _AcademyIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMultiple = ref.watch(hasMultipleAcademiesProvider);
    final academyInfo = ref.watch(currentAcademyInfoProvider);

    if (!hasMultiple || academyInfo == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kHair),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.building2, size: 16, color: _kInk),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ACADEMIA',
                    style: TextStyle(
                      color: _kInk2,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    academyInfo.name,
                    style: const TextStyle(
                      color: _kInk,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () => context.push('/portal/academias'),
              icon: const Icon(LucideIcons.arrowRightLeft, size: 14),
              label: const Text('TROCAR'),
              style: TextButton.styleFrom(
                foregroundColor: _kRed,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
