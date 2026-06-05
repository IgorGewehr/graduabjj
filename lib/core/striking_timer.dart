/// Pure, dependency-free helpers for the striking round timer (C1).
///
/// No Flutter imports so the phase-sequence and time-format math stays
/// unit-testable (mirrors `class_occurrences.dart`, `strength_math.dart`).
library;

enum TimerPhaseKind { round, rest }

/// One segment of a session: a fighting round or a rest interval.
class TimerPhase {
  final TimerPhaseKind kind;

  /// 1-based round number. For a [rest] phase, the round it follows.
  final int round;
  final int seconds;

  const TimerPhase({
    required this.kind,
    required this.round,
    required this.seconds,
  });

  bool get isRound => kind == TimerPhaseKind.round;
}

/// "MM:SS" for a non-negative second count. Minutes are not capped at 59
/// (90s -> "01:30", 3700s -> "61:40").
String fmtMmss(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final m = s ~/ 60;
  final sec = s % 60;
  return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
}

/// Builds the round/rest sequence. No rest after the final round, and rest
/// phases are skipped entirely when [restSec] <= 0. Returns empty when inputs
/// are non-positive.
List<TimerPhase> buildPhases({
  required int rounds,
  required int roundSec,
  required int restSec,
}) {
  if (rounds <= 0 || roundSec <= 0) return const [];
  final out = <TimerPhase>[];
  for (var i = 1; i <= rounds; i++) {
    out.add(TimerPhase(kind: TimerPhaseKind.round, round: i, seconds: roundSec));
    if (i < rounds && restSec > 0) {
      out.add(TimerPhase(kind: TimerPhaseKind.rest, round: i, seconds: restSec));
    }
  }
  return out;
}

/// Total wall-clock seconds of the whole session (rounds + rests).
int totalSessionSeconds({
  required int rounds,
  required int roundSec,
  required int restSec,
}) =>
    buildPhases(rounds: rounds, roundSec: roundSec, restSec: restSec)
        .fold(0, (sum, p) => sum + p.seconds);

/// Total active fighting minutes (rounds only), rounded down. Used to
/// pre-fill the session log from the timer.
int totalRoundMinutes({required int rounds, required int roundSec}) =>
    (rounds <= 0 || roundSec <= 0) ? 0 : (rounds * roundSec) ~/ 60;
