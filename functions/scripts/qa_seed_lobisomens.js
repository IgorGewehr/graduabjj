/**
 * QA seed — dados de teste na academia Lobisomens Jiu Jitsu (feat/onboarding-quiz-interactive).
 *
 * Cria SÓ docs com id `qa_*` e nome "[QA] ..." — nada que já exista é alterado,
 * exceto no modo opt-in `--admin-link` (ver abaixo, com backup completo).
 *
 *   DRY RUN (padrão, só lê):        node functions/scripts/qa_seed_lobisomens.js --email=<admin>
 *   CRIAR dados de teste:           node functions/scripts/qa_seed_lobisomens.js --email=<admin> --apply
 *   + vincular SEU admin a uma ficha (testa a correção do desvincular de admin):
 *                                   node functions/scripts/qa_seed_lobisomens.js --email=<admin> --apply --admin-link
 *   REMOVER tudo (e restaurar o admin): node functions/scripts/qa_seed_lobisomens.js --email=<admin> --cleanup
 *
 * Auth: Application Default Credentials (gcloud auth application-default login).
 *
 * SEGURANÇA: recusa rodar se o nome da academia resolvida não contiver
 * "lobisomens" (a menos que --academy=<id> E --i-know-this-is-not-lobisomens).
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

// Sem e-mail padrão de propósito: um e-mail digitado errado cairia numa conta
// que não existe (ou, pior, em outra) — e o repositório não guarda e-mail pessoal.
const EMAIL_ARG = process.argv.find((a) => a.startsWith('--email='));
if (!EMAIL_ARG || !EMAIL_ARG.split('=')[1]) {
  console.error('Informe a conta admin da academia de teste: --email=<e-mail do admin>');
  process.exit(1);
}
const EMAIL = EMAIL_ARG.split('=')[1];
const APPLY = process.argv.includes('--apply');
const CLEANUP = process.argv.includes('--cleanup');
const ADMIN_LINK = process.argv.includes('--admin-link');
const ACADEMY_ARG = (process.argv.find((a) => a.startsWith('--academy=')) || '').split('=')[1];
const FORCE = process.argv.includes('--i-know-this-is-not-lobisomens');
const PROJECT_ID = process.env.GCLOUD_PROJECT || 'arpjj-76350';
const BACKUP = path.join(__dirname, '.qa_backup.json');

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;

// Backup/restauração que PRESERVA o tipo Timestamp (JSON.stringify viraria um
// objeto comum e o restore gravaria um mapa no lugar de joinedAt etc.).
const isTs = (v) => v && typeof v.toDate === 'function' && 'seconds' in v && 'nanoseconds' in v;
function ser(v) {
  if (v === undefined) return { __undef: true };
  if (isTs(v)) return { __ts: [v.seconds, v.nanoseconds] };
  if (Array.isArray(v)) return v.map(ser);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, ser(x)]));
  return v;
}
function deser(v) {
  if (v && v.__undef) return undefined;
  if (v && v.__ts) return new Timestamp(v.__ts[0], v.__ts[1]);
  if (Array.isArray(v)) return v.map(deser);
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, deser(x)]));
  return v;
}

const S = (n) => `qa_s${n}`;
const FAKE_UID = 'qa_fake_uid';

function students(adminUid) {
  const now = Timestamp.now();
  const base = (n, name, extra = {}) => ({
    fullName: `[QA] ${name}`,
    status: 'active',
    category: 'adult',
    currentBelt: 'white',
    currentStripes: 0,
    tuitionValue: 0,
    tuitionDay: 10,
    isProfilePublic: false,
    startDate: now,
    createdAt: now,
    updatedAt: now,
    _qa: true,
    ...extra,
  });
  const list = {
    [S(1)]: base(1, 'Ana (valor personalizado)'),
    [S(2)]: base(2, 'Bruno (valor + vencimento)'),
    [S(3)]: base(3, 'Carla (vencimento personalizado)'),
    [S(4)]: base(4, 'Davi (sem personalização)'),
    [S(5)]: base(5, 'Edu (em 2 planos = conflito)'),
    [S(6)]: base(6, 'Fabio (sem plano)'),
    [S(7)]: base(7, 'Gil (conta de aluno vinculada)', {
      email: 'qa_fake@example.invalid',
      linkedUserId: FAKE_UID,
    }),
  };
  if (ADMIN_LINK) {
    list[S(8)] = base(8, 'Hugo (SEU admin vinculado)', {
      email: EMAIL,
      linkedUserId: adminUid,
    });
  }
  return list;
}

function plans() {
  const created = Timestamp.fromDate(new Date('2026-01-01T12:00:00Z'));
  return {
    qa_plan_a: {
      name: '[QA] Plano Mensal',
      monthlyValue: 200,
      billingPeriod: 'monthly',
      defaultDueDay: 10,
      classesPerWeek: null,
      studentIds: [S(1), S(2), S(3), S(4), S(5)],
      customValues: { [S(1)]: 150, [S(2)]: 120 },
      customDueDays: { [S(2)]: 20, [S(3)]: 15 },
      isActive: true,
      createdAt: created,
      updatedAt: Timestamp.now(),
      _qa: true,
    },
    qa_plan_b: {
      name: '[QA] Plano Extra',
      monthlyValue: 100,
      billingPeriod: 'monthly',
      defaultDueDay: 10,
      studentIds: [S(5)],
      customValues: {},
      customDueDays: {},
      isActive: true,
      createdAt: created,
      updatedAt: Timestamp.now(),
      _qa: true,
    },
  };
}

async function resolveAcademy(uid) {
  const mapSnap = await db.doc(`userAcademyMapping/${uid}`).get();
  if (!mapSnap.exists) throw new Error(`userAcademyMapping/${uid} não existe`);
  const m = mapSnap.data();
  const ids = ACADEMY_ARG ? [ACADEMY_ARG] : (m.academyIds || []);
  const found = [];
  for (const id of ids) {
    const a = await db.doc(`academies/${id}`).get();
    found.push({ id, name: (a.exists && (a.get('name') || a.get('academyName'))) || '(sem nome)' });
  }
  console.log('Academias da conta:', found.map((f) => `${f.name} [${f.id}]`).join(' | '));
  const match = found.filter((f) => /lobisomens/i.test(f.name));
  if (match.length === 1) return { id: match[0].id, name: match[0].name, mapping: m };
  if (ACADEMY_ARG && FORCE && found.length === 1) return { id: found[0].id, name: found[0].name, mapping: m };
  throw new Error(
    match.length === 0
      ? 'Nenhuma academia "Lobisomens" nessa conta. Abortando por segurança.'
      : 'Mais de uma academia "Lobisomens". Use --academy=<id>.',
  );
}

async function cleanup(A) {
  console.log(`\n== CLEANUP em ${A} ==`);
  // 1) restaura o admin PRIMEIRO (se o seed mexeu nele)
  if (fs.existsSync(BACKUP)) {
    const b = JSON.parse(fs.readFileSync(BACKUP, 'utf8'));
    if (b.academyId === A) {
      const mapRef = db.doc(`userAcademyMapping/${b.uid}`);
      const userRef = db.doc(`academies/${A}/users/${b.uid}`);
      const entry = deser(b.mappingEntry);
      if (entry === undefined) {
        // o seed CRIOU esse entry (só com studentId): remove, não deixa resto
        await mapRef.update({ [`academyDetails.${A}`]: FieldValue.delete() });
      } else {
        await mapRef.update({ [`academyDetails.${A}`]: entry, academyIds: FieldValue.arrayUnion(A) });
      }
      if (b.userDoc) await userRef.set(deser(b.userDoc));
      else await userRef.delete();
      console.log('  seu acesso restaurado a partir do backup');
      fs.unlinkSync(BACKUP);
    }
  }
  const ids = [...Array(8).keys()].map((i) => S(i + 1));
  for (const id of ids) await db.doc(`academies/${A}/students/${id}`).delete();
  for (const id of ['qa_plan_a', 'qa_plan_b']) await db.doc(`academies/${A}/plans/${id}`).delete();
  await db.doc(`userAcademyMapping/${FAKE_UID}`).delete();
  await db.doc(`academies/${A}/users/${FAKE_UID}`).delete();
  console.log('  removidos: alunos qa_s1..s8, planos qa_plan_a/b, conta fake');
  console.log('  (cobranças geradas por você durante o teste NÃO são removidas aqui — apague pelo app)');
}

(async () => {
  const user = await admin.auth().getUserByEmail(EMAIL);
  console.log(`conta ${EMAIL} -> uid ${user.uid}`);
  const { id: A, name } = await resolveAcademy(user.uid);
  console.log(`academia alvo: ${name} [${A}]  modo: ${CLEANUP ? 'CLEANUP' : APPLY ? 'APPLY' : 'DRY-RUN'}${ADMIN_LINK ? ' +admin-link' : ''}`);

  if (CLEANUP) return cleanup(A);

  const st = students(user.uid);
  const pl = plans();
  console.log(`\nVai criar: ${Object.keys(st).length} alunos, ${Object.keys(pl).length} planos, 1 conta fake vinculada`);
  Object.entries(st).forEach(([id, d]) => console.log(`  aluno ${id}: ${d.fullName}`));
  Object.entries(pl).forEach(([id, d]) => console.log(`  plano ${id}: ${d.name} (alunos: ${d.studentIds.length})`));
  if (!APPLY) { console.log('\nDRY-RUN: nada foi escrito. Use --apply.'); return; }

  if (ADMIN_LINK) {
    // backup COMPLETO antes de mexer no seu acesso
    const mapSnap = await db.doc(`userAcademyMapping/${user.uid}`).get();
    const userSnap = await db.doc(`academies/${A}/users/${user.uid}`).get();
    const entry = ((mapSnap.data() || {}).academyDetails || {})[A];
    fs.writeFileSync(BACKUP, JSON.stringify({
      uid: user.uid, academyId: A,
      mappingEntry: ser(entry),
      userDoc: userSnap.exists ? ser(userSnap.data()) : null,
    }, null, 2));
    console.log(`  seu acesso hoje: role(mapping)=${entry && entry.role} role(users)=${userSnap.exists ? userSnap.get('role') : '(sem doc)'}`);
    console.log(`  backup do seu acesso salvo em ${BACKUP}`);
  }

  const batch = db.batch();
  Object.entries(st).forEach(([id, d]) => batch.set(db.doc(`academies/${A}/students/${id}`), d));
  Object.entries(pl).forEach(([id, d]) => batch.set(db.doc(`academies/${A}/plans/${id}`), d));
  // conta de aluno FAKE (nenhum login real) vinculada ao qa_s7 nas duas eras
  batch.set(db.doc(`userAcademyMapping/${FAKE_UID}`), {
    academyIds: [A], primaryAcademyId: A,
    academyDetails: { [A]: { studentId: S(7), role: 'student', status: 'active' } },
    updatedAt: FieldValue.serverTimestamp(), _qa: true,
  });
  batch.set(db.doc(`academies/${A}/users/${FAKE_UID}`), { role: 'student', studentId: S(7), _qa: true });
  if (ADMIN_LINK) {
    batch.update(db.doc(`userAcademyMapping/${user.uid}`), { [`academyDetails.${A}.studentId`]: S(8) });
    batch.set(db.doc(`academies/${A}/users/${user.uid}`), { studentId: S(8) }, { merge: true });
  }
  await batch.commit();
  console.log('\nOK. Para desfazer tudo: node functions/scripts/qa_seed_lobisomens.js --cleanup');
})().catch((e) => { console.error('ERRO:', e.message); process.exit(1); });
