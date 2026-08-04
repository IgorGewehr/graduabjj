'use strict';

// QA — AULA PARTICULAR: a cobrança financial type='private_lesson' concede UMA
// presença real ao aluno quando paga (sem turma/plano), via
// grantPrivateLessonAttendance. Estes testes fixam os INVARIANTES de correção
// que tornam o grant exactly-once e a liquidação resiliente a crash, espelhando
// o estilo source-pinning de mp_pix_payer_validation.test.js. Quebram se alguém
// regredir a idempotência, o id determinístico ou o caminho completeGrant.
//
// Ancorado em functions/server_functions.js:
//   - function grantPrivateLessonAttendance(...)   -> tx idempotente
//   - mpMktSettle ramo 'fin'                        -> grant pós-commit + completeGrant
//   - exports.markPrivateLessonGiven               -> grant manual gated p/ staff

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const SRC = fs.readFileSync(
  path.join(__dirname, '..', 'server_functions.js'),
  'utf8'
);

// Recorta o corpo de uma `function nome(...) { ... }` até o `\n}` de coluna 0.
function fnBody(decl) {
  const start = SRC.indexOf(decl);
  assert.ok(start > 0, `${decl} presente`);
  const end = SRC.indexOf('\n}', start);
  assert.ok(end > start, `${decl} delimitado`);
  return SRC.slice(start, end);
}

test('grantPrivateLessonAttendance é idempotente por financial (flag + id determinístico)', () => {
  const body = fnBody('async function grantPrivateLessonAttendance');

  // Guard de idempotência: bail quando a cobrança já concedeu a presença.
  assert.ok(
    body.includes("finSnap.data().attendanceGranted === true"),
    'guard attendanceGranted === true presente'
  );

  // Id determinístico inclui o financialId (sufixo) — duas aulas no mesmo dia
  // geram presenças distintas (a regra padrão {studentId}_{classId}_{YYYYMMDD}
  // colidiria e perderia uma presença paga).
  assert.ok(
    body.includes('aula_particular') &&
      body.includes('String(financialId).slice(-6)'),
    'id de presença determinístico com sufixo do financialId'
  );

  // Presença já existente é reconciliada SEM re-incrementar o contador.
  assert.ok(
    body.includes('if (attSnap.exists)'),
    'reconciliação sem duplo incremento quando a presença já existe'
  );

  // Cria a presença E incrementa attendanceCount na MESMA transação (espelha o
  // markPresent do cliente — consistência de ranking/streak/graduação).
  assert.ok(
    body.includes('tx.set(attRef') &&
      body.includes("attendanceCount: admin.firestore.FieldValue.increment(1)"),
    'presença + incremento de attendanceCount atômicos na transação'
  );
});

test('mpMktSettle (ramo fin) concede a presença e tem caminho completeGrant', () => {
  // O grant roda APÓS o commit do dinheiro, gated por type === 'private_lesson'.
  assert.ok(
    SRC.includes("finSettle.finData?.type === 'private_lesson'") &&
      SRC.includes('grantPrivateLessonAttendance(academyId, docId, finSettle.finData'),
    'grant pós-liquidação para private_lesson presente'
  );

  // Crash entre o commit do dinheiro e o grant: re-entrega do webhook vê
  // paid && !attendanceGranted e completa só o grant (espelho do completeStock).
  assert.ok(
    SRC.includes('completeGrant: true'),
    'caminho completeGrant (recuperação de crash) presente'
  );
  assert.ok(
    SRC.includes("snap.data().type === 'private_lesson'") &&
      SRC.includes("snap.data().attendanceGranted !== true"),
    'detecção paid && !attendanceGranted dentro da transação de settle'
  );
});

test('markPrivateLessonGiven é gated para staff e reusa o grant idempotente', () => {
  const start = SRC.indexOf('exports.markPrivateLessonGiven');
  assert.ok(start > 0, 'callable markPrivateLessonGiven presente');
  const body = SRC.slice(start, SRC.indexOf('\n});', start));

  assert.ok(
    body.includes('getUserAcademyMembership(request.auth.uid, academyId)') &&
      body.includes("membership.role === 'admin'") &&
      body.includes("membership.role === 'instructor'"),
    'gate admin/instrutor via getUserAcademyMembership'
  );
  assert.ok(
    body.includes("fin.type !== 'private_lesson'"),
    'recusa cobrança que não é aula particular'
  );
  // Reusa o MESMO helper do webhook — conceder manual + receber MP não duplica.
  assert.ok(
    body.includes('grantPrivateLessonAttendance(academyId, financialId, fin'),
    'reusa grantPrivateLessonAttendance (convergência manual/webhook)'
  );
});
