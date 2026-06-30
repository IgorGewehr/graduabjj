Vou estruturar o relatório a partir dos dados fornecidos.

## Resumo

Workflow de hardening pós-auditoria (pagamentos MP, inadimplência, regras, graduação, retenção, cobrança, onboarding) em 7 grupos.

- Implementados: ~30 achados (server-payments 9; server-inadimplência 10; rules 2; index 2; graduation-ui 2; retention 2; billing 1; grad-engine 1).
- Adiados (deferred): 4 — self check-in QR (rules), auto-promo→CF (rules + grad-engine), e dois itens arquiteturais documentados.
- Com ressalvas (verdict concerns): 2 grupos — `server` e `grad-engine`. Os outros 5 (`rules`, `index`, `graduation-ui`, `retention`, `billing`) passaram limpos.
- Compilação global: os 4 comandos passaram sem erros (`node --check` em index.js, server_functions.js e scripts/backfill_instructor_permissions.js; `dart analyze lib/` sem nenhuma linha de erro).
- Nada foi commitado nem deployado. Trabalho em branch `firebase-production`.

## Implementado por área

### Pagamentos (functions/server_functions.js)
- markPrivateLessonGiven (~5720, branch markPaidCash): cancela PIX MP em aberto (best-effort via novo helper `mpCancelPixPayment`) e limpa campos pix* ao marcar pago em dinheiro; declarado `{ secrets: MP_MKT_SECRETS }` para renovar OAuth no cancelamento.
- mpMktSettle (branch fin `status==='paid'`): novo tratamento de "paid sem gatewayPaymentId MP" + pagamento MP aprovado → registra `unmatchedPayment reason='duplicate'` e notifica admin, sem creditar de novo (idempotente por paymentId).
- createMpCardPayment (~4114): antes de cobrar cartão, cancela PIX vivo; se PIX já aprovado, recusa o cartão; se cancelamento não confirma, recusa — fecha janela de double-charge.
- createMpPix (~3651): lança `mapMpPixError` quando MP retorna sem `transaction_data`/`qr_code` vazio, em vez de QR vazio (cobre createMpPixPayment e createMpOrderPixPayment).
- createMpCardPayment catch: novo `mapMpCardError(e, statusDetail)` mapeia status_detail/cause em mensagens pt-BR acionáveis (fallback `internal` para detalhes não reconhecidos).
- CPF por checksum: trocado gate de comprimento por `validateCPF` nos dois caminhos PIX; CPF agora obrigatório no cartão (mudança de contrato — chamadas sem CPF falham com failed-precondition).
- resumeMpSubscription / updateSubscriptionCard: novo `assertSubscriptionStillBillable(sub)` rejeita estado terminal e termo esgotado (por contagem ou data) antes de reautorizar; retrocompatível (months<=0/sem termEndsAt nunca bloqueia).
- mercadoPagoMarketplaceWebhook (~5218): anti-replay do ts (janela 5 min) espelhando mercadoPagoWebhook.
- sendWhatsAppServer: só retorna `sent:true` com `res.ok && body.success===true`.
- requestWithdrawal (passo 4b): gate barato `abacatePayEnabled!==true` (latente, AbacatePay off em prod).

### Inadimplência / Crons (functions/server_functions.js)
- scheduledOverdueCheck: query agora `status in ['pending','overdue']` (a escada D+3/D+7/D+15/D+30 nunca disparava); dedup por estágio em TODOS os canais (push+interna+WhatsApp) via `resolveStage` + persistência de `lastReminderStage`/`lastReminderAt` no doc.
- scheduledOverdueCheck + scheduledDueSoonReminder: try/catch por-academia; null-guard em `dueDate` (continue em vez de derrubar o run); `Number(...)||0` em totalOverdueAmount.
- getStudentUserId (~111): substituída varredura O(usuários) de userAcademyMapping por leitura direta de `student.linkedUserId`; sem uid → null (graceful).
- upsertAutoAchievement: ao `.create()` inédito, envia push + notificação interna ('achievement'); ALREADY_EXISTS não re-notifica.
- sendBillingReminderWhatsApp: opt-out por aluno (`student.whatsappOptOut===true`); `normalizePhoneServer` (dígitos + prefixo 55); copy diferenciada por `financial.type` (templates genéricos sem ameaça de suspensão).
- scheduledDueSoonReminder: antecedência configurável `billingSettings.dueSoonOffsets` (default [7,2]); dedup via `lastDueSoonStage`; WhatsApp D+0 só no vencimento.
- isOverdueBR/daysOverdueBR: vencido só após fim do dia (23:59:59) em America/Sao_Paulo; contagem por dia-calendário.
- scheduledMonthlyTuitionGeneration (nova CF agendada 06:00 BRT): gera mensalidades server-side espelhando generateMonthlyTuitions; idempotente por (studentId, planId, referenceMonth); gate `settings/billing.autoTuitionEnabled===true` (FALSE por padrão).

### Regras (firestore.rules)
- academies update (~360-378): `mpConnected` adicionado ao conjunto de chaves server-only — cliente não pode mais forjar conexão MP. `abacatePayEnabled`/`asaasEnabled` propositalmente NÃO incluídos (settings_screen ainda os escreve via update direto).
- instructorLinkCodes (~617-639) / linkCodes (~644-668): removidas as cláusulas `allow update` que deixavam qualquer autenticado gravar usedAt/usedBy → `allow update: if false` / só `isStaffOrMonitor`. Fecha DoS de queima cross-academy de códigos. `LinkCodeService.markAsUsed()` ficou órfão (zero callers).

### Graduação (lib/screens/admin/graduation_screen.dart)
- _showPromotionSheet / _getNextBelt (~469-490, 671, 862): deriva `category`, `muaythaiVariant`, `hasGradeSystem`; usa `getGradesForSport(sportId, category, variant)` em vez de sempre BJJ. Esportes GradeSystem.none (boxe/MMA/musculação) mostram aviso e botão desabilitado. Guard de no-op: stripe exige `selectedStripes>currentStripes`, faixa exige `selectedBelt!=currentBelt`.
- promotion-type Row (~626-636): `maxStripesForCurrent = getGradeDefinition(sportId, currentBelt)?.maxStripes ?? 0` substitui o teto hardcoded em 4 (preta BJJ=6, Karatê=10); seletor de grau só aparece se maxStripes>0.

### Retenção (lib/services/retention_service.dart)
- Factor 3 + helpers (~238-241, 546-561): `_isFinancialOverdue` espelha `Payment.isOverdue` (dueDate passado E status fora de {paid,cancelled}) com fallback retrocompatível; `_readDate` lê Timestamp/DateTime/String.
- Novo enum `DelinquencyConsequence {none,warn,restrict}` + `DelinquencyPolicy` (warnAfter=1, restrictAfter=30, `allowAutoRestrict=false` default); `consequenceForStudent`/`consequenceForDaysOverdue`/`maxDaysOverdue`. Apenas classifica, não bloqueia — sem consumidor (0 callers).

### Cobrança (lib/services/billing_reminder_service.dart)
- sendBulkWhatsAppForStage (~992-1110): unifica dedup por estágio com o cron — lê `lastReminderStage` de cada financial, pula se `== stage.value`, grava marcador só no sucesso. Fecha duplicação app↔cron e reenvio ilimitado do mesmo estágio. (Método sem caller em lib/ hoje.)

### Login / Onboarding (functions/index.js)
- joinAcademy (149-153, 259-271): captura cpf/phone sanitizados só dentro do branch de student órfão (atômico); email do userData verificado.
- demoteToStudent (~591-594) / revokeMember (~643-646): guard que lê `academies/{id}.ownerId` e bloqueia ação contra o DONO (`permission-denied`); retrocompatível (academias sem ownerId não afetadas).
- caktoWebhook (957-980): fail-closed — secret ausente → 503, mismatch → 401 (antes secret não configurado pulava auth).
- mpHandlePayment reversal guard (1249-1290): refunded/charged_back só revogam quando a charge é o pagamento ativo da assinatura; cancelled exige paywallPayments/{chargeId}. Para evento de PIX abandonado/expirado.
- trialExpiryReminder (~1574-1697): reabilitado (estava em bloco comentado); job diário 13:00 BRT; idempotente via `trialReminderSentAt`; degrada gracioso sem NOTIFICATION_API_KEY.

### grad-engine (lib/services/belt_progression_service.dart, attendance_service.dart)
- promote() (~826-985): novo param opcional `idempotencyKey`; quando presente usa IDs determinísticos (`promo_<key>`) numa runTransaction read-before-write (create-if-absent) para progressão + conquista. Caminho sem chave (promoção manual admin) preserva comportamento legado (auto-id).
- _maybeAutoPromote() (~537-557): passa key `<studentId>_<sport>_<belt>_<stripes>` — duas presenças concorrentes no mesmo limiar colapsam numa única promoção, eliminando docs/conquistas duplicados.

## Adiado (e por quê)

- monthly-tuition (server): a CF `scheduledMonthlyTuitionGeneration` está SEGURA POR PADRÃO (`autoTuitionEnabled=false`). REVISAR MODELO DE COBRANÇA antes de habilitar em qualquer academia.
- consequência de inadimplência (retention): `DelinquencyPolicy`/`consequenceForStudent` apenas classificam; `allowAutoRestrict` default false. Wire-up de bloqueio (check-in/reserva) é decisão de produto — não implementado, sem consumidor.
- self check-in inflando attendanceCount (rules ~445-457): deferido — arquitetural; mitigação correta é mover contagem para server (CF/transação) + validar QR assinado.
- auto-promo / auto-graduação que falha p/ monitor (rules ~505-507): deferido — depende de mover auto-graduação para server-side.
- auto-promoção → Cloud Function on-attendance-create (grad-engine): deferido — o fix de idempotência por ID determinístico já blinda contra dupla-promoção; migração para trigger on-create fica como follow-up (exige mover checkEligibility/promote para functions + ajustar rules).

## Ressalvas da verificação

Grupos com verdict `concerns`: **server** e **grad-engine**. Demais: pass.

Major:
- getStudentUserId (server_functions.js:111-135): agora depende EXCLUSIVAMENTE de `student.linkedUserId`. Alunos LEGADOS linkados por caminho que populou só o mapping (sem linkedUserId) passam a retornar null → degrada SOMENTE notificações (push/interna em sendBillingReminderWhatsApp:623, due-soon:732, milestone:1614, promoção:6829). NÃO afeta cobrança/webhook/settle/dinheiro. Mitigável com backfill antes do deploy.

Minor (server):
- createMpSubscription: guarda de duplicidade passou a incluir status 'error' no where-in. Docs 'error' legados <24h com mpPreapprovalId podem bloquear retry por até 24h (desejável: esconde órfão). Opcional: exigir `possibleOrphan===true`.
- payment_service.dart foi designado ao grupo mas NÃO recebeu alteração. A nova CF duplica a lógica de generateMonthlyTuitions; validar paridade exata cliente↔servidor antes de habilitar autoTuitionEnabled.

Minor (grad-engine):
- belt_progression_service.dart:942-960: id determinístico permanente. Se um grau for revertido/corrigido e houver futura auto-promoção ao MESMO alvo, cai em `existing.exists` e faz no-op TOTAL — não reaplica `updateData`, currentGrade não avança. Probabilidade baixa (progressão é forward-only). Fix sugerido: mover `tx.update(student, updateData)` para fora do guard de existência.
- Escopo (onlyAssignedFilesTouched=false): git status mostra arquivos modificados fora do grupo grad-engine (sports.dart, auth_provider.dart, graduation_screen.dart, student_detail_screen.dart, link_code_screen.dart, monitor_student_detail_screen.dart, billing_reminder_service.dart, retention_service.dart, team_service.dart). Confirmar com o orquestrador a atribuição correta por grupo.

Minor (rules):
- firestore.rules:419 (users create, branch student): acessa `getUserAcademyMapping().academyDetails.keys()` sem guardar `keys().hasAll(['academyDetails'])`. Fail-CLOSED (seguro) e inalcançável no app atual (joins via CF/Admin SDK). Lacuna de robustez latente.
- attendance write (560) / financials create (~694): instrutores legados sem as extraPermissions ('attendance:take'/'financial:create') perdem write silenciosamente. Auditar `academyDetails.*.role=='instructor'` em prod e backfill de grants antes/com o deploy.

Minor (index):
- trialExpiryReminder lê NOTIFICATION_API_KEY de process.env (não secrets[]); sem key válida o envio dá não-2xx e silenciosamente não estampa trialReminderSentAt (no-op, sem retry). Confirmar a key no functions/.env do deploy.
- mpHandlePayment reversal: academia legada sem `subscription.externalPaymentId` não auto-revoga refund de charge pré-fix (precisa de tratamento manual). Trade-off deliberado.

Minor (billing):
- N+1 reads (uma `.get()` por item para lastReminderStage); lastReminderAt usa relógio do device (Timestamp.fromDate) vs serverTimestamp() do cron; overwrite backward do marcador se admin dispara estágio anterior manualmente (1 mensagem extra, sem perda financeira). Método sem caller em lib/ hoje.

## Antes de deployar

Nada foi commitado/deployado. Ordem e validações sugeridas:

1. firestore.rules: NÃO houve validação por emulador (JDK 21+ ausente; só revisão manual de balanceamento de chaves 128/128, 549/549, 85/85). Rodar emulador ou Firebase preview antes do deploy das rules.
2. Backfill obrigatório antes do deploy das functions: rodar one-shot que varre userAcademyMapping e estampa `student.linkedUserId` onde faltar (academyDetails[acad].studentId → students/{id}.linkedUserId). Sem isso, alunos legados perdem notificações.
3. Auditar instrutores legados: query em `userAcademyMapping` com role=='instructor' e confirmar/backfill extraPermissions ('attendance:take', 'financial:create', 'competitions:create') antes/junto das rules.
4. Confirmar segredos no deploy: `CAKTO_WEBHOOK_SECRET` (índice — fail-closed agora dá 503 se ausente) e `NOTIFICATION_API_KEY` no functions/.env (trialExpiryReminder e billing).
5. NÃO habilitar `settings/billing.autoTuitionEnabled` em nenhuma academia sem antes validar paridade exata entre generateMonthlyTuitions (cliente) e scheduledMonthlyTuitionGeneration (CF) — clamp de dia, período não-mensal, cardOnly. A CF é idempotente por referenceMonth+planId, mas testar a coexistência com o botão manual.
6. Manter `DelinquencyPolicy.allowAutoRestrict=false` (sem consumidor de bloqueio) — decisão de produto pendente.
7. Validar template do e-mail de trial e o backfill_instructor_permissions.js (node --check passou) antes de executá-lo.
8. Confirmar com o orquestrador a atribuição de arquivos fora do escopo grad-engine (vários callers/telas no working tree) antes de commitar por grupo.