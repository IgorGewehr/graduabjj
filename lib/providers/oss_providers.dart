import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

/// OSS RECÍPROCO — providers do nudge de reciprocidade do feed.
///
/// Base científica (docs/b2c/PESQUISA_PSICOLOGIA_RETENCAO_RIVAIS_2026-07.md):
/// - §2.1 [A] Franken, Bekhuis & Tolsma 2023: receber kudos é CAUSAL — faz o
///   atleta treinar mais e com mais frequência.
/// - P2: "adicionar retribuição fácil (dar oss de volta)" — quem recebe kudos
///   tende a retribuir e o laço vira loop.
///
/// A UI consome isto como um microtexto discreto no botão de oss do
/// `_PostCard` (cena_screen.dart) — sem banner, sem seção nova. Em qualquer
/// falha (índice ausente, rede, rules) o provider degrada para set vazio e a
/// feature some silenciosamente.

/// Janela de "recente": um oss dado há mais de 14 dias não gera nudge — o
/// gatilho de reciprocidade é o laço vivo, não dívida antiga.
const _recentLikerWindow = Duration(days: 14);

/// Uids de quem me deu oss RECENTEMENTE (últimos 14 dias).
///
/// Query na coleção top-level `likes` (doc: likerUid, likerName, authorUid,
/// postId, createdAt — ver `feed_posts_service.dart`):
/// `where(authorUid == meuUid) + orderBy(createdAt desc) + limit(30)`.
/// Requer índice composto `likes (authorUid ASC, createdAt DESC)` — declarado
/// em firestore.indexes.json. O corte de 14 dias é aplicado client-side sobre
/// os (no máx.) 30 likes mais recentes.
final myRecentLikersProvider = FutureProvider<Set<String>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return const <String>{};
  try {
    final cutoff = DateTime.now().subtract(_recentLikerWindow);
    final snap = await FirebaseFirestore.instance
        .collection('likes')
        .where('authorUid', isEqualTo: user.id)
        .orderBy('createdAt', descending: true)
        .limit(30)
        .get();
    final likers = <String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final likerUid = data['likerUid'];
      final createdAt = data['createdAt'];
      if (likerUid is! String || likerUid.isEmpty) continue;
      // createdAt é serverTimestamp: em docs recém-commitados é sempre
      // Timestamp; qualquer outra coisa (pending/legado) é descartada.
      if (createdAt is! Timestamp) continue;
      if (createdAt.toDate().isBefore(cutoff)) break; // ordenado desc
      likers.add(likerUid);
    }
    return likers;
  } catch (_) {
    // Falha silenciosa: sem nudge, o feed segue idêntico ao de antes.
    return const <String>{};
  }
});
