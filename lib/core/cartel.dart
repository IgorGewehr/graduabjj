/// Pure, dependency-free aggregation for a fighter's record/cartel (C3).
///
/// No Flutter/Firestore imports so the win/loss math + label stay unit-testable
/// (mirrors `striking_timer.dart`, `class_occurrences.dart`). The Firestore
/// model (`fight_record.dart`) imports these enums so they have a single source.
library;

/// Outcome of a single fight.
enum FightResult { win, loss, draw, nc } // nc = no contest / sem resultado

extension FightResultX on FightResult {
  String get value => name;

  String get label {
    switch (this) {
      case FightResult.win:
        return 'Vitória';
      case FightResult.loss:
        return 'Derrota';
      case FightResult.draw:
        return 'Empate';
      case FightResult.nc:
        return 'Sem resultado';
    }
  }

  /// Short tag for compact UI (V/D/E/NC).
  String get tag {
    switch (this) {
      case FightResult.win:
        return 'V';
      case FightResult.loss:
        return 'D';
      case FightResult.draw:
        return 'E';
      case FightResult.nc:
        return 'NC';
    }
  }

  static FightResult fromString(String? v) =>
      FightResult.values.firstWhere((r) => r.name == v,
          orElse: () => FightResult.win);
}

/// How a fight ended.
enum FightMethod { ko, tko, decision, submission, dq, other }

extension FightMethodX on FightMethod {
  String get value => name;

  String get label {
    switch (this) {
      case FightMethod.ko:
        return 'Nocaute (KO)';
      case FightMethod.tko:
        return 'Nocaute técnico (TKO)';
      case FightMethod.decision:
        return 'Decisão';
      case FightMethod.submission:
        return 'Finalização';
      case FightMethod.dq:
        return 'Desqualificação';
      case FightMethod.other:
        return 'Outro';
    }
  }

  /// KO and TKO both count as a "knockout" for the cartel summary.
  bool get isKnockout => this == FightMethod.ko || this == FightMethod.tko;

  static FightMethod fromString(String? v) =>
      FightMethod.values.firstWhere((m) => m.name == v,
          orElse: () => FightMethod.other);
}

/// Aggregated record. [koWins] and [subWins] are subsets of [wins].
class CartelSummary {
  final int wins;
  final int losses;
  final int draws;
  final int nc;
  final int koWins;
  final int subWins;

  const CartelSummary({
    this.wins = 0,
    this.losses = 0,
    this.draws = 0,
    this.nc = 0,
    this.koWins = 0,
    this.subWins = 0,
  });

  int get total => wins + losses + draws + nc;

  /// "12V-3D-1E", appending NC only when present ("12V-3D-1E-2NC").
  String get record {
    final base = '${wins}V-${losses}D-${draws}E';
    return nc > 0 ? '$base-${nc}NC' : base;
  }
}

/// Folds (result, method) pairs into a [CartelSummary].
CartelSummary summarizeCartel(
    Iterable<({FightResult result, FightMethod method})> fights) {
  var wins = 0, losses = 0, draws = 0, nc = 0, koWins = 0, subWins = 0;
  for (final f in fights) {
    switch (f.result) {
      case FightResult.win:
        wins++;
        if (f.method.isKnockout) koWins++;
        if (f.method == FightMethod.submission) subWins++;
        break;
      case FightResult.loss:
        losses++;
        break;
      case FightResult.draw:
        draws++;
        break;
      case FightResult.nc:
        nc++;
        break;
    }
  }
  return CartelSummary(
    wins: wins,
    losses: losses,
    draws: draws,
    nc: nc,
    koWins: koWins,
    subWins: subWins,
  );
}
