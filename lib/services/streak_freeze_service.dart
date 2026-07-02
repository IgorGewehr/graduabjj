import 'package:cloud_firestore/cloud_firestore.dart';

import 'weekly_streak.dart';

/// FREEZE do streak semanal — "modo lesão" / "semana de descanso" (§4.3 e
/// §6.4 da pesquisa de retenção: 31% dos praticantes de BJJ já tiveram lesão
/// séria; lesionado que vê o streak quebrar em silêncio abandona o app).
///
/// CONTRATO (compartilhado com as CFs de push e o feed_materializer):
/// `users/{uid}.streakFreezes` = mapa `{ 'YYYY-Www': 'lesao' | 'descanso' }`.
/// Semana congelada SEM treino é PONTE do streak (não conta como treinada,
/// não quebra a continuidade — ver `computeWeeklyStreak(frozenWeeks:)`);
/// semana congelada COM treino conta normalmente (treino vence).
///
/// Owner-scoped: o próprio lutador lê/escreve (rules de `users/{uid}` já
/// permitem update de campos não sensíveis). Só a semana ISO CORRENTE pode
/// ser congelada/descongelada — congelar o passado reescreveria história e
/// congelar o futuro viraria estoque de "seguro" (anti-padrão de streak).
///
/// PODA client-side: toda escrita remove chaves com mais de [_keepWeeks]
/// (~60) semanas — o backend poda `retention.weeklyBuckets` do mesmo jeito e
/// nenhum cálculo olha mais longe que isso.
class StreakFreezeService {
  StreakFreezeService(this.uid);

  /// Motivos válidos — o valor é persistido e lido pelas CFs; nada fora
  /// destes dois entra no mapa.
  static const String reasonLesao = 'lesao';
  static const String reasonDescanso = 'descanso';

  /// Horizonte de retenção do mapa (semanas). > 52 para o recorde anual
  /// continuar atravessando pontes antigas.
  static const int _keepWeeks = 60;

  final String uid;

  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  /// Congela a semana ISO CORRENTE com [reason] ('lesao' | 'descanso').
  /// Idempotente (recongelar só regrava o motivo). Aproveita a escrita para
  /// PODAR chaves com mais de [_keepWeeks] semanas (e chaves malformadas).
  Future<void> freezeCurrentWeek(String reason) async {
    if (reason != reasonLesao && reason != reasonDescanso) {
      throw ArgumentError.value(
          reason, 'reason', "use 'lesao' ou 'descanso'");
    }
    final now = DateTime.now();
    final snap = await _doc.get();
    final patch = <String, dynamic>{
      ..._pruneDeletes(_parse(snap.data()), now),
      isoWeekKeyOf(now): reason,
    };
    await _doc.set({'streakFreezes': patch}, SetOptions(merge: true));
  }

  /// Descongela a semana ISO CORRENTE (no-op se não estava congelada).
  Future<void> unfreezeCurrentWeek() async {
    await _doc.set({
      'streakFreezes': {isoWeekKeyOf(DateTime.now()): FieldValue.delete()},
    }, SetOptions(merge: true));
  }

  /// Chaves 'YYYY-Www' congeladas — o shape que `computeWeeklyStreak`
  /// recebe em `frozenWeeks`. Leitura única (para watch, use [watch]).
  Future<Set<String>> getFrozenWeeks() async {
    final snap = await _doc.get();
    return _parse(snap.data()).keys.toSet();
  }

  /// Espelho ao vivo do mapa completo `{ 'YYYY-Www': motivo }` — a UI usa o
  /// MOTIVO da semana corrente para renderizar "modo lesão" vs "descanso";
  /// `.keys.toSet()` alimenta o cálculo do streak.
  Stream<Map<String, String>> watch() =>
      _doc.snapshots().map((s) => _parse(s.data()));

  /// Extrai/valida o mapa do doc: só entradas String→String sobrevivem.
  Map<String, String> _parse(Map<String, dynamic>? data) {
    final raw = data?['streakFreezes'];
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries)
        if (e.value is String) e.key.toString(): e.value as String,
    };
  }

  /// Sentinelas `FieldValue.delete()` para chaves mais antigas que o
  /// horizonte (ou malformadas) — aplicadas junto do set(merge) da escrita.
  Map<String, dynamic> _pruneDeletes(Map<String, String> existing, DateTime now) {
    // Chave gerada por isoWeekKeyOf é sempre bem-formada → parse não-nulo.
    final cutoff = mondayUtcOfIsoWeekKey(isoWeekKeyOf(now))!
        .subtract(const Duration(days: 7 * _keepWeeks));
    final deletes = <String, dynamic>{};
    for (final key in existing.keys) {
      final monday = mondayUtcOfIsoWeekKey(key);
      if (monday == null || monday.isBefore(cutoff)) {
        deletes[key] = FieldValue.delete();
      }
    }
    return deletes;
  }
}
