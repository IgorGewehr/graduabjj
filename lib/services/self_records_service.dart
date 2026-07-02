import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/self_record.dart';
import 'firebase_service.dart';

// Re-export so callers using the service get the models too.
export '../models/self_record.dart';

/// CRUD dos registros AUTO-DECLARADOS do lutador (§1.4 do plano):
/// graduações e competições que o próprio aluno declara, em coleções SEPARADAS
/// de `beltProgressions`/`achievements` (verificados/= TETO).
///
/// Caminhos:
///   `academies/{aid}/students/{sid}/selfGraduations/{id}`
///   `academies/{aid}/students/{sid}/selfCompetitions/{id}`
///
/// Ownership + `source` imutável + proibição de escrever em `beltProgressions`
/// são garantidos nas Firestore Rules (F2b). O TETO (grau ≤ verificado) é
/// enforced no client + Cloud Function — não aqui. `createdAt` é carimbado pelo
/// servidor no add.
class SelfRecordsService {
  final String academyId;
  late final Collections _collections;

  SelfRecordsService(this.academyId) {
    _collections = Collections.forAcademy(academyId);
  }

  CollectionReference _graduations(String studentId) =>
      _collections.student(studentId).collection('selfGraduations');

  CollectionReference _competitions(String studentId) =>
      _collections.student(studentId).collection('selfCompetitions');

  // ── Graduações auto-declaradas ──────────────────────────────────────────

  /// Cria uma graduação auto-declarada. Força `source:'self'` e carimba
  /// `createdAt` no servidor. Retorna o id do doc criado.
  Future<String> addGraduation(String studentId, SelfGraduation grad) async {
    final ref = await _graduations(studentId).add({
      ...grad.toMap(),
      'source': 'self',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Atualiza campos editáveis (ex.: `date`). `source` permanece imutável por
  /// Rule — não enviar.
  Future<void> updateGraduation(
    String studentId,
    String id,
    Map<String, dynamic> data,
  ) =>
      _graduations(studentId).doc(id).update(data);

  Future<void> deleteGraduation(String studentId, String id) =>
      _graduations(studentId).doc(id).delete();

  /// Lista as graduações auto-declaradas do aluno, mais recentes primeiro.
  Future<List<SelfGraduation>> listGraduations(String studentId) async {
    final snap =
        await _graduations(studentId).orderBy('date', descending: true).get();
    return snap.docs.map(SelfGraduation.fromFirestore).toList();
  }

  // ── Competições auto-declaradas ─────────────────────────────────────────

  /// Cria uma competição auto-declarada (da academia marcada ou externa).
  /// Força `source:'self'` e carimba `createdAt` no servidor. Retorna o id.
  Future<String> addCompetition(String studentId, SelfCompetition comp) async {
    final ref = await _competitions(studentId).add({
      ...comp.toMap(),
      'source': 'self',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateCompetition(
    String studentId,
    String id,
    Map<String, dynamic> data,
  ) =>
      _competitions(studentId).doc(id).update(data);

  Future<void> deleteCompetition(String studentId, String id) =>
      _competitions(studentId).doc(id).delete();

  /// Lista as competições auto-declaradas do aluno, mais recentes primeiro.
  Future<List<SelfCompetition>> listCompetitions(String studentId) async {
    final snap =
        await _competitions(studentId).orderBy('date', descending: true).get();
    return snap.docs.map(SelfCompetition.fromFirestore).toList();
  }
}
