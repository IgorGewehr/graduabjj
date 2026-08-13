'use strict';

const BILLING_TIME_ZONE = 'America/Sao_Paulo';

function timestampToDate(value) {
  if (!value) return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value.toDate === 'function') {
    const converted = value.toDate();
    return converted instanceof Date && !Number.isNaN(converted.getTime())
      ? converted
      : null;
  }
  const converted = new Date(value);
  return Number.isNaN(converted.getTime()) ? null : converted;
}

function datePartsInBillingTimeZone(value) {
  const date = timestampToDate(value);
  if (!date) return null;
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: BILLING_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const byType = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return {
    year: Number(byType.year),
    month: Number(byType.month),
    day: Number(byType.day),
  };
}

function billingDateAtStartOfDay(year, month, day) {
  const desiredAsUtc = Date.UTC(year, month - 1, day, 0, 0, 0, 0);
  let candidateMs = desiredAsUtc;
  const formatter = new Intl.DateTimeFormat('en-US', {
    timeZone: BILLING_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  });
  // Two passes handle timezone offset changes without hard-coding UTC-3.
  for (let pass = 0; pass < 2; pass++) {
    const parts = Object.fromEntries(
      formatter.formatToParts(new Date(candidateMs)).map((part) => [part.type, part.value])
    );
    const observedAsUtc = Date.UTC(
      Number(parts.year),
      Number(parts.month) - 1,
      Number(parts.day),
      Number(parts.hour),
      Number(parts.minute),
      Number(parts.second)
    );
    candidateMs += desiredAsUtc - observedAsUtc;
  }
  return new Date(candidateMs);
}

function compareCalendarDates(a, b) {
  if (a.year !== b.year) return a.year - b.year;
  if (a.month !== b.month) return a.month - b.month;
  return a.day - b.day;
}

function clampDueDay(year, month, dueDay) {
  const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const parsed = Math.trunc(Number(dueDay));
  if (!Number.isFinite(parsed)) return Math.min(10, lastDay);
  return Math.max(1, Math.min(parsed, lastDay));
}

/**
 * A plan/student membership can only generate a charge for a month when both
 * the plan and the membership existed no later than that month's due date.
 * Missing timestamps are treated as legacy data and remain eligible.
 */
function isMembershipEligibleForMonth({
  planCreatedAt,
  studentAddedAt,
  referenceYear,
  referenceMonth,
  dueDay,
}) {
  const due = {
    year: Number(referenceYear),
    month: Number(referenceMonth),
    day: clampDueDay(referenceYear, referenceMonth, dueDay),
  };
  for (const timestamp of [planCreatedAt, studentAddedAt]) {
    const created = datePartsInBillingTimeZone(timestamp);
    if (created && compareCalendarDates(created, due) > 0) return false;
  }
  return true;
}

function findConflictingStudentIds(entries) {
  const planIdsByStudent = new Map();
  for (const entry of entries) {
    if (!entry || !entry.studentId || !entry.planId) continue;
    if (!planIdsByStudent.has(entry.studentId)) {
      planIdsByStudent.set(entry.studentId, new Set());
    }
    planIdsByStudent.get(entry.studentId).add(entry.planId);
  }
  return new Set(
    [...planIdsByStudent.entries()]
      .filter(([, planIds]) => planIds.size > 1)
      .map(([studentId]) => studentId)
  );
}

module.exports = {
  BILLING_TIME_ZONE,
  billingDateAtStartOfDay,
  clampDueDay,
  datePartsInBillingTimeZone,
  findConflictingStudentIds,
  isMembershipEligibleForMonth,
};
