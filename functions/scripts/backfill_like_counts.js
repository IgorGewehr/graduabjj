// One-off: recomputa feedPosts/{id}.likeCount a partir da coleção `likes`
// (os likes criados ANTES da CF onFeedLikeWrite não tinham sido contados).
// Idempotente (set do valor absoluto). Rodar: cd functions && node scripts/backfill_like_counts.js
const admin = require('firebase-admin');
admin.initializeApp({ projectId: 'arpjj-76350' });
const db = admin.firestore();

(async () => {
  const likes = await db.collection('likes').get();
  const byPost = new Map();
  for (const d of likes.docs) {
    const pid = d.data().postId;
    if (!pid) continue;
    byPost.set(pid, (byPost.get(pid) || 0) + 1);
  }
  let written = 0;
  for (const [postId, count] of byPost) {
    try {
      await db.doc(`feedPosts/${postId}`).update({ likeCount: count });
      written++;
    } catch (_) { /* post pode não existir */ }
  }
  console.log(`likes: ${likes.size} · posts com like: ${byPost.size} · likeCount atualizados: ${written}`);
  process.exit(0);
})().catch((e) => { console.error('ERRO:', e.message); process.exit(1); });
