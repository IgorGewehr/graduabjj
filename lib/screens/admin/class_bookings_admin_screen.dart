import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/class_occurrences.dart';
import '../../core/theme.dart';
import '../../models/class_booking.dart';
import '../../models/student.dart';
import '../../services/attendance_service.dart';
import '../../services/class_booking_service.dart';
import '../../services/class_service.dart';
import '../../services/firebase_service.dart';
import '../../services/settings_service.dart';
import '../../services/student_service.dart';
import '../../widgets/polish/polish.dart';

/// Admin "Reservas" (A1) — ocorrências das turmas com vagas/fila, gestão do
/// roster por ocorrência (confirmados/espera, add/remove manual) e indicador de
/// no-show (confirmado sem presença na data). Staff ignora corte/janela.
class ClassBookingsAdminScreen extends StatefulWidget {
  const ClassBookingsAdminScreen({super.key});

  @override
  State<ClassBookingsAdminScreen> createState() =>
      _ClassBookingsAdminScreenState();
}

class _AdminOccRow {
  final String classId;
  final String className;
  final int? maxStudents;
  final OccurrenceSlot slot;
  final String occId;
  ClassOccurrence? occ;

  _AdminOccRow({
    required this.classId,
    required this.className,
    required this.maxStudents,
    required this.slot,
    required this.occId,
  });

  int? get effMax => maxStudents ?? occ?.maxStudents;
  int get confirmed => occ?.confirmedCount ?? 0;
  int get waitlist => occ?.waitlistCount ?? 0;
}

class _ClassBookingsAdminScreenState extends State<ClassBookingsAdminScreen> {
  String get _academyId => FirebaseService.academyId;
  late final ClassBookingService _bookings = ClassBookingService(_academyId);

  bool _loading = true;
  String? _error;
  List<_AdminOccRow> _rows = [];

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
      final startOfDay = DateTime(now.year, now.month, now.day);
      final settings =
          await SettingsService(_academyId).getAcademySettings();
      final windowDays = settings?.bookingWindowDays ?? 7;
      final classes = await ClassService(_academyId).list();

      final rows = <_AdminOccRow>[];
      for (final c in classes) {
        final slots = c.schedule
            .map((s) => ScheduleSlot(
                  dayOfWeek: s.dayOfWeek,
                  startTime: s.startTime,
                  endTime: s.endTime,
                ))
            .toList();
        final multi = hasMultipleSlotsPerDay(slots);
        // from startOfDay so today's earlier classes appear (no-show review).
        final occs = upcomingOccurrences(slots,
            from: startOfDay, windowDays: windowDays);
        for (final o in occs) {
          rows.add(_AdminOccRow(
            classId: c.id,
            className: c.name,
            maxStudents: c.maxStudents,
            slot: o,
            occId: occurrenceId(c.id, o.date, o.startTime, multiPerDay: multi),
          ));
        }
      }
      rows.sort((a, b) => a.slot.slotStart.compareTo(b.slot.slotStart));

      final occMap = await _bookings
          .occurrencesByIds(rows.map((r) => r.occId).toSet().toList());
      for (final r in rows) {
        r.occ = occMap[r.occId];
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

  static const _weekdays = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
  String _dayLabel(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '${_weekdays[d.weekday % 7]}, $dd/$mm';
  }

  Future<void> _openRoster(_AdminOccRow r) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OccurrenceRosterSheet(
        academyId: _academyId,
        classId: r.classId,
        className: r.className,
        occId: r.occId,
        slot: r.slot,
        dayLabel: _dayLabel(r.slot.date),
      ),
    );
    await _load(); // counters may have changed
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reservas')),
      body: _body(),
    );
  }

  Widget _body() {
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
            subtitle: _error!,
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
            title: 'Nenhuma ocorrência',
            subtitle:
                'Não há aulas com horário nos próximos dias. Verifique os horários das turmas.',
          ),
        ]),
      );
    }

    final now = DateTime.now();
    final children = <Widget>[];
    String? lastDay;
    for (final r in _rows) {
      final dayKey = yyyyMMdd(r.slot.date);
      if (dayKey != lastDay) {
        lastDay = dayKey;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(_dayLabel(r.slot.date),
              style:
                  AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700)),
        ));
      }
      children.add(_row(r, now));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
          padding: const EdgeInsets.only(bottom: 24), children: children),
    );
  }

  Widget _row(_AdminOccRow r, DateTime now) {
    final cap = r.effMax == null ? '∞' : '${r.effMax}';
    final past = r.slot.slotStart.isBefore(now);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: ListTile(
        onTap: () => _openRoster(r),
        title: Text(r.className,
            style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text('${r.slot.startTime}–${r.slot.endTime}'
            '${past ? ' · encerrada' : ''}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${r.confirmed}/$cap',
                style: AppTheme.bodyMedium
                    .copyWith(fontWeight: FontWeight.w700)),
            if (r.waitlist > 0)
              Text('espera ${r.waitlist}',
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.warning)),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet: roster of one occurrence with no-show flags + manage actions.
class _OccurrenceRosterSheet extends StatefulWidget {
  final String academyId;
  final String classId;
  final String className;
  final String occId;
  final OccurrenceSlot slot;
  final String dayLabel;

  const _OccurrenceRosterSheet({
    required this.academyId,
    required this.classId,
    required this.className,
    required this.occId,
    required this.slot,
    required this.dayLabel,
  });

  @override
  State<_OccurrenceRosterSheet> createState() => _OccurrenceRosterSheetState();
}

class _OccurrenceRosterSheetState extends State<_OccurrenceRosterSheet> {
  late final ClassBookingService _bookings =
      ClassBookingService(widget.academyId);

  bool _loading = true;
  bool _busy = false;
  List<ClassBooking> _confirmed = [];
  List<ClassBooking> _waitlist = [];
  Set<String> _present = {};

  bool get _isPast => widget.slot.slotStart.isBefore(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final roster = await _bookings.rosterForOccurrence(widget.occId);
      final confirmed =
          roster.where((b) => b.status == BookingStatus.confirmed).toList();
      final waitlist =
          roster.where((b) => b.status == BookingStatus.waitlist).toList();
      Set<String> present = {};
      if (_isPast) {
        present = await AttendanceService(widget.academyId)
            .getPresentStudentIds(widget.classId, date: widget.slot.date);
      }
      if (!mounted) return;
      setState(() {
        _confirmed = confirmed;
        _waitlist = waitlist;
        _present = present;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(ClassBooking b) async {
    setState(() => _busy = true);
    try {
      await _bookings.cancel(
        classId: widget.classId,
        date: b.date,
        startTime: b.startTime,
        studentId: b.studentId,
        slotStartMillis: widget.slot.slotStart.millisecondsSinceEpoch,
      );
      await _load();
    } catch (e) {
      _snack('Erro ao remover: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final booked = {..._confirmed, ..._waitlist}.map((b) => b.studentId).toSet();
    // Roster candidates: active students (∩ class roster when it has one).
    final all = await StudentService(widget.academyId).getActive();
    final cls = await ClassService(widget.academyId).getById(widget.classId);
    final roster = cls?.studentIds ?? const <String>[];
    final candidates = all
        .where((s) => !booked.contains(s.id))
        .where((s) => roster.isEmpty || roster.contains(s.id))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    if (!mounted) return;
    if (candidates.isEmpty) {
      _snack('Nenhum aluno disponível para adicionar.');
      return;
    }
    final picked = await showModalBottomSheet<Student>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _StudentPicker(candidates: candidates),
    );
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final res = await _bookings.reserve(
        classId: widget.classId,
        date: yyyyMMdd(widget.slot.date),
        startTime: widget.slot.startTime,
        studentId: picked.id,
        slotStartMillis: widget.slot.slotStart.millisecondsSinceEpoch,
      );
      _snack(res.status == BookingStatus.confirmed
          ? '${picked.fullName} confirmado.'
          : '${picked.fullName} entrou na espera.');
      await _load();
    } catch (e) {
      _snack('Erro ao adicionar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.className,
                            style: AppTheme.titleMedium
                                .copyWith(fontWeight: FontWeight.w700)),
                        Text(
                            '${widget.dayLabel} · ${widget.slot.startTime}–${widget.slot.endTime}',
                            style: AppTheme.bodySmall
                                .copyWith(color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _add,
                    icon: const Icon(LucideIcons.userPlus, size: 16),
                    label: const Text('Adicionar'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        _sectionHeader(
                            'Confirmados (${_confirmed.length})'),
                        if (_confirmed.isEmpty)
                          _emptyRow('Ninguém confirmado.'),
                        ..._confirmed.map((b) => _bookingTile(b,
                            isNoShow: _isPast &&
                                !_present.contains(b.studentId))),
                        const SizedBox(height: 8),
                        _sectionHeader('Lista de espera (${_waitlist.length})'),
                        if (_waitlist.isEmpty)
                          _emptyRow('Sem fila de espera.'),
                        ..._waitlist.asMap().entries.map((e) =>
                            _bookingTile(e.value, position: e.key + 1)),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionHeader(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(t,
            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
      );

  Widget _emptyRow(String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(t,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary)),
      );

  Widget _bookingTile(ClassBooking b, {int? position, bool isNoShow = false}) {
    return ListTile(
      dense: true,
      leading: position != null
          ? CircleAvatar(
              radius: 13,
              backgroundColor: AppTheme.warning.withValues(alpha: 0.15),
              child: Text('$position',
                  style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.warning, fontWeight: FontWeight.w700)))
          : Icon(
              isNoShow ? LucideIcons.userX : LucideIcons.userCheck,
              size: 20,
              color: isNoShow ? AppTheme.error : AppTheme.success,
            ),
      title: Text(b.studentName.isEmpty ? '(sem nome)' : b.studentName),
      subtitle: isNoShow
          ? Text('Faltou', style: AppTheme.bodySmall.copyWith(color: AppTheme.error))
          : (b.bookedBy == BookedBy.staff
              ? Text('Adicionado pela equipe',
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textSecondary))
              : null),
      trailing: IconButton(
        tooltip: 'Remover',
        onPressed: _busy ? null : () => _remove(b),
        icon: const Icon(LucideIcons.trash2, size: 18),
        color: AppTheme.error,
      ),
    );
  }
}

/// Simple searchable-ish student picker (list, tap to pick).
class _StudentPicker extends StatefulWidget {
  final List<Student> candidates;
  const _StudentPicker({required this.candidates});

  @override
  State<_StudentPicker> createState() => _StudentPickerState();
}

class _StudentPickerState extends State<_StudentPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.candidates
        .where((s) => s.fullName.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(LucideIcons.search),
                hintText: 'Buscar aluno',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: filtered.length,
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(LucideIcons.user, size: 20),
                title: Text(filtered[i].fullName),
                onTap: () => Navigator.pop(context, filtered[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
