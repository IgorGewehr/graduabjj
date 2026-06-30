/**
 * Backfill students/{id}.linkedUserId from userAcademyMapping.
 *
 * WHY: after the audit, server-side notification lookups (getStudentUserId in
 * server_functions.js) resolve a student's app account via student.linkedUserId
 * instead of scanning the whole userAcademyMapping collection. Students that were
 * linked by a legacy path that only populated the mapping (academyDetails[acad]
 * .studentId) but never stamped students/{id}.linkedUserId would otherwise stop
 * receiving billing/milestone notifications. This one-shot stamps the reverse
 * pointer so legacy AND new students both resolve.
 *
 * SAFETY: idempotent — only SETS linkedUserId when it is currently absent/null.
 * Never overwrites an existing link (a record already linked to a DIFFERENT uid
 * is reported as a conflict and skipped). Read-only by default.
 *
 * Auth: uses Application Default Credentials (gcloud ADC) for project arpjj-76350.
 *
 *   DRY RUN (default, no writes):   node functions/scripts/backfill_linked_user_id.js
 *   APPLY:                          node functions/scripts/backfill_linked_user_id.js --apply
 */
const admin = require('firebase-admin');

const APPLY = process.argv.includes('--apply');
const PROJECT_ID = process.env.GCLOUD_PROJECT || 'arpjj-76350';

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

(async () => {
  console.log(`[backfill linkedUserId] project=${PROJECT_ID} mode=${APPLY ? 'APPLY' : 'DRY-RUN'}`);
  const mappings = await db.collection('userAcademyMapping').get();
  console.log(`userAcademyMapping docs: ${mappings.size}`);

  let toSet = 0, alreadyOk = 0, conflicts = 0, missingStudent = 0, noStudentId = 0;
  const writes = [];

  for (const m of mappings.docs) {
    const uid = m.id;
    const details = (m.data() || {}).academyDetails || {};
    for (const [academyId, detail] of Object.entries(details)) {
      const studentId = detail && detail.studentId;
      if (!studentId) { noStudentId++; continue; }
      const ref = db.doc(`academies/${academyId}/students/${studentId}`);
      const snap = await ref.get();
      if (!snap.exists) { missingStudent++; continue; }
      const linked = snap.get('linkedUserId');
      if (linked === uid) { alreadyOk++; continue; }
      if (linked) { // linked to a different uid — do NOT clobber
        conflicts++;
        console.warn(`  CONFLICT academies/${academyId}/students/${studentId}: linkedUserId=${linked} != mapping uid=${uid}`);
        continue;
      }
      toSet++;
      if (APPLY) {
        writes.push(ref.set({
          linkedUserId: uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true }));
        if (writes.length >= 400) { await Promise.all(writes.splice(0)); }
      } else {
        console.log(`  WOULD SET academies/${academyId}/students/${studentId}.linkedUserId = ${uid}`);
      }
    }
  }
  if (APPLY && writes.length) await Promise.all(writes);

  console.log('\n--- resumo ---');
  console.log(`a setar (órfãos): ${toSet}`);
  console.log(`já corretos:      ${alreadyOk}`);
  console.log(`conflitos (skip): ${conflicts}`);
  console.log(`student inexistente: ${missingStudent}`);
  console.log(`sem studentId:    ${noStudentId}`);
  console.log(APPLY ? '\nAPLICADO.' : '\nDRY-RUN — nada escrito. Rode com --apply para gravar.');
  process.exit(0);
})().catch((e) => { console.error('FALHA:', e); process.exit(1); });
