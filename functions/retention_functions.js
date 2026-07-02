/**
 * §2 do plano REPAGINADA_ADMIN_ALUNO100 — fundação de dados de retenção.
 *
 * Duas Cloud Functions (gen2):
 *
 * 1) onAttendanceWrite — DISPATCHER extensível em
 *      academies/{academyId}/attendance/{attendanceId}
 *    (create E delete; update só interessa se studentId/date mudou — vira
 *    delete+create). Cada handler roda em try/catch próprio: um falhar não
 *    derruba os outros. Handlers atuais:
 *      • retention: mantém incremental o mapa `retention` no doc do aluno
 *        (lastAttendanceDate só-avança + weeklyBuckets por semana ISO, com
 *        poda automática de buckets além de ~9 semanas);
 *      • feed: dispara a materialização server-side dos marcos do aluno
 *        (./feed_materializer, contrato fixo — best-effort).
 *    Handlers futuros (§9.1: push goal-gradient/streak, GALERA F3:
 *    trainingPairs) plugam no array ATTENDANCE_HANDLERS.
 *
 * 2) computeRetentionDaily — job agendado (03:30 America/Sao_Paulo) que, por
 *    academia, recomputa as janelas rolantes de TODOS os alunos ativos a
 *    partir de 1 query range de attendance (últimos 30d) — corrige drift do
 *    incremental —, calcula o score de risco v1 (PORT fiel da fórmula
 *    40/30/20/10 de lib/services/retention_service.dart:188-396), fecha os
 *    outcomes de retentionContacts pendentes e grava o snapshot diário em
 *    academies/{aid}/retentionSnapshots/{YYYY-MM-DD} (doc-id determinístico —
 *    re-rodar no mesmo dia sobrescreve, idempotente).
 *
 * Shape do mapa `retention` no doc do aluno (academies/{aid}/students/{sid}):
 *   retention: {
 *     lastAttendanceDate: Timestamp,
 *     attendanceLast7d: int,
 *     attendanceLast30d: int,
 *     weeklyBuckets: { '2026-W27': int, ... },   // últimas ~9 semanas ISO
 *     riskScore: int,
 *     riskLevel: 'low'|'medium'|'high'|'critical',
 *     riskComputedAt: Timestamp,
 *     riskFormulaVersion: 1,
 *   }
 *
 * INVARIANTES (§10 do plano — não-negociáveis):
 *   • retention.*, riskScore e retentionContacts NUNCA são espelhados em
 *     publicProfiles/fighterProfiles nem expostos ao aluno — este módulo só
 *     escreve no doc do aluno (staff-only) e em subcoleções da academia.
 *   • Semana ISO: segunda-feira é o início; chave 'YYYY-Www' com ISO
 *     week-year (dias civis calculados em America/Sao_Paulo).
 */

'use strict';

const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

const db = admin.firestore();
const { FieldValue, Timestamp } = admin.firestore;

// ============================================================
// Constantes / helpers de calendário (semana ISO em America/Sao_Paulo)
// ============================================================

const SP_TZ = 'America/Sao_Paulo';
const MS_DAY = 86400000;
const MS_WEEK = 7 * MS_DAY;

/** Janela de retenção dos weeklyBuckets: semana corrente + 8 anteriores. */
const BUCKET_WEEKS = 9;

/** Janela (dias) para fechar outcome de contato de retenção. */
const CONTACT_RECOVERY_WINDOW_DAYS = 14;

// 'en-CA' formata YYYY-MM-DD — parse trivial.
const spDayFmt = new Intl.DateTimeFormat('en-CA', {
  timeZone: SP_TZ, year: 'numeric', month: '2-digit', day: '2-digit',
});
const spMonthFmt = new Intl.DateTimeFormat('en-CA', {
  timeZone: SP_TZ, year: 'numeric', month: '2-digit',
});

/** 'YYYY-MM-DD' do instante no fuso de São Paulo (doc-id do snapshot). */
function spDayKey(date) {
  return spDayFmt.format(date);
}

/** 'YYYY-MM' do instante no fuso de São Paulo (janela "mês corrente"). */
function spMonthKey(date) {
  return spMonthFmt.format(date);
}

/**
 * Converte um instante para o DIA CIVIL em São Paulo, materializado como Date
 * em UTC-midnight — usado só para aritmética de calendário (semana ISO), nunca
 * como instante real.
 */
function spCivilDate(date) {
  const [y, m, d] = spDayFmt.format(date).split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

/** Segunda-feira da semana do dia civil (segunda = início, convenção ISO). */
function mondayOf(civil) {
  const dayNum = (civil.getUTCDay() + 6) % 7; // Mon=0 .. Sun=6
  return new Date(civil.getTime() - dayNum * MS_DAY);
}

/**
 * Chave ISO 'YYYY-Www' de um dia civil (algoritmo padrão: a quinta-feira da
 * semana decide o ISO week-year).
 */
function isoWeekKeyFromCivil(civil) {
  const dayNum = (civil.getUTCDay() + 6) % 7;
  const thursday = new Date(civil.getTime() + (3 - dayNum) * MS_DAY);
  const isoYear = thursday.getUTCFullYear();
  const jan4 = new Date(Date.UTC(isoYear, 0, 4));
  const firstThursday = new Date(jan4.getTime() + (3 - ((jan4.getUTCDay() + 6) % 7)) * MS_DAY);
  const week = 1 + Math.round((thursday.getTime() - firstThursday.getTime()) / MS_WEEK);
  return `${isoYear}-W${String(week).padStart(2, '0')}`;
}

/** Chave ISO 'YYYY-Www' de um instante (dia civil em São Paulo). */
function isoWeekKey(date) {
  return isoWeekKeyFromCivil(spCivilDate(date));
}

/**
 * Set das chaves das últimas `n` semanas ISO (incluindo a corrente) — janela
 * de retenção dos weeklyBuckets. Tudo fora deste set é podado.
 */
function allowedWeekKeys(now, n = BUCKET_WEEKS) {
  const keys = new Set();
  let monday = mondayOf(spCivilDate(now));
  for (let i = 0; i < n; i++) {
    keys.add(isoWeekKeyFromCivil(monday));
    monday = new Date(monday.getTime() - MS_WEEK);
  }
  return keys;
}

// ============================================================
// Helpers de leitura defensiva (Timestamp | Date | string ISO)
// ============================================================

function readDate(raw) {
  if (!raw) return null;
  if (typeof raw.toDate === 'function') return raw.toDate(); // Timestamp
  if (raw instanceof Date) return raw;
  if (typeof raw === 'string') {
    const d = new Date(raw);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

/** Data da presença (campo `date` do doc de attendance — Timestamp). */
function attendanceDate(data) {
  return data ? readDate(data.date) : null;
}

// ============================================================
// Handler: retenção incremental (create/delete de attendance)
// ============================================================

/**
 * No create: avança retention.lastAttendanceDate (nunca regride) e incrementa
 * o bucket da semana ISO da presença. No delete: decrementa o bucket (piso 0;
 * lastAttendanceDate NÃO é recalculado aqui — caro; o job diário corrige).
 * Sempre: poda buckets fora da janela de ~9 semanas.
 *
 * Transação por efeito: a leitura do doc do aluno é necessária para o
 * "só-avança" do lastAttendanceDate e para o piso 0 do decremento. As escritas
 * usam dot-notation ('retention.weeklyBuckets.2026-W27') para nunca
 * sobrescrever o mapa inteiro.
 */
async function retentionHandler({ academyId, effects }) {
  for (const effect of effects) {
    const { kind, studentId, date } = effect;
    if (!studentId || !date) continue; // doc malformado — nada a fazer

    const studentRef = db
      .collection('academies').doc(academyId)
      .collection('students').doc(studentId);
    const weekKey = isoWeekKey(date);
    const allowed = allowedWeekKeys(new Date());

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(studentRef);
      if (!snap.exists) return; // aluno removido — sem agregado a manter

      const retention = (snap.data() || {}).retention || {};
      const buckets = retention.weeklyBuckets || {};
      const updates = {};

      if (kind === 'create') {
        const current = readDate(retention.lastAttendanceDate);
        if (!current || date.getTime() > current.getTime()) {
          updates['retention.lastAttendanceDate'] = Timestamp.fromDate(date);
        }
        // Presença retroativa além da janela não cria bucket já podável.
        if (allowed.has(weekKey)) {
          updates[`retention.weeklyBuckets.${weekKey}`] = FieldValue.increment(1);
        }
      } else if (kind === 'delete') {
        // Piso 0: só decrementa se o bucket existe e é positivo.
        const cur = Number(buckets[weekKey]) || 0;
        if (cur > 0) {
          updates[`retention.weeklyBuckets.${weekKey}`] = FieldValue.increment(-1);
        }
      }

      // Poda automática: buckets além das ~9 semanas saem do mapa.
      for (const key of Object.keys(buckets)) {
        if (!allowed.has(key)) {
          updates[`retention.weeklyBuckets.${key}`] = FieldValue.delete();
        }
      }

      if (Object.keys(updates).length > 0) tx.update(studentRef, updates);
    });
  }
}

// ============================================================
// Handler: materialização do feed (best-effort, módulo paralelo)
// ============================================================

/**
 * Dispara o recompute dos marcos feed-relevantes do(s) aluno(s) afetado(s).
 * O módulo ./feed_materializer é dono de todos os invariantes do feed
 * (doc-ids determinísticos, create-if-absent, hiddenByAuthor/hiddenByStaff).
 * require() lazy + try/catch por aluno: se o módulo faltar ou falhar, o
 * restante do dispatcher segue intacto.
 */
async function feedHandler({ academyId, effects }) {
  const studentIds = [...new Set(effects.map((e) => e.studentId).filter(Boolean))];
  for (const studentId of studentIds) {
    try {
      // eslint-disable-next-line global-require
      const { materializeAttendanceMarcos } = require('./feed_materializer');
      await materializeAttendanceMarcos({ db, academyId, studentId });
    } catch (e) {
      console.error(
        `[onAttendanceWrite:feed] materialize falhou (academy ${academyId}, student ${studentId})`,
        e && e.message
      );
    }
  }
}

// ============================================================
// Dispatcher onAttendanceWrite (extensível: 1 trigger, N handlers)
// ============================================================

// Handlers novos (push §9.1, trainingPairs GALERA F3) entram aqui.
const ATTENDANCE_HANDLERS = [
  { name: 'retention', fn: retentionHandler },
  { name: 'feed', fn: feedHandler },
];

exports.onAttendanceWrite = onDocumentWritten(
  { document: 'academies/{academyId}/attendance/{attendanceId}', region: 'us-central1' },
  async (event) => {
    const beforeSnap = event.data && event.data.before;
    const afterSnap = event.data && event.data.after;
    const before = beforeSnap && beforeSnap.exists ? beforeSnap.data() : null;
    const after = afterSnap && afterSnap.exists ? afterSnap.data() : null;
    const { academyId, attendanceId } = event.params;

    // Efeitos normalizados: create → +1; delete → -1; update que troca
    // studentId/date → delete(before) + create(after); update irrelevante
    // (notas, verifiedBy...) → ignora.
    const effects = [];
    if (!before && after) {
      effects.push({ kind: 'create', studentId: after.studentId, date: attendanceDate(after) });
    } else if (before && !after) {
      effects.push({ kind: 'delete', studentId: before.studentId, date: attendanceDate(before) });
    } else if (before && after) {
      const beforeDate = attendanceDate(before);
      const afterDate = attendanceDate(after);
      const sameStudent = before.studentId === after.studentId;
      const sameDate =
        (beforeDate ? beforeDate.getTime() : null) === (afterDate ? afterDate.getTime() : null);
      if (sameStudent && sameDate) return; // update sem impacto nos agregados
      effects.push({ kind: 'delete', studentId: before.studentId, date: beforeDate });
      effects.push({ kind: 'create', studentId: after.studentId, date: afterDate });
    } else {
      return;
    }

    const ctx = { db, academyId, attendanceId, effects };
    for (const handler of ATTENDANCE_HANDLERS) {
      try {
        await handler.fn(ctx);
      } catch (e) {
        // Um handler falhar NUNCA derruba os demais.
        console.error(
          `[onAttendanceWrite] handler '${handler.name}' falhou ` +
          `(academy ${academyId}, attendance ${attendanceId})`,
          e && e.message
        );
      }
    }
  }
);

// ============================================================
// Score de risco v1 — PORT fiel de retention_service.dart:188-396
// ============================================================

/**
 * Regra canônica de "pagamento vencido" — PORT fiel de
 * RetentionService._isFinancialOverdue (retention_service.dart:555-564):
 * vencido = dueDate no passado E status fora de {paid, cancelled}; fallback
 * retrocompatível para docs sem dueDate já marcados 'overdue'.
 */
function isFinancialOverdue(financial, now) {
  const status = String(financial.status || '');
  if (status === 'paid' || status === 'cancelled') return false;
  const dueDate = readDate(financial.dueDate);
  if (dueDate) return dueDate.getTime() < now.getTime();
  return status === 'overdue';
}

/**
 * Fórmula v1 (pesos 40/30/20/10) — PORT fiel de
 * RetentionService.calculateStudentRisk (retention_service.dart:188-396):
 *   Fator 1 (40): queda de frequência — presenças últimos 15d vs 15d
 *     anteriores. Queda ≥50% → 40; ≥25% → 25; <0% → 10; sem histórico anterior
 *     E sem presença recente → 40 (nenhuma presença em 30d).
 *   Fator 2 (30): inatividade — dias desde a última presença.
 *     >30 → 30; >14 → 20; >7 → 10.
 *   Fator 3 (20): pagamentos vencidos. >2 → 20; ==2 → 15; ==1 → 10.
 *   Fator 4 (10): tempo de casa. <3 meses → 10; <6 → 5.
 * Classificação: >=75 critical / >=50 high / >=25 medium / senão low.
 */
function computeRiskScoreV1({
  recentCount, previousCount, daysSinceLastAttendance, overdueCount, monthsAtAcademy,
}) {
  let total = 0;

  // --- Fator 1: queda de frequência (peso 40) ---
  if (previousCount > 0) {
    const changePercent = ((recentCount - previousCount) / previousCount) * 100;
    if (changePercent <= -50) total += 40;
    else if (changePercent <= -25) total += 25;
    else if (changePercent < 0) total += 10;
  } else if (recentCount === 0) {
    total += 40; // nenhuma presença nos últimos 30 dias
  }

  // --- Fator 2: inatividade (peso 30) ---
  if (daysSinceLastAttendance > 30) total += 30;
  else if (daysSinceLastAttendance > 14) total += 20;
  else if (daysSinceLastAttendance > 7) total += 10;

  // --- Fator 3: pagamentos vencidos (peso 20) ---
  if (overdueCount > 2) total += 20;
  else if (overdueCount === 2) total += 15;
  else if (overdueCount === 1) total += 10;

  // --- Fator 4: tempo de casa (peso 10) ---
  if (monthsAtAcademy < 3) total += 10;
  else if (monthsAtAcademy < 6) total += 5;

  const score = Math.min(100, Math.max(0, total));
  let level;
  if (score >= 75) level = 'critical';
  else if (score >= 50) level = 'high';
  else if (score >= 25) level = 'medium';
  else level = 'low';

  return { score, level };
}

/** Diferença em meses (espelha RetentionService._differenceInMonths). */
function differenceInMonths(a, b) {
  return (a.getFullYear() - b.getFullYear()) * 12 + (a.getMonth() - b.getMonth());
}

// ============================================================
// Job diário: computeRetentionDaily
// ============================================================

/**
 * Acumulador de writes em batches de <=500 ops (flush em 450, mesmo teto dos
 * scripts de backfill do repo).
 */
function makeBatcher() {
  let batch = db.batch();
  let ops = 0;
  let flushed = 0;
  return {
    update(ref, data) {
      batch.update(ref, data);
      ops++;
    },
    set(ref, data) {
      batch.set(ref, data);
      ops++;
    },
    async maybeFlush() {
      if (ops >= 450) {
        await batch.commit();
        flushed += ops;
        batch = db.batch();
        ops = 0;
      }
    },
    async flush() {
      if (ops > 0) {
        await batch.commit();
        flushed += ops;
        batch = db.batch();
        ops = 0;
      }
      return flushed;
    },
  };
}

/**
 * Recompute completo de UMA academia (janelas rolantes + score v1 + outcomes
 * de contatos + snapshot diário). Exportado para reuso/teste.
 */
async function computeAcademyRetention(academyId, now = new Date()) {
  const acadRef = db.collection('academies').doc(academyId);
  const cutoff30 = new Date(now.getTime() - 30 * MS_DAY);
  const cutoff15 = new Date(now.getTime() - 15 * MS_DAY);
  const cutoff7 = new Date(now.getTime() - 7 * MS_DAY);

  // ── 1 query range: attendance dos últimos 30d, agrupada em memória ────────
  const attSnap = await acadRef.collection('attendance')
    .where('date', '>=', Timestamp.fromDate(cutoff30))
    .get();
  const attByStudent = new Map(); // studentId → Date[]
  for (const doc of attSnap.docs) {
    const d = doc.data() || {};
    const date = attendanceDate(d);
    if (!d.studentId || !date) continue;
    if (!attByStudent.has(d.studentId)) attByStudent.set(d.studentId, []);
    attByStudent.get(d.studentId).push(date);
  }

  // ── Pagamentos vencidos por aluno (regra canônica) ─────────────────────────
  // not-in {paid, cancelled} espelha o filtro do Dart; a checagem fina de
  // dueDate acontece em memória via isFinancialOverdue.
  const overdueByStudent = new Map(); // studentId → count
  const finSnap = await acadRef.collection('financials')
    .where('status', 'not-in', ['paid', 'cancelled'])
    .get();
  for (const doc of finSnap.docs) {
    const f = doc.data() || {};
    if (!f.studentId || !isFinancialOverdue(f, now)) continue;
    overdueByStudent.set(f.studentId, (overdueByStudent.get(f.studentId) || 0) + 1);
  }

  // ── Alunos (uma leitura: ativos p/ recompute, ex-alunos p/ churn) ──────────
  const studentsSnap = await acadRef.collection('students').get();

  const allowed = allowedWeekKeys(now);
  // Semanas cuja segunda-feira cai DENTRO da janela de 30d são recomputáveis
  // integralmente a partir da query (sobrescreve — corrige drift). Semanas mais
  // antigas ficam como o incremental deixou (só sofrem poda de janela).
  const recomputableKeys = new Set();
  {
    const cutoffCivil = spCivilDate(cutoff30);
    let monday = mondayOf(spCivilDate(now));
    while (monday.getTime() >= cutoffCivil.getTime()) {
      recomputableKeys.add(isoWeekKeyFromCivil(monday));
      monday = new Date(monday.getTime() - MS_WEEK);
    }
  }

  const batcher = makeBatcher();
  const monthKey = spMonthKey(now);

  const atRisk = { critical: 0, high: 0, medium: 0 };
  let activeStudents = 0;
  let churnedThisMonth = 0;
  let totalAttendance30d = 0;
  // studentId → última presença efetiva (max entre persistido e query) — usada
  // no fechamento de outcomes de contatos.
  const effectiveLastByStudent = new Map();

  for (const sDoc of studentsSnap.docs) {
    const s = sDoc.data() || {};
    const status = String(s.status || 'active'); // default espelha Student.fromFirestore

    // Churn consumado (§2.3): transição p/ inactive|transferred no mês corrente.
    if (status === 'inactive' || status === 'transferred') {
      const changedAt = readDate(s.statusChangedAt);
      if (changedAt && spMonthKey(changedAt) === monthKey) churnedThisMonth++;
      continue; // agregados de retenção só para alunos ativos
    }
    if (status !== 'active') continue; // injured/suspended: fora do radar

    activeStudents++;
    const retention = s.retention || {};
    const existingBuckets = retention.weeklyBuckets || {};
    const dates = attByStudent.get(sDoc.id) || [];
    totalAttendance30d += dates.length;

    // Janelas rolantes (mesmos cortes do Dart: isAfter estrito).
    const last30 = dates.length;
    const last7 = dates.filter((d) => d.getTime() > cutoff7.getTime()).length;
    const recent15 = dates.filter((d) => d.getTime() > cutoff15.getTime()).length;
    const prev15 = last30 - recent15;

    // lastAttendanceDate efetivo: máximo entre o persistido e o da janela.
    const storedLast = readDate(retention.lastAttendanceDate);
    let queryLast = null;
    for (const d of dates) {
      if (!queryLast || d.getTime() > queryLast.getTime()) queryLast = d;
    }
    const effectiveLast =
      queryLast && (!storedLast || queryLast.getTime() > storedLast.getTime())
        ? queryLast
        : storedLast;
    if (effectiveLast) effectiveLastByStudent.set(sDoc.id, effectiveLast);

    const daysSinceLastAttendance = effectiveLast
      ? Math.floor((now.getTime() - effectiveLast.getTime()) / MS_DAY)
      : 999; // espelha o sentinela do Dart (sem presença conhecida)

    const startDate = readDate(s.startDate);
    const monthsAtAcademy = startDate ? differenceInMonths(now, startDate) : 0;

    const { score, level } = computeRiskScoreV1({
      recentCount: recent15,
      previousCount: prev15,
      daysSinceLastAttendance,
      overdueCount: overdueByStudent.get(sDoc.id) || 0,
      monthsAtAcademy,
    });
    if (level in atRisk) atRisk[level]++;

    // ── Monta o update (dot-notation: nunca sobrescreve o mapa inteiro) ─────
    const updates = {
      'retention.attendanceLast7d': last7,
      'retention.attendanceLast30d': last30,
      'retention.riskScore': score,
      'retention.riskLevel': level,
      'retention.riskComputedAt': Timestamp.fromDate(now),
      'retention.riskFormulaVersion': 1,
    };
    if (queryLast && (!storedLast || queryLast.getTime() > storedLast.getTime())) {
      updates['retention.lastAttendanceDate'] = Timestamp.fromDate(queryLast);
    }

    // Buckets: recomputa (sobrescreve) as semanas cobertas pela janela de 30d.
    const freshBuckets = {};
    for (const d of dates) {
      const key = isoWeekKey(d);
      if (recomputableKeys.has(key)) freshBuckets[key] = (freshBuckets[key] || 0) + 1;
    }
    for (const key of recomputableKeys) {
      const fresh = freshBuckets[key] || 0;
      const hasCur = Object.prototype.hasOwnProperty.call(existingBuckets, key);
      const cur = hasCur ? Number(existingBuckets[key]) || 0 : null;
      if (fresh > 0) {
        if (cur !== fresh) updates[`retention.weeklyBuckets.${key}`] = fresh;
      } else if (hasCur) {
        updates[`retention.weeklyBuckets.${key}`] = FieldValue.delete(); // mapa esparso
      }
    }
    // Poda: chaves fora da janela de ~9 semanas.
    for (const key of Object.keys(existingBuckets)) {
      if (!allowed.has(key)) updates[`retention.weeklyBuckets.${key}`] = FieldValue.delete();
    }

    batcher.update(sDoc.ref, updates);
    await batcher.maybeFlush();
  }

  // ── Fecha outcomes de retentionContacts pendentes (§3.2) ───────────────────
  // recovered: presença em <=14d após o contato; lost: janela venceu sem
  // presença; senão continua pending.
  const flippedById = new Map(); // contactId → 'recovered'|'lost'
  const pendingSnap = await acadRef.collection('retentionContacts')
    .where('outcome', '==', 'pending')
    .get();
  for (const doc of pendingSnap.docs) {
    const c = doc.data() || {};
    const contactAt = readDate(c.at);
    if (!contactAt || !c.studentId) continue;
    const windowEnd = new Date(contactAt.getTime() + CONTACT_RECOVERY_WINDOW_DAYS * MS_DAY);

    const dates = attByStudent.get(c.studentId) || [];
    const effectiveLast = effectiveLastByStudent.get(c.studentId) || null;
    const returned =
      dates.some((d) => d.getTime() > contactAt.getTime() && d.getTime() <= windowEnd.getTime()) ||
      (effectiveLast &&
        effectiveLast.getTime() > contactAt.getTime() &&
        effectiveLast.getTime() <= windowEnd.getTime());

    let outcome = null;
    if (returned) outcome = 'recovered';
    else if (now.getTime() > windowEnd.getTime()) outcome = 'lost';
    if (!outcome) continue; // janela ainda aberta — segue pending

    flippedById.set(doc.id, outcome);
    batcher.update(doc.ref, { outcome, outcomeAt: Timestamp.fromDate(now) });
    await batcher.maybeFlush();
  }

  // ── Métricas de contato do mês (para o snapshot) ───────────────────────────
  // Início do mês civil em SP: 00:00 SP = 03:00 UTC (Brasil sem DST desde 2019).
  const [my, mm] = monthKey.split('-').map(Number);
  const monthStart = new Date(Date.UTC(my, mm - 1, 1, 3, 0, 0));
  let contactsMade = 0;
  let recoveredAfterContact = 0;
  const monthContactsSnap = await acadRef.collection('retentionContacts')
    .where('at', '>=', Timestamp.fromDate(monthStart))
    .get();
  for (const doc of monthContactsSnap.docs) {
    contactsMade++;
    // Estado pós-run: considera os outcomes recém-fechados neste run.
    const outcome = flippedById.get(doc.id) || String((doc.data() || {}).outcome || '');
    if (outcome === 'recovered') recoveredAfterContact++;
  }

  // ── Snapshot diário (doc-id determinístico YYYY-MM-DD em SP) ───────────────
  const avgWeeklyAttendance = activeStudents > 0
    ? Math.round((totalAttendance30d * (7 / 30) / activeStudents) * 100) / 100
    : 0;
  batcher.set(acadRef.collection('retentionSnapshots').doc(spDayKey(now)), {
    atRisk,
    activeStudents,
    churnedThisMonth,
    avgWeeklyAttendance,
    contactsMade,
    recoveredAfterContact,
    computedAt: Timestamp.fromDate(now),
  });

  const written = await batcher.flush();
  console.log(
    `[retentionDaily] academy ${academyId}: ${activeStudents} ativos, ` +
    `${attSnap.size} presenças/30d, atRisk c=${atRisk.critical}/h=${atRisk.high}/m=${atRisk.medium}, ` +
    `churnMês=${churnedThisMonth}, contatos fechados=${flippedById.size}, writes=${written}`
  );
}

/**
 * Scheduled: diário às 03:30 (America/Sao_Paulo). Espelha o shape de iteração
 * por academia de scheduledGamificationMilestones (server_functions.js) e as
 * opts v2 das scheduled de assinatura (onSchedule + timeZone + timeoutSeconds).
 */
exports.computeRetentionDaily = onSchedule(
  { schedule: '30 3 * * *', timeZone: 'America/Sao_Paulo', timeoutSeconds: 540 },
  async () => {
    console.log('[retentionDaily] start');
    const academiesSnap = await db.collection('academies').get();

    for (const academyDoc of academiesSnap.docs) {
      try {
        await computeAcademyRetention(academyDoc.id);
      } catch (e) {
        // Uma academia falhar nunca aborta o cron inteiro.
        console.error(`[retentionDaily] academy ${academyDoc.id} failed`, e && e.message);
      }
    }
    console.log('[retentionDaily] done');
  }
);

// Reuso/teste (mesmo padrão de processAcademyGamification).
exports.computeAcademyRetention = computeAcademyRetention;
exports.computeRiskScoreV1 = computeRiskScoreV1;
exports.isoWeekKey = isoWeekKey;
