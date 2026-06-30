import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../services/student_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/common/grade_display.dart';

/// Visão enxuta de um evento de acesso (doc academies/{id}/accessEvents/{...}),
/// gravado pela Cloud Function ingestAccessEvent quando a catraca POSTa um giro.
@immutable
class AccessEventView {
  final String id;
  final String? studentId;
  final String outcome;
  final bool granted;
  final String? displayMsg;
  final DateTime? receivedAt;

  const AccessEventView({
    required this.id,
    required this.studentId,
    required this.outcome,
    required this.granted,
    required this.displayMsg,
    required this.receivedAt,
  });

  factory AccessEventView.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    return AccessEventView(
      id: doc.id,
      studentId: d['studentId'] as String?,
      outcome: (d['outcome'] ?? '') as String,
      granted: d['granted'] == true,
      displayMsg: d['displayMsg'] as String?,
      receivedAt: (d['receivedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Liberou o giro (presença concedida ou já registrada hoje).
  bool get isGranted =>
      outcome == 'attendance_granted' ||
      outcome == 'duplicate' ||
      outcome == 'duplicate_day';

  bool get isAlreadyToday => outcome == 'duplicate_day';
  bool get isDeniedOverdue => outcome == 'denied_overdue';
  bool get isNoMatch => outcome == 'no_match';
}

/// Stream do ÚLTIMO evento de acesso da academia do usuário logado (o PC do
/// balcão roda como uma conta da academia). O kiosk deduplica por id e ignora
/// eventos anteriores ao início da sessão, então só reage a giros NOVOS.
final kioskLatestEventProvider =
    StreamProvider.autoDispose<AccessEventView?>((ref) {
  final academyId = ref.watch(currentUserProvider).valueOrNull?.academyId;
  if (academyId == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('academies')
      .doc(academyId)
      .collection('accessEvents')
      .orderBy('receivedAt', descending: true)
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty ? null : AccessEventView.fromDoc(s.docs.first));
});

enum _KioskMode { idle, processing, granted, denied }

/// Tela KIOSK da catraca — totem de balcão, fullscreen, sem AppBar/nav. Mostra
/// IDLE (relógio + "aproxime-se"), BEM-VINDO (foto + nome + faixa + ✅ + som) ou
/// NEGADO (❌ + motivo, ex.: financeiro pendente), com auto-reset.
class KioskScreen extends ConsumerStatefulWidget {
  const KioskScreen({super.key});

  @override
  ConsumerState<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends ConsumerState<KioskScreen> {
  static const _resetAfter = Duration(seconds: 6);

  final DateTime _startedAt = DateTime.now();
  final Set<String> _seen = {};

  _KioskMode _mode = _KioskMode.idle;
  Student? _student;
  String? _message;
  bool _alreadyToday = false;

  DateTime _clock = DateTime.now();
  Timer? _clockTimer;
  Timer? _resetTimer;

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _clock = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleEvent(AccessEventView ev) async {
    // Dedupe + ignora eventos anteriores ao início do kiosk (não reage a giro
    // velho ao abrir a tela).
    if (_seen.contains(ev.id)) return;
    if (ev.receivedAt != null && ev.receivedAt!.isBefore(_startedAt)) return;
    _seen.add(ev.id);
    await _present(ev);
  }

  /// Apresenta um evento (real ou simulado) na máquina de estados.
  Future<void> _present(AccessEventView ev) async {
    _resetTimer?.cancel();
    setState(() {
      _mode = _KioskMode.processing;
      _student = null;
      _message = null;
      _alreadyToday = ev.isAlreadyToday;
    });

    Student? student;
    if (ev.studentId != null) {
      final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
      if (academyId != null) {
        student = await StudentService(academyId)
            .getById(ev.studentId!)
            .catchError((_) => null);
      }
    }
    if (!mounted) return;

    final granted = ev.isGranted;
    setState(() {
      _mode = granted ? _KioskMode.granted : _KioskMode.denied;
      _student = student;
      _alreadyToday = ev.isAlreadyToday;
      _message = granted
          ? (student != null
              ? (ev.isAlreadyToday
                  ? 'Presença já registrada hoje'
                  : 'Bem-vindo(a)!')
              : 'Acesso liberado')
          : (ev.displayMsg ??
              (ev.isDeniedOverdue
                  ? 'Financeiro pendente — procure a recepção'
                  : ev.isNoMatch
                      ? 'Não reconhecido'
                      : 'Acesso negado'));
    });

    // Feedback tátil/sonoro (custom sounds = TODO: precisa de audioplayers).
    if (granted) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    SystemSound.play(SystemSoundType.alert);

    _resetTimer = Timer(_resetAfter, () {
      if (mounted) setState(() => _mode = _KioskMode.idle);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Reage a cada novo evento de acesso da academia.
    ref.listen<AsyncValue<AccessEventView?>>(kioskLatestEventProvider,
        (prev, next) {
      final ev = next.valueOrNull;
      if (ev != null) _handleEvent(ev);
    });

    final bg = switch (_mode) {
      _KioskMode.granted => AppTheme.success,
      _KioskMode.denied => AppTheme.error,
      _ => AppTheme.background,
    };

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: _buildBody(),
        ),
      ),
      // Sai do modo kiosk (no balcão ficaria atrás de um PIN; aqui simples).
      floatingActionButton: _mode == _KioskMode.idle
          ? _KioskDevControls(
              onSimulate: (granted) => _present(_mockEvent(granted)),
              onExit: () => context.go('/admin'),
            )
          : null,
    );
  }

  AccessEventView _mockEvent(bool granted) => AccessEventView(
        id: 'mock-${DateTime.now().microsecondsSinceEpoch}',
        studentId: ref.read(currentUserProvider).valueOrNull?.studentId,
        outcome: granted ? 'attendance_granted' : 'denied_overdue',
        granted: granted,
        displayMsg: granted ? null : 'Financeiro pendente — procure a recepção',
        receivedAt: DateTime.now(),
      );

  Widget _buildBody() {
    switch (_mode) {
      case _KioskMode.idle:
        return _IdleView(clock: _clock, key: const ValueKey('idle'));
      case _KioskMode.processing:
        return const Center(
          key: ValueKey('processing'),
          child: CircularProgressIndicator(),
        );
      case _KioskMode.granted:
        return _ResultView(
          key: const ValueKey('granted'),
          granted: true,
          student: _student,
          message: _message ?? '',
          alreadyToday: _alreadyToday,
        );
      case _KioskMode.denied:
        return _ResultView(
          key: const ValueKey('denied'),
          granted: false,
          student: _student,
          message: _message ?? '',
          alreadyToday: false,
        );
    }
  }
}

class _IdleView extends StatelessWidget {
  final DateTime clock;
  const _IdleView({required this.clock, super.key});

  @override
  Widget build(BuildContext context) {
    final hh = clock.hour.toString().padLeft(2, '0');
    final mm = clock.minute.toString().padLeft(2, '0');
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('$hh:$mm',
              style: AppTheme.displayLarge.copyWith(
                fontSize: 96,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              )),
          const SizedBox(height: 16),
          Icon(LucideIcons.scanFace, size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          Text('Aproxime-se da catraca',
              style: AppTheme.headlineLarge
                  .copyWith(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final bool granted;
  final Student? student;
  final String message;
  final bool alreadyToday;

  const _ResultView({
    required this.granted,
    required this.student,
    required this.message,
    required this.alreadyToday,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    const onColor = Colors.white;
    final sport = student?.getPrimarySport();
    final grade = (student != null && sport != null)
        ? student!.getGrade(sport)?.currentGrade
        : null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Foto do aluno (quando concedido e há foto).
            if (granted && student != null)
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: onColor.withValues(alpha: 0.2),
                  border: Border.all(color: onColor, width: 4),
                ),
                clipBehavior: Clip.antiAlias,
                child: (student!.photoUrl ?? '').isEmpty
                    ? Center(
                        child: Text(
                          student!.fullName.isNotEmpty
                              ? student!.fullName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.w800,
                              color: onColor),
                        ),
                      )
                    : AppCachedImage(
                        imageUrl: student!.photoUrl!,
                        width: 180,
                        height: 180,
                        fit: BoxFit.cover,
                      ),
              )
            else
              Icon(granted ? LucideIcons.checkCircle2 : LucideIcons.xCircle,
                  size: 160, color: onColor),
            const SizedBox(height: 28),
            Icon(granted ? LucideIcons.check : LucideIcons.x,
                size: 56, color: onColor),
            const SizedBox(height: 12),
            // Nome (quando há aluno) + mensagem.
            if (student != null)
              Text(
                student!.fullName,
                textAlign: TextAlign.center,
                style: AppTheme.displayMedium
                    .copyWith(color: onColor, fontWeight: FontWeight.w800),
              ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.headlineLarge.copyWith(color: onColor),
            ),
            // Faixa (display grande) quando concedido.
            if (granted && sport != null && grade != null) ...[
              const SizedBox(height: 24),
              GradeDisplayLarge(sportId: sport, grade: grade),
            ],
          ],
        ),
      ),
    );
  }
}

/// Controles de balcão/dev visíveis só no IDLE: simular giro (teste sem
/// hardware) e sair do modo kiosk. Em produção o "sair" ficaria atrás de PIN.
class _KioskDevControls extends StatelessWidget {
  final void Function(bool granted) onSimulate;
  final VoidCallback onExit;

  const _KioskDevControls({required this.onSimulate, required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (kDebugMode) ...[
          FloatingActionButton.extended(
            heroTag: 'kioskSimOk',
            backgroundColor: AppTheme.success,
            onPressed: () => onSimulate(true),
            icon: const Icon(LucideIcons.check),
            label: const Text('Simular OK'),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'kioskSimDeny',
            backgroundColor: AppTheme.error,
            onPressed: () => onSimulate(false),
            icon: const Icon(LucideIcons.x),
            label: const Text('Simular bloqueio'),
          ),
          const SizedBox(width: 12),
        ],
        FloatingActionButton.small(
          heroTag: 'kioskExit',
          onPressed: onExit,
          child: const Icon(LucideIcons.logOut),
        ),
      ],
    );
  }
}
