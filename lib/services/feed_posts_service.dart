import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/feed_post.dart';

/// Feed social de RETENÇÃO — coleção top-level `feedPosts/{postId}`.
///
/// Irmão de [FriendService] (`friend_service.dart`). Implementa o PRODUTOR
/// (create-if-absent idempotente), leitura do feed em duas dimensões
/// (PARCEIROS e ACADEMIA) e o subsistema de LIKE (coleção `likes/{postId}_{likerUid}`).
///
/// Invariantes:
/// - [emitIfAbsent]: JAMAIS reescreve um id determinístico existente — preserva
///   `hiddenByAuthor` e a imutabilidade do marco (§8.1 do plano).
/// - `hiddenByAuthor:false` sempre gravado no create → filtro server-side
///   `hiddenByAuthor == false` é confiável em todo doc.
/// - Like doc-id composto `{postId}_{likerUid}` → anti-spam, 1 like por par.
/// - Self-like bloqueado client-side (check de authorUid) e server-side pela rule.
///
/// Índices necessários (firestore.indexes.json):
///   feedPosts: (authorUid, hiddenByAuthor, occurredAt desc) — aba PARCEIROS
///   feedPosts: (academyId, hiddenByAuthor, occurredAt desc)  — aba ACADEMIA
class FeedPostsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _posts =>
      _db.collection('feedPosts');

  CollectionReference<Map<String, dynamic>> get _likes =>
      _db.collection('likes');

  // ── PRODUTOR ──────────────────────────────────────────────────────────────

  /// Cria [post] no Firestore usando [FeedPost.postId] como doc-id APENAS se
  /// o doc ainda não existe. Idempotente: se o doc já existe (incluindo quando
  /// `hiddenByAuthor == true`), não faz nada — preserva a exclusão do autor.
  ///
  /// Usa transação para garantir atomicidade do "create-if-absent".
  Future<void> emitIfAbsent(FeedPost post) async {
    final ref = _posts.doc(post.postId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.exists) return; // idempotent — do not overwrite or resurface
      tx.set(ref, post.toMap());
    });
  }

  // ── FEED: PARCEIROS ───────────────────────────────────────────────────────

  /// Posts da audiência [uids] (colegas de turma ∪ co-presença ∪ follows).
  ///
  /// Batcheia `whereIn` em lotes de 10 (limite do Firestore). Resultados de
  /// todos os lotes são mesclados e re-ordenados por `occurredAt` desc antes de
  /// aplicar [limit]. Filtra `hiddenByAuthor == false` server-side.
  ///
  /// Requer índice composto: (authorUid, hiddenByAuthor, occurredAt desc).
  Future<List<FeedPost>> feedForAudience(
    List<String> uids, {
    int limit = 50,
  }) async {
    if (uids.isEmpty) return const [];
    final out = <FeedPost>[];
    for (var i = 0; i < uids.length; i += 10) {
      final chunk = uids.sublist(i, min(i + 10, uids.length));
      final q = await _posts
          .where('authorUid', whereIn: chunk)
          .where('hiddenByAuthor', isEqualTo: false)
          .orderBy('occurredAt', descending: true)
          .limit(limit) // cap per-batch; merged list re-limits below
          .get();
      out.addAll(q.docs.map((d) => FeedPost.fromMap(d.data())));
    }
    out.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  // ── FEED: ACADEMIA ────────────────────────────────────────────────────────

  /// Posts de todos os autores da academia [academyId], `hiddenByAuthor == false`,
  /// ordenados por `occurredAt` desc.
  ///
  /// Requer índice composto: (academyId, hiddenByAuthor, occurredAt desc).
  Future<List<FeedPost>> feedForAcademy(
    String academyId, {
    int limit = 50,
  }) async {
    final q = await _posts
        .where('academyId', isEqualTo: academyId)
        .where('hiddenByAuthor', isEqualTo: false)
        .orderBy('occurredAt', descending: true)
        .limit(limit)
        .get();
    return q.docs.map((d) => FeedPost.fromMap(d.data())).toList();
  }

  // ── LIKE ──────────────────────────────────────────────────────────────────

  /// Registra um like de [giverUid] no post [postId].
  /// Doc-id: `{postId}_{giverUid}` — anti-spam, 1 like por par.
  ///
  /// [authorUid] é denormalizado no like doc para bloquear self-like sem um
  /// get() adicional (validado também pela Firestore rule). No-op client-side
  /// quando `giverUid == authorUid`.
  Future<void> like({
    required String giverUid,
    required String postId,
    required String authorUid,
    required String giverName,
    required String giverBelt,
    required int giverStripes,
  }) async {
    if (giverUid == authorUid) return;
    await _likes.doc('${postId}_$giverUid').set({
      'postId': postId,
      'likerUid': giverUid,
      'authorUid': authorUid,
      'createdAt': FieldValue.serverTimestamp(),
      'likerName': giverName,
      'likerBelt': giverBelt,
      'likerStripes': giverStripes,
    });
  }

  /// Remove o like de [giverUid] no post [postId].
  Future<void> unlike({
    required String giverUid,
    required String postId,
  }) async {
    await _likes.doc('${postId}_$giverUid').delete();
  }

  /// Contagem de likes por post — v1 (sem CF): 1 aggregation-read por postId.
  ///
  /// Retorna `Map<postId, count>`. Em v2 (com CF `onLikeWrite`), substituir
  /// por leitura do campo `likeCount` denormalizado no doc do post (O(0)).
  Future<Map<String, int>> likeCount(List<String> postIds) async {
    if (postIds.isEmpty) return const {};
    final counts = <String, int>{};
    await Future.wait(
      postIds.map((postId) async {
        final agg =
            await _likes.where('postId', isEqualTo: postId).count().get();
        counts[postId] = agg.count ?? 0;
      }),
    );
    return counts;
  }

  /// Quais dos [postIds] o usuário [myUid] já curtiu.
  ///
  /// Usa `whereIn(documentId)` em lotes de 30 — mesmo padrão de
  /// `getFriends` (`friend_service.dart:155`). Retorna Set de postIds curtidos.
  Future<Set<String>> didILike(String myUid, List<String> postIds) async {
    if (postIds.isEmpty || myUid.isEmpty) return const {};
    final liked = <String>{};
    // Doc-ids compostos: {postId}_{myUid}
    final docIds = postIds.map((p) => '${p}_$myUid').toList();
    for (var i = 0; i < docIds.length; i += 30) {
      final chunk = docIds.sublist(i, min(i + 30, docIds.length));
      final q = await _likes
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final d in q.docs) {
        final postId = d.data()['postId'] as String?;
        if (postId != null) liked.add(postId);
      }
    }
    return liked;
  }

  // ── EXCLUIR (FLAG, NÃO DELETE) ────────────────────────────────────────────

  /// Oculta o post [postId] setando `hiddenByAuthor = true`.
  ///
  /// Só o autor deve chamar (rule Firestore restringe update a
  /// `affectedKeys().hasOnly(['hiddenByAuthor', 'hiddenAt'])`).
  ///
  /// O produtor ([emitIfAbsent]) respeita a flag: como o doc JÁ EXISTE com
  /// hiddenByAuthor=true, o create-if-absent encontra o doc e não reescreve —
  /// a supressão gruda contra regeneração automática.
  Future<void> hide(String postId) async {
    await _posts.doc(postId).update({
      'hiddenByAuthor': true,
      'hiddenAt': FieldValue.serverTimestamp(),
    });
  }

  // ── MODERAÇÃO (STAFF: admin/professor da academia) ────────────────────────

  /// Oculta/reexibe o post [postId] para TODA a academia (moderação).
  ///
  /// Só o staff da academia do post deve chamar — a rule Firestore restringe o
  /// update a `hasOnly(['hiddenByStaff','hiddenByStaffAt','staffHeadline'])` e
  /// exige `isAcademyStaff(resource.data.academyId)`. Diferente de [hide] (autor):
  /// aqui o feed do aluno filtra `hiddenByStaff` client-side. Reexibir apaga o
  /// timestamp para não deixar lixo.
  Future<void> staffSetHidden(String postId, bool hidden) async {
    await _posts.doc(postId).update({
      'hiddenByStaff': hidden,
      'hiddenByStaffAt':
          hidden ? FieldValue.serverTimestamp() : FieldValue.delete(),
    });
  }

  /// Sobrescreve (ou limpa, com [headline] null/vazio) o texto exibido do post
  /// [postId]. Aparece para todos via [FeedPost.displayHeadline]. Staff-only.
  Future<void> staffSetHeadline(String postId, String? headline) async {
    final v = headline?.trim();
    await _posts.doc(postId).update({
      'staffHeadline':
          (v == null || v.isEmpty) ? FieldValue.delete() : v,
    });
  }
}

/// Singleton — mesmo padrão de `friendService` em `friend_service.dart`.
final feedPostsService = FeedPostsService();
