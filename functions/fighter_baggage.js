// ============================================================
// BAGAGEM DO LUTADOR — importa a identidade do atleta para a ficha da NOVA
// academia no momento do vínculo multi-academia (joinAcademy).
//
// Tese do produto (B2C): a identidade é do LUTADOR e viaja com ele — ele chega
// na academia nova já de faixa azul, com sua caminhada, seus campeonatos e
// seus dados pessoais. O professor novo ajusta o que quiser depois.
//
// Política de cópia (conservadora, idempotente):
//  - Ficha (fill-não-sobrescreve): campo pessoal só é copiado se estiver VAZIO
//    na ficha nova — nunca sobrescreve o que o professor novo digitou.
//  - Graduação: só copiada se a ficha nova está no DEFAULT (sem sportData e
//    faixa branca sem graus). Faixa atual viaja; o HISTÓRICO verificado de
//    promoções (beltProgressions) NÃO — pertence à academia que graduou.
//  - startDate: fica a mais antiga (a caminhada começa onde começou).
//  - initialAttendanceCount: total de aulas verificadas da academia de origem
//    vira baseline "informado" na nova (mesma semântica do mestre informar
//    treinos anteriores ao app) — só quando a ficha nova ainda não tem nada.
//  - selfGraduations/selfCompetitions: declarações do PRÓPRIO atleta — 100%
//    portáteis; copiadas com o MESMO doc-id (re-runs não duplicam).
//  - Conquistas de competição VERIFICADAS da origem viram selfCompetitions na
//    nova academia (id determinístico import_<id>): a nova academia não
//    verificou aquilo, mas o cartel do atleta continua contando a história.
//  - NUNCA copiados: attendance, financeiro, retention.*, notas internas.
// ============================================================

/**
 * Importa a bagagem do lutador para a ficha recém-vinculada.
 * Best-effort: lança apenas em erro de programação; chamadas de leitura/
 * escrita têm falha isolada por etapa.
 *
 * @param {object} args
 * @param {FirebaseFirestore.Firestore} args.db
 * @param {string} args.uid           auth uid do atleta
 * @param {string} args.targetAcademyId
 * @param {string} args.targetStudentId
 * @return {Promise<{imported: string[]}>} etapas efetivamente aplicadas
 */
async function importFighterBaggage({db, uid, targetAcademyId, targetStudentId}) {
  const imported = [];

  // ── 1. Acha a MELHOR ficha de origem (outra academia do mapping) ─────────
  // O studentId da origem pode morar em 3 lugares, conforme a era do vínculo:
  //  (a) mapping.academyDetails[aid].studentId (formato atual);
  //  (b) academies/{aid}/users/{uid}.studentId (formato LEGADO — contas
  //      antigas como a base da T23 vivem aqui);
  //  (c) students.linkedUserId == uid (fallback por query).
  const mapSnap = await db.collection('userAcademyMapping').doc(uid).get();
  const mapping = mapSnap.exists ? (mapSnap.data() || {}) : {};
  const details = mapping.academyDetails || {};
  const candidateIds = (mapping.academyIds || [])
      .filter((aid) => aid !== targetAcademyId);
  if (candidateIds.length === 0) return {imported};

  let source = null; // {academyId, studentId, data}
  for (const aid of candidateIds) {
    let sid = details[aid] && details[aid].studentId;
    if (!sid) {
      const au = await db.collection('academies').doc(aid)
          .collection('users').doc(uid).get();
      sid = au.exists ? (au.data() || {}).studentId : null;
    }
    let data = null;
    if (sid) {
      const snap = await db.collection('academies').doc(aid)
          .collection('students').doc(sid).get();
      if (snap.exists) data = snap.data() || {};
    }
    if (!data) {
      const q = await db.collection('academies').doc(aid)
          .collection('students')
          .where('linkedUserId', '==', uid).limit(1).get();
      if (!q.empty) {
        sid = q.docs[0].id;
        data = q.docs[0].data() || {};
      }
    }
    if (!data) continue;
    const total = (data.initialAttendanceCount || 0) + (data.attendanceCount || 0);
    if (!source || total > source.total) {
      source = {academyId: aid, studentId: sid, data, total};
    }
  }
  if (!source) return {imported};
  const src = source.data;

  const targetRef = db.collection('academies').doc(targetAcademyId)
      .collection('students').doc(targetStudentId);
  const targetSnap = await targetRef.get();
  if (!targetSnap.exists) return {imported};
  const tgt = targetSnap.data() || {};

  // ── 2. Ficha: pessoais fill-não-sobrescreve + caminhada + graduação ──────
  const upd = {};
  const empty = (v) => v === undefined || v === null || v === '' ||
      (Array.isArray(v) && v.length === 0);

  const FILL_FIELDS = [
    'phone', 'cpf', 'birthDate', 'weight', 'height', 'photoUrl', 'nickname',
    'gender', 'emergencyContact', 'category',
  ];
  for (const f of FILL_FIELDS) {
    if (empty(tgt[f]) && !empty(src[f])) upd[f] = src[f];
  }

  // startDate: a caminhada começa onde começou (fica a mais antiga).
  if (src.startDate && (!tgt.startDate ||
      src.startDate.toMillis() < tgt.startDate.toMillis())) {
    upd.startDate = src.startDate;
  }

  // Aulas verificadas de origem viram baseline "informado" na ficha nova —
  // só quando ela ainda não tem contagem nenhuma (ficha recém-criada).
  const tgtTotal = (tgt.initialAttendanceCount || 0) + (tgt.attendanceCount || 0);
  if (tgtTotal === 0 && source.total > 0) {
    upd.initialAttendanceCount = source.total;
  }

  // Graduação: o atleta chega de faixa. Só se a ficha nova está no DEFAULT
  // (professor ainda não definiu nada) — senão a palavra é dele. Atenção:
  // a criação da ficha grava um sportData default (branca/0), então "tem
  // sportData" não significa "professor definiu" — default = toda modalidade
  // em grau inicial sem graus.
  const sportDataIsDefault = (sd) => {
    if (sd === undefined || sd === null) return true;
    const entries = Object.values(sd);
    if (entries.length === 0) return true;
    return entries.every((g) => {
      const grade = (g && g.currentGrade) || 'white';
      const stripes = (g && g.currentStripes) || 0;
      return (grade === 'white' || grade === '') && stripes === 0;
    });
  };
  const tgtIsDefaultGrade =
      sportDataIsDefault(tgt.sportData) &&
      (!tgt.currentBelt || tgt.currentBelt === 'white') &&
      (tgt.currentStripes || 0) === 0;
  if (tgtIsDefaultGrade) {
    // sportData efetivo da ORIGEM: fichas legadas guardam a faixa só em
    // currentBelt/currentStripes (sportData ausente ou default) — deriva o
    // sportData.bjj a partir do legado, senão o app (que resolve a faixa
    // pelo sportData PRIMEIRO) continuaria mostrando branca.
    let sdToWrite = null;
    if (!sportDataIsDefault(src.sportData)) {
      sdToWrite = src.sportData;
    } else if (src.currentBelt && src.currentBelt !== 'white') {
      sdToWrite = {bjj: {
        currentGrade: src.currentBelt,
        currentStripes: src.currentStripes || 0,
      }};
    }
    if (sdToWrite) upd.sportData = sdToWrite;
    if (src.currentBelt) upd.currentBelt = src.currentBelt;
    if (src.currentStripes !== undefined) upd.currentStripes = src.currentStripes;
    if (!empty(src.sports)) upd.sports = src.sports;
    if (src.primarySport) upd.primarySport = src.primarySport;
  }

  if (Object.keys(upd).length > 0) {
    upd.updatedAt = new Date();
    await targetRef.update(upd);
    imported.push(`ficha:${Object.keys(upd).join(',')}`);
  }

  // ── 3. Self-records (declarações do atleta — portáteis por definição) ────
  const srcStudentRef = db.collection('academies').doc(source.academyId)
      .collection('students').doc(source.studentId);
  for (const sub of ['selfGraduations', 'selfCompetitions']) {
    const docs = await srcStudentRef.collection(sub).get();
    let copied = 0;
    for (const d of docs.docs) {
      const ref = targetRef.collection(sub).doc(d.id); // mesmo id = idempotente
      const exists = (await ref.get()).exists;
      if (!exists) {
        await ref.set(d.data());
        copied++;
      }
    }
    if (copied > 0) imported.push(`${sub}:${copied}`);
  }

  // ── 4. Competições VERIFICADAS de origem → selfCompetitions na nova ──────
  // (a nova academia não as verificou; entram como cartel declarado do
  // atleta, com id determinístico p/ nunca duplicar em re-runs)
  const achievements = await db.collection('academies').doc(source.academyId)
      .collection('achievements')
      .where('studentId', '==', source.studentId)
      .where('type', '==', 'competition')
      .get();
  let compCopied = 0;
  for (const a of achievements.docs) {
    const ad = a.data() || {};
    const ref = targetRef.collection('selfCompetitions').doc(`import_${a.id}`);
    const exists = (await ref.get()).exists;
    if (exists) continue;
    await ref.set({
      sport: ad.sport || 'bjj',
      name: ad.competitionName || ad.title || 'Competição',
      date: ad.date || new Date(),
      placement: ad.position || null,
      external: true,
      externalAcademy: null,
      source: 'self',
      createdBy: uid,
      createdAt: new Date(),
      importedFrom: `${source.academyId}/achievements/${a.id}`,
    });
    compCopied++;
  }
  if (compCopied > 0) imported.push(`achievements→selfComps:${compCopied}`);

  return {imported};
}

module.exports = {importFighterBaggage};
