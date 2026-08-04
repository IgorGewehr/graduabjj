import 'package:cloud_firestore/cloud_firestore.dart';

/// Tolerant date parsing for showcase blobs read back from Firestore.
/// Accepts Timestamp (canonical), int millis, or ISO string. Null-safe.
DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) return DateTime.tryParse(v);
  return null;
}

int _asInt(dynamic v) => (v as num?)?.toInt() ?? 0;

/// Nullable: campos de contagem de treino que podem ser INDETERMINÁVEIS
/// (baseline sem-data informado pelo mestre cobre o período do marco) — null
/// = "não sabemos com certeza", e a UI omite o número em vez de mentir.
int? _asIntN(dynamic v) => (v as num?)?.toInt();

/// Um marco de GRADUAÇÃO materializado (grau OU faixa). Carrega o ESFORÇO já
/// computado (delta de presenças/meses até este marco) — o visitante lê isto
/// pronto, sem tocar a attendance privada da academia do dono.
class FighterGraduation {
  final String sport;
  final String belt;
  final int stripes;
  final bool isBeltChange;
  final DateTime date;

  /// Presenças acumuladas NESTE BLOCO (delta de baselineCount p/ o marco
  /// anterior). É "aulas até este grau/faixa". NULL = indeterminável (o
  /// baseline sem-data do mestre cobre o período) — a UI omite a contagem.
  final int? trainingsToReach;

  /// Meses inteiros entre o marco anterior (ou startDate) e este.
  final int monthsToReach;

  /// baselineCount neste ponto (cumulativo-vida) — para contexto/debug.
  /// NULL = indeterminável (ver [trainingsToReach]).
  final int? cumulativeTrainings;

  /// true quando a unidade de [trainingsToReach] é "pontos" (academia com
  /// class weights), não "aulas".
  final bool weighted;

  /// Origem do marco: `'verified'` (de `beltProgressions`, = TETO) ou `'auto'`
  /// (de `selfGraduations`, auto-declarado pelo aluno). Default `'verified'`
  /// para retrocompat com vitrines materializadas antes da Jornada multi-fonte.
  final String source;

  const FighterGraduation({
    required this.sport,
    required this.belt,
    required this.stripes,
    required this.isBeltChange,
    required this.date,
    required this.trainingsToReach,
    required this.monthsToReach,
    required this.cumulativeTrainings,
    this.weighted = false,
    this.source = 'verified',
  });

  Map<String, dynamic> toMap() => {
        'sport': sport,
        'belt': belt,
        'stripes': stripes,
        'isBeltChange': isBeltChange,
        'date': Timestamp.fromDate(date),
        'trainingsToReach': trainingsToReach,
        'monthsToReach': monthsToReach,
        'cumulativeTrainings': cumulativeTrainings,
        'weighted': weighted,
        'source': source,
      };

  factory FighterGraduation.fromMap(Map<String, dynamic> d) => FighterGraduation(
        sport: (d['sport'] ?? 'bjj').toString(),
        belt: (d['belt'] ?? 'white').toString(),
        stripes: _asInt(d['stripes']),
        isBeltChange: d['isBeltChange'] == true,
        date: _parseDate(d['date']) ?? DateTime.now(),
        trainingsToReach: _asIntN(d['trainingsToReach']),
        monthsToReach: _asInt(d['monthsToReach']),
        cumulativeTrainings: _asIntN(d['cumulativeTrainings']),
        weighted: d['weighted'] == true,
        source: (d['source'] ?? 'verified').toString(),
      );
}

/// Um marco de COMPETIÇÃO materializado, com a "estrada" desde a competição
/// anterior (treinos/meses/graus acumulados no intervalo).
class FighterCompetitionMark {
  final String name;
  final DateTime date;

  /// 'gold' | 'silver' | 'bronze' | 'participant'.
  final String position;
  final String sport;

  // Contexto opcional (vem de CompetitionResult; null quando só há Achievement).
  final String? beltCategory;
  final String? weightCategory;
  final String? modality;

  /// Presenças entre a competição anterior (ou startDate) e esta.
  /// NULL = indeterminável (baseline sem-data cobre o período) — UI omite.
  final int? trainingsSincePrev;

  /// Meses inteiros desde a competição anterior (ou startDate).
  final int monthsSincePrev;

  /// Nº de progressões (graus + faixas) registradas no intervalo.
  final int gradesSincePrev;

  /// Presenças totais acumuladas até a data desta competição (baseline do
  /// mestre INCLUÍDO quando a competição é posterior ao histórico in-app).
  /// NULL = indeterminável — UI omite.
  final int? cumulativeTrainings;

  /// Origem do marco: `'verified'` (de `achievements`/competições da academia)
  /// ou `'auto'` (de `selfCompetitions`, externas/auto-declaradas). Default
  /// `'verified'` para retrocompat com vitrines materializadas antes da Jornada
  /// multi-fonte.
  final String source;

  const FighterCompetitionMark({
    required this.name,
    required this.date,
    required this.position,
    required this.sport,
    this.beltCategory,
    this.weightCategory,
    this.modality,
    required this.trainingsSincePrev,
    required this.monthsSincePrev,
    required this.gradesSincePrev,
    required this.cumulativeTrainings,
    this.source = 'verified',
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'date': Timestamp.fromDate(date),
        'position': position,
        'sport': sport,
        if (beltCategory != null) 'beltCategory': beltCategory,
        if (weightCategory != null) 'weightCategory': weightCategory,
        if (modality != null) 'modality': modality,
        'trainingsSincePrev': trainingsSincePrev,
        'monthsSincePrev': monthsSincePrev,
        'gradesSincePrev': gradesSincePrev,
        'cumulativeTrainings': cumulativeTrainings,
        'source': source,
      };

  factory FighterCompetitionMark.fromMap(Map<String, dynamic> d) =>
      FighterCompetitionMark(
        name: (d['name'] ?? '').toString(),
        date: _parseDate(d['date']) ?? DateTime.now(),
        position: (d['position'] ?? 'participant').toString(),
        sport: (d['sport'] ?? 'bjj').toString(),
        beltCategory: d['beltCategory'] as String?,
        weightCategory: d['weightCategory'] as String?,
        modality: d['modality'] as String?,
        trainingsSincePrev: _asIntN(d['trainingsSincePrev']),
        monthsSincePrev: _asInt(d['monthsSincePrev']),
        gradesSincePrev: _asInt(d['gradesSincePrev']),
        cumulativeTrainings: _asIntN(d['cumulativeTrainings']),
        source: (d['source'] ?? 'verified').toString(),
      );
}

/// Cartel de medalhas (estilo BoxRec): ouro/prata/bronze + total.
class MedalCount {
  final int gold;
  final int silver;
  final int bronze;
  final int total;

  const MedalCount({
    this.gold = 0,
    this.silver = 0,
    this.bronze = 0,
    this.total = 0,
  });

  Map<String, dynamic> toMap() => {
        'gold': gold,
        'silver': silver,
        'bronze': bronze,
        'total': total,
      };

  factory MedalCount.fromMap(Map<String, dynamic>? d) => MedalCount(
        gold: _asInt(d?['gold']),
        silver: _asInt(d?['silver']),
        bronze: _asInt(d?['bronze']),
        total: _asInt(d?['total']),
      );
}

/// Perfil PÚBLICO (PII-free) do lutador — espelho em `fighterProfiles/{uid}`.
/// Usado por descoberta/amigos cross-academy. Nome/faixa/stats são públicos;
/// nada de CPF/telefone/financeiro aqui.
///
/// Estendido com a VITRINE materializada (graduations/competitions/medals +
/// recordStreak/firstTrainingDate). O DONO computa e grava; o VISITANTE lê o
/// doc inteiro em 1 read. Todos os campos de vitrine são opcionais e o
/// `fromMap` é tolerante a docs legados (default vazio).
class FighterProfile {
  final String uid;
  final String name;
  final String belt;
  final int stripes;
  final String sport;
  final String? photoUrl;
  final String fighterCode;
  final int totalTrainings;
  final int currentStreak;
  final String? academyName;

  // ── Vitrine (showcase) materializada ──
  final int recordStreak;
  final DateTime? firstTrainingDate;
  final DateTime? lastTrainingDate;
  final List<FighterGraduation> graduations;
  final List<FighterCompetitionMark> competitions;
  final MedalCount medals;
  final DateTime? showcaseUpdatedAt;

  const FighterProfile({
    required this.uid,
    required this.name,
    required this.belt,
    required this.stripes,
    required this.sport,
    required this.fighterCode,
    this.photoUrl,
    this.totalTrainings = 0,
    this.currentStreak = 0,
    this.academyName,
    this.recordStreak = 0,
    this.firstTrainingDate,
    this.lastTrainingDate,
    this.graduations = const [],
    this.competitions = const [],
    this.medals = const MedalCount(),
    this.showcaseUpdatedAt,
  });

  /// true quando o doc já tem a vitrine materializada (ao menos um marco).
  bool get hasShowcase =>
      graduations.isNotEmpty || competitions.isNotEmpty || medals.total > 0;

  factory FighterProfile.fromMap(Map<String, dynamic> d) {
    List<T> parseList<T>(dynamic raw, T Function(Map<String, dynamic>) f) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => f(Map<String, dynamic>.from(e)))
          .toList();
    }

    return FighterProfile(
      uid: (d['uid'] ?? '').toString(),
      name: (d['name'] ?? 'Lutador').toString(),
      belt: (d['belt'] ?? 'white').toString(),
      stripes: _asInt(d['stripes']),
      sport: (d['sport'] ?? 'bjj').toString(),
      photoUrl: d['photoUrl'] as String?,
      fighterCode: (d['fighterCode'] ?? '').toString(),
      totalTrainings: _asInt(d['totalTrainings']),
      currentStreak: _asInt(d['currentStreak']),
      academyName: d['academyName'] as String?,
      recordStreak: _asInt(d['recordStreak']),
      firstTrainingDate: _parseDate(d['firstTrainingDate']),
      lastTrainingDate: _parseDate(d['lastTrainingDate']),
      graduations: parseList(d['graduations'], FighterGraduation.fromMap),
      competitions:
          parseList(d['competitions'], FighterCompetitionMark.fromMap),
      medals: MedalCount.fromMap(
          d['medals'] is Map ? Map<String, dynamic>.from(d['medals']) : null),
      showcaseUpdatedAt: _parseDate(d['showcaseUpdatedAt']),
    );
  }

  /// Serialização dos campos PÚBLICOS BÁSICOS (sem os blobs de vitrine, que o
  /// mirror grava à parte com seu próprio gating de idempotência).
  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'belt': belt,
        'stripes': stripes,
        'sport': sport,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'fighterCode': fighterCode,
        'totalTrainings': totalTrainings,
        'currentStreak': currentStreak,
        if (academyName != null) 'academyName': academyName,
      };
}
