/**
 * Sprint R — one-shot backfill of the publicProfiles mirror.
 *
 * Iterates every academies/{academyId} and every students/{studentId} and
 * writes the SAME SAFE (PII-free) projection that the mirrorStudentPublicProfile
 * Cloud Function writes to academies/{academyId}/publicProfiles/{studentId}.
 * Reuses buildPublicProfileProjection from ../server_functions.js so the
 * allowlist can never drift between the trigger and the backfill.
 *
 * The mirror contains ZERO PII — same allowlist/denylist as the CF.
 *
 * Uses the Admin SDK with the project's service account key.
 *   Project:  arpjj-76350
 *   SA key:   /Users/igorgewehr/WebstormProjects/marcusjj/scripts/serviceAccountKey.json
 *
 * RUN COMMAND (from the repo root; does nothing destructive — set/merge only):
 *   GOOGLE_APPLICATION_CREDENTIALS=/Users/igorgewehr/WebstormProjects/marcusjj/scripts/serviceAccountKey.json \
 *     node functions/scripts/backfill_public_profiles.js
 *
 * DRY RUN (count only, no writes):
 *   GOOGLE_APPLICATION_CREDENTIALS=/Users/igorgewehr/WebstormProjects/marcusjj/scripts/serviceAccountKey.json \
 *     node functions/scripts/backfill_public_profiles.js --dry-run
 */

'use strict';

const path = require('path');
const admin = require('firebase-admin');

const SERVICE_ACCOUNT_PATH =
  process.env.GOOGLE_APPLICATION_CREDENTIALS ||
  '/Users/igorgewehr/WebstormProjects/marcusjj/scripts/serviceAccountKey.json';

const DRY_RUN = process.argv.includes('--dry-run');

// eslint-disable-next-line import/no-dynamic-require, global-require
const serviceAccount = require(path.resolve(SERVICE_ACCOUNT_PATH));

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: serviceAccount.project_id || 'arpjj-76350',
});

const db = admin.firestore();

// Reuse the EXACT projection the Cloud Function uses (single source of truth).
const {
  buildPublicProfileProjection,
  PUBLIC_PROFILE_SAFE_FIELDS,
} = require('../server_functions');

async function main() {
  console.log('=== Sprint R — publicProfiles backfill ===');
  console.log(`project: ${serviceAccount.project_id || 'arpjj-76350'}`);
  console.log(`dry-run: ${DRY_RUN}`);
  console.log(`safe fields mirrored: ${PUBLIC_PROFILE_SAFE_FIELDS.join(', ')}`);
  console.log('');

  const academiesSnap = await db.collection('academies').get();
  console.log(`Found ${academiesSnap.size} academies.\n`);

  let totalStudents = 0;
  let totalWritten = 0;
  let totalErrors = 0;

  for (const academyDoc of academiesSnap.docs) {
    const academyId = academyDoc.id;
    const studentsSnap = await db
      .collection('academies').doc(academyId)
      .collection('students')
      .get();

    if (studentsSnap.empty) {
      console.log(`[${academyId}] 0 students — skipping`);
      continue;
    }

    let written = 0;
    let errors = 0;

    // Batch writes (<=450 ops/batch; Firestore limit is 500).
    let batch = db.batch();
    let batchOps = 0;
    const commitBatch = async () => {
      if (batchOps === 0) return;
      if (!DRY_RUN) await batch.commit();
      batch = db.batch();
      batchOps = 0;
    };

    for (const studentDoc of studentsSnap.docs) {
      totalStudents++;
      try {
        const projection = buildPublicProfileProjection(studentDoc.data());
        const mirrorRef = db
          .collection('academies').doc(academyId)
          .collection('publicProfiles').doc(studentDoc.id);
        batch.set(mirrorRef, projection, { merge: true });
        batchOps++;
        written++;
        totalWritten++;
        if (batchOps >= 450) await commitBatch();
      } catch (e) {
        errors++;
        totalErrors++;
        console.error(
          `  [${academyId}/${studentDoc.id}] projection/write failed:`,
          e && e.message,
        );
      }
    }
    await commitBatch();

    console.log(
      `[${academyId}] students=${studentsSnap.size} mirrored=${written}` +
      (errors ? ` errors=${errors}` : '') +
      (DRY_RUN ? ' (dry-run, not written)' : ''),
    );
  }

  console.log('');
  console.log('=== Done ===');
  console.log(`academies:        ${academiesSnap.size}`);
  console.log(`students seen:    ${totalStudents}`);
  console.log(`profiles mirrored:${totalWritten}${DRY_RUN ? ' (dry-run)' : ''}`);
  console.log(`errors:           ${totalErrors}`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('FATAL:', e);
    process.exit(1);
  });
