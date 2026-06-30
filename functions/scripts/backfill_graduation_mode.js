/**
 * Disable auto-graduation across all academies WITHOUT breaking the live app.
 *
 * WHY: graduation is a deliberate professor act — the system must never write a
 * belt on its own. The OLD app (still in production until the new build is
 * approved) auto-promotes only when academy.autoGraduationEnabled==true AND
 * academy.graduationMode=='auto' (attendance_service.dart). Flipping
 * graduationMode from 'auto' to 'suggest' makes the old app SKIP the auto-write
 * (early return) while KEEPING autoGraduationEnabled==true so the eligibility
 * SUGGESTION stays visible to the professor (student_detail_screen).
 *
 * SAFETY: idempotent — only changes docs where graduationMode=='auto'. Leaves
 * autoGraduationEnabled and everything else untouched. Read-only by default.
 *
 * Auth: Application Default Credentials (gcloud ADC) for project arpjj-76350.
 *
 *   DRY RUN (default):  node functions/scripts/backfill_graduation_mode.js
 *   APPLY:              node functions/scripts/backfill_graduation_mode.js --apply
 */
const admin = require('firebase-admin');

const APPLY = process.argv.includes('--apply');
const PROJECT_ID = process.env.GCLOUD_PROJECT || 'arpjj-76350';

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

(async () => {
  console.log(`[backfill graduationMode auto->suggest] project=${PROJECT_ID} mode=${APPLY ? 'APPLY' : 'DRY-RUN'}`);
  const academies = await db.collection('academies').get();
  console.log(`academies: ${academies.size}`);

  let toFlip = 0, autoGradOnButManual = 0;
  const writes = [];
  for (const a of academies.docs) {
    const d = a.data() || {};
    if (d.graduationMode === 'auto') {
      toFlip++;
      console.log(`  ${a.id}: graduationMode 'auto' -> 'suggest' (autoGraduationEnabled=${d.autoGraduationEnabled})`);
      if (APPLY) {
        writes.push(a.ref.set({
          graduationMode: 'suggest',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true }));
      }
    } else if (d.autoGraduationEnabled === true) {
      autoGradOnButManual++; // eligibility shown, but not auto — already safe
    }
  }
  if (APPLY && writes.length) await Promise.all(writes);

  console.log('\n--- resumo ---');
  console.log(`academias em 'auto' (a corrigir): ${toFlip}`);
  console.log(`autoGraduationEnabled=true mas já não-auto (ok): ${autoGradOnButManual}`);
  console.log(APPLY ? '\nAPLICADO.' : '\nDRY-RUN — nada escrito. Rode com --apply para gravar.');
  process.exit(0);
})().catch((e) => { console.error('FALHA:', e); process.exit(1); });
