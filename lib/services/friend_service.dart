import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/fighter_profile.dart';

/// Sistema de AMIGOS (v1, client-side, cost-safe):
///  - `fighterProfiles/{uid}`: espelho público do lutador (escrito pelo dono).
///  - `follows/{followerUid}_{targetUid}`: grafo de seguir (1-direcional).
///  - adicionar amigo por CÓDIGO curto (fighterCode) — sem busca/descoberta
///    invasiva: você só acha quem te passou o código.
class FriendService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _db.collection('fighterProfiles');
  CollectionReference<Map<String, dynamic>> get _follows =>
      _db.collection('follows');

  /// Escreve/atualiza o próprio espelho público. Gera um `fighterCode` estável
  /// na 1ª vez (preserva o existente). Retorna o código.
  ///
  /// Os campos de VITRINE ([graduations]/[competitions]/[medals]/[recordStreak]
  /// /[firstTrainingDate]) só são gravados quando o DONO os fornece E o
  /// [showcaseHash] mudou em relação ao já materializado — assim uma abertura
  /// que não alterou nada não reescreve os blobs grandes (cost-safe). Os campos
  /// básicos continuam sendo gravados em toda chamada (paridade com o legado).
  Future<String> mirror({
    required String uid,
    required String name,
    required String belt,
    required int stripes,
    required String sport,
    String? photoUrl,
    int totalTrainings = 0,
    int currentStreak = 0,
    String? academyName,
    // ── Vitrine (opcional) ──
    int? recordStreak,
    DateTime? firstTrainingDate,
    DateTime? lastTrainingDate,
    List<FighterGraduation>? graduations,
    List<FighterCompetitionMark>? competitions,
    MedalCount? medals,
    String? showcaseHash,
  }) async {
    final ref = _profiles.doc(uid);
    final snap = await ref.get();
    final existing = snap.data();
    var code = existing?['fighterCode'] as String?;
    if (code == null || code.isEmpty) code = _genCode();

    final payload = <String, dynamic>{
      'uid': uid,
      'name': name,
      'belt': belt,
      'stripes': stripes,
      'sport': sport,
      if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
      'fighterCode': code,
      'totalTrainings': totalTrainings,
      'currentStreak': currentStreak,
      if (academyName != null && academyName.isNotEmpty)
        'academyName': academyName,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Vitrine: só (re)grava os blobs quando fornecidos e o hash mudou.
    final showcaseChanged = graduations != null &&
        (showcaseHash == null ||
            showcaseHash != (existing?['showcaseHash'] as String?));
    if (showcaseChanged) {
      payload['graduations'] = graduations.map((g) => g.toMap()).toList();
      payload['competitions'] =
          (competitions ?? const <FighterCompetitionMark>[])
              .map((c) => c.toMap())
              .toList();
      payload['medals'] = (medals ?? const MedalCount()).toMap();
      if (recordStreak != null) payload['recordStreak'] = recordStreak;
      if (firstTrainingDate != null) {
        payload['firstTrainingDate'] = Timestamp.fromDate(firstTrainingDate);
      }
      if (lastTrainingDate != null) {
        payload['lastTrainingDate'] = Timestamp.fromDate(lastTrainingDate);
      }
      if (showcaseHash != null) payload['showcaseHash'] = showcaseHash;
      payload['showcaseUpdatedAt'] = FieldValue.serverTimestamp();
    }

    await ref.set(payload, SetOptions(merge: true));
    return code;
  }

  /// Lê o espelho público de [uid] (1 read). Usado pela VISÃO DE VISITANTE para
  /// renderizar a vitrine sem tocar a attendance privada da academia do dono.
  Future<FighterProfile?> getProfile(String uid) async {
    final snap = await _profiles.doc(uid).get();
    final data = snap.data();
    if (data == null) return null;
    return FighterProfile.fromMap(data);
  }

  /// Procura um lutador pelo código curto (case-insensitive).
  Future<FighterProfile?> findByCode(String code) async {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return null;
    final q = await _profiles.where('fighterCode', isEqualTo: c).limit(1).get();
    if (q.docs.isEmpty) return null;
    return FighterProfile.fromMap(q.docs.first.data());
  }

  Future<void> addFriend({
    required String myUid,
    required String targetUid,
  }) async {
    if (myUid == targetUid) return;
    await _follows.doc('${myUid}_$targetUid').set({
      'followerUid': myUid,
      'targetUid': targetUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeFriend({
    required String myUid,
    required String targetUid,
  }) async {
    await _follows.doc('${myUid}_$targetUid').delete();
  }

  /// Meus amigos, BIDIRECIONAL: quem EU sigo (follows.followerUid == myUid) E
  /// quem ME segue (follows.targetUid == myUid). Faz a UNIÃO dos "outros" uids
  /// (dedup) e hidrata os perfis públicos. Assim quem me adicionou por código
  /// aparece nos meus amigos e vice-versa.
  /// Cost-safe: 2 queries nos follows + leituras whereIn em lotes de 10.
  Future<List<FighterProfile>> getFriends(String myUid) async {
    final results = await Future.wait([
      _follows.where('followerUid', isEqualTo: myUid).get(),
      _follows.where('targetUid', isEqualTo: myUid).get(),
    ]);
    final ids = <String>{};
    // Quem eu sigo → o "outro" é o targetUid.
    for (final d in results[0].docs) {
      final other = d.data()['targetUid'] as String?;
      if (other != null && other != myUid) ids.add(other);
    }
    // Quem me segue → o "outro" é o followerUid.
    for (final d in results[1].docs) {
      final other = d.data()['followerUid'] as String?;
      if (other != null && other != myUid) ids.add(other);
    }
    if (ids.isEmpty) return const [];
    final idList = ids.toList();
    final out = <FighterProfile>[];
    for (var i = 0; i < idList.length; i += 10) {
      final end = (i + 10) > idList.length ? idList.length : i + 10;
      final chunk = idList.sublist(i, end);
      final q =
          await _profiles.where(FieldPath.documentId, whereIn: chunk).get();
      out.addAll(q.docs.map((d) => FighterProfile.fromMap(d.data())));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  // Alfabeto sem caracteres ambíguos (0/O/1/I) para o código ser ditável.
  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  String _genCode() {
    final r = Random.secure();
    return List.generate(6, (_) => _alphabet[r.nextInt(_alphabet.length)])
        .join();
  }
}

final friendService = FriendService();
