import 'package:cloud_firestore/cloud_firestore.dart';

/// Tolerant date parsing for self-declared records read back from Firestore.
/// Accepts Timestamp (canonical), DateTime, int millis, or ISO string.
DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) return DateTime.tryParse(v);
  return null;
}

int _asInt(dynamic v) => (v as num?)?.toInt() ?? 0;

/// Graduação AUTO-DECLARADA pelo próprio lutador (§1.3/§1.4 do plano).
///
/// Vive em `academies/{aid}/students/{sid}/selfGraduations/{id}` (ou
/// `fighterProfiles/{uid}/selfGraduations` no mundo B2C solo). NUNCA toca
/// `beltProgressions` (= TETO verificado). `source` é sempre `'self'` e
/// imutável (enforced em Rules). O grau só pode ser ≤ TETO verificado —
/// validado no client + Cloud Function, fora deste modelo.
class SelfGraduation {
  /// Doc id (vazio antes de persistir).
  final String id;
  final String sport;

  /// Grade id na escada do esporte (ex.: faixa BJJ, ponta MT). Ver
  /// `getGradesForSport` (sports.dart).
  final String grade;
  final int stripes;

  /// Data da graduação — editável pelo aluno.
  final DateTime date;

  /// Sempre `'self'`. Distingue do verificado (`beltProgressions`).
  final String source;

  /// uid de quem declarou (= dono do registro).
  final String createdBy;

  /// Carimbo de criação (server-set). Null antes de persistir.
  final DateTime? createdAt;

  const SelfGraduation({
    this.id = '',
    required this.sport,
    required this.grade,
    this.stripes = 0,
    required this.date,
    this.source = 'self',
    required this.createdBy,
    this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'sport': sport,
        'grade': grade,
        'stripes': stripes,
        'date': Timestamp.fromDate(date),
        'source': source,
        'createdBy': createdBy,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      };

  /// Retrocompatível: defaults seguros para docs legados/parciais.
  factory SelfGraduation.fromMap(Map<String, dynamic> d, {String id = ''}) =>
      SelfGraduation(
        id: id,
        sport: (d['sport'] ?? 'bjj').toString(),
        grade: (d['grade'] ?? '').toString(),
        stripes: _asInt(d['stripes']),
        date: _parseDate(d['date']) ?? DateTime.now(),
        source: (d['source'] ?? 'self').toString(),
        createdBy: (d['createdBy'] ?? '').toString(),
        createdAt: _parseDate(d['createdAt']),
      );

  factory SelfGraduation.fromFirestore(DocumentSnapshot doc) =>
      SelfGraduation.fromMap(
        (doc.data() as Map<String, dynamic>?) ?? const {},
        id: doc.id,
      );
}

/// Confronto individual dentro de uma [SelfCompetition] — RIVAIS R0
/// ("adversário de chave", §6.1 da pesquisa de retenção).
///
/// É o diário de lutas do PRÓPRIO aluno: o adversário NÃO precisa estar no
/// app e nada dele é exposto — o dado vive dentro do doc da competição
/// auto-declarada (owner-writable) e só a Jornada do próprio aluno lê.
/// `result` é sempre `'win' | 'loss' | 'draw'` (perspectiva do aluno).
class SelfMatch {
  final String opponentName;

  /// Equipe do adversário (opcional) — exibida com respeito (§3.4: a
  /// identidade de equipe é sagrada; rival é adversário de chave, não colega).
  final String? opponentTeam;

  /// `'win' | 'loss' | 'draw'` — do ponto de vista do aluno.
  final String result;

  const SelfMatch({
    required this.opponentName,
    this.opponentTeam,
    required this.result,
  });

  Map<String, dynamic> toMap() => {
        'opponentName': opponentName,
        if (opponentTeam != null) 'opponentTeam': opponentTeam,
        'result': result,
      };

  /// Retrocompatível: defaults seguros para mapas legados/parciais.
  factory SelfMatch.fromMap(Map<String, dynamic> d) {
    final team = d['opponentTeam'];
    final result = (d['result'] ?? '').toString();
    return SelfMatch(
      opponentName: (d['opponentName'] ?? '').toString(),
      opponentTeam:
          (team is String && team.trim().isNotEmpty) ? team : null,
      result: const {'win', 'loss', 'draw'}.contains(result) ? result : 'draw',
    );
  }

  /// Parse tolerante de uma lista vinda do Firestore: ignora entradas que não
  /// sejam mapas ou que não tenham nome de adversário.
  static List<SelfMatch> listFrom(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((m) => SelfMatch.fromMap(Map<String, dynamic>.from(m)))
        .where((m) => m.opponentName.trim().isNotEmpty)
        .toList();
  }
}

/// Competição AUTO-DECLARADA pelo próprio lutador (§1.3/§1.4/§4.2 do plano).
///
/// Vive em `academies/{aid}/students/{sid}/selfCompetitions/{id}`. Cobre
/// tanto marcações de campeonatos quanto lutas por OUTRA academia
/// (`external == true` + `externalAcademy`). `source` sempre `'self'`.
class SelfCompetition {
  /// Doc id (vazio antes de persistir).
  final String id;
  final String sport;
  final String name;
  final DateTime date;

  /// Colocação/posição (ex.: 'gold' | 'silver' | 'bronze' | 'participant').
  final String? placement;

  /// Texto livre de resultado (ex.: "Campeão", "2º lugar").
  final String? result;

  /// true quando a competição foi por outra academia (não a atual).
  final bool external;

  /// Nome da academia externa (quando `external`).
  final String? externalAcademy;

  /// Confrontos da chave registrados pelo aluno (RIVAIS R0, §6.1). Opcional —
  /// lista vazia quando o aluno não registrou lutas individuais. Máximo de 8
  /// por competição (enforced na UI de captura).
  final List<SelfMatch> matches;

  /// Sempre `'self'`.
  final String source;

  /// uid de quem declarou (= dono do registro).
  final String createdBy;

  /// Carimbo de criação (server-set). Null antes de persistir.
  final DateTime? createdAt;

  const SelfCompetition({
    this.id = '',
    required this.sport,
    required this.name,
    required this.date,
    this.placement,
    this.result,
    this.external = false,
    this.externalAcademy,
    this.matches = const [],
    this.source = 'self',
    required this.createdBy,
    this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'sport': sport,
        'name': name,
        'date': Timestamp.fromDate(date),
        if (placement != null) 'placement': placement,
        if (result != null) 'result': result,
        'external': external,
        if (externalAcademy != null) 'externalAcademy': externalAcademy,
        if (matches.isNotEmpty)
          'matches': matches.map((m) => m.toMap()).toList(),
        'source': source,
        'createdBy': createdBy,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      };

  /// Retrocompatível: defaults seguros para docs legados/parciais.
  factory SelfCompetition.fromMap(Map<String, dynamic> d, {String id = ''}) =>
      SelfCompetition(
        id: id,
        sport: (d['sport'] ?? 'bjj').toString(),
        name: (d['name'] ?? '').toString(),
        date: _parseDate(d['date']) ?? DateTime.now(),
        placement: d['placement'] as String?,
        result: d['result'] as String?,
        external: d['external'] == true,
        externalAcademy: d['externalAcademy'] as String?,
        matches: SelfMatch.listFrom(d['matches']),
        source: (d['source'] ?? 'self').toString(),
        createdBy: (d['createdBy'] ?? '').toString(),
        createdAt: _parseDate(d['createdAt']),
      );

  factory SelfCompetition.fromFirestore(DocumentSnapshot doc) =>
      SelfCompetition.fromMap(
        (doc.data() as Map<String, dynamic>?) ?? const {},
        id: doc.id,
      );
}
