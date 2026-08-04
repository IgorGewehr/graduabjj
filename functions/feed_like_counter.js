// CF: mantém feedPosts/{postId}.likeCount denormalizado (O(0) na leitura do
// feed — sem .count() aggregation por post, que custava $ por abertura de tela).
// onWrite em likes/{likeId}: create → +1, delete → -1. Idempotente por natureza
// (cada like é 1 doc de id determinístico {postId}_{likerUid}).
//
// §9.1 do plano (REPAGINADA_ADMIN_ALUNO100_PLANO.md): no CREATE, além do
// increment, envia push "like recebido" ao AUTOR do post via o portão único
// sendPushIfAllowed (push_functions.js) — respeita notificationPrefs.social e
// quiet hours; category 'social' NÃO consome o cap semanal de treino.
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { sendPushIfAllowed } = require('./push_functions');

// ---------------------------------------------------------------------------
// Headline curta para o corpo do push — espelho LEVE do getter `headline` de
// lib/models/feed_post.dart (que é client-side; o doc Firestore guarda só
// type + payload + staffHeadline). Sem match → corpo genérico.
// ---------------------------------------------------------------------------
function shortHeadlineFromPost(post) {
  if (post.staffHeadline) return String(post.staffHeadline);
  const type = String(post.type || '');
  const p = (post.payload && typeof post.payload === 'object') ? post.payload : {};
  switch (type) {
    case 'graduacao': {
      if (p.isBeltChange === true && p.belt) return `Faixa ${p.belt}`;
      const stripes = Number(p.stripes) || 0;
      return stripes > 0 ? `${stripes}º grau` : null;
    }
    case 'competicao': {
      const medal = { gold: 'Ouro', silver: 'Prata', bronze: 'Bronze' }[p.position] || null;
      const name = p.name ? String(p.name) : '';
      if (medal && name) return `${medal} · ${name}`;
      return name || 'Competiu';
    }
    case 'streak_milestone': {
      const weeks = Number(p.weeks) || 0;
      return weeks > 0 ? `${weeks} semanas seguidas` : null;
    }
    case 'sparring_record': {
      const recorde = Number(p.recorde) || 0;
      return recorde > 0 ? `Melhor noite: ${recorde} rolas` : null;
    }
    case 'weekly_volume': {
      const trainings = Number(p.trainings) || 0;
      const rolas = Number(p.rolas) || 0;
      const parts = [];
      if (trainings > 0) parts.push(`${trainings} treino${trainings === 1 ? '' : 's'} essa semana`);
      if (rolas > 0) parts.push(`${rolas} rola${rolas === 1 ? '' : 's'}`);
      return parts.length > 0 ? parts.join(' · ') : null;
    }
    case 'mat_milestone': {
      const marco = String(p.marco || '');
      if (!marco) return null;
      if (marco.endsWith('yr')) {
        const yr = marco.slice(0, -2);
        return `${yr} ano${yr === '1' ? '' : 's'} de tatame`;
      }
      return `${marco} aulas`;
    }
    default:
      return null;
  }
}

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
    const postRef = db.doc(`feedPosts/${postId}`);
    try {
      await postRef.update({
        likeCount: FieldValue.increment(delta),
      });
    } catch (e) {
      // Post pode não existir (ex.: excluído) — ignora, sem quebrar o like.
      console.warn('[onFeedLikeWrite] update falhou', postId, e.message);
    }

    // Push "like recebido" — SÓ no create (delete de like nunca notifica).
    if (delta !== 1) return;
    try {
      const authorUid = after.authorUid; // denormalizado no like doc
      const likerUid = after.likerUid;
      if (!authorUid || authorUid === likerUid) return; // self-like: no-op

      // Lê o post para um corpo melhor; se sumiu (excluído entre o like e a
      // CF) ou está oculto, não notifica.
      const postSnap = await postRef.get();
      if (!postSnap.exists) return;
      const post = postSnap.data() || {};
      if (post.hiddenByAuthor === true || post.hiddenByStaff === true) return;

      const likerName = after.likerName ? String(after.likerName) : 'Alguém';
      const headline = shortHeadlineFromPost(post);

      await sendPushIfAllowed({
        db,
        uid: authorUid,
        category: 'social',
        title: `${likerName} curtiu seu marco`,
        body: headline || 'Seu marco recebeu um salve.',
        // actionUrl: não há rota de post individual no vocabulário do app
        // (o feed vive dentro da Cena) — cai no hub/feed genérico.
        data: { type: 'feed_like', postId, actionUrl: '/portal/cena' },
      });
    } catch (e) {
      // Push é best-effort — nunca falha o contador por causa dele.
      console.warn('[onFeedLikeWrite] push de like falhou', postId, e.message);
    }
  }
);
