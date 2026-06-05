import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/striking_session.dart';
import '../../providers/providers.dart';
import '../../services/firebase_service.dart';
import '../../services/striking_session_service.dart';
import '../../widgets/polish/polish.dart';
import 'cartel_screen.dart';
import 'striking_timer_screen.dart';

const _strikingSports = [SportId.muaythai, SportId.boxing, SportId.kickboxing];

String _sportLabel(String v) {
  switch (v) {
    case 'boxing':
      return 'Boxe';
    case 'kickboxing':
      return 'Kickboxing';
    case 'muaythai':
    default:
      return 'Muay Thai';
  }
}

/// Portal "Trocação" hub (C1): round timer + session log + history.
class StrikingScreen extends ConsumerStatefulWidget {
  const StrikingScreen({super.key});

  @override
  ConsumerState<StrikingScreen> createState() => _StrikingScreenState();
}

class _StrikingScreenState extends ConsumerState<StrikingScreen> {
  String get _academyId => FirebaseService.academyId;
  late final StrikingSessionService _service =
      StrikingSessionService(_academyId);

  bool _loading = true;
  String? _studentId;
  String _studentName = '';
  List<String> _sportOptions = const [];
  List<StrikingSession> _sessions = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final student = await ref.read(currentStudentProvider.future);
    if (student == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final striking = student
        .getSports()
        .where(_strikingSports.contains)
        .map((s) => s.value)
        .toList();
    _studentId = student.id;
    _studentName = student.fullName;
    _sportOptions =
        striking.isNotEmpty ? striking : _strikingSports.map((s) => s.value).toList();
    await _loadSessions();
  }

  Future<void> _loadSessions() async {
    if (_studentId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final list = await _service.getByStudent(_studentId!, limit: 50);
      if (!mounted) return;
      setState(() {
        _sessions = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openTimer() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const StrikingTimerScreen()),
    );
    if (result != null) {
      await _openRegister(
        rounds: result['rounds'] as int?,
        roundDurationSec: result['roundDurationSec'] as int?,
        totalMinutes: result['totalMinutes'] as int?,
      );
    }
  }

  Future<void> _openRegister(
      {int? rounds, int? roundDurationSec, int? totalMinutes}) async {
    if (_studentId == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RegisterSheet(
        sportOptions: _sportOptions,
        initialRounds: rounds,
        initialRoundDurationSec: roundDurationSec,
        initialTotalMinutes: totalMinutes,
        onSave: (session) => _service.create(session),
        studentId: _studentId!,
        studentName: _studentName,
      ),
    );
    if (saved == true) await _loadSessions();
  }

  static const _months = [
    '', 'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trocação')),
      body: _loading
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: PolishSkeleton.list(count: 5, scrollable: false),
            )
          : _studentId == null
              ? const PolishedEmptyState(
                  icon: LucideIcons.userX,
                  title: 'Perfil não vinculado',
                  subtitle: 'Sua conta ainda não está vinculada a um aluno.',
                )
              : RefreshIndicator(
                  onRefresh: _loadSessions,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      _actions(),
                      const SizedBox(height: 8),
                      Card(
                        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: ListTile(
                          leading: const Icon(LucideIcons.swords,
                              color: AppTheme.primary),
                          title: const Text('Meu cartel'),
                          subtitle: const Text('Sua ficha de luta oficial'),
                          trailing: const Icon(LucideIcons.chevronRight),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const CartelScreen()),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text('Histórico',
                            style: AppTheme.titleSmall
                                .copyWith(fontWeight: FontWeight.w700)),
                      ),
                      if (_sessions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: PolishedEmptyState(
                            icon: LucideIcons.clipboardList,
                            title: 'Sem sessões ainda',
                            subtitle:
                                'Registre seus treinos de trocação para acompanhar a evolução.',
                          ),
                        )
                      else
                        ..._historyTiles(),
                    ],
                  ),
                ),
    );
  }

  Widget _actions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _openTimer,
              icon: const Icon(LucideIcons.timer),
              label: const Text('Iniciar timer'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => _openRegister(),
              icon: const Icon(LucideIcons.plus),
              label: const Text('Registrar'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _historyTiles() {
    final out = <Widget>[];
    int? lastKey;
    for (final s in _sessions) {
      final key = s.date.year * 100 + s.date.month;
      if (key != lastKey) {
        lastKey = key;
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('${_months[s.date.month]} ${s.date.year}',
              style: AppTheme.bodySmall
                  .copyWith(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
        ));
      }
      out.add(_sessionTile(s));
    }
    return out;
  }

  Widget _sessionTile(StrikingSession s) {
    final dd = s.date.day.toString().padLeft(2, '0');
    final mm = s.date.month.toString().padLeft(2, '0');
    final parts = <String>[
      '${s.rounds} rounds',
      if (s.totalMinutes != null) '${s.totalMinutes} min',
      if (s.rpe != null) 'RPE ${s.rpe}',
    ];
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
          child: const Icon(LucideIcons.swords, size: 18, color: AppTheme.primary),
        ),
        title: Text('${s.type.label} · ${_sportLabel(s.sport)}',
            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text('$dd/$mm · ${parts.join(' · ')}'
            '${s.notes != null && s.notes!.isNotEmpty ? '\n${s.notes}' : ''}'),
        isThreeLine: s.notes != null && s.notes!.isNotEmpty,
        trailing: IconButton(
          icon: const Icon(LucideIcons.trash2, size: 18),
          color: AppTheme.error,
          onPressed: () => _confirmDelete(s),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(StrikingSession s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir sessão?'),
        content: Text('${s.type.label} · ${_sportLabel(s.sport)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Voltar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _service.delete(s.id);
      await _loadSessions();
    }
  }
}

/// Bottom sheet to log a striking session.
class _RegisterSheet extends StatefulWidget {
  final List<String> sportOptions;
  final int? initialRounds;
  final int? initialRoundDurationSec;
  final int? initialTotalMinutes;
  final String studentId;
  final String studentName;
  final Future<void> Function(StrikingSession) onSave;

  const _RegisterSheet({
    required this.sportOptions,
    required this.studentId,
    required this.studentName,
    required this.onSave,
    this.initialRounds,
    this.initialRoundDurationSec,
    this.initialTotalMinutes,
  });

  @override
  State<_RegisterSheet> createState() => _RegisterSheetState();
}

class _RegisterSheetState extends State<_RegisterSheet> {
  late String _sport = widget.sportOptions.first;
  StrikingType _type = StrikingType.bag;
  late int _rounds = widget.initialRounds ?? 3;
  double _rpe = 6;
  final _notes = TextEditingController();
  late final TextEditingController _totalMinutesCtrl = TextEditingController(
      text: widget.initialTotalMinutes?.toString() ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    _totalMinutesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(StrikingSession(
        id: '',
        studentId: widget.studentId,
        studentName: widget.studentName,
        sport: _sport,
        type: _type,
        rounds: _rounds,
        roundDurationSec: widget.initialRoundDurationSec,
        totalMinutes: int.tryParse(_totalMinutesCtrl.text.trim()),
        rpe: _rpe.round(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        date: DateTime.now(),
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Registrar sessão',
                style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (widget.sportOptions.length > 1) ...[
              Text('Modalidade', style: AppTheme.bodySmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: widget.sportOptions
                    .map((v) => ChoiceChip(
                          label: Text(_sportLabel(v)),
                          selected: _sport == v,
                          onSelected: (_) => setState(() => _sport = v),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],
            Text('Tipo', style: AppTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: StrikingType.values
                  .map((t) => ChoiceChip(
                        label: Text(t.label),
                        selected: _type == t,
                        onSelected: (_) => setState(() => _type = t),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text('Rounds', style: AppTheme.bodyLarge)),
                IconButton.filledTonal(
                    onPressed: _rounds > 1
                        ? () => setState(() => _rounds--)
                        : null,
                    icon: const Icon(LucideIcons.minus)),
                SizedBox(
                    width: 48,
                    child: Text('$_rounds',
                        textAlign: TextAlign.center,
                        style: AppTheme.titleMedium
                            .copyWith(fontWeight: FontWeight.w700))),
                IconButton.filledTonal(
                    onPressed: _rounds < 30
                        ? () => setState(() => _rounds++)
                        : null,
                    icon: const Icon(LucideIcons.plus)),
              ],
            ),
            Row(
              children: [
                Expanded(child: Text('Duração total (min)', style: AppTheme.bodyLarge)),
                SizedBox(
                  width: 90,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    controller: _totalMinutesCtrl,
                    decoration: const InputDecoration(hintText: '—'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Esforço (RPE): ${_rpe.round()}', style: AppTheme.bodyLarge),
            Slider(
              value: _rpe,
              min: 1,
              max: 10,
              divisions: 9,
              label: '${_rpe.round()}',
              onChanged: (v) => setState(() => _rpe = v),
            ),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Salvar sessão'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
