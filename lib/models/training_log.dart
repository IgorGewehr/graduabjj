import 'package:cloud_firestore/cloud_firestore.dart';

/// Tolerant date parsing for training logs read back from Firestore.
/// Accepts Timestamp (canonical), DateTime, int millis, or ISO string.
/// (Mirrors `self_record.dart:_parseDate` — kept local to avoid coupling.)
DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// SELF-LOG de sparring do lutador — o "TREINEI HOJE" count-first.
///
/// Vive em `users/{uid}/training_logs/{logId}` (owner-scoped, ver
/// firestore.rules). O CORAÇÃO é [sparringCount]: o número de rolas/rounds/
/// randoris do dia. Todo o resto é metadado LEVE e opcional.
///
/// ANTI-FRAUDE (intocável): este log é do LUTADOR, para retenção/insight. NUNCA
/// é lido por nenhum caminho de graduação — graduação-por-presença lê só
/// `academies/{aid}/attendance`. [source] é sempre `'self'` para distinguir da
/// presença verificada. [linkedAttendanceId] é só ponteiro de display/dedup
/// quando o count foi anexado a uma aula real; somar counts nunca toca a
/// contagem de presença.
///
/// Dedup: UM doc por DIA (`date` em `DateUtils.dateOnly`). O service faz
/// upsert-by-date, então anexar rolas a qualquer dia não duplica linha.
///
/// Retrocompat: docs legados (sem `sparringCount`/`source`) leem `0`/`'self'`.
class TrainingLog {
  /// Doc id (vazio antes de persistir).
  final String id;

  /// Dia do treino, sempre `DateUtils.dateOnly` (00:00 local). Chave de dedup.
  final DateTime date;

  /// `SportId.value` (`'bjj'`, `'muaythai'`…). Define a UNIDADE do count.
  /// `null` = legado → tratar como `bjj`.
  final String? sport;

  /// CORAÇÃO — número de rolas/rounds/randoris do dia. `>= 0`. Ausente em docs
  /// legados → `0`.
  final int sparringCount;

  /// Metadado leve: `'leve' | 'media' | 'dura'`.
  final String? intensity;

  /// Metadado leve: `'leve' | 'na_medida' | 'pesado' | 'quebrado'`.
  final String? feeling;

  /// Texto curto livre (≤140).
  final String? note;

  /// Opcional avançado — técnicas drilladas.
  final List<String> techniques;

  /// Opcional avançado — parceiros de treino.
  final List<String> partners;

  /// Quando o dia TAMBÉM tem presença verificada e o count foi anexado a essa
  /// aula. Só display/dedup — NÃO afeta contagem de presença/graduação.
  final String? linkedAttendanceId;

  /// Sempre `'self'`. Distingue de attendance verificada.
  final String source;

  /// Academia de contexto (quando o lutador tem uma). Mantido p/ contexto.
  final String? academyId;

  /// Carimbo de criação (server-set). Null antes de persistir.
  final DateTime? createdAt;

  /// Carimbo de atualização (server-set em cada update).
  final DateTime? updatedAt;

  const TrainingLog({
    this.id = '',
    required this.date,
    this.sport,
    this.sparringCount = 0,
    this.intensity,
    this.feeling,
    this.note,
    this.techniques = const [],
    this.partners = const [],
    this.linkedAttendanceId,
    this.source = 'self',
    this.academyId,
    this.createdAt,
    this.updatedAt,
  });

  /// Esporte efetivo (legado `null` → BJJ), para insights/unidade.
  String get effectiveSport => sport ?? 'bjj';

  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(date),
        if (sport != null) 'sport': sport,
        'sparringCount': sparringCount,
        if (intensity != null) 'intensity': intensity,
        if (feeling != null) 'feeling': feeling,
        if (note != null) 'note': note,
        'techniques': techniques,
        'partners': partners,
        if (linkedAttendanceId != null) 'linkedAttendanceId': linkedAttendanceId,
        'source': source,
        if (academyId != null) 'academyId': academyId,
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
        if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      };

  /// Retrocompatível: defaults seguros para docs legados/parciais.
  factory TrainingLog.fromMap(Map<String, dynamic> d, {String id = ''}) =>
      TrainingLog(
        id: id,
        date: _parseDate(d['date']) ?? DateTime.now(),
        sport: d['sport'] as String?,
        sparringCount: (d['sparringCount'] as num?)?.toInt() ?? 0,
        intensity: d['intensity'] as String?,
        feeling: d['feeling'] as String?,
        note: d['note'] as String?,
        techniques: List<String>.from(d['techniques'] ?? const []),
        partners: List<String>.from(d['partners'] ?? const []),
        linkedAttendanceId: d['linkedAttendanceId'] as String?,
        source: (d['source'] ?? 'self').toString(),
        academyId: d['academyId'] as String?,
        createdAt: _parseDate(d['createdAt']),
        updatedAt: _parseDate(d['updatedAt']),
      );

  factory TrainingLog.fromFirestore(DocumentSnapshot doc) => TrainingLog.fromMap(
        (doc.data() as Map<String, dynamic>?) ?? const {},
        id: doc.id,
      );
}
