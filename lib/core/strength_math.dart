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

/// Carga (kg) correspondente a [pct]% do [oneRM]. [pct] em 0..100. Entradas
/// inválidas → 0. (E2 — calculadora de 1RM.)
double loadForPercent(double oneRM, num pct) {
  if (oneRM <= 0 || pct <= 0) return 0;
  return oneRM * (pct / 100.0);
}

/// Faixa de reps tipicamente associada a uma intensidade (% do 1RM), só para
/// orientar a tabela. Aproximação comum de força/hipertrofia.
String repHintForPercent(int pct) {
  if (pct >= 95) return '1-2 reps';
  if (pct >= 90) return '2-4 reps';
  if (pct >= 85) return '3-5 reps';
  if (pct >= 80) return '5-7 reps';
  if (pct >= 75) return '7-9 reps';
  if (pct >= 70) return '10-12 reps';
  if (pct >= 65) return '12-15 reps';
  return '15+ reps';
}

/// Tabela de %1RM (de 100% até [minPct], decrescendo de [step]) com a carga
/// correspondente — usada na calculadora. Lista vazia se [oneRM] <= 0.
List<({int pct, double load, String repHint})> percentTable(
  double oneRM, {
  int step = 5,
  int minPct = 50,
}) {
  if (oneRM <= 0 || step <= 0) return const [];
  final out = <({int pct, double load, String repHint})>[];
  for (var p = 100; p >= minPct; p -= step) {
    out.add((pct: p, load: loadForPercent(oneRM, p), repHint: repHintForPercent(p)));
  }
  return out;
}
