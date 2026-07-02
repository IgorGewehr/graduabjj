/// STREAK SEMANAL do LUTADOR — modelo confirmado pelo dono.
///
/// Uma SEMANA (ISO, seg→dom, identificada pela SEGUNDA) "conta" quando teve
/// pelo menos 1 TREINO nela — treino = presença verificada (`attendance`) OU
/// self-log (`users/{uid}/training_logs`), fundidos e deduplicados por DIA.
///
/// - [WeeklyStreakResult.currentWeeks] = nº de semanas consecutivas que
///   contaram, terminando na semana ATUAL. GRACE: a semana atual SEM treino
///   ainda NÃO quebra (fica pendente até domingo); a quebra só ocorre quando
///   uma semana PASSADA fecha com zero treino.
/// - [WeeklyStreakResult.recordWeeks] = maior run de semanas-com-treino já
///   registrado.
/// - [WeeklyStreakResult.weeks] = os últimos N status semanais (mais antigo →
///   atual), para o strip da UI.
///
/// A função é PURA: recebe um `Set<DateTime>` de DIAS-TREINADOS + o "agora" e
/// não toca em I/O. A fusão attendance+self-log (e o filtro por esporte) é
/// responsabilidade do chamador — aqui só chega o conjunto de dias.
library;

/// Status de UMA semana no strip. [weekStart] é a SEGUNDA (00:00 UTC) que
/// identifica a semana; [trained] indica se teve >=1 treino; [isCurrent] marca
/// a semana em curso (a que ganha o GRACE).
class WeekCell {
  const WeekCell({
    required this.weekStart,
    required this.trained,
    required this.isCurrent,
  });

  /// Segunda-feira (00:00 UTC) que identifica a semana.
  final DateTime weekStart;

  /// A semana teve pelo menos 1 treino (presença ou self-log).
  final bool trained;

  /// É a semana ATUAL (pendente enquanto sem treino — não quebra o streak).
  final bool isCurrent;
}

/// Resultado do cálculo semanal. Record-shape amigável para providers.
typedef WeeklyStreakResult = ({
  int currentWeeks,
  int recordWeeks,
  List<WeekCell> weeks,
});

/// Normaliza qualquer data para a SEGUNDA da sua semana ISO, em UTC 00:00.
/// Usar UTC internamente torna a aritmética de semanas imune a DST (subtrair
/// 7 dias é sempre exato); o dia CALENDÁRIO local é preservado ao construir a
/// data a partir de `year/month/day`.
DateTime _mondayUtc(DateTime d) {
  final day = DateTime.utc(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - 1)); // weekday: Seg=1..Dom=7
}

/// Calcula o streak SEMANAL a partir dos DIAS-TREINADOS.
///
/// [trainedDays] — dias com treino (qualquer horário; são normalizados a
///   dateOnly/semana internamente). Já devem estar FUNDIDOS (attendance +
///   self-log) e, se for por-esporte, já FILTRADOS por esporte pelo chamador.
/// [now] — o "agora" (local); só o dia calendário importa.
/// [stripLength] — quantas semanas devolver no strip (default 8), terminando na
///   semana atual.
WeeklyStreakResult computeWeeklyStreak({
  required Set<DateTime> trainedDays,
  required DateTime now,
  int stripLength = 8,
}) {
  final currentWeek = _mondayUtc(now);

  // Semanas (segunda-UTC) que tiveram >=1 treino.
  final trainedWeeks = <DateTime>{
    for (final d in trainedDays) _mondayUtc(d),
  };

  // ── STREAK ATUAL (com GRACE da semana em curso) ──────────────────────────
  // Se a semana atual TEM treino, ela entra no run. Se NÃO tem, ela é apenas
  // pendente (não quebra): o run começa a ser contado a partir da semana
  // passada. Caminhamos para trás enquanto as semanas contarem.
  int currentWeeks = 0;
  var cursor = trainedWeeks.contains(currentWeek)
      ? currentWeek
      : currentWeek.subtract(const Duration(days: 7));
  while (trainedWeeks.contains(cursor)) {
    currentWeeks++;
    cursor = cursor.subtract(const Duration(days: 7));
  }

  // ── RECORDE (maior run de semanas consecutivas em todo o histórico) ───────
  int recordWeeks = 0;
  if (trainedWeeks.isNotEmpty) {
    final sorted = trainedWeeks.toList()..sort();
    int run = 1;
    recordWeeks = 1;
    for (var i = 1; i < sorted.length; i++) {
      final consecutive = sorted[i].difference(sorted[i - 1]).inDays == 7;
      run = consecutive ? run + 1 : 1;
      if (run > recordWeeks) recordWeeks = run;
    }
  }
  if (currentWeeks > recordWeeks) recordWeeks = currentWeeks;

  // ── STRIP (últimas [stripLength] semanas, antiga → atual) ─────────────────
  final weeks = <WeekCell>[
    for (var i = stripLength - 1; i >= 0; i--)
      () {
        final ws = currentWeek.subtract(Duration(days: 7 * i));
        return WeekCell(
          weekStart: ws,
          trained: trainedWeeks.contains(ws),
          isCurrent: ws == currentWeek,
        );
      }(),
  ];

  return (currentWeeks: currentWeeks, recordWeeks: recordWeeks, weeks: weeks);
}
