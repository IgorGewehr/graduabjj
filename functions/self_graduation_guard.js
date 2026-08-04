/**
 * F2c — Cloud Function de TETO para auto-graduações (selfGraduations).
 *
 * Defesa em profundidade. O aluno declara graduações passadas em
 *   academies/{aid}/students/{sid}/selfGraduations/{id}
 * (coleção aditiva, NUNCA toca beltProgressions). As Firestore Rules garantem
 * ownership + `source:'self'` imutável, mas NÃO conseguem validar a POSIÇÃO na
 * escada de graus (a ordenação vive no catálogo Dart `sports.dart`). Esta
 * função `onWrite` replica essa ordenação no Node e REJEITA (deleta o doc)
 * qualquer auto-graduação acima do TETO verificado em
 *   students/{sid}.sportData[sport].currentGrade / currentStripes
 * (BJJ legado sem sportData cai no par currentBelt/currentStripes do doc raiz).
 *
 * O client também filtra o seletor para ≤ teto (1ª camada); esta CF é a 2ª.
 *
 * Limitações conhecidas (documentadas de propósito):
 *  - A ordenação das escadas é uma RÉPLICA estática do catálogo Dart
 *    (`lib/core/sports.dart`). Se um grau novo for adicionado lá sem espelhar
 *    aqui, ele não será encontrado na escada e a auto-graduação será REJEITADA
 *    (fail-closed — preferimos negar a aceitar um grau não validável).
 *  - Esportes sem faixa (`GradeSystem.none`: boxe, MMA, musculação) não têm
 *    auto-graduação: qualquer doc é rejeitado.
 *  - Sem grau verificado para o esporte (sportData ausente), não há teto a
 *    comparar → rejeita (o aluno não tem standing verificado nesse esporte).
 */

const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

const db = admin.firestore();

// ============================================================
// Réplica das escadas de graus (espelho de lib/core/sports.dart).
// Cada escada é uma lista ORDENADA do grau mais baixo ao mais alto. `max` é o
// maxStripes daquele grau (clamp de graus internos). Sports com GradeSystem.none
// não aparecem aqui (sem faixa → sem auto-graduação).
// ============================================================

const LADDER_BJJ_ADULT = [
  { id: 'white', max: 4 }, { id: 'blue', max: 4 }, { id: 'purple', max: 4 },
  { id: 'brown', max: 4 }, { id: 'black', max: 6 },
  { id: 'red-black', max: 0 }, { id: 'red-white', max: 0 }, { id: 'red', max: 0 },
];

const LADDER_BJJ_KIDS = [
  { id: 'white', max: 4 }, { id: 'grey', max: 4 }, { id: 'grey-white', max: 4 },
  { id: 'grey-black', max: 4 }, { id: 'yellow', max: 4 }, { id: 'yellow-white', max: 4 },
  { id: 'yellow-black', max: 4 }, { id: 'orange', max: 4 }, { id: 'orange-white', max: 4 },
  { id: 'orange-black', max: 4 }, { id: 'green', max: 4 }, { id: 'green-white', max: 4 },
  { id: 'green-black', max: 4 },
];

const LADDER_MT_CBMT = [
  { id: 'white', max: 0 }, { id: 'white-red', max: 0 }, { id: 'red', max: 0 },
  { id: 'red-lightblue', max: 0 }, { id: 'light-blue', max: 0 },
  { id: 'lightblue-darkblue', max: 0 }, { id: 'dark-blue', max: 0 },
  { id: 'darkblue-black', max: 0 }, { id: 'black', max: 0 },
  { id: 'black-white', max: 0 }, { id: 'black-white-red', max: 0 },
];

const LADDER_MT_CBMTT = [
  { id: 'mt2-white', max: 0 }, { id: 'mt2-yellow', max: 0 }, { id: 'mt2-yellow-white', max: 0 },
  { id: 'mt2-green', max: 0 }, { id: 'mt2-green-white', max: 0 }, { id: 'mt2-blue', max: 0 },
  { id: 'mt2-blue-white', max: 0 }, { id: 'mt2-brown', max: 0 }, { id: 'mt2-brown-white', max: 0 },
  { id: 'mt2-red', max: 0 }, { id: 'mt2-red-white', max: 0 }, { id: 'mt2-black', max: 0 },
  { id: 'mt2-black-white', max: 0 }, { id: 'mt2-silver', max: 0 }, { id: 'mt2-gold', max: 0 },
  { id: 'mt2-gold-silver', max: 0 },
];

const LADDER_KARATE = [
  { id: 'white', max: 1 }, { id: 'yellow', max: 1 }, { id: 'orange', max: 1 },
  { id: 'green', max: 1 }, { id: 'blue', max: 1 }, { id: 'purple', max: 1 },
  { id: 'brown', max: 1 }, { id: 'black', max: 10 },
];

const LADDER_JUDO = [
  { id: 'white', max: 0 }, { id: 'grey', max: 0 }, { id: 'blue', max: 0 },
  { id: 'yellow', max: 0 }, { id: 'orange', max: 0 }, { id: 'green', max: 0 },
  { id: 'purple', max: 0 }, { id: 'brown', max: 0 }, { id: 'black', max: 0 },
  { id: 'coral', max: 0 }, { id: 'red', max: 0 },
];

const LADDER_KICKBOXING = [
  { id: 'white', max: 1 }, { id: 'yellow', max: 1 }, { id: 'orange', max: 1 },
  { id: 'green', max: 1 }, { id: 'blue', max: 1 }, { id: 'brown', max: 1 },
  { id: 'black', max: 10 },
];

const LADDER_LUTALIVRE = [
  { id: 'white', max: 0 }, { id: 'yellow', max: 0 }, { id: 'orange', max: 0 },
  { id: 'black', max: 0 }, { id: 'black-red', max: 0 }, { id: 'red-white', max: 0 },
];

// Sports sem faixa (GradeSystem.none) — nenhuma auto-graduação permitida.
const GRADELESS_SPORTS = new Set(['boxing', 'mma', 'musculacao']);

// Para cada esporte, as escadas CANDIDATAS (a real é a que contém o grau
// VERIFICADO). BJJ tem adulto+kids; Muay Thai tem as 2 federações.
const LADDERS_BY_SPORT = {
  bjj: [LADDER_BJJ_ADULT, LADDER_BJJ_KIDS],
  muaythai: [LADDER_MT_CBMT, LADDER_MT_CBMTT],
  karate: [LADDER_KARATE],
  judo: [LADDER_JUDO],
  kickboxing: [LADDER_KICKBOXING],
  lutalivre: [LADDER_LUTALIVRE],
};

/**
 * Resolve o esporte (legado null → 'bjj').
 */
function normalizeSport(sport) {
  return sport == null || sport === '' ? 'bjj' : String(sport);
}

/**
 * Posição (índice) de um grau numa escada. -1 se não existir.
 */
function indexInLadder(ladder, gradeId) {
  return ladder.findIndex((g) => g.id === gradeId);
}

/**
 * Lê o grau VERIFICADO (teto) do aluno para o esporte.
 * Retorna { grade, stripes } ou null se não houver standing verificado.
 */
function readVerifiedGrade(studentData, sport) {
  const sportData = studentData.sportData || {};
  const entry = sportData[sport];
  if (entry && typeof entry === 'object' && entry.currentGrade) {
    return {
      grade: String(entry.currentGrade),
      stripes: Number(entry.currentStripes) || 0,
    };
  }
  // BJJ legado: sem sportData.bjj → par currentBelt/currentStripes da raiz.
  if (sport === 'bjj') {
    return {
      grade: String(studentData.currentBelt || 'white'),
      stripes: Number(studentData.currentStripes) || 0,
    };
  }
  return null;
}

/**
 * Decide se a auto-graduação declarada respeita o teto verificado.
 * Retorna { ok: true } ou { ok: false, reason }.
 */
function evaluateCeiling(selfGrade, verified, sport) {
  if (GRADELESS_SPORTS.has(sport)) {
    return { ok: false, reason: `sport '${sport}' has no belt system (GradeSystem.none)` };
  }
  if (!verified) {
    return { ok: false, reason: `no verified grade for sport '${sport}' (no ceiling)` };
  }
  const candidateLadders = LADDERS_BY_SPORT[sport];
  if (!candidateLadders) {
    return { ok: false, reason: `unknown sport '${sport}' (no ladder in catalog)` };
  }
  // A escada real é a que contém o grau VERIFICADO (resolve adulto/kids p/ BJJ
  // e a variante de federação p/ Muay Thai sem precisar de outro campo).
  const ladder = candidateLadders.find((l) => indexInLadder(l, verified.grade) >= 0);
  if (!ladder) {
    return { ok: false, reason: `verified grade '${verified.grade}' not found in any ladder for '${sport}'` };
  }
  const verifiedIdx = indexInLadder(ladder, verified.grade);
  const selfIdx = indexInLadder(ladder, selfGrade.grade);
  if (selfIdx < 0) {
    return { ok: false, reason: `self grade '${selfGrade.grade}' not in the verified ladder for '${sport}'` };
  }
  if (selfIdx > verifiedIdx) {
    return { ok: false, reason: `self grade '${selfGrade.grade}' (idx ${selfIdx}) above verified '${verified.grade}' (idx ${verifiedIdx})` };
  }
  if (selfIdx === verifiedIdx && selfGrade.stripes > verified.stripes) {
    return { ok: false, reason: `self stripes ${selfGrade.stripes} above verified ${verified.stripes} at grade '${selfGrade.grade}'` };
  }
  // Clamp interno: graus não podem exceder o maxStripes do próprio grau.
  const maxStripes = ladder[selfIdx].max;
  if (selfGrade.stripes < 0 || selfGrade.stripes > maxStripes) {
    return { ok: false, reason: `self stripes ${selfGrade.stripes} out of range [0..${maxStripes}] for grade '${selfGrade.grade}'` };
  }
  return { ok: true };
}

/**
 * Trigger de TETO — onWrite (create/update) em selfGraduations.
 * Valida a posição na escada e DELETA o doc se acima do teto verificado.
 */
exports.enforceSelfGraduationCeiling = onDocumentWritten(
  'academies/{academyId}/students/{studentId}/selfGraduations/{selfGradId}',
  async (event) => {
    const after = event.data && event.data.after;
    // Delete → nada a validar.
    if (!after || !after.exists) return;

    const { academyId, studentId, selfGradId } = event.params;
    const data = after.data() || {};

    const sport = normalizeSport(data.sport);
    const selfGrade = {
      grade: data.grade == null ? null : String(data.grade),
      stripes: Number(data.stripes) || 0,
    };

    // Sem grau declarado: doc malformado → rejeita.
    if (!selfGrade.grade) {
      console.warn(`[selfGradGuard] reject ${selfGradId} (student ${studentId}, academy ${academyId}): missing grade`);
      await after.ref.delete().catch((e) => console.error('[selfGradGuard] delete failed', e));
      return;
    }

    let studentSnap;
    try {
      studentSnap = await db
        .collection('academies').doc(academyId)
        .collection('students').doc(studentId)
        .get();
    } catch (e) {
      console.error(`[selfGradGuard] failed to read student ${studentId} in ${academyId}`, e);
      return; // erro transitório de leitura — não deleta às cegas.
    }

    if (!studentSnap.exists) {
      console.warn(`[selfGradGuard] reject ${selfGradId}: student ${studentId} not found in ${academyId}`);
      await after.ref.delete().catch((e) => console.error('[selfGradGuard] delete failed', e));
      return;
    }

    const verified = readVerifiedGrade(studentSnap.data() || {}, sport);
    const verdict = evaluateCeiling(selfGrade, verified, sport);

    if (!verdict.ok) {
      console.warn(
        `[selfGradGuard] REJECT self-graduation ${selfGradId} ` +
        `(academy ${academyId}, student ${studentId}, sport ${sport}, ` +
        `grade ${selfGrade.grade}+${selfGrade.stripes}): ${verdict.reason}`
      );
      await after.ref.delete().catch((e) => console.error('[selfGradGuard] delete failed', e));
      return;
    }

    console.log(
      `[selfGradGuard] OK self-graduation ${selfGradId} ` +
      `(student ${studentId}, sport ${sport}, grade ${selfGrade.grade}+${selfGrade.stripes})`
    );
  }
);
