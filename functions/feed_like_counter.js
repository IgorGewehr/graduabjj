// CF: mantém feedPosts/{postId}.likeCount denormalizado (O(0) na leitura do
// feed — sem .count() aggregation por post, que custava $ por abertura de tela).
// onWrite em likes/{likeId}: create → +1, delete → -1. Idempotente por natureza
// (cada like é 1 doc de id determinístico {postId}_{likerUid}).
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

exports.onFeedLikeWrite = onDocumentWritten(
  { document: 'likes/{likeId}', region: 'us-central1' },
  async (event) => {
    const before = event.data?.before?.exists ? event.data.before.data() : null;
    const after = event.data?.after?.exists ? event.data.after.data() : null;

    let delta = 0;
    if (!before && after) delta = 1;       // like criado
    else if (before && !after) delta = -1; // like removido
    else return; // update (não muda contagem)

    const postId = (after || before).postId;
    if (!postId) return;

    const db = getFirestore();
    try {
      await db.doc(`feedPosts/${postId}`).update({
        likeCount: FieldValue.increment(delta),
      });
    } catch (e) {
      // Post pode não existir (ex.: excluído) — ignora, sem quebrar o like.
      console.warn('[onFeedLikeWrite] update falhou', postId, e.message);
    }
  }
);
