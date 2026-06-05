import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/class_occurrences.dart';
import '../../core/theme.dart';
import '../../models/class_booking.dart';
import '../../providers/providers.dart';
import '../../services/class_booking_service.dart';
import '../../services/class_service.dart';
import '../../services/firebase_service.dart';
import '../../widgets/polish/polish.dart';

/// Portal "Reservar aula" (A1) — ocorrências dos próximos dias das turmas
/// elegíveis, com vagas, lista de espera e cancelamento. Capacidade é
/// server-authoritative (callables); esta tela só lê e dispara as ações.
class ClassBookingScreen extends ConsumerWidget {
  const ClassBookingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);
    final settings = ref.watch(academySettingsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Reservar aula')),
      body: studentAsync.when(
        loading: () => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PolishSkeleton.header(),
              const SizedBox(height: 16),
              PolishSkeleton.list(count: 5, scrollable: false, showAvatar: false),
            ],
          ),
        ),
        error: (e, _) => const PolishedEmptyState(
          icon: LucideIcons.alertTriangle,
          title: 'Erro ao carregar',
          subtitle: 'Verifique sua conexão e tente novamente.',
          accent: AppTheme.error,
        ),
        data: (student) {
          if (student == null) {
            return const PolishedEmptyState(
              icon: LucideIcons.userX,
              title: 'Perfil não vinculado',
              subtitle: 'Sua conta ainda não está vinculada a um aluno.',
            );
          }
          if (settings != null && settings.bookingEnabled != true) {
            return const PolishedEmptyState(
              icon: LucideIcons.lock,
              title: 'Reservas indisponíveis',
              subtitle: 'Sua academia ainda não habilitou a reserva de aulas.',
            );
          }
          return _BookingBody(
            studentId: student.id,
            windowDays: settings?.bookingWindowDays ?? 7,
            cutoffMinutes: settings?.bookingCancelCutoffMinutes ?? 60,
          );
        },
      ),
    );
  }
}

/// One bookable occurrence paired with its (possibly absent) counter and the
/// student's own booking for it.
class _OccRow {
  final String classId;
  final String className;
  final String? instructorName;
  final int? maxStudents;
  final OccurrenceSlot slot;
  final String occId;
  ClassOccurrence? occ;
  ClassBooking? mine;

  _OccRow({
    required this.classId,
    required this.className,
    required this.instructorName,
    required this.maxStudents,
    required this.slot,
    required this.occId,
  });

  int get confirmed => occ?.confirmedCount ?? 0;

  /// Capacity from the class, falling back to the occurrence counter (used for
  /// synthetic rows reconstructed from a booking when the class isn't loaded).
  int? get effMax => maxStudents ?? occ?.maxStudents;
  bool get isFull => effMax != null && confirmed >= effMax!;
}

class _BookingBody extends ConsumerStatefulWidget {
  final String studentId;
  final int windowDays;
  final int cutoffMinutes;

  const _BookingBody({
    required this.studentId,
    required this.windowDays,
    required this.cutoffMinutes,
  });

  @override
  ConsumerState<_BookingBody> createState() => _BookingBodyState();
}

class _BookingBodyState extends ConsumerState<_BookingBody> {
  String get _academyId => FirebaseService.academyId;
  late final ClassBookingService _bookings = ClassBookingService(_academyId);

  bool _loading = true;
  String? _error;
  List<_OccRow> _rows = [];
  final Set<String> _busy = {}; // occIds with an in-flight action

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final classes = await ClassService(_academyId).list();

      // Eligible: enrolled, explicitly open, or no roster (mirrors the callable
      // + the QR self-check-in rule).
      final eligible = classes.where((c) {
        final roster = c.studentIds;
        return c.isOpenClass == true ||
            roster.isEmpty ||
            roster.contains(widget.studentId);
      });

      final rows = <_OccRow>[];
      for (final c in eligible) {
        final slots = c.schedule
            .map((s) => ScheduleSlot(
                  dayOfWeek: s.dayOfWeek,
                  startTime: s.startTime,
                  endTime: s.endTime,
                ))
            .toList();
        final multi = hasMultipleSlotsPerDay(slots);
        final occs =
            upcomingOccurrences(slots, from: now, windowDays: widget.windowDays);
        for (final o in occs) {
          rows.add(_OccRow(
            classId: c.id,
            className: c.name,
            instructorName: c.instructorName,
            maxStudents: c.maxStudents,
            slot: o,
            occId: occurrenceId(c.id, o.date, o.startTime, multiPerDay: multi),
          ));
        }
      }
      // Hydrate my bookings first so we can guarantee every active reservation
      // is shown even if the class is no longer eligible (e.g. removed from the
      // roster) — otherwise it would become invisible and uncancellable.
      final mine = await _bookings.activeBookingsForStudent(widget.studentId);
      final mineByOcc = {for (final b in mine) b.occId: b};
      final coveredOccIds = rows.map((r) => r.occId).toSet();
      for (final b in mine) {
        if (coveredOccIds.contains(b.occId)) continue;
        final start = b.slotStart;
        if (start == null || !start.isAfter(now)) continue; // past/unknown
        rows.add(_OccRow(
          classId: b.classId,
          className: b.className,
          instructorName: null,
          maxStudents: null,
          slot: OccurrenceSlot(
            date: DateTime(start.year, start.month, start.day),
            dayOfWeek: weekdaySunZero(start),
            startTime: b.startTime,
            endTime: b.endTime,
            slotStart: start,
          ),
          occId: b.occId,
        ));
      }
      rows.sort((a, b) => a.slot.slotStart.compareTo(b.slot.slotStart));

      // Hydrate counters.
      final occMap = await _bookings.occurrencesByIds(
          rows.map((r) => r.occId).toSet().toList());
      for (final r in rows) {
        r.occ = occMap[r.occId];
        r.mine = mineByOcc[r.occId];
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _reserve(_OccRow r) async {
    setState(() => _busy.add(r.occId));
    try {
      final res = await _bookings.reserve(
        classId: r.classId,
        date: yyyyMMdd(r.slot.date),
        startTime: r.slot.startTime,
        studentId: widget.studentId,
        slotStartMillis: r.slot.slotStart.millisecondsSinceEpoch,
      );
      final msg = res.status == BookingStatus.confirmed
          ? 'Vaga confirmada!'
          : 'Você entrou na lista de espera'
              '${res.position > 0 ? ' (posição ${res.position})' : ''}.';
      _snack(msg,
          color: res.status == BookingStatus.confirmed
              ? AppTheme.success
              : null);
      await _load();
    } catch (e) {
      _snack(_friendlyError(e), color: AppTheme.error);
    } finally {
      if (mounted) setState(() => _busy.remove(r.occId));
    }
  }

  Future<void> _cancel(_OccRow r) async {
    setState(() => _busy.add(r.occId));
    try {
      final res = await _bookings.cancel(
        classId: r.classId,
        date: yyyyMMdd(r.slot.date),
        startTime: r.slot.startTime,
        studentId: widget.studentId,
        slotStartMillis: r.slot.slotStart.millisecondsSinceEpoch,
      );
      _snack(res.promotedStudentId != null
          ? 'Reserva cancelada. A próxima pessoa da espera foi promovida.'
          : 'Reserva cancelada.');
      await _load();
    } catch (e) {
      _snack(_friendlyError(e), color: AppTheme.error);
    } finally {
      if (mounted) setState(() => _busy.remove(r.occId));
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    // FirebaseFunctionsException carries the server message after the code.
    final i = s.indexOf(']');
    final tail = i >= 0 && i + 1 < s.length ? s.substring(i + 1).trim() : s;
    return tail.isEmpty ? 'Não foi possível concluir.' : tail;
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  static const _weekdays = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

  String _dayLabel(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${_weekdays[d.weekday % 7]}, $dd/$mm';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: PolishSkeleton.list(count: 6, scrollable: false),
      );
    }
    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          const SizedBox(height: 80),
          PolishedEmptyState(
            icon: LucideIcons.alertTriangle,
            title: 'Erro ao carregar',
            subtitle: _friendlyError(_error!),
            accent: AppTheme.error,
          ),
        ]),
      );
    }
    if (_rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: const [
          SizedBox(height: 80),
          PolishedEmptyState(
            icon: LucideIcons.calendarX,
            title: 'Nenhuma aula disponível',
            subtitle:
                'Não há aulas das suas turmas nos próximos dias para reservar.',
          ),
        ]),
      );
    }

    // Group by calendar day.
    final children = <Widget>[];
    String? lastDay;
    for (final r in _rows) {
      final dayKey = yyyyMMdd(r.slot.date);
      if (dayKey != lastDay) {
        lastDay = dayKey;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(_dayLabel(r.slot.date),
              style: AppTheme.titleSmall
                  .copyWith(fontWeight: FontWeight.w700)),
        ));
      }
      children.add(_card(r));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: children),
    );
  }

  Widget _card(_OccRow r) {
    final busy = _busy.contains(r.occId);
    final mine = r.mine;
    final now = DateTime.now();

    // Vagas text.
    final String vagas;
    if (r.effMax == null) {
      vagas = 'Vagas livres';
    } else {
      vagas = '${r.confirmed}/${r.effMax} vagas';
    }

    Widget trailing;
    if (mine != null && mine.status == BookingStatus.confirmed) {
      trailing = _cancelButton(r, now, label: 'Cancelar', badge: 'Confirmada',
          badgeColor: AppTheme.success);
    } else if (mine != null && mine.status == BookingStatus.waitlist) {
      trailing = _cancelButton(r, now, label: 'Sair da espera',
          badge: 'Na espera', badgeColor: AppTheme.warning);
    } else if (r.isFull) {
      trailing = FilledButton.tonalIcon(
        onPressed: busy ? null : () => _reserve(r),
        icon: const Icon(LucideIcons.clock, size: 16),
        label: const Text('Espera'),
      );
    } else {
      trailing = FilledButton.icon(
        onPressed: busy ? null : () => _reserve(r),
        icon: const Icon(LucideIcons.check, size: 16),
        label: const Text('Reservar'),
      );
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.className,
                      style: AppTheme.titleSmall
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${r.slot.startTime}–${r.slot.endTime}'
                    '${r.instructorName != null && r.instructorName!.isNotEmpty ? ' · ${r.instructorName}' : ''}',
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(
                      r.isFull ? LucideIcons.users : LucideIcons.userCheck,
                      size: 13,
                      color: r.isFull ? AppTheme.warning : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(vagas,
                        style: AppTheme.bodySmall.copyWith(
                            color: r.isFull
                                ? AppTheme.warning
                                : AppTheme.textSecondary)),
                  ]),
                ],
              ),
            ),
            const SizedBox(width: 8),
            busy
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : trailing,
          ],
        ),
      ),
    );
  }

  Widget _cancelButton(_OccRow r, DateTime now,
      {required String label,
      required String badge,
      required Color badgeColor}) {
    final allowed = canCancel(r.slot.slotStart, now, widget.cutoffMinutes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(badge,
              style: AppTheme.bodySmall.copyWith(
                  color: badgeColor, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: allowed ? () => _confirmCancel(r) : null,
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.error,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 32),
          ),
          child: Text(allowed
              ? label
              : 'Sem cancelar (<${widget.cutoffMinutes}min)'),
        ),
      ],
    );
  }

  Future<void> _confirmCancel(_OccRow r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar reserva?'),
        content: Text(
            '${r.className} · ${_dayLabel(r.slot.date)} ${r.slot.startTime}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar reserva'),
          ),
        ],
      ),
    );
    if (ok == true) await _cancel(r);
  }
}
