import 'dart:math' as math;

import '../models/fighter_profile.dart';
import '../models/training_log.dart';

/// INSIGHTS de SPARRING do lutador — puros, calculados a partir dos self-logs
/// (`training_logs`) + as datas de graduação (`beltProgressions`, via showcase).
///
/// ANTI-FRAUDE (intocável): nada aqui promove faixa. `sparringCount` é do
/// LUTADOR (retenção/insight). As graduações entram SÓ como DATAS que delimitam
/// os blocos de esforço ("N rolas até a faixa X") — nenhuma rola vira presença.
///
/// Assimetria pró-retenção: métricas monotônicas (total, recorde, esforço por
/// bloco) sempre existem; a TENDÊNCIA só é materializada quando é POSITIVA de
/// verdade — se estagnou/caiu, [trend] é `null` e a UI não renderiza nada (nunca
/// desmotiva).
class SparringInsights {
  /// Σ `sparringCount` de todas as sessões com count>0 (todos os esportes).
  final int totalAll;

  /// Total de sparrings por esporte (`effectiveSport` → Σ count).
  final Map<String, int> totalBySport;

  /// Maior `sparringCount` numa única sessão (all-time, todos os esportes).
  final int bestNight;

  /// Recorde de melhor noite por esporte.
  final Map<String, int> bestNightBySport;

  /// Nº de sessões com count>0 por esporte.
  final Map<String, int> sessionsBySport;

  /// "N rolas até a faixa X" — um por marco de graduação com esforço>0, desc
  /// por data (mais recente primeiro).
  final List<GraduationEffort> gradEfforts;

  /// Tendência de melhora — `null` quando NÃO é positiva (por design).
  final TrendSignal? trend;

  const SparringInsights({
    required this.totalAll,
    required this.totalBySport,
    required this.bestNight,
    required this.bestNightBySport,
    required this.sessionsBySport,
    required this.gradEfforts,
    required this.trend,
  });

  /// Total de sessões com count>0 (soma de [sessionsBySport]).
  int get totalSessions =>
      sessionsBySport.values.fold(0, (a, b) => a + b);

  /// Esportes que têm ao menos uma sessão com count>0.
  Set<String> get sportsWithCount => totalBySport.keys.toSet();
}

/// Esforço de sparring acumulado no bloco `(marco anterior, este marco]` — a
/// narrativa "N rolas até a faixa azul". Motivacional: NÃO promove faixa.
class GraduationEffort {
  final String sport; // SportId.value
  final String belt;
  final int stripes;
  final bool isBeltChange;
  final DateTime date;

  /// Σ `sparringCount` (do mesmo esporte) entre o marco anterior e este.
  final int sparringsInBlock;

  const GraduationEffort({
    required this.sport,
    required this.belt,
    required this.stripes,
    required this.isBeltChange,
    required this.date,
    required this.sparringsInBlock,
  });
}

/// Sinal de TENDÊNCIA POSITIVA de um esporte (janelas recentes vs anteriores).
/// Só é criado quando `recentAvg >= prevAvg * 1.15` — nunca representa queda.
class TrendSignal {
  final String sport;
  final double recentAvg;
  final double prevAvg;
  final int deltaPerc; // ex.: 23 → "+23%"

  const TrendSignal({
    required this.sport,
    required this.recentAvg,
    required this.prevAvg,
    required this.deltaPerc,
  });
}

/// Engine PURO (sem I/O). Quem chama passa os logs (já lidos) e as datas de
/// graduação (do showcase). Retorna `null` quando não há NENHUMA sessão com
/// count>0 — nesse caso a UI simplesmente não renderiza a seção.
class SparringEngine {
  SparringEngine._();

  // Gate de tendência: recente >= 15% acima da janela anterior.
  static const double _trendGate = 1.15;
  // Janelas de tendência (últimas N vs N anteriores) e mínimo por janela.
  static const int _trendWindow = 5;
  static const int _trendMinPerWindow = 3;

  static SparringInsights? compute({
    required List<TrainingLog> logs,
    required List<FighterGraduation> graduations,
  }) {
    // Só sessões com count>0 (musculação/check-ins ficam de fora).
    final counted = logs.where((l) => l.sparringCount > 0).toList();
    if (counted.isEmpty) return null;

    var totalAll = 0;
    var bestNight = 0;
    final totalBySport = <String, int>{};
    final bestNightBySport = <String, int>{};
    final sessionsBySport = <String, int>{};

    for (final l in counted) {
      final s = l.effectiveSport;
      totalAll += l.sparringCount;
      totalBySport[s] = (totalBySport[s] ?? 0) + l.sparringCount;
      sessionsBySport[s] = (sessionsBySport[s] ?? 0) + 1;
      if (l.sparringCount > bestNight) bestNight = l.sparringCount;
      if (l.sparringCount > (bestNightBySport[s] ?? 0)) {
        bestNightBySport[s] = l.sparringCount;
      }
    }

    return SparringInsights(
      totalAll: totalAll,
      totalBySport: totalBySport,
      bestNight: bestNight,
      bestNightBySport: bestNightBySport,
      sessionsBySport: sessionsBySport,
      gradEfforts: _gradEfforts(counted, graduations),
      trend: _trend(counted),
    );
  }

  // ── "N rolas até a faixa X" — esforço por bloco entre graduações ──────────
  // Para cada marco (por esporte, asc), soma o `sparringCount` dos logs do MESMO
  // esporte em `(dataDoMarcoAnterior, g.date]`. O 1º bloco não tem lower-bound
  // (pega tudo até a data do marco). Só emite blocos com esforço>0.
  static List<GraduationEffort> _gradEfforts(
    List<TrainingLog> counted,
    List<FighterGraduation> graduations,
  ) {
    if (graduations.isEmpty) return const [];

    final logsBySport = <String, List<TrainingLog>>{};
    for (final l in counted) {
      logsBySport.putIfAbsent(l.effectiveSport, () => []).add(l);
    }
    final gradsBySport = <String, List<FighterGraduation>>{};
    for (final g in graduations) {
      gradsBySport.putIfAbsent(g.sport, () => []).add(g);
    }

    final out = <GraduationEffort>[];
    gradsBySport.forEach((sport, grads) {
      final asc = [...grads]..sort((a, b) => a.date.compareTo(b.date));
      final slogs = logsBySport[sport] ?? const <TrainingLog>[];
      DateTime? prevDate;
      for (final g in asc) {
        var sum = 0;
        for (final l in slogs) {
          final afterLower = prevDate == null || l.date.isAfter(prevDate);
          final beforeUpper = !l.date.isAfter(g.date);
          if (afterLower && beforeUpper) sum += l.sparringCount;
        }
        if (sum > 0) {
          out.add(GraduationEffort(
            sport: sport,
            belt: g.belt,
            stripes: g.stripes,
            isBeltChange: g.isBeltChange,
            date: g.date,
            sparringsInBlock: sum,
          ));
        }
        prevDate = g.date;
      }
    });

    out.sort((a, b) => b.date.compareTo(a.date)); // desc p/ exibição
    return out;
  }

  // ── Tendência POSITIVA (dispara SÓ quando sobe) ───────────────────────────
  // Por esporte: sessões count>0 asc. recent = últimas 5, prev = as 5 antes.
  // Exige >=3 em cada janela. Dispara só se recentAvg >= prevAvg*1.15. Escolhe
  // o esporte com maior deltaPerc. Nenhum passa → null (UI omite tendência).
  static TrendSignal? _trend(List<TrainingLog> counted) {
    final bySport = <String, List<TrainingLog>>{};
    for (final l in counted) {
      bySport.putIfAbsent(l.effectiveSport, () => []).add(l);
    }

    TrendSignal? best;
    bySport.forEach((sport, list) {
      if (list.length < _trendWindow + _trendMinPerWindow) return;
      final asc = [...list]..sort((a, b) => a.date.compareTo(b.date));

      final recentStart = asc.length - _trendWindow;
      final recent = asc.sublist(recentStart);
      final prevStart = math.max(0, recentStart - _trendWindow);
      final prev = asc.sublist(prevStart, recentStart);
      if (recent.length < _trendMinPerWindow ||
          prev.length < _trendMinPerWindow) {
        return;
      }

      final recentAvg = _avg(recent);
      final prevAvg = _avg(prev);
      if (prevAvg <= 0) return;
      if (recentAvg < prevAvg * _trendGate) return;

      final deltaPerc = ((recentAvg / prevAvg - 1) * 100).round();
      if (best == null || deltaPerc > best!.deltaPerc) {
        best = TrendSignal(
          sport: sport,
          recentAvg: recentAvg,
          prevAvg: prevAvg,
          deltaPerc: deltaPerc,
        );
      }
    });
    return best;
  }

  static double _avg(List<TrainingLog> xs) =>
      xs.map((e) => e.sparringCount).reduce((a, b) => a + b) / xs.length;
}
