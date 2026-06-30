/**
 * access_control/overdue_util.js — definição CANÔNICA de "vencido" (BR wall-clock)
 * ============================================================================
 *
 * Fonte ÚNICA da verdade sobre quem está em atraso. Reusada por:
 *   - server_functions.js (cron scheduledOverdueCheck / dunning ladder)
 *   - access_control/financial_gate.js (bloqueio na catraca por inadimplência)
 *
 * Mantê-las juntas garante que o PORTÃO e o cron de cobrança NUNCA discordem de
 * quem está inadimplente. process.env.TZ está pinado em America/Sao_Paulo
 * (index.js), então os getters de Date abaixo são wall-clock BR.
 *
 * Estas funções são PURAS (sem I/O) e o módulo NÃO carrega firebase-admin, para
 * poder ser exigido tanto pelo caminho crítico da catraca quanto pelos crons sem
 * arrastar dependências pesadas. `node --check` deve passar.
 * ============================================================================
 */

'use strict';

// Detecção de vencido normalizada para o FIM DO DIA do vencimento em horário de
// Brasília. Sem isso, uma cobrança que vence "hoje" às 00:00 já apareceria como
// "atrasada há 0 dias". Considera vencida só a partir do dia SEGUINTE ao
// vencimento.
function isOverdueBR(dueDate, now) {
  const endOfDueDay = new Date(
    dueDate.getFullYear(), dueDate.getMonth(), dueDate.getDate(), 23, 59, 59, 999
  );
  return now.getTime() > endOfDueDay.getTime();
}

// Dias de atraso por DIA-CALENDÁRIO (BR), não por janela de 24h crua. Venceu
// ontem => 1, há 7 dias => 7. Evita o off-by-one do Math.floor(ms/dia).
function daysOverdueBR(dueDate, now) {
  const startDue = new Date(dueDate.getFullYear(), dueDate.getMonth(), dueDate.getDate());
  const startNow = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const diff = Math.round((startNow.getTime() - startDue.getTime()) / (1000 * 60 * 60 * 24));
  return diff > 0 ? diff : 0;
}

module.exports = { isOverdueBR, daysOverdueBR };
