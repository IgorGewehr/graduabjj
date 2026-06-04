// Pure strength math (sem deps de Flutter/Firestore, testável). PR e volume a
// partir das séries registradas. Uma "série" é (reps, load[kg]).

typedef SetTuple = ({int reps, double load});

/// 1RM estimado pela fórmula de **Epley**: load × (1 + reps/30).
/// reps == 1 → o próprio load. Entradas inválidas → 0.
double epley1RM(double load, int reps) {
  if (load <= 0 || reps <= 0) return 0;
  if (reps == 1) return load;
  return load * (1 + reps / 30.0);
}

/// Maior carga (kg) entre as séries. 0 se vazio.
double bestLoad(Iterable<SetTuple> sets) {
  double best = 0;
  for (final s in sets) {
    if (s.load > best) best = s.load;
  }
  return best;
}

/// Maior 1RM estimado (Epley) entre as séries. 0 se vazio.
double best1RM(Iterable<SetTuple> sets) {
  double best = 0;
  for (final s in sets) {
    final e = epley1RM(s.load, s.reps);
    if (e > best) best = e;
  }
  return best;
}

/// Volume total da sessão = Σ (reps × load).
double sessionVolume(Iterable<SetTuple> sets) {
  double v = 0;
  for (final s in sets) {
    if (s.reps > 0 && s.load > 0) v += s.reps * s.load;
  }
  return v;
}
