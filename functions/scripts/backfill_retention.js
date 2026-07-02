/**
 * Backfill B-R1 — semeia o mapa `retention` no doc de TODOS os alunos
 * (academies/{aid}/students/{sid}) a partir das presenças dos últimos 60 dias,
 * ANTES do deploy da CF `onAttendanceWrite` / `computeRetentionDaily`
 * (plano REPAGINADA_ADMIN_ALUNO100 §2.4 — runbook: backfill → rules/índices →
 * CF → app). Sem ele o radar nasce dizendo que todo mundo está a 999 dias sem
 * treinar.
 *
 * O QUE ESCREVE (dot-notation, nunca sobrescreve campos irmãos):
 *   retention.lastAttendanceDate   — max(date) das presenças (só se maior que
 *                                    o já persistido — nunca regride)
 *   retention.attendanceLast7d     — presenças nos últimos 7 dias
 *   retention.attendanceLast30d    — presenças nos últimos 30 dias
 *   retention.weeklyBuckets        — mapa { 'YYYY-Www': int } das últimas ~9
 *                                    semanas ISO (segunda-feira início, dia
 *                                    civil em America/Sao_Paulo) — escrito
 *                                    inteiro (o seed é a fonte da verdade da
 *                                    janela; roda ANTES da CF incremental)
 *   statusChangedAt / statusChangeReason — semeados como null SÓ se ausentes
 *                                    (§2.3: churn consumado passa a datar
 *                                    transições daqui pra frente)
 *
 * O QUE NÃO FAZ:
 *   • NÃO computa riskScore/riskLevel — isso é do job diário
 *     computeRetentionDaily (functions/retention_functions.js).
 *   • NÃO toca em publicProfiles/fighterProfiles (retention.* é dado interno
 *     da academia, invisível ao aluno — invariante §10).
 *
 * IDEMPOTÊNCIA: re-rodar recomputa os mesmos valores a partir da mesma fonte
 * (attendance). Campos condicionais (lastAttendanceDate só-avança,
 * statusChangedAt só-se-ausente) nunca regridem estado já existente.
 *
 * COMO RODAR (de dentro de functions/):
 *   # 1. Service-account key do projeto arpjj-76350:
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json
 *
 *   # 2. Dry-run primeiro (contagens, NENHUM write):
 *   node scripts/backfill_retention.js --dry-run
 *
 *   # 3. Aplicar:
 *   node scripts/backfill_retention.js
 *
 * Project: arpjj-76350
 */

'use strict';

const path = require('path');
const admin = require('firebase-admin');

// ─── Config ───────────────────────────────────────────────────────────────────

const PROJECT_ID = 'arpjj-76350';
const DRY_RUN = process.argv.includes('--dry-run');
const VERBOSE = process.argv.includes('--verbose');

/** Janela de varredura de attendance (dias). */
const SCAN_DAYS = 60;
/** Janela de retenção dos weeklyBuckets: semana corrente + 8 anteriores. */
const BUCKET_WEEKS = 9;

const SERVICE_ACCOUNT_PATH = process.env.GOOGLE_APPLICATION_CREDENTIALS || '';

// ─── Firebase init (mesmo padrão dos demais scripts em functions/scripts/) ────

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

const db = admin.firestore();
const Timestamp = admin.firestore.Timestamp;

// ─── Calendário: semana ISO em America/Sao_Paulo ──────────────────────────────
// (Espelho dos helpers de functions/retention_functions.js — mesma convenção:
// segunda-feira início, chave 'YYYY-Www' com ISO week-year.)

const SP_TZ = 'America/Sao_Paulo';
const MS_DAY = 86400000;
const MS_WEEK = 7 * MS_DAY;

const spDayFmt = new Intl.DateTimeFormat('en-CA', {
  timeZone: SP_TZ, year: 'numeric', month: '2-digit', day: '2-digit',
});

/** Dia civil em SP materializado como Date UTC-midnight (só aritmética). */
function spCivilDate(date) {
  const [y, m, d] = spDayFmt.format(date).split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

/** Segunda-feira da semana do dia civil. */
function mondayOf(civil) {
  const dayNum = (civil.getUTCDay() + 6) % 7; // Mon=0 .. Sun=6
  return new Date(civil.getTime() - dayNum * MS_DAY);
}

/** Chave ISO 'YYYY-Www' (quinta-feira da semana decide o week-year). */
function isoWeekKeyFromCivil(civil) {
  const dayNum = (civil.getUTCDay() + 6) % 7;
  const thursday = new Date(civil.getTime() + (3 - dayNum) * MS_DAY);
  const isoYear = thursday.getUTCFullYear();
  const jan4 = new Date(Date.UTC(isoYear, 0, 4));
  const firstThursday = new Date(jan4.getTime() + (3 - ((jan4.getUTCDay() + 6) % 7)) * MS_DAY);
  const week = 1 + Math.round((thursday.getTime() - firstThursday.getTime()) / MS_WEEK);
  return `${isoYear}-W${String(week).padStart(2, '0')}`;
}

function isoWeekKey(date) {
  return isoWeekKeyFromCivil(spCivilDate(date));
}

/** Chaves das últimas `n` semanas ISO (incluindo a corrente). */
function allowedWeekKeys(now, n = BUCKET_WEEKS) {
  const keys = new Set();
  let monday = mondayOf(spCivilDate(now));
  for (let i = 0; i < n; i++) {
    keys.add(isoWeekKeyFromCivil(monday));
    monday = new Date(monday.getTime() - MS_WEEK);
  }
  return keys;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function readDate(raw) {
  if (!raw) return null;
  if (typeof raw.toDate === 'function') return raw.toDate();
  if (raw instanceof Date) return raw;
  if (typeof raw === 'string') {
    const d = new Date(raw);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log('=== Backfill B-R1: retention.* (últimos 60d de attendance) ===');
  console.log(`project:  ${(serviceAccount && serviceAccount.project_id) || process.env.GCLOUD_PROJECT || PROJECT_ID}`);
  console.log(`dry-run:  ${DRY_RUN}`);
  console.log('');

  const now = new Date();
  const cutoff60 = new Date(now.getTime() - SCAN_DAYS * MS_DAY);
  const cutoff30 = new Date(now.getTime() - 30 * MS_DAY);
  const cutoff7 = new Date(now.getTime() - 7 * MS_DAY);
  const allowed = allowedWeekKeys(now);

  const academiesSnap = await db.collection('academies').get();
  console.log(`Academies found: ${academiesSnap.size}`);
  console.log('');

  let totalStudents = 0;
  let totalWrites = 0;
  let totalAttendance = 0;

  for (const academyDoc of academiesSnap.docs) {
    const academyId = academyDoc.id;
    const acadRef = academyDoc.ref;

    // ── 1. Attendance dos últimos 60d, agrupada por aluno ──────────────────
    const attSnap = await acadRef.collection('attendance')
      .where('date', '>=', Timestamp.fromDate(cutoff60))
      .get();

    const attByStudent = new Map(); // studentId → Date[]
    for (const doc of attSnap.docs) {
      const d = doc.data() || {};
      const date = readDate(d.date);
      if (!d.studentId || !date) continue;
      if (!attByStudent.has(d.studentId)) attByStudent.set(d.studentId, []);
      attByStudent.get(d.studentId).push(date);
    }
    totalAttendance += attSnap.size;

    // ── 2. Todos os alunos da academia ──────────────────────────────────────
    const studentsSnap = await acadRef.collection('students').get();
    totalStudents += studentsSnap.size;

    let batch = db.batch();
    let batchOps = 0;
    let academyWrites = 0;

    for (const sDoc of studentsSnap.docs) {
      const s = sDoc.data() || {};
      const retention = s.retention || {};
      const dates = attByStudent.get(sDoc.id) || [];

      // Janelas rolantes.
      const last7 = dates.filter((d) => d.getTime() > cutoff7.getTime()).length;
      const last30 = dates.filter((d) => d.getTime() > cutoff30.getTime()).length;

      // Última presença na janela de 60d.
      let queryLast = null;
      for (const d of dates) {
        if (!queryLast || d.getTime() > queryLast.getTime()) queryLast = d;
      }

      // Buckets das últimas ~9 semanas (mapa esparso: só semanas com presença).
      const buckets = {};
      for (const d of dates) {
        const key = isoWeekKey(d);
        if (allowed.has(key)) buckets[key] = (buckets[key] || 0) + 1;
      }

      const updates = {
        'retention.attendanceLast7d': last7,
        'retention.attendanceLast30d': last30,
        // Seed é dono da janela: escreve o mapa inteiro (roda ANTES da CF
        // incremental — nada concorre com este write).
        'retention.weeklyBuckets': buckets,
      };
      // lastAttendanceDate só-avança: nunca regride um valor já persistido.
      const storedLast = readDate(retention.lastAttendanceDate);
      if (queryLast && (!storedLast || queryLast.getTime() > storedLast.getTime())) {
        updates['retention.lastAttendanceDate'] = Timestamp.fromDate(queryLast);
      }
      // §2.3: campos de churn consumado, semeados SÓ se ausentes (uma transição
      // já datada por alguém nunca é apagada por re-run).
      if (!Object.prototype.hasOwnProperty.call(s, 'statusChangedAt')) {
        updates.statusChangedAt = null;
      }
      if (!Object.prototype.hasOwnProperty.call(s, 'statusChangeReason')) {
        updates.statusChangeReason = null;
      }

      if (VERBOSE) {
        console.log(
          `  + ${academyId}/${sDoc.id}: last7=${last7} last30=${last30} ` +
          `buckets=${Object.keys(buckets).length} last=${queryLast ? queryLast.toISOString() : '-'}`
        );
      }

      batch.update(sDoc.ref, updates);
      batchOps++;
      academyWrites++;

      if (batchOps >= 450) {
        if (!DRY_RUN) await batch.commit();
        batch = db.batch();
        batchOps = 0;
      }
    }

    if (batchOps > 0 && !DRY_RUN) await batch.commit();
    totalWrites += academyWrites;

    console.log(
      `  academy ${academyId}: ${studentsSnap.size} alunos, ` +
      `${attSnap.size} presenças/60d, ${academyWrites} docs semeados` +
      `${DRY_RUN ? ' (dry-run)' : ''}`
    );
  }

  console.log('');
  console.log('=== Done ===');
  console.log(`Total alunos:      ${totalStudents}`);
  console.log(`Total presenças:   ${totalAttendance} (últimos ${SCAN_DAYS}d)`);
  console.log(`Docs semeados:     ${totalWrites}${DRY_RUN ? ' (dry-run, NOT committed)' : ''}`);
  console.log('');
  if (DRY_RUN) {
    console.log('DRY RUN — re-rode sem --dry-run para aplicar.');
    console.log('Depois: rules/índices → CF (onAttendanceWrite + computeRetentionDaily) → app.');
  } else {
    console.log('APPLIED — siga o runbook: rules/índices → CF → app.');
    console.log('O score de risco será computado pelo job diário computeRetentionDaily.');
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('FATAL:', e);
    process.exit(1);
  });
