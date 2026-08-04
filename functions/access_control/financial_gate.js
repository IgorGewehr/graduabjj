/**
 * access_control/financial_gate.js — bloqueio da catraca por INADIMPLÊNCIA.
 * ============================================================================
 *
 * Greenfield/aditivo. DEFAULT OFF: ausência de config OU blockOnOverdue!==true
 * => libera (deploy é no-op em prod até a academia optar). FAIL-OPEN total:
 * qualquer erro/timeout/campo malformado => blocked:false (nunca prende um
 * aluno no portão por falha de infra).
 *
 * Reusa a definição CANÔNICA de "vencido" (isOverdueBR/daysOverdueBR de
 * access_control/overdue_util.js) — o PORTÃO e o cron de cobrança NUNCA
 * discordam de quem está em atraso. process.env.TZ pinado em America/Sao_Paulo.
 *
 * Config por academia (academies/{id}.accessControl):
 *   { blockOnOverdue:false, graceDays:0, blockTypes:['monthly_tuition'] }
 *
 * `node --check` deve passar.
 * ============================================================================
 */

'use strict';

const admin = require('firebase-admin');
if (!admin.apps || admin.apps.length === 0) {
  try { admin.initializeApp(); } catch (_) { /* já inicializado em outro path */ }
}
const db = admin.firestore();

const { isOverdueBR, daysOverdueBR } = require('./overdue_util');

// TODO (quais financial types contam): default só mensalidade prende. Avulsa
// (loja), private_lesson e subscription_overcharge (isOvercharge = dinheiro
// DEVIDO ao aluno) NUNCA bloqueiam — jailar um membro pagante por uma camiseta
// seria um bug de confiança. Override por cfg.blockTypes.
const DEFAULT_BLOCK_TYPES = ['monthly_tuition'];

/**
 * Verifica se o aluno está bloqueado por inadimplência.
 * Retorna SEMPRE um objeto; FAIL-OPEN embutido (try/catch).
 *
 * @param {string} academyId
 * @param {string} studentId  já sanitizado (isSafeSegment) pelo núcleo.
 * @param {Date} occurredAt  timestamp ORIGINAL do evento (usado como `now`,
 *   coerente com a presença que preserva o original).
 * @param {object} cfg  academies/{id}.accessControl (pode ser null/ausente).
 * @returns {Promise<{blocked:boolean, reason:string|null, amountOverdue:number}>}
 */
async function checkOverdueGate(academyId, studentId, occurredAt, cfg) {
  try {
    // DEFAULT OFF — feature desligada => libera.
    if (!cfg || cfg.blockOnOverdue !== true) {
      return { blocked: false, reason: null, amountOverdue: 0 };
    }
    if (!academyId || !studentId) {
      return { blocked: false, reason: null, amountOverdue: 0 };
    }
    // `now` = timestamp do evento (não Date.now()).
    const now = (occurredAt instanceof Date && !isNaN(occurredAt.getTime()))
      ? occurredAt : new Date();

    const blockTypes = (Array.isArray(cfg.blockTypes) && cfg.blockTypes.length)
      ? cfg.blockTypes : DEFAULT_BLOCK_TYPES;
    const graceDays = Number.isFinite(cfg.graceDays) ? cfg.graceDays : 0;

    // Conjunto PEQUENO de cobranças abertas do aluno. status in [pending,overdue]
    // = mesma definição do cron (server_functions.js scheduledOverdueCheck);
    // 'overdue' já materializado e 'pending' que pode ter vencido entram. O
    // fim-de-dia (isOverdueBR) é avaliado em memória — não cabe em range query.
    const snap = await db.collection(`academies/${academyId}/financials`)
      .where('studentId', '==', studentId)
      .where('status', 'in', ['pending', 'overdue'])
      .get();

    let amount = 0;
    let blocked = false;
    for (const d of snap.docs) {
      const f = d.data() || {};
      // Só os tipos configurados prendem (default: só mensalidade).
      if (!blockTypes.includes(f.type || 'monthly_tuition')) continue;
      // isOvercharge = dinheiro DEVIDO ao aluno (subscription_overcharge): nunca.
      if (f.isOvercharge === true) continue;
      // null-guard (HIGH): sem dueDate válido não dá p/ afirmar vencimento.
      if (!f.dueDate || typeof f.dueDate.toDate !== 'function') continue;
      const due = f.dueDate.toDate();
      if (!isOverdueBR(due, now)) continue;              // definição canônica
      if (daysOverdueBR(due, now) <= graceDays) continue; // tolerância (grace)
      blocked = true;
      amount += (Number(f.amount) || 0);
    }

    return { blocked, reason: blocked ? 'overdue' : null, amountOverdue: amount };
  } catch (_) {
    // FAIL-OPEN: qualquer erro (query, índice ausente, campo malformado) libera.
    return { blocked: false, reason: 'check_error', amountOverdue: 0 };
  }
}

module.exports = { checkOverdueGate };
