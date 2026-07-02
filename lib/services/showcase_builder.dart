import '../models/fighter_profile.dart';
import '../models/self_record.dart';
import 'achievement_service.dart';
import 'attendance_service.dart';
import 'belt_progression_service.dart';

/// Resultado puro do cálculo da vitrine do lutador (lado do DONO). Carrega os
/// blobs já derivados (graduações com esforço, competições com a estrada,
/// cartel de medalhas) + os totais/streak. O DONO materializa isto em
/// `fighterProfiles/{uid}`; o VISITANTE lê pronto (1 read).
class ShowcaseData {
  final List<FighterGraduation> graduations;
  final List<FighterCompetitionMark> competitions;
  final MedalCount medals;
  final int currentStreak;
  final int recordStreak;
  final int totalTrainings;
  final DateTime firstTrainingDate;

  /// Data da presença MAIS RECENTE (max de attendance.date). `null` quando o
  /// dono não tem nenhuma presença registrada.
  final DateTime? lastTrainingDate;

  const ShowcaseData({
    required this.graduations,
    required this.competitions,
    required this.medals,
    required this.currentStreak,
    required this.recordStreak,
    required this.totalTrainings,
    required this.firstTrainingDate,
    this.lastTrainingDate,
  });

  /// Hash leve para idempotência do write (só re-grava a vitrine quando muda).
  /// Captura os sinais que alteram a vitrine sem serializar os blobs inteiros.
  String get hash =>
      '$totalTrainings|${graduations.length}|${competitions.length}|'
      '$currentStreak|$recordStreak|${medals.total}';
}

/// Serviço PURO (sem I/O) que computa a vitrine a partir de dados que o DONO já
/// carregou (cost-safe: nenhuma query nova é feita aqui — quem chama passa as
/// listas). Algoritmos: §2 da SPEC.
///
/// - Graduações: delta consecutivo de `baselineCount`/`promotionDate` por
///   esporte (esforço por bloco), com clamp ≥0 contra reversões/correções.
/// - Competições: contagem de presenças no intervalo entre marcos (binary
///   search sobre as datas) + meses + nº de progressões no intervalo.
class ShowcaseBuilder {
  ShowcaseBuilder._();

  /// Meses INTEIROS completos entre [a] e [b] (b >= a). 0 se b for antes de a.
  static int monthsBetween(DateTime a, DateTime b) {
    if (!b.isAfter(a)) return 0;
    var months = (b.year - a.year) * 12 + (b.month - a.month);
    if (b.day < a.day) months -= 1;
    return months < 0 ? 0 : months;
  }

  /// Computa a vitrine. Todas as listas são do PRÓPRIO academyId do dono.
  ///
  /// [progressions] — `BeltProgressionService.getByStudent` (qualquer ordem).
  /// [attendance]   — `AttendanceService.getByStudent(limit: alto)`.
  /// [competitions] — `AchievementService.getCompetitions` (type=competition).
  /// [selfGraduations] — `SelfRecordsService.listGraduations` (auto-declaradas).
  /// [selfCompetitions] — `SelfRecordsService.listCompetitions` (auto/externas).
  /// [streak]       — streak SEMANAL já POR ESPORTE (esporte PRINCIPAL), fundido
  ///   presença+self-log e computado via `computeWeeklyStreak`. `currentWeeks` =
  ///   semanas consecutivas correntes (com grace); `recordWeeks` = recorde.
  /// [startDate]    — `student.startDate` (âncora do 1º bloco).
  /// [totalTrainings] — `student.totalAttendanceCount`.
  /// [useWeights]   — academia usa class weights → unidade vira "pontos".
  static ShowcaseData build({
    required List<BeltProgression> progressions,
    required List<Attendance> attendance,
    required List<Achievement> competitions,
    required ({int currentWeeks, int recordWeeks}) streak,
    required DateTime startDate,
    required int totalTrainings,
    List<SelfGraduation> selfGraduations = const [],
    List<SelfCompetition> selfCompetitions = const [],
    bool useWeights = false,
    // Baseline SEM DATA informado pelo mestre (student.initialAttendanceCount):
    // treinos anteriores ao app. Pertence ao esporte principal/legado
    // [baselineSport]. Usado para o cumulativo ABSOLUTO de competições e
    // graduações auto-declaradas — quando o marco é ANTERIOR ao histórico
    // in-app, a contagem é INDETERMINÁVEL e fica null (a UI omite; regra do
    // produto: nunca mostrar um número que pode estar errado).
    int initialCount = 0,
    String baselineSport = 'bjj',
  }) {
    // Dias de presença POR ESPORTE (legado sem sport = 'bjj'), asc, p/ countAt.
    // Base única para o cumulativo/esforço por-esporte de graduações e
    // competições (verified + auto), substituindo a contagem global anterior.
    final attBySport = <String, List<DateTime>>{};
    for (final a in attendance) {
      attBySport.putIfAbsent(a.sport ?? 'bjj', () => []).add(a.date);
    }
    for (final list in attBySport.values) {
      list.sort((a, b) => a.compareTo(b));
    }

    // Presença mais recente entre TODOS os esportes (max das datas; null se
    // não há nenhuma presença). Cada lista já está asc, então o último de cada
    // é o max do esporte.
    DateTime? lastTrainingDate;
    for (final list in attBySport.values) {
      if (list.isEmpty) continue;
      final last = list.last;
      if (lastTrainingDate == null || last.isAfter(lastTrainingDate)) {
        lastTrainingDate = last;
      }
    }

    final graduations = _buildGraduations(
      progressions: progressions,
      selfGraduations: selfGraduations,
      attBySport: attBySport,
      startDate: startDate,
      useWeights: useWeights,
      initialCount: initialCount,
      baselineSport: baselineSport,
    );
    final comps = _buildCompetitions(
      competitions: competitions,
      selfCompetitions: selfCompetitions,
      attBySport: attBySport,
      progressions: progressions,
      startDate: startDate,
      initialCount: initialCount,
      baselineSport: baselineSport,
    );
    final medals = _buildMedals(competitions);

    return ShowcaseData(
      graduations: graduations,
      competitions: comps,
      medals: medals,
      currentStreak: streak.currentWeeks,
      recordStreak: streak.recordWeeks,
      totalTrainings: totalTrainings,
      firstTrainingDate: startDate,
      lastTrainingDate: lastTrainingDate,
    );
  }

  // ── §2.1 Graduações (MERGE verified + auto, por esporte) ─────────────────
  // Verified (`beltProgressions`, = TETO) preserva o cálculo histórico
  // (delta de `baselineCount`, unidade "pontos" quando ponderado). Auto
  // (`selfGraduations`, declarado pelo aluno) deriva o esforço da presença
  // POR ESPORTE (countAt). Cada marco carrega seu `source`; a lista final é
  // mesclada e ordenada por data.
  static List<FighterGraduation> _buildGraduations({
    required List<BeltProgression> progressions,
    required List<SelfGraduation> selfGraduations,
    required Map<String, List<DateTime>> attBySport,
    required DateTime startDate,
    required bool useWeights,
    int initialCount = 0,
    String baselineSport = 'bjj',
  }) {
    final out = <FighterGraduation>[];

    // Chaves dos graus VERIFIED (esporte+faixa+graus). Quando um AUTO repete o
    // MESMO grau de um VERIFIED, o verified vence e o auto é descartado (evita
    // marco duplicado na timeline + esforço contado em duas bases).
    final verifiedKeys = <String>{};

    // ── Verified: agrupa por esporte (legado sem sport = 'bjj'), asc. ──
    final bySport = <String, List<BeltProgression>>{};
    for (final p in progressions) {
      bySport.putIfAbsent(p.sport ?? 'bjj', () => []).add(p);
    }
    for (final entry in bySport.entries) {
      final asc = [...entry.value]
        ..sort((a, b) => a.promotionDate.compareTo(b.promotionDate));
      var prevBaseline = 0;
      var prevDate = startDate;
      for (final p in asc) {
        final effort = (p.baselineCount - prevBaseline).clamp(0, 1 << 31).toInt();
        final months = monthsBetween(prevDate, p.promotionDate);
        out.add(FighterGraduation(
          sport: entry.key,
          belt: p.newBelt,
          stripes: p.newStripes,
          isBeltChange: p.isBeltChange,
          date: p.promotionDate,
          trainingsToReach: effort,
          monthsToReach: months,
          cumulativeTrainings: p.baselineCount,
          weighted: useWeights && p.effectiveCountAtPromotion != null,
          source: 'verified',
        ));
        verifiedKeys.add('${entry.key}|${p.newBelt}|${p.newStripes}');
        prevBaseline = p.baselineCount;
        prevDate = p.promotionDate;
      }
    }

    // ── Auto (self): agrupa por esporte, asc; esforço = presença POR ESPORTE. ──
    final selfBySport = <String, List<SelfGraduation>>{};
    for (final g in selfGraduations) {
      selfBySport.putIfAbsent(g.sport, () => []).add(g);
    }
    for (final entry in selfBySport.entries) {
      final attDays = attBySport[entry.key] ?? const <DateTime>[];
      // Baseline do mestre só se aplica ao esporte principal/legado.
      final effInitial = entry.key == baselineSport ? initialCount : 0;
      final asc = [...entry.value]..sort((a, b) => a.date.compareTo(b.date));
      int? prevCount = 0; // no startDate o aluno tinha 0 treinos, por definição
      var prevDate = startDate;
      for (final g in asc) {
        final cum = _cumAt(attDays, g.date, effInitial);
        // Verified vence: se já existe o MESMO grau verificado, pula o auto
        // duplicado (mas mantém o encadeamento de esforço/datas intacto).
        if (!verifiedKeys.contains('${entry.key}|${g.grade}|${g.stripes}')) {
          out.add(FighterGraduation(
            sport: entry.key,
            belt: g.grade,
            stripes: g.stripes,
            // Sem evento de troca explícito no auto-declarado: tratamos faixa
            // nova (0 graus) como troca de faixa para destaque na timeline.
            isBeltChange: g.stripes == 0,
            date: g.date,
            // null quando qualquer ponta do intervalo é indeterminável.
            trainingsToReach: (cum != null && prevCount != null)
                ? (cum - prevCount).clamp(0, 1 << 31).toInt()
                : null,
            monthsToReach: monthsBetween(prevDate, g.date),
            cumulativeTrainings: cum,
            weighted: false,
            source: 'auto',
          ));
        }
        prevCount = cum;
        prevDate = g.date;
      }
    }

    // Desc por data (mais recente primeiro) para exibição.
    out.sort((a, b) => b.date.compareTo(a.date));
    return out;
  }

  // ── §2.2 Competições (MERGE verified + auto, a estrada POR ESPORTE) ───────
  // A "estrada" entre marcos (treinos/meses/graus) encadeia POR ESPORTE: o
  // cumulativo usa a presença daquele esporte (countAt) e os graus contam só
  // progressões do mesmo esporte. Verified vêm de `achievements`; auto de
  // `selfCompetitions` (externas/auto-declaradas), cada marco com seu `source`.
  static List<FighterCompetitionMark> _buildCompetitions({
    required List<Achievement> competitions,
    required List<SelfCompetition> selfCompetitions,
    required Map<String, List<DateTime>> attBySport,
    required List<BeltProgression> progressions,
    required DateTime startDate,
    int initialCount = 0,
    String baselineSport = 'bjj',
  }) {
    if (competitions.isEmpty && selfCompetitions.isEmpty) return const [];

    // Chave de evento p/ dedup verified↔auto: esporte + nome (normalizado) +
    // dia (y-m-d). Quando um AUTO repete o MESMO evento de um VERIFIED, o
    // verified vence e o auto é descartado (evita marco/esforço duplicados).
    String compKey(String sport, String name, DateTime date) =>
        '$sport|${name.trim().toLowerCase()}|${date.year}-${date.month}-${date.day}';

    // Evento de competição normalizado (verified | auto), agrupável por esporte.
    final bySport = <String, List<_CompEvent>>{};
    final verifiedCompKeys = <String>{};
    for (final c in competitions) {
      final sport = c.sport ?? 'bjj';
      final name = (c.competitionName?.trim().isNotEmpty ?? false)
          ? c.competitionName!
          : c.title;
      bySport.putIfAbsent(sport, () => []).add(_CompEvent(
            name: name,
            date: c.date,
            position: c.position?.value ?? 'participant',
            sport: sport,
            source: 'verified',
          ));
      verifiedCompKeys.add(compKey(sport, name, c.date));
    }
    for (final c in selfCompetitions) {
      if (verifiedCompKeys.contains(compKey(c.sport, c.name, c.date))) continue;
      bySport.putIfAbsent(c.sport, () => []).add(_CompEvent(
            name: c.name,
            date: c.date,
            position: c.placement ?? 'participant',
            sport: c.sport,
            source: 'auto',
          ));
    }

    final out = <FighterCompetitionMark>[];
    for (final entry in bySport.entries) {
      final attDays = attBySport[entry.key] ?? const <DateTime>[];
      // Baseline do mestre só se aplica ao esporte principal/legado.
      final effInitial = entry.key == baselineSport ? initialCount : 0;
      final compsAsc = [...entry.value]
        ..sort((a, b) => a.date.compareTo(b.date));
      var prevDate = startDate;
      int? prevCount = 0; // no startDate o aluno tinha 0 treinos, por definição
      for (final c in compsAsc) {
        final cum = _cumAt(attDays, c.date, effInitial);
        final grades = progressions
            .where((p) =>
                (p.sport ?? 'bjj') == entry.key &&
                p.promotionDate.isAfter(prevDate) &&
                !p.promotionDate.isAfter(c.date))
            .length;
        out.add(FighterCompetitionMark(
          name: c.name,
          date: c.date,
          position: c.position,
          sport: c.sport,
          // null quando qualquer ponta do intervalo é indeterminável — a UI
          // omite a contagem em vez de subestimar (ex.: "15 treinos" num aluno
          // com 100+ informados pelo mestre antes do app).
          trainingsSincePrev: (cum != null && prevCount != null)
              ? (cum - prevCount).clamp(0, 1 << 31).toInt()
              : null,
          monthsSincePrev: monthsBetween(prevDate, c.date),
          gradesSincePrev: grades,
          cumulativeTrainings: cum,
          source: c.source,
        ));
        prevDate = c.date;
        prevCount = cum;
      }
    }

    out.sort((a, b) => b.date.compareTo(a.date)); // desc p/ exibição
    return out;
  }

  /// Treinos ABSOLUTOS até [date] no bucket do esporte, considerando o
  /// baseline sem-data do mestre ([initialCount]).
  ///
  /// Regra da CERTEZA (pedido do produto): o baseline representa treinos
  /// ANTERIORES a todo o histórico in-app, mas sem datas — então:
  /// - sem baseline → contagem in-app é exata;
  /// - com baseline E [date] >= 1ª presença in-app → baseline + in-app(<=date)
  ///   (todo o baseline já tinha acontecido);
  /// - com baseline E [date] ANTERIOR ao histórico in-app (marco retroativo)
  ///   → IMPOSSÍVEL saber quantos treinos o aluno tinha → null (UI omite).
  static int? _cumAt(List<DateTime> attDays, DateTime date, int initialCount) {
    final inApp = _upperBound(attDays, date);
    if (initialCount <= 0) return inApp;
    if (attDays.isEmpty || date.isBefore(attDays.first)) return null;
    return initialCount + inApp;
  }

  static MedalCount _buildMedals(List<Achievement> competitions) {
    var gold = 0, silver = 0, bronze = 0;
    for (final c in competitions) {
      switch (c.position) {
        case CompetitionPosition.gold:
          gold++;
          break;
        case CompetitionPosition.silver:
          silver++;
          break;
        case CompetitionPosition.bronze:
          bronze++;
          break;
        default:
          break;
      }
    }
    return MedalCount(
      gold: gold,
      silver: silver,
      bronze: bronze,
      total: gold + silver + bronze,
    );
  }

  /// Quantos elementos de [sorted] (asc) são <= [target]. O(log n).
  static int _upperBound(List<DateTime> sorted, DateTime target) {
    var lo = 0, hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid].isAfter(target)) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }
}

/// Evento de competição normalizado (verified | auto) usado internamente pelo
/// merge POR ESPORTE em [ShowcaseBuilder._buildCompetitions].
class _CompEvent {
  final String name;
  final DateTime date;
  final String position;
  final String sport;
  final String source;

  const _CompEvent({
    required this.name,
    required this.date,
    required this.position,
    required this.sport,
    required this.source,
  });
}
