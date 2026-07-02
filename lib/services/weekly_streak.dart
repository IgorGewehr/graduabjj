/// STREAK SEMANAL do LUTADOR — modelo confirmado pelo dono.
///
/// Uma SEMANA (ISO, seg→dom, identificada pela SEGUNDA) "conta" quando teve
/// pelo menos 1 TREINO nela — treino = presença verificada (`attendance`) OU
/// self-log (`users/{uid}/training_logs`), fundidos e deduplicados por DIA.
///
/// - [WeeklyStreakResult.currentWeeks] = nº de semanas que CONTARAM (semanas
///   TREINADAS) no run que termina na semana ATUAL. GRACE: a semana atual SEM
///   treino ainda NÃO quebra (fica pendente até domingo); a quebra só ocorre
///   quando uma semana PASSADA fecha com zero treino E sem freeze.
/// - [WeeklyStreakResult.recordWeeks] = maior run de semanas-com-treino já
///   registrado.
/// - [WeeklyStreakResult.weeks] = os últimos N status semanais (mais antigo →
///   atual), para o strip da UI.
///
/// FREEZE / MODO LESÃO (§4.3 + §6.4 da pesquisa de retenção): uma semana
/// presente em `frozenWeeks` (chaves 'YYYY-Www' de `users/{uid}.streakFreezes`)
/// e SEM treino vira PONTE — não conta como semana treinada (nem no streak
/// atual nem no recorde), mas NÃO QUEBRA a continuidade. "Streak de 4 semanas"
/// continua significando 4 semanas TREINADAS. TREINO VENCE: semana congelada
/// que teve treino conta normalmente (congelar nunca apaga treino real).
///
/// A função é PURA: recebe um `Set<DateTime>` de DIAS-TREINADOS + o "agora" e
/// não toca em I/O. A fusão attendance+self-log (e o filtro por esporte) é
/// responsabilidade do chamador — aqui só chega o conjunto de dias. As
/// `frozenWeeks` também chegam prontas (o dono é `StreakFreezeService`).
library;

/// Status de UMA semana no strip. [weekStart] é a SEGUNDA (00:00 UTC) que
/// identifica a semana; [trained] indica se teve >=1 treino; [isCurrent] marca
/// a semana em curso (a que ganha o GRACE); [frozen] marca semana congelada
/// (modo lesão/descanso) — quando `trained` também é true, o treino vence.
class WeekCell {
  const WeekCell({
    required this.weekStart,
    required this.trained,
    required this.isCurrent,
    this.frozen = false,
  });

  /// Segunda-feira (00:00 UTC) que identifica a semana.
  final DateTime weekStart;

  /// A semana teve pelo menos 1 treino (presença ou self-log).
  final bool trained;

  /// É a semana ATUAL (pendente enquanto sem treino — não quebra o streak).
  final bool isCurrent;

  /// A semana está CONGELADA (users/{uid}.streakFreezes — 'lesao'|'descanso').
  /// Sem treino = PONTE do streak; com treino, [trained] prevalece.
  final bool frozen;
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

/// Chave ISO-8601 'YYYY-Www' (ISO week-year; segunda = início) do dia
/// calendário de [date]. MESMO formato/algoritmo do backend
/// (`functions/push_functions.js:isoWeekKey`) e de `Student._isoWeekKey`
/// (retention.weeklyBuckets): a quinta-feira da semana determina o ano ISO.
/// É a chave usada em `users/{uid}.streakFreezes`.
String isoWeekKeyOf(DateTime date) {
  final thursday = _mondayUtc(date).add(const Duration(days: 3));
  final jan1 = DateTime.utc(thursday.year, 1, 1);
  final dayOfYear = thursday.difference(jan1).inDays; // 0-based
  final weekNum = dayOfYear ~/ 7 + 1;
  return '${thursday.year}-W${weekNum.toString().padLeft(2, '0')}';
}

/// Inverso de [isoWeekKeyOf]: SEGUNDA (UTC 00:00) da semana ISO 'YYYY-Www'.
/// ISO 8601: 4 de janeiro está SEMPRE na semana 1 do seu ano ISO. Retorna
/// `null` para chave malformada (dado sujo no mapa não derruba o cálculo).
DateTime? mondayUtcOfIsoWeekKey(String key) {
  final m = RegExp(r'^(\d{4})-W(\d{2})$').firstMatch(key);
  if (m == null) return null;
  final year = int.parse(m.group(1)!);
  final week = int.parse(m.group(2)!);
  if (week < 1 || week > 53) return null;
  final jan4 = DateTime.utc(year, 1, 4);
  final monday1 = jan4.subtract(Duration(days: jan4.weekday - 1));
  return monday1.add(Duration(days: 7 * (week - 1)));
}

/// true se TODAS as semanas estritamente entre [prev] e [next] (segundas-UTC,
/// prev < next) estão congeladas — o run atravessa o gap como PONTE. Gap de
/// exatamente 1 semana (consecutivas) é trivialmente true.
bool _bridged(DateTime prev, DateTime next, Set<DateTime> frozenMondays) {
  var w = prev.add(const Duration(days: 7));
  while (w.isBefore(next)) {
    if (!frozenMondays.contains(w)) return false;
    w = w.add(const Duration(days: 7));
  }
  return true;
}

/// Calcula o streak SEMANAL a partir dos DIAS-TREINADOS.
///
/// [trainedDays] — dias com treino (qualquer horário; são normalizados a
///   dateOnly/semana internamente). Já devem estar FUNDIDOS (attendance +
///   self-log) e, se for por-esporte, já FILTRADOS por esporte pelo chamador.
/// [now] — o "agora" (local); só o dia calendário importa.
/// [stripLength] — quantas semanas devolver no strip (default 8), terminando na
///   semana atual.
/// [frozenWeeks] — chaves 'YYYY-Www' de `users/{uid}.streakFreezes` (modo
///   lesão/descanso). Semana congelada SEM treino = PONTE: não soma em
///   [WeeklyStreakResult.currentWeeks] nem em recordWeeks, mas não quebra o
///   run. Semana congelada COM treino conta normalmente (treino vence).
///   Chaves malformadas são ignoradas.
WeeklyStreakResult computeWeeklyStreak({
  required Set<DateTime> trainedDays,
  required DateTime now,
  int stripLength = 8,
  Set<String> frozenWeeks = const {},
}) {
  final currentWeek = _mondayUtc(now);

  // Semanas (segunda-UTC) que tiveram >=1 treino.
  final trainedWeeks = <DateTime>{
    for (final d in trainedDays) _mondayUtc(d),
  };

  // Semanas congeladas, como segunda-UTC (chave suja → ignorada).
  final frozenMondays = <DateTime>{};
  for (final k in frozenWeeks) {
    final monday = mondayUtcOfIsoWeekKey(k);
    if (monday != null) frozenMondays.add(monday);
  }

  // ── STREAK ATUAL (GRACE da semana em curso + PONTE de semanas congeladas) ──
  // Caminha da semana atual para trás: semana TREINADA soma; semana CONGELADA
  // sem treino é ponte (não soma, não quebra); a semana ATUAL sem treino e sem
  // freeze é apenas pendente (grace). A primeira semana PASSADA sem treino e
  // sem freeze quebra o run. Termina sempre: os dois sets são finitos.
  int currentWeeks = 0;
  var cursor = currentWeek;
  var isCurrentCursor = true;
  while (true) {
    if (trainedWeeks.contains(cursor)) {
      currentWeeks++;
    } else if (frozenMondays.contains(cursor)) {
      // PONTE — modo lesão/descanso.
    } else if (isCurrentCursor) {
      // GRACE — semana atual pendente até domingo.
    } else {
      break;
    }
    isCurrentCursor = false;
    cursor = cursor.subtract(const Duration(days: 7));
  }

  // ── RECORDE (maior run de semanas TREINADAS; pontes não somam nem quebram) ─
  int recordWeeks = 0;
  if (trainedWeeks.isNotEmpty) {
    final sorted = trainedWeeks.toList()..sort();
    int run = 1;
    recordWeeks = 1;
    for (var i = 1; i < sorted.length; i++) {
      final linked = _bridged(sorted[i - 1], sorted[i], frozenMondays);
      run = linked ? run + 1 : 1;
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
          frozen: frozenMondays.contains(ws),
        );
      }(),
  ];

  return (currentWeeks: currentWeeks, recordWeeks: recordWeeks, weeks: weeks);
}
