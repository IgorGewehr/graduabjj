import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' show DateUtils;

import '../models/training_log.dart';

/// Acesso aos SELF-LOGS de sparring do lutador (`users/{uid}/training_logs`).
///
/// Owner-scoped (o dado é da PESSOA, não da academia). ANTI-FRAUDE: nada aqui é
/// lido por caminhos de graduação — graduação lê só `academies/{aid}/attendance`.
///
/// Regra de ouro: UM doc por DIA. [upsertForDay] procura o log do mesmo
/// `dateOnly` e atualiza; senão cria. Isso permite "anexar rolas a qualquer
/// dia" (com ou sem professor) sem duplicar linha.
class TrainingLogService {
  TrainingLogService(this.uid);

  final String uid;

  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('training_logs');

  /// Leitura bounded, date desc. Usada pelo HISTÓRICO e pelos insights.
  Future<List<TrainingLog>> recent({int limit = 120}) async {
    final snap =
        await _col.orderBy('date', descending: true).limit(limit).get();
    return snap.docs.map(TrainingLog.fromFirestore).toList();
  }

  /// Upsert POR DIA: procura log com o mesmo `dateOnly`; atualiza se achar, cria
  /// se não. Retorna o id do doc. Grava `updatedAt` sempre; `createdAt` +
  /// `source:'self'` só no create.
  Future<String> upsertForDay({
    required DateTime date,
    required int sparringCount,
    String? sport,
    String? intensity,
    String? feeling,
    String? note,
    String? linkedAttendanceId,
    String? academyId,
  }) async {
    final day = DateUtils.dateOnly(date);
    final existing = await _col
        .where('date', isEqualTo: Timestamp.fromDate(day))
        .limit(1)
        .get();

    // Valores concretos (sem sentinelas) — seguros p/ create e update.
    final concrete = <String, dynamic>{
      'date': Timestamp.fromDate(day),
      'sparringCount': sparringCount,
      if (sport != null) 'sport': sport,
      if (intensity != null) 'intensity': intensity,
      if (feeling != null) 'feeling': feeling,
      if (note != null) 'note': note,
      if (linkedAttendanceId != null) 'linkedAttendanceId': linkedAttendanceId,
      if (academyId != null && academyId.isNotEmpty) 'academyId': academyId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (existing.docs.isNotEmpty) {
      // Update: limpa os opcionais ausentes (merge aceita delete()).
      final ref = existing.docs.first.reference;
      await ref.set({
        ...concrete,
        if (sport == null) 'sport': FieldValue.delete(),
        if (intensity == null) 'intensity': FieldValue.delete(),
        if (feeling == null) 'feeling': FieldValue.delete(),
        if (note == null) 'note': FieldValue.delete(),
        if (linkedAttendanceId == null)
          'linkedAttendanceId': FieldValue.delete(),
      }, SetOptions(merge: true));
      return ref.id;
    }

    // Create: só valores concretos + defaults imutáveis (sem sentinela delete).
    final ref = _col.doc();
    await ref.set({
      ...concrete,
      'source': 'self',
      'techniques': <String>[],
      'partners': <String>[],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Patch arbitrário (usado p/ detalhes opcionais: intensity/feeling/techniques
  /// /partners/note). Carimba `updatedAt` server-side.
  Future<void> patch(String id, Map<String, dynamic> fields) async {
    await _col.doc(id).update({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) async {
    await _col.doc(id).delete();
  }
}
