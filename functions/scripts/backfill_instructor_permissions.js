/**
 * One-shot backfill of instructor extraPermissions BEFORE deploying the
 * granular-permission firestore.rules (audit finding: rules now enforce
 * attendance:take / financial:create / competitions:create for the
 * 'instructor' role, where previously ANY instructor had full staff access).
 *
 * WHY THIS IS REQUIRED FIRST:
 * The new rules authorize an instructor write only when
 *   userAcademyMapping.academyDetails[academyId].extraPermissions
 * contains the matching permission (helper hasExtraPermission, firestore.rules
 * ~160-166). But isAcademyInstructor (firestore.rules ~60-69) recognizes an
 * instructor via EITHER the mapping OR the academy-scoped user doc
 * (academies/{academyId}/users/{uid}.role == 'instructor'), while
 * hasExtraPermission reads ONLY the mapping. So a "legacy" instructor whose
 * role lives only in the user doc (no academyDetails entry) would pass the
 * instructor check but FAIL hasExtraPermission and be locked out of chamada /
 * lançar cobrança / competições the moment the rules deploy.
 *
 * This migration finds every instructor by BOTH sources and grants the
 * permissions they implicitly had before, so the rules deploy is non-breaking.
 * Admins are unaffected (they bypass the permission gate) and are skipped.
 *
 * PHILOSOPHY: preserve existing capability on migrate. After this runs, admins
 * can TIGHTEN per-instructor in Settings -> Equipe (that's the new control the
 * audit fix enables); we do NOT retroactively impose least-privilege here,
 * because that would silently remove access instructors currently rely on.
 *
 * Idempotent: uses arrayUnion, so re-running never duplicates or removes perms.
 * Non-destructive: only adds the 3 permissions + (when missing) an instructor
 * academyDetails entry; never deletes fields or downgrades roles.
 *
 *   Project:  arpjj-76350
 *   SA key:   path from GOOGLE_APPLICATION_CREDENTIALS (or the default below)
 *
 * DRY RUN FIRST (counts + lists, no writes):
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json \
 *     node functions/scripts/backfill_instructor_permissions.js --dry-run
 *
 * THEN APPLY:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json \
 *     node functions/scripts/backfill_instructor_permissions.js
 */

'use strict';

const path = require('path');
const admin = require('firebase-admin');

const SERVICE_ACCOUNT_PATH =
  process.env.GOOGLE_APPLICATION_CREDENTIALS || '';

const DRY_RUN = process.argv.includes('--dry-run');

// The permissions whose enforcement is NEWLY added to firestore.rules. These
// map 1:1 to the rules the audit changed (attendance write, financials create,
// competitions + competitionResults writes). graduation:manage is intentionally
// NOT here: it was ALREADY enforced before this change, so instructors lacking
// it already could not graduate — granting it now would ADD a capability, not
// preserve one. Must stay a subset of GRANTABLE_EXTRA_PERMISSIONS (index.js).
const BACKFILL_PERMS = [
  'attendance:take',
  'financial:create',
  'competitions:create',
];

// Auth: use the service-account file when GOOGLE_APPLICATION_CREDENTIALS is set;
// otherwise fall back to Application Default Credentials (gcloud ADC).
let serviceAccount = null;
if (SERVICE_ACCOUNT_PATH) {
  // eslint-disable-next-line import/no-dynamic-require, global-require
  serviceAccount = require(path.resolve(SERVICE_ACCOUNT_PATH));
}

admin.initializeApp(
  serviceAccount
    ? {
        credential: admin.credential.cert(serviceAccount),
        projectId: serviceAccount.project_id || 'arpjj-76350',
      }
    : { projectId: process.env.GCLOUD_PROJECT || 'arpjj-76350' },
);

const db = admin.firestore();
const {FieldValue} = admin.firestore;

async function main() {
  console.log('=== Backfill instructor extraPermissions ===');
  console.log(`project:  ${(serviceAccount && serviceAccount.project_id) || process.env.GCLOUD_PROJECT || 'arpjj-76350'}`);
  console.log(`dry-run:  ${DRY_RUN}`);
  console.log(`granting: ${BACKFILL_PERMS.join(', ')}`);
  console.log('');

  // candidates keyed `${uid}|${academyId}` so the two sources de-dupe.
  // value: { uid, academyId, source: Set<'mapping'|'userDoc'> }
  const candidates = new Map();
  const addCandidate = (uid, academyId, source) => {
    const key = `${uid}|${academyId}`;
    const c = candidates.get(key) || {uid, academyId, source: new Set()};
    c.source.add(source);
    candidates.set(key, c);
  };

  // mappingCache[uid] = academyDetails map (so we can read existing role/perms
  // and decide skip-admin / create-entry without re-reading per write).
  const mappingCache = new Map();

  // ---- Source 1: userAcademyMapping.academyDetails[*].role == 'instructor' ----
  const mappingSnap = await db.collection('userAcademyMapping').get();
  for (const doc of mappingSnap.docs) {
    const details = (doc.data() || {}).academyDetails || {};
    mappingCache.set(doc.id, details);
    for (const [academyId, entry] of Object.entries(details)) {
      if (entry && entry.role === 'instructor') {
        addCandidate(doc.id, academyId, 'mapping');
      }
    }
  }
  console.log(`Scanned ${mappingSnap.size} userAcademyMapping docs.`);

  // ---- Source 2: academies/{id}/users where role == 'instructor' ----
  const academiesSnap = await db.collection('academies').get();
  for (const academyDoc of academiesSnap.docs) {
    const academyId = academyDoc.id;
    const usersSnap = await db
      .collection('academies').doc(academyId)
      .collection('users')
      .where('role', '==', 'instructor')
      .get();
    for (const u of usersSnap.docs) {
      addCandidate(u.id, academyId, 'userDoc');
    }
  }
  console.log(`Scanned ${academiesSnap.size} academies' users subcollections.`);
  console.log(`Distinct instructor (uid, academy) pairs: ${candidates.size}\n`);

  let granted = 0;
  let createdEntries = 0;
  let skippedAdmin = 0;
  let alreadyComplete = 0;

  let batch = db.batch();
  let batchOps = 0;
  const commitBatch = async () => {
    if (batchOps === 0) return;
    if (!DRY_RUN) await batch.commit();
    batch = db.batch();
    batchOps = 0;
  };

  for (const {uid, academyId, source} of candidates.values()) {
    const details = mappingCache.get(uid) || {};
    const entry = details[academyId];

    // Admins bypass the permission gate; never touch them.
    if (entry && entry.role === 'admin') {
      skippedAdmin++;
      continue;
    }

    const existingPerms = Array.isArray(entry && entry.extraPermissions) ?
      entry.extraPermissions : [];
    const missing = BACKFILL_PERMS.filter((p) => !existingPerms.includes(p));
    const needsEntry = !entry || !entry.role; // legacy / user-doc-only instructor

    if (missing.length === 0 && !needsEntry) {
      alreadyComplete++;
      continue;
    }

    // Deep-merge payload: arrayUnion creates the array if absent and never
    // duplicates. Set role/status only when the academyDetails entry is missing
    // so we never overwrite an existing (non-admin) role.
    const detailPatch = {
      extraPermissions: FieldValue.arrayUnion(...BACKFILL_PERMS),
    };
    if (needsEntry) {
      detailPatch.role = 'instructor';
      detailPatch.status = 'active';
      createdEntries++;
      console.log(
        `  + ${uid} @ ${academyId}: CREATING academyDetails entry ` +
        `(instructor known only via [${[...source].join(',')}]) + perms`,
      );
    } else {
      console.log(
        `  ~ ${uid} @ ${academyId}: adding [${missing.join(', ')}]`,
      );
    }

    batch.set(
      db.collection('userAcademyMapping').doc(uid),
      {academyDetails: {[academyId]: detailPatch}},
      {merge: true},
    );
    batchOps++;
    granted++;
    if (batchOps >= 450) await commitBatch();
  }
  await commitBatch();

  console.log('');
  console.log('=== Done ===');
  console.log(`instructor pairs:        ${candidates.size}`);
  console.log(`granted/updated:         ${granted}${DRY_RUN ? ' (dry-run, not written)' : ''}`);
  console.log(`  of which new entries:  ${createdEntries} (were lockout-risk: role only in user doc)`);
  console.log(`already complete:        ${alreadyComplete}`);
  console.log(`skipped (admins):        ${skippedAdmin}`);
  console.log('');
  console.log(DRY_RUN ?
    'DRY RUN — re-run without --dry-run to apply, THEN deploy firestore.rules.' :
    'APPLIED — safe to deploy the granular-permission firestore.rules now.');
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('FATAL:', e);
    process.exit(1);
  });
