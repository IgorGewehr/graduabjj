/**
 * access_control/class_resolver.js — resolve a TURMA ATIVA de um aluno no
 * momento do giro da catraca (Arquitetura C, server-side).
 * ============================================================================
 *
 * Helper PURO (SEM I/O). As classes já vêm lidas de academies/{id}/classes pelo
 * handler (uma única .get() por POST, fora da transação). Este módulo só decide
 * QUAL turma casa o evento, espelhando a semântica client-side do
 * lib/services/class_service.dart (acceptsCheckinFrom / getCurrentClass /
 * isHappeningNow) verbatim.
 *
 * Por que server-side e por que PURO: o classId resolvido entra no doc-id
 * determinístico da presença (studentId_classId_YYYYMMDD), que é a chave de
 * idempotência. A resolução DEVE ser determinística (re-entrega do MESMO evento
 * resolve SEMPRE a mesma turma) — daí o tie-break estável final por classId.
 *
 * IMPORTANTE (fuso): dow/minutes do occurredAt são derivados em wall-clock BR
 * (process.env.TZ pinado em America/Sao_Paulo no index.js), pois a grade guarda
 * dayOfWeek 0=Dom..6=Sab e 'HH:MM' em horário local BR. `node --check` passa.
 * ============================================================================
 */

'use strict';

// SECURITY (C1 — path injection): mesmo charset estrito do núcleo. O classId
// resolvido vira SEGMENTO de path (doc-id da presença), então mesmo vindo do
// nosso próprio Firestore ele é revalidado antes de retornar (defensivo, não
// regride C1).
const SAFE_ID_RE = /^[A-Za-z0-9_-]{1,128}$/;
const isSafeSegment = (s) => typeof s === 'string' && SAFE_ID_RE.test(s);

// Tolerância padrão da janela (minutos). PRE espelha o "30 min antes do início"
// do getCurrentClass (class_service.dart:227); POST é uma folga ADITIVA para o
// aluno que gira a catraca alguns minutos após o sino ainda cair na turma.
// TODO (tolerância de janela): confirmar com a academia se 30/30 é o ideal;
// override por device.scheduleToleranceMinutes já suportado abaixo.
const DEFAULT_PRE = 30;
const DEFAULT_POST = 30;

// ---------------------------------------------------------------------------
// Derivação BR-local do timestamp do evento (TZ pinado).
// ---------------------------------------------------------------------------
/** dayOfWeek 0=Dom..6=Sab (mesmo formato da grade e de bk_weekdayFromDateStr). */
function dowBR(d) { return d.getDay(); }
/** minutos desde a meia-noite, wall-clock BR. */
function minutesBR(d) { return d.getHours() * 60 + d.getMinutes(); }

/** Parse 'HH:MM' (local) -> minutos. Retorna NaN se malformado. */
function hmToMin(hm) {
  if (typeof hm !== 'string') return NaN;
  const m = hm.match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return NaN;
  const h = Number(m[1]);
  const mi = Number(m[2]);
  if (!Number.isFinite(h) || !Number.isFinite(mi)) return NaN;
  return h * 60 + mi;
}

/**
 * acceptsCheckinFrom — porta de matrícula, espelha class_service.dart:86-90.
 * Só boolean REAL conta para isOpenClass; qualquer outra coisa = legado/null.
 */
function acceptsCheckin(cls, studentId) {
  const open = (cls.isOpenClass === true);
  const strict = (cls.isOpenClass === false);
  const ids = Array.isArray(cls.studentIds) ? cls.studentIds : [];
  if (open) return true;
  if (strict) return ids.includes(studentId);
  return ids.length === 0 || ids.includes(studentId); // null=legado
}

/**
 * Resolve a turma ATIVA para (studentId) no occurredAt.
 *
 * @param {Array<object>} classes  docs JÁ lidos (snapshot.docs.map id+data),
 *   filtrados ou não por isActive (filtramos defensivamente de novo aqui).
 * @param {string} studentId  já sanitizado (isSafeSegment) pelo núcleo.
 * @param {Date} occurredAt  timestamp ORIGINAL do evento.
 * @param {object} device  { sport?, category?, scheduleToleranceMinutes? }
 * @returns {{classId:string, className:string, sport:string, weight:number}|null}
 *   null => nenhuma turma casa => fallback sintético no recordAccessEvent.
 */
function resolveActiveClass(classes, studentId, occurredAt, device) {
  if (!Array.isArray(classes) || classes.length === 0) return null;
  if (!studentId) return null;
  if (!(occurredAt instanceof Date) || isNaN(occurredAt.getTime())) return null;

  const dow = dowBR(occurredAt);
  const mins = minutesBR(occurredAt);

  const dev = device || {};
  const tol = Number(dev.scheduleToleranceMinutes);
  const PRE = Number.isFinite(tol) ? tol : DEFAULT_PRE;
  const POST = Number.isFinite(tol) ? tol : DEFAULT_POST;

  const candidates = [];

  for (const cls of classes) {
    if (!cls || typeof cls.id !== 'string') continue;
    if (cls.isActive === false) continue;

    // --- Modalidade: porta genérica (device.sport ausente) casa qualquer. ---
    if (dev.sport != null && dev.sport !== '') {
      const clsSport = (cls.sport != null && cls.sport !== '') ? cls.sport : 'bjj';
      if (clsSport !== dev.sport) continue;
    }

    // --- Categoria: category==null = wildcard (não over-filtra legado). ---
    if (dev.category != null && dev.category !== '') {
      if (cls.category != null && cls.category !== dev.category) continue;
    }

    // --- Matrícula (canCheckIn) ---
    if (!acceptsCheckin(cls, studentId)) continue;

    // --- Janela de horário com tolerância ---
    const schedule = Array.isArray(cls.schedule) ? cls.schedule : [];
    let strictIn = false;
    let startClosest = -1; // maior start <= mins (ou start do slot grace)
    let anyEligible = false;

    for (const slot of schedule) {
      if (!slot || slot.dayOfWeek !== dow) continue;
      const start = hmToMin(slot.startTime);
      let end = hmToMin(slot.endTime);
      if (!Number.isFinite(start) || !Number.isFinite(end)) continue;
      // Guard meia-noite (turmas BJJ não cruzam; defensivo).
      if (end < start) end += 1440;

      const grace = (mins >= start - PRE) && (mins <= end + POST);
      if (!grace) continue;
      anyEligible = true;

      const sIn = (mins >= start) && (mins <= end);
      if (sIn) strictIn = true;

      // startClosest = maior start <= mins; se nenhum <= mins, usa o start do
      // slot grace (start futuro próximo) para manter o ranking estável.
      if (start <= mins) {
        if (start > startClosest) startClosest = start;
      } else if (startClosest === -1) {
        startClosest = start;
      }
    }

    if (!anyEligible) continue;

    // SECURITY (C1): pula candidata com id não-seguro (defensivo).
    if (!isSafeSegment(cls.id)) continue;

    const ids = Array.isArray(cls.studentIds) ? cls.studentIds : [];
    candidates.push({
      cls,
      strictIn,
      startClosest,
      enrolledStrict: ids.includes(studentId),
    });
  }

  if (candidates.length === 0) return null;

  // Desempate DETERMINÍSTICO (load-bearing p/ idempotência):
  //   1) strictIn (em andamento) antes de só-grace;
  //   2) startClosest mais recente (maior start <= mins) primeiro;
  //   3) enrolledStrict (aluno na lista) antes de turma aberta;
  //   4) classId ascendente (tie-break estável final).
  candidates.sort((a, b) => {
    if (a.strictIn !== b.strictIn) return a.strictIn ? -1 : 1;
    if (a.startClosest !== b.startClosest) return b.startClosest - a.startClosest;
    if (a.enrolledStrict !== b.enrolledStrict) return a.enrolledStrict ? -1 : 1;
    return a.cls.id < b.cls.id ? -1 : (a.cls.id > b.cls.id ? 1 : 0);
  });

  const cls = candidates[0].cls;
  return {
    classId: cls.id,
    className: (typeof cls.name === 'string' && cls.name) ? cls.name : cls.id,
    sport: (cls.sport != null && cls.sport !== '') ? cls.sport : 'bjj',
    weight: (typeof cls.weight === 'number' && Number.isFinite(cls.weight)) ? cls.weight : 1,
  };
}

module.exports = {
  resolveActiveClass,
  // exportados p/ teste:
  dowBR,
  minutesBR,
  hmToMin,
  acceptsCheckin,
};
