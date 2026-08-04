/**
 * One-shot backfill that seeds `feedPosts` with HISTORICAL graduation and
 * competition milestones for every student who has already claimed their
 * account (linkedUserId != null).
 *
 * WHY THIS IS NEEDED:
 * The social feed is materialised client-side by the post owner (FeedPostsService
 * → myShowcaseProvider) every time the owner opens the app. Without a backfill,
 * the feed would be empty for all existing users until each one opens the app
 * after the update ships. Running this script once seeds ALL historical milestones
 * up-front so the feed is dense from day 1.
 *
 * WHAT IT WRITES:
 *   feedPosts/{postId}  — deterministic ids (same scheme used by the app client):
 *     grad_{uid}_{yyyymmdd}_{belt}{stripes}   — one per beltProgression
 *     comp_{uid}_{yyyymmdd}_{slug}            — one per competition achievement
 *
 * WHAT IT READS (read-only, never mutates):
 *   academies/{id}                            — list of academies
 *   academies/{id}/students                   — filter: linkedUserId != null
 *   academies/{id}/beltProgressions           — filter: studentId
 *   academies/{id}/achievements               — filter: studentId + type=competition
 *
 * IDEMPOTENCY:
 *   All post ids are deterministic.  The script batch-reads each candidate id
 *   before writing; it only writes docs that do NOT yet exist (create-if-absent).
 *   Safe to re-run: already-present docs are skipped without modification.
 *   `hiddenByAuthor` in an existing doc is NEVER overwritten — a user who hid a
 *   post cannot have it un-hidden by re-running this script.
 *
 * INVARIANTS (mirrors GALERA_SOCIAL_FEED_PLANO.md §8):
 *   • Marco imutável: existing docs are NEVER touched.
 *   • hiddenByAuthor:false on every new doc (required by feed server-side filter).
 *   • occurredAt = real event date (promotionDate / competition date).
 *   • authorName/Belt/Stripes taken from student's CURRENT state (can go stale —
 *     acceptable, same as kudos/fighterProfiles pattern).
 *
 * ID SLUG FUNCTION (must match client Dart implementation):
 *   slugify(name) → name.trim().toLowerCase(), non-alphanum replaced by '_',
 *   leading/trailing underscores stripped.
 *
 * HOW TO RUN:
 *   # 1. Obtain a service-account key for arpjj-76350 and set the env var:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json
 *
 *   # 2. Dry-run first (counts + lists, NO writes):
 *   node functions/scripts/backfill_feed_posts.js --dry-run
 *
 *   # 3. Apply (writes only missing docs):
 *   node functions/scripts/backfill_feed_posts.js
 *
 *   # 4. After the script completes, deploy firestore.rules (adds feedPosts +
 *        likes rules) and then ship the app update.
 *
 * Project: arpjj-76350
 */

'use strict';

const path = require('path');
const admin = require('firebase-admin');

// ─── Config ───────────────────────────────────────────────────────────────────

const PROJECT_ID = 'arpjj-76350';
const DRY_RUN    = process.argv.includes('--dry-run');
const VERBOSE    = process.argv.includes('--verbose');

const SERVICE_ACCOUNT_PATH = process.env.GOOGLE_APPLICATION_CREDENTIALS || '';

// ─── Firebase init ─────────────────────────────────────────────────────────────

let serviceAccount = null;
if (SERVICE_ACCOUNT_PATH) {
  // eslint-disable-next-line import/no-dynamic-require, global-require
  serviceAccount = require(path.resolve(SERVICE_ACCOUNT_PATH));
}

admin.initializeApp(
  serviceAccount
    ? {
        credential: admin.credential.cert(serviceAccount),
        projectId: serviceAccount.project_id || PROJECT_ID,
      }
    : { projectId: process.env.GCLOUD_PROJECT || PROJECT_ID },
);

const db            = admin.firestore();
const FieldValue    = admin.firestore.FieldValue;
const Timestamp     = admin.firestore.Timestamp;

// ─── Helpers ──────────────────────────────────────────────────────────────────

/** Format a Date as yyyymmdd (UTC). */
function yyyymmdd(date) {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  const d = String(date.getUTCDate()).padStart(2, '0');
  return `${y}${m}${d}`;
}

/**
 * Slugify a competition name to produce a stable post-id component.
 * MUST match the Dart client implementation (FeedPostsService):
 *   name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '')
 */
function slugify(name) {
  return name
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_|_$/g, '');
}

/**
 * Months between two JS Dates (same formula as Dart's monthsBetween helper in
 * showcase_builder.dart).
 */
function monthsBetween(from, to) {
  return (to.getFullYear() - from.getFullYear()) * 12
       + (to.getMonth() - from.getMonth());
}

/**
 * Batch-read up to `chunkSize` doc refs at once (Admin SDK getAll limit = 500).
 * Returns a Set of existing doc ids.
 */
async function existingDocIds(refs, chunkSize = 490) {
  const existing = new Set();
  for (let i = 0; i < refs.length; i += chunkSize) {
    const chunk = refs.slice(i, i + chunkSize);
    const snaps = await db.getAll(...chunk);
    for (const snap of snaps) {
      if (snap.exists) existing.add(snap.id);
    }
  }
  return existing;
}

/**
 * Commit a Firestore batch and open a fresh one.
 */
async function flushBatch(batch, opsRef, dryRun) {
  if (opsRef.count === 0) return;
  if (!dryRun) await batch.commit();
  opsRef.count = 0;
  return db.batch();
}

// ─── Post builders ────────────────────────────────────────────────────────────

/**
 * Build feedPost docs for all beltProgressions of a single student.
 *
 * Matches showcase_builder.dart _buildGraduations (verified/Firestore source),
 * computing effort (trainingsToReach) as delta of baselineCount between
 * consecutive promotions and monthsToReach from student.startDate.
 *
 * Returns Array<{postId, data}>.
 */
function buildGradPosts({ uid, academyId, student, progressions }) {
  // Sort ascending by promotionDate (same order as showcase_builder).
  const asc = [...progressions].sort(
    (a, b) => a.promotionDate.toMillis() - b.promotionDate.toMillis(),
  );

  const posts = [];
  let prevBaseline = 0;
  // Student startDate; fall back to the first progression date if absent.
  const startDate = student.startDate
    ? student.startDate.toDate()
    : (asc.length > 0 ? asc[0].promotionDate.toDate() : new Date());
  let prevDate = startDate;

  for (const bp of asc) {
    const promotionDate = bp.promotionDate.toDate();
    // baselineCount mirrors BeltProgression.baselineCount in Dart:
    //   effectiveCountAtPromotion ?? totalClasses
    const baselineCount =
      (typeof bp.effectiveCountAtPromotion === 'number')
        ? bp.effectiveCountAtPromotion
        : (bp.totalClasses ?? 0);

    const trainingsToReach = Math.max(0, baselineCount - prevBaseline);
    const months           = Math.max(0, monthsBetween(prevDate, promotionDate));
    const isBeltChange     = bp.previousBelt !== bp.newBelt;
    const belt             = bp.newBelt   || 'white';
    const stripes          = bp.newStripes ?? 0;

    const dateStr = yyyymmdd(promotionDate);
    const postId  = `grad_${uid}_${dateStr}_${belt}${stripes}`;

    posts.push({
      postId,
      data: {
        postId,
        authorUid:      uid,
        type:           'graduacao',
        payload: {
          belt,
          stripes,
          isBeltChange,
          trainingsToReach,
          monthsToReach: months,
        },
        occurredAt:     bp.promotionDate,   // real event Timestamp
        createdAt:      FieldValue.serverTimestamp(),
        academyId:      academyId,
        hiddenByAuthor: false,
        likeCount:      0,
        authorName:     student.displayName,
        authorBelt:     student.currentBelt   || 'white',
        authorStripes:  student.currentStripes ?? 0,
        authorPhotoUrl: student.photoUrl       || null,
        dedupeKey:      postId,
      },
    });

    prevBaseline = baselineCount;
    prevDate     = promotionDate;
  }

  return posts;
}

/**
 * Build feedPost docs for all competition achievements of a single student.
 *
 * Matches showcase_builder.dart _buildCompetitions (verified/Firestore source).
 * Uses competitionName (falls back to title) for the slug, same as the Dart
 * code (showcase_builder.dart:252-255).
 *
 * Returns Array<{postId, data}>.
 */
function buildCompPosts({ uid, academyId, student, competitions }) {
  const posts = [];

  for (const ach of competitions) {
    // Name: competitionName priority over title (matches showcase_builder:252-255).
    const rawName = (ach.competitionName && ach.competitionName.trim())
      ? ach.competitionName
      : (ach.title || '');
    if (!rawName) continue;

    const compDate = ach.date.toDate();
    const dateStr  = yyyymmdd(compDate);
    const slug     = slugify(rawName);
    if (!slug) continue;

    const postId = `comp_${uid}_${dateStr}_${slug}`;

    posts.push({
      postId,
      data: {
        postId,
        authorUid:      uid,
        type:           'competicao',
        payload: {
          name:     rawName,
          position: ach.position || 'participant',
        },
        occurredAt:     ach.date,           // real event Timestamp
        createdAt:      FieldValue.serverTimestamp(),
        academyId:      academyId,
        hiddenByAuthor: false,
        likeCount:      0,
        authorName:     student.displayName,
        authorBelt:     student.currentBelt   || 'white',
        authorStripes:  student.currentStripes ?? 0,
        authorPhotoUrl: student.photoUrl       || null,
        dedupeKey:      postId,
      },
    });
  }

  return posts;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log('=== Backfill feedPosts (graduacao + competicao) ===');
  console.log(`project:  ${(serviceAccount && serviceAccount.project_id) || process.env.GCLOUD_PROJECT || PROJECT_ID}`);
  console.log(`dry-run:  ${DRY_RUN}`);
  console.log('');

  // ── 1. Enumerate academies ─────────────────────────────────────────────────
  const academiesSnap = await db.collection('academies').get();
  console.log(`Academies found: ${academiesSnap.size}`);

  // Accumulate all candidate posts across all academies before writing.
  // Key: postId → data  (later deduplicated by postId so cross-academy
  // conflicts use the first-seen copy — acceptable since ids include uid+date).
  const candidates = new Map(); // postId → data

  let totalStudents     = 0;
  let claimedStudents   = 0;
  let totalProgressions = 0;
  let totalCompetitions = 0;

  for (const academyDoc of academiesSnap.docs) {
    const academyId = academyDoc.id;

    // ── 2. Load claimed students for this academy ──────────────────────────
    const studentsSnap = await db
      .collection('academies').doc(academyId)
      .collection('students')
      .where('linkedUserId', '!=', null)
      .get();

    totalStudents  += studentsSnap.size;
    claimedStudents += studentsSnap.size;

    if (studentsSnap.empty) continue;

    // Build a map studentId → studentData for quick lookup.
    const studentMap = new Map();
    for (const sDoc of studentsSnap.docs) {
      const d = sDoc.data();
      studentMap.set(sDoc.id, {
        id:            sDoc.id,
        linkedUserId:  d.linkedUserId,
        displayName:   d.nickname && d.nickname.trim()
          ? d.nickname.trim()
          : (d.fullName || ''),
        currentBelt:   d.currentBelt   || 'white',
        currentStripes:(typeof d.currentStripes === 'number') ? d.currentStripes : 0,
        photoUrl:      d.photoUrl      || null,
        startDate:     d.startDate     || null,
      });
    }

    const studentIds = [...studentMap.keys()];

    // ── 3. Load beltProgressions in batches of 10 (whereIn limit) ─────────
    // Firestore whereIn supports up to 30 values; we batch 10 to be safe.
    const bpBySid = new Map(); // studentId → BeltProgression[]
    for (let i = 0; i < studentIds.length; i += 10) {
      const chunk = studentIds.slice(i, i + 10);
      const bpSnap = await db
        .collection('academies').doc(academyId)
        .collection('beltProgressions')
        .where('studentId', 'in', chunk)
        .get();
      for (const bDoc of bpSnap.docs) {
        const bd = bDoc.data();
        const sid = bd.studentId;
        if (!bpBySid.has(sid)) bpBySid.set(sid, []);
        bpBySid.get(sid).push(bd);
      }
      totalProgressions += bpSnap.size;
    }

    // ── 4. Load competition achievements in batches of 10 ─────────────────
    const compBySid = new Map(); // studentId → Achievement[]
    for (let i = 0; i < studentIds.length; i += 10) {
      const chunk = studentIds.slice(i, i + 10);
      const achSnap = await db
        .collection('academies').doc(academyId)
        .collection('achievements')
        .where('studentId', 'in', chunk)
        .where('type', '==', 'competition')
        .get();
      for (const aDoc of achSnap.docs) {
        const ad = aDoc.data();
        const sid = ad.studentId;
        if (!compBySid.has(sid)) compBySid.set(sid, []);
        compBySid.get(sid).push(ad);
      }
      totalCompetitions += achSnap.size;
    }

    // ── 5. Build candidate posts per student ──────────────────────────────
    for (const [sid, student] of studentMap.entries()) {
      const uid = student.linkedUserId;

      const progressions = bpBySid.get(sid) || [];
      const competitions = compBySid.get(sid) || [];

      const gradPosts = buildGradPosts({ uid, academyId, student, progressions });
      const compPosts = buildCompPosts({ uid, academyId, student, competitions });

      for (const p of [...gradPosts, ...compPosts]) {
        if (!candidates.has(p.postId)) {
          candidates.set(p.postId, p.data);
        }
      }
    }

    console.log(
      `  academy ${academyId}: ${studentsSnap.size} claimed students, ` +
      `${[...bpBySid.values()].reduce((s, a) => s + a.length, 0)} progressions, ` +
      `${[...compBySid.values()].reduce((s, a) => s + a.length, 0)} competitions`,
    );
  }

  console.log('');
  console.log(`Total claimed students:   ${claimedStudents}`);
  console.log(`Total beltProgressions:   ${totalProgressions}`);
  console.log(`Total competition achiev: ${totalCompetitions}`);
  console.log(`Candidate feedPosts:      ${candidates.size}`);
  console.log('');

  if (candidates.size === 0) {
    console.log('Nothing to write. Exiting.');
    return;
  }

  // ── 6. Filter to only docs that do NOT yet exist (create-if-absent) ────────
  const candidateIds   = [...candidates.keys()];
  const feedPostsCol   = db.collection('feedPosts');
  const candidateRefs  = candidateIds.map((id) => feedPostsCol.doc(id));

  console.log('Checking which feedPosts already exist...');
  const alreadyExisting = await existingDocIds(candidateRefs);
  console.log(`Already present (skip):   ${alreadyExisting.size}`);

  const toWrite = candidateIds.filter((id) => !alreadyExisting.has(id));
  console.log(`To write:                 ${toWrite.length}`);
  console.log('');

  if (toWrite.length === 0) {
    console.log('All candidates already exist. Nothing to write.');
    return;
  }

  // ── 7. Write in batches of 450 ─────────────────────────────────────────────
  let batch     = db.batch();
  let batchOps  = { count: 0 };
  let written   = 0;

  for (const postId of toWrite) {
    const data = candidates.get(postId);
    if (VERBOSE) console.log(`  + ${postId}`);

    batch.create(feedPostsCol.doc(postId), data);
    batchOps.count++;
    written++;

    if (batchOps.count >= 450) {
      batch = await flushBatch(batch, batchOps, DRY_RUN) || db.batch();
    }
  }
  await flushBatch(batch, batchOps, DRY_RUN);

  console.log('=== Done ===');
  console.log(`Written:                  ${written}${DRY_RUN ? ' (dry-run, NOT committed)' : ''}`);
  console.log(`Skipped (existed):        ${alreadyExisting.size}`);
  console.log('');
  if (DRY_RUN) {
    console.log('DRY RUN — re-run without --dry-run to apply.');
    console.log('Then deploy firestore.rules (feedPosts + likes rules) + ship app update.');
  } else {
    console.log('APPLIED — deploy firestore.rules (feedPosts + likes) then ship app.');
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('FATAL:', e);
    process.exit(1);
  });
