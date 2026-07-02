// One-off: perfil PÚBLICO por padrão (app social, opt-out). Seta
// isProfilePublic=true nos students existentes que estão false E no espelho
// publicProfiles. Só toca esse campo. Rodar: cd functions && node scripts/backfill_public_default.js
const admin = require('firebase-admin');
admin.initializeApp({ projectId: 'arpjj-76350' });
const db = admin.firestore();

(async () => {
  const acads = await db.collection('academies').get();
  let students = 0, mirrors = 0;
  for (const acad of acads.docs) {
    const sSnap = await acad.ref.collection('students').get();
    for (const s of sSnap.docs) {
      if (s.data().isProfilePublic !== true) {
        await s.ref.set({ isProfilePublic: true }, { merge: true });
        students++;
      }
      // espelho (external/web lê publicProfiles.isProfilePublic)
      await acad.ref.collection('publicProfiles').doc(s.id)
        .set({ isProfilePublic: true }, { merge: true });
      mirrors++;
    }
  }
  console.log(`academias: ${acads.size} · students → público: ${students} · publicProfiles: ${mirrors}`);
  process.exit(0);
})().catch((e) => { console.error('ERRO:', e.message); process.exit(1); });
