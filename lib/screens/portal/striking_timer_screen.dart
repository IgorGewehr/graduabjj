import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/striking_timer.dart';
import '../../core/theme.dart';

/// Full-screen round timer (C1). Pure UI: no backend. Configurable rounds /
/// round duration / rest, with haptic + system-sound cues. On finish it offers
/// to log the session (pops with the preset so the hub pre-fills the sheet).
class StrikingTimerScreen extends StatefulWidget {
  const StrikingTimerScreen({super.key});

  @override
  State<StrikingTimerScreen> createState() => _StrikingTimerScreenState();
}

class _StrikingTimerScreenState extends State<StrikingTimerScreen> {
  int _rounds = 3;
  int _roundSec = 180; // 3 min
  int _restSec = 60; // 1 min

  List<TimerPhase> _phases = const [];
  int _index = 0;
  int _remaining = 0;
  bool _running = false;
  bool _finished = false;
  Timer? _ticker;

  TimerPhase? get _phase =>
      (_index >= 0 && _index < _phases.length) ? _phases[_index] : null;
  bool get _started => _phases.isNotEmpty && !_finished;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    final phases = buildPhases(
        rounds: _rounds, roundSec: _roundSec, restSec: _restSec);
    if (phases.isEmpty) return;
    setState(() {
      _phases = phases;
      _index = 0;
      _remaining = phases.first.seconds;
      _finished = false;
      _running = true;
    });
    HapticFeedback.mediumImpact();
    _tickLoop();
  }

  void _tickLoop() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_running) return;
      setState(() {
        _remaining--;
        if (_remaining == 10 || _remaining == 3) {
          HapticFeedback.lightImpact();
          SystemSound.play(SystemSoundType.click);
        }
        if (_remaining <= 0) {
          _advance();
        }
      });
    });
  }

  void _advance() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    if (_index + 1 >= _phases.length) {
      _running = false;
      _finished = true;
      _ticker?.cancel();
      return;
    }
    _index++;
    _remaining = _phases[_index].seconds;
  }

  void _togglePause() {
    setState(() => _running = !_running);
    HapticFeedback.selectionClick();
  }

  void _reset() {
    _ticker?.cancel();
    setState(() {
      _phases = const [];
      _index = 0;
      _remaining = 0;
      _running = false;
      _finished = false;
    });
  }

  void _jump(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= _phases.length) return;
    setState(() {
      _index = next;
      _remaining = _phases[next].seconds;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isRest = _phase?.isRound == false;
    final bg = _finished
        ? AppTheme.success
        : !_started
            ? AppTheme.surface
            : (isRest ? AppTheme.warning : AppTheme.primary);
    final onBg = !_started ? AppTheme.textPrimary : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: onBg,
        title: const Text('Timer de rounds'),
      ),
      body: SafeArea(
        child: _started
            ? _runningView(onBg, isRest)
            : _finished
                ? _finishedView()
                : _configView(),
      ),
    );
  }

  // ---- Idle: configure presets ---------------------------------------------
  Widget _configView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Text('Configurar rounds',
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 24),
          _stepperRow('Rounds', '$_rounds', () => _bump(() => _rounds--, _rounds > 1),
              () => _bump(() => _rounds++, _rounds < 20)),
          _stepperRow('Duração do round', fmtMmss(_roundSec),
              () => _bump(() => _roundSec -= 15, _roundSec > 15),
              () => _bump(() => _roundSec += 15, _roundSec < 900)),
          _stepperRow('Descanso', fmtMmss(_restSec),
              () => _bump(() => _restSec -= 15, _restSec > 0),
              () => _bump(() => _restSec += 15, _restSec < 600)),
          const SizedBox(height: 16),
          Text('Total: ${fmtMmss(totalSessionSeconds(rounds: _rounds, roundSec: _roundSec, restSec: _restSec))}',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _start,
              icon: const Icon(LucideIcons.play),
              label: const Text('Iniciar'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ),
        ],
      ),
    );
  }

  void _bump(VoidCallback change, bool allowed) {
    if (!allowed) return;
    setState(change);
    HapticFeedback.selectionClick();
  }

  Widget _stepperRow(
      String label, String value, VoidCallback onMinus, VoidCallback onPlus) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTheme.bodyLarge)),
          IconButton.filledTonal(
              onPressed: onMinus, icon: const Icon(LucideIcons.minus)),
          SizedBox(
            width: 84,
            child: Text(value,
                textAlign: TextAlign.center,
                style: AppTheme.titleMedium
                    .copyWith(fontWeight: FontWeight.w700)),
          ),
          IconButton.filledTonal(
              onPressed: onPlus, icon: const Icon(LucideIcons.plus)),
        ],
      ),
    );
  }

  // ---- Running --------------------------------------------------------------
  Widget _runningView(Color onBg, bool isRest) {
    final phase = _phase!;
    final total = phase.seconds == 0 ? 1 : phase.seconds;
    final progress = 1 - (_remaining / total);
    final roundCount = _phases.where((p) => p.isRound).length;

    return Column(
      children: [
        const Spacer(),
        Text(isRest ? 'DESCANSO' : 'ROUND ${phase.round}/$roundCount',
            style: AppTheme.titleLarge
                .copyWith(color: onBg, fontWeight: FontWeight.w800, letterSpacing: 2)),
        const SizedBox(height: 16),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 220,
              height: 220,
              child: CircularProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                strokeWidth: 10,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation(onBg),
              ),
            ),
            Text(fmtMmss(_remaining),
                style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                    color: onBg,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _circleBtn(LucideIcons.skipBack, onBg, () => _jump(-1)),
            _circleBtn(_running ? LucideIcons.pause : LucideIcons.play, onBg,
                _togglePause,
                big: true),
            _circleBtn(LucideIcons.skipForward, onBg, () => _jump(1)),
          ],
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: _reset,
          icon: Icon(LucideIcons.rotateCcw, color: onBg, size: 18),
          label: Text('Reiniciar', style: TextStyle(color: onBg)),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _circleBtn(IconData icon, Color color, VoidCallback onTap,
      {bool big = false}) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        padding: EdgeInsets.all(big ? 22 : 16),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        child: Icon(icon, color: color, size: big ? 40 : 26),
      ),
    );
  }

  // ---- Finished -------------------------------------------------------------
  Widget _finishedView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.checkCircle, color: Colors.white, size: 72),
            const SizedBox(height: 16),
            Text('Treino concluído!',
                style: AppTheme.titleLarge.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                '$_rounds rounds · ${fmtMmss(_roundSec)} cada',
                style: AppTheme.bodyLarge.copyWith(color: Colors.white70)),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.success,
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                onPressed: () => Navigator.pop(context, {
                  'rounds': _rounds,
                  'roundDurationSec': _roundSec,
                  'totalMinutes':
                      totalRoundMinutes(rounds: _rounds, roundSec: _roundSec),
                }),
                icon: const Icon(LucideIcons.clipboardList),
                label: const Text('Registrar sessão'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
