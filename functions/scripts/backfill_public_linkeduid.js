// One-off: copia students/{sid}.linkedUserId → publicProfiles/{sid}.linkedUserId
// em todas as academias. Necessário pro social intra-academia (colega de turma
// → uid → perfil/posts). Idempotente (merge). Só toca publicProfiles.
// Rodar: cd functions && node scripts/backfill_public_linkeduid.js
const admin = require('firebase-admin');
admin.initializeApp({ projectId: 'arpjj-76350' });
const db = admin.firestore();

(async () => {
  const acads = await db.collection('academies').get();
  let scanned = 0, written = 0, skipped = 0;
  for (const acad of acads.docs) {
    const students = await acad.ref.collection('students').get();
    for (const s of students.docs) {
      scanned++;
      const uid = s.data().linkedUserId;
      if (!uid || typeof uid !== 'string') { skipped++; continue; }
      await acad.ref.collection('publicProfiles').doc(s.id)
        .set({ linkedUserId: uid }, { merge: true });
      written++;
    }
  }
  console.log(`\nacademias: ${acads.size} · alunos varridos: ${scanned}`);
  console.log(`publicProfiles atualizados com linkedUserId: ${written} · sem uid (skip): ${skipped}`);
  process.exit(0);
})().catch((e) => { console.error('ERRO:', e.message); process.exit(1); });
