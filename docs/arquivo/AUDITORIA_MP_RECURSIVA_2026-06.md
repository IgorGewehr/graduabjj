> **Arquivado (2026-07):** re-auditoria recursiva de 2026-06 (4 rodadas). A
> maioria dos achados high/medium foi corrigida em `server_functions.js` e nos
> services de loja/pagamento no código atual. Mantido como registro histórico
> das correções aplicadas; não é referência viva.

I'll write the audit report directly from the provided data.

## Resumo

A auditoria recursiva do Mercado Pago convergiu em **4 rodadas**, com **48 achados confirmados** distribuídos pelos seis fronts (loja, financeiro PIX, financeiro cartão, OAuth, webhook/settle, integridade de valor).

Distribuição por severidade: **high** (cobrança dupla silenciosa, oversell sem restauração, reconnect órfão), **medium** (3DS, races de webhook/refresh, estorno parcial), **low** (hardening OAuth, drifts de estoque staff-only) e **info** (integridade de valor confirmada como correta).

Correções aplicadas: **a esmagadora maioria dos high/medium foi corrigida** em `functions/server_functions.js`, `lib/services/store_service.dart`, `lib/services/payment_service.dart`, `lib/services/abacate_pay_service.dart`, `lib/widgets/payment_sheets.dart`, `lib/screens/admin/store_orders_admin_screen.dart` e `firestore.rules`. **Deferidos** (exigem nova superfície server-side, fora do escopo cirúrgico): decremento atômico do mark-paid manual da loja (precisa virar CF + travar flip no `firestore.rules`), reconcile MP proativo (job/callable), e o wallet AbacatePay (latente, gated off).

Estado de compilação:
- `node --check functions/server_functions.js` → **OK**
- `node --check functions/index.js` → **OK**
- `dart analyze lib/` (filtro `error`) → **vazio**

**Veredito geral:** os três caminhos vivos (PIX, cartão, OAuth/recebimento) ficaram substancialmente mais resilientes. Os vetores de **cobrança dupla silenciosa** (cash-then-PIX na loja e na mensalidade, card→card, card→PIX bidirecional, mark-paid retendo `gatewayPaymentId`) agora **geram alerta de conciliação** ou são **prevenidos por guard**. O 3DS deixou de ser tratado como recusa. **Não há perda de dinheiro irrecuperável nos fluxos vivos**: todo double-charge residual cai em `duplicatePayment` → `mpMktRecordUnmatchedPayment` + notify admin (reembolso manual, mas detectado). Riscos residuais são operacionais (decremento de estoque do mark-paid manual ainda client-side, mitigado por guard server-side; estorno parcial agora registrado mas a reversão de benefício depende de conciliação manual).

## Por área

### Loja (store) — PIX
- **Cancelamento de pedido pago não restaurava estoque** (`lib/screens/admin/store_orders_admin_screen.dart:677` → `store_service.dart:766-818`): `_cancelOrder` chamava `_updateStatus(cancelled)`, deixando estoque drifted. **Corrigido**: rota agora delega a `StoreService.cancelOrder` (restaura estoque de pedidos não-pendentes, só `inStock`).
- **Pedido marcado pago manual + pago por PIX = no-op silencioso** (`server_functions.js:5446-5461` / `~5618-5626` order branch): **corrigido** espelhando o branch financial — pedido `paid` sem `gatewayPaymentId` que recebe MP aprovado retorna `duplicatePayment`.
- **Cash-then-mesmo-PIX vivo, cobrança dupla silenciosa** (`server_functions.js:5741-5764` / `~5749-5778`): **corrigido** com guard `paid` + `gatewayPaymentId === chargeId` + sem `stockSettled` → `duplicatePayment`.
- **"Marcar como Pago" não cancelava PIX vivo no MP** (`store_service.dart:842-887`, `766-818`): **corrigido** com `_killLivePixOnPaid(orderId)` — limpa campos pix e best-effort `cancelMpPix`, ligado a `updateOrderStatus(paid)` e `markOrderAsPaid`.
- **Oversell server-side no settle (estoque ia a negativo)** (`server_functions.js:5530-5540` / `~5615-5660`): **corrigido** — decremento agora roda em transação por-produto com piso `Math.max(0, cur-qty)`; falta de estoque registra `oversell` + notify.
- **`cancelOrder` restaurava estoque não-atômico** (`store_service.dart:820-839`): **corrigido** — `FieldValue.increment(qty)` no lugar de read-then-write.
- **Regra de create sem whitelist** (`firestore.rules:797-813`): **corrigido** — `!keys().hasAny([gatewayPaymentId, externalPaymentId, pixCode, pixAmount, pixExpiresAt, stockSettled, paidAt, ...])`, fechando o seed do reuse-guard.
- **Decremento do mark-paid manual client-side/não-atômico** (`store_service.dart:900-949` + `server_functions.js:5842-5862`): **deferido** — exige `markOrderPaidManual` (onCall admin-gated, tx com piso) + travar flip no `firestore.rules`. Mitigado pelo guard `paid` sem `gatewayPaymentId` (5754-5755).
- AbacatePay `createOrderPixPayment` (tolerância 1 real, unidades mistas): **info**, latente/gated off.

### Financeiro — PIX
- **PIX órfão sem self-heal por external_reference** (`server_functions.js:3898-3939`, `createMpPix ~3672`): **corrigido** — `GET /v1/payments/search?external_reference` antes do mint adota PIX pending vivo (valor/qr/expiry validados) em vez de cunhar 2º pagável.
- **Falha no `finRef.update` final fora do try/catch / PIX órfão pagável** (`3849-3874`, `3981-4006`): mitigado pelo self-heal acima + lock auto-expira em 60s.
- **PIX reaproveitado sem revalidar valor** (`3807-3817` reuse guard + `3700-3753` hasFreshPix): **corrigido** — persiste `pixAmount` (REAIS); reuse só com match de 1 centavo, senão cancela e re-minta.
- **Mark-paid manual retinha `gatewayPaymentId`** (`payment_service.dart:650-679` + `server_functions.js:5779-5806`): **corrigido** no Dart — `markAsPaid` apaga `gatewayPaymentId` (`FieldValue.delete`) + `paymentGateway:'manual'`, jogando o doc no caminho de duplicidade.
- **Cartão pendente deixa campos PIX órfãos → 2º cartão bloqueado até 24h** (`4270-4284` + `5349-5353`): **corrigido** — após cancelar PIX no card path, apaga `pixCode/.../gatewayPaymentId`.
- **Early-reuse devolve QR já cancelado pelo card path**: **corrigido** pela causa raiz acima.
- `checkPixStatus` AbacatePay-only desconectado do MP (`2980-3016`): **info/deferido** — UI usa listener realtime; falta só reconcile MP proativo (nice-to-have).

### Financeiro — Cartão
- **in_process/pending/3DS tratado como recusa → retry duplica cobrança** (`payment_sheets.dart:1605-1631` + `abacate_pay_service.dart:49-72` + `server_functions.js:4207-4218`): **corrigido** — DTO `CardPaymentResult` ganhou `status/statusDetail/threeDsUrl` + getters `isPending/requiresThreeDs`; `_handlePayment` abre 3DS via `launchUrl`, mostra "em análise", seta `_paymentPending` e **bloqueia novo submit**. Cobre fluxo avulso e assinatura (mesmo `CardPaymentSheet`).
- **Guard card→PIX unilateral (double-charge inversa)** (`4206-4219` vs `3863-3874`): **corrigido** — `createMpCardPayment` persiste `cardPendingPaymentId/Status/ExpiresAt`; helper `mpCancelLivePendingCard` invocado em ambos caminhos PIX antes de mintar (guard bidirecional).
- **Guard card→card ausente** (`4184-4211`, `5301-5320`): **corrigido** — `mpCancelLivePendingCard` chamado no início de `createMpCardPayment`.
- **Guard card→card ignorava cartão JÁ APROVADO não liquidado** (`4256` + `5375-5394`): **corrigido** — helper retorna `{cancelled,alreadyApproved}`; se `alreadyApproved` ou `!cancelled`, lança `HttpsError('failed-precondition')` em vez de cobrar.
- **TTL local de 1h liberava 2º cartão** (`4370-4371` + `5380-5383`): **corrigido** — removido early-return por TTL; consulta estado real no MP (`GET`), TTL virou dica suave.
- **`cardPending*` não limpo em rejected/expira** (`4286-4301` + `5301-5316`): **corrigido** — webhook chama `mpClearCardPendingIfMatches` (tx, só se `cardPendingPaymentId === payment.id`) em rejected/cancelled.
- **Settle aprovado não limpa `cardPending*`** (`4358-4359` + `5955-5966`): **corrigido** — `FieldValue.delete()` dos marcadores no update `paid` de ambos os branches.

### Conexão OAuth (recebimento)
- **Callback persistia tokens antes de `mpConnected`** (`3260-3282`): **corrigido** — `db.batch()` atômico + `set(merge)`.
- **disconnect não expunha órfãos ao admin** (`3379-3416`): **corrigido** — persiste `mpHasOrphanPreapprovals` + `mpOrphanPreapprovalIds` + IDs na notificação.
- **Refresh concorrente double-refresh (lock stale, sem timeout)** (`3050-3067` + `3158-3186`): **corrigido** — `AbortSignal.timeout(20s)` < `LOCK_STALE_MS(30s)`.
- **Rotação de refresh_token perdida em falha de escrita** (`3165-3186`): **corrigido** — retry com backoff + `mpNeedsReauth=true` + `HttpsError('unavailable')` recuperável.
- **Nonce não invalidado em falha de troca** (`3231-3298`): **corrigido** — delete best-effort no catch.
- **Reconnect sobrescrevia mpAuth antigo sem cancelar preapprovals** (`3289-3299`): **corrigido** — compara `mpUserId` vs `tok.user_id`; troca de conta com subs ativas cancela preapprovals da conta antiga (token antigo) + registra órfãos + notify.
- **disconnect não revogava token no MP** (`3450`): **corrigido** — `DELETE /users/{mpUserId}/applications/{client_id}` best-effort antes do delete local.
- **state não amarra admin iniciador** (`3238-3244`): **corrigido** — nonce 8→16 bytes + `oauthAdminUid` para forense.

### Webhook / Settle / Reversão
- **Over-restore de estoque no estorno sob re-entregas** (`5784-5833`): **corrigido** — restauração movida para DENTRO da tx do flip de status (reads antes de writes); `stockRestorePending` removida; re-entregas viram no-op.
- **Estorno via `subscription_authorized_payment` não tratado** (`4524-4542`): **corrigido** — branch `MP_REVERSAL_STATUSES` → `mpSubHandleReversal(academyId, subRef.id, ap.payment)`.
- **`mpSubSettleCycle` não validava valor vs `recurringValue`** (`4343,4375,4527`): **corrigido** — grava `amountMismatch` + notify quando diverge >1 centavo.
- **Estorno PARCIAL silenciosamente ignorado** (`5450-5460`): **corrigido** — `mpMktHandlePartialRefund` (tx, exige `paid` + mesmo `gatewayPaymentId`, `partialRefundEvent`+`partialRefundKey` idempotente, notify). A reversão do benefício (estoque/presença) ainda depende de conciliação manual.
- **Webhook de academia desconectada → 500/retry** (`5530-5531`): **corrigido** — `failed-precondition` sem `refreshToken` → `200 skipped:'no_token'`; caso transitório mantém 500/retry.
- **Tópico vazio → GET non-payment → 500/retry** (`5509-5531`): **corrigido** — `e.status===404` → `200 skipped:'not_a_payment'`.

### Integridade de valor (transversal)
Área **limpa** — todos os achados são **info/garantia**, sem correção necessária. `application_fee` é omitido (não enviado), MP liquida direto na conta da academia (0% taxa, sem float/wallet de plataforma). Convenção de unidade consistente: `transaction_amount`/`financials.amount`/`order.total` sempre **REAIS**; `wallet`/`walletTransactions` sempre **CENTAVOS** (isolado, AbacatePay, gated off). O `gatewayFee` fixo de 80c e o não-crédito de PIX na wallet são **latentes** (AbacatePay off; MP nunca toca o wallet) — débito técnico documentado, sem exposição em prod.

## Conexão OAuth (recebimento) — veredito

O caminho de recebimento está agora **sólido**, com os defeitos de atomicidade e concorrência fechados.

**State/CSRF:** o nonce é o token anti-CSRF, segredo server-side nunca exposto ao atacante (segue só no browser da vítima), single-use, TTL 10min. Foi endurecido de 8→16 bytes (128 bits), agora deletado em **qualquer** desfecho (sucesso, expiração e falha de troca — `3231-3298`), e passou a registrar `oauthAdminUid` para forense. A fronteira de segurança real (academia) sempre esteve no state; o binding por-admin é hardening, não vetor.

**Rotação de refresh_token:** o ponto mais delicado — perda da rotação numa falha de escrita pós-MP (`3165-3186`) — agora tem retry+backoff e degrada para `mpNeedsReauth` + `HttpsError('unavailable')` recuperável em vez de quebrar a conexão silenciosamente.

**Lock:** o double-refresh sob carga (lock stale reivindicado com holder vivo) foi fechado com `AbortSignal.timeout(20s)` < `LOCK_STALE_MS(30s)` (`3050-3067`), garantindo que um holder travado aborte antes que seu lock seja reivindicado.

**Segurança do token / disconnect:** o disconnect agora faz **revoke best-effort** (`DELETE /users/{mpUserId}/applications/{client_id}`) antes do delete local (`3450`), honrando a intenção do admin e encurtando a janela de um refresh_token vazado. O **reconnect com troca de conta** (vetor high real) deixou de orfanar preapprovals: cancela com o token antigo + registra órfãos + notifica (`3289-3299`). O callback é atômico (`db.batch()` + `set(merge)`), eliminando o estado token-vivo-mas-`mpConnected:false`.

Residual aceitável: a revogação e o cancel cross-account são best-effort (não bloqueiam o disconnect/connect), coerente com o contrato OAuth do MP — quando o token já foi revogado externamente, a única resolução é manual no painel, e o admin é notificado.

## Integridade de valor — veredito

**Confirmada consistente, sem dinheiro preso no fluxo MP vivo.** A unidade canônica é **REAIS** em `transaction_amount`, `financials.amount` e `order.total`; o `amount` do cliente (centavos) jamais é gravado — só validado por `validateAmount` (inteiro) e cross-check de 1 centavo. O caminho cartão faz `transactionAmount = expectedCentavos/100` (`:4104`), round-trip lossless absorvido pelas tolerâncias de 1 centavo do settle (`:5468`, `:5604`).

O modelo **`application_fee~0`** é implementado por **omissão** do campo em `/v1/payments` e preapproval (o MP rejeita 0): o dinheiro liquida **direto na conta da academia**, sem float/wallet de plataforma — não há onde dinheiro ficar preso. O settle credita REAIS no doc certo, **exatamente uma vez**, protegido por mismatch-guards e idempotência determinística (`5808-5844` financial, `5643-5688` order, `4464-4502` subscription).

A única convenção em **centavos** (`wallet`/`walletTransactions`/`requestWithdrawal`) é uma **ilha isolada e duplamente morta**: só gravável via endpoints AbacatePay (gated `abacatePayEnabled=false`) e `mpMktSettle` nunca toca o wallet. O risco "100x" exige duas mudanças futuras inexistentes (reativar AbacatePay E ligar MP ao wallet sem conversão). Mantida como nota de hardening.

## Residual / antes de deployar

**Nada foi commitado nem deployado.** Todas as edições estão no working tree; `node --check` (server_functions.js, index.js) e `dart analyze lib/` passam sem erros.

Itens **deferidos** a revisar/agendar antes de fechar o ciclo:
1. **Mark-paid manual de pedido da loja** (`store_service.dart:900-949`): o decremento de estoque segue client-side, não-atômico vs settle MP. Fix recomendado: criar `markOrderPaidManual` (onCall admin-gated, `runTransaction` por item com piso em 0, grava `status=paid`+`paymentMethod='cash'`+sem `gatewayPaymentId` atomicamente) e **endurecer `firestore.rules`** para negar o flip `pendingPayment→paid` pelo cliente em `storeOrders`. Mitigado hoje pelo guard `paid` sem `gatewayPaymentId` (`5754-5755`) — janela de corrida, não perda determinística.
2. **Broaden do branch financial do settle** (`server_functions.js:5793`): docs **financial** marcados manual ficam com `paymentGateway='manual'` e `method='pix'`, então o gate cash-like de 5793 **não casa** e o 2º pagamento PIX cai no no-op. Apagar `gatewayPaymentId` (já feito no Dart) cobre **pedidos** (branch order 5631 dispara incondicional em `!gatewayPaymentId`), mas **financials precisam** que 5793 inclua `paymentGateway==='manual'`. **Verificar se esse broaden foi aplicado** antes de deployar — caso contrário o cash-then-PIX da mensalidade permanece silencioso.
3. **Reconcile MP proativo** (nice-to-have): job/callable `GET /v1/payments/{id}` como rede de segurança para webhooks perdidos, disparando o `mpMktSettle` idempotente — sem creditar fora do caminho idempotente.
4. **Reversão de benefício no estorno parcial**: `mpMktHandlePartialRefund` registra + alerta, mas estoque parcial e presença de aula particular não são revertidos automaticamente — conciliação manual.
5. **Surface de UI no app Flutter** para `mpHasOrphanPreapprovals` (server-side já persistido) — exibir aviso destacado nas configurações.
6. **Wallet AbacatePay** (`gatewayFee` fixo 80c, não-crédito PIX): só revisar **se/quando** AbacatePay for reativado; padronizar unidade para REAIS antes de ligar ao fluxo MP.

**Compat com app antigo preservada** em todos os fixes: campos novos no `CardPaymentResult` são parâmetros opcionais (respostas antigas → null); `set(merge)` evita lançar em docs inexistentes; apagar `gatewayPaymentId` não quebra leituras legadas; whitelist do `firestore.rules` usa `hasAny` (não `hasOnly` estrito), preservando o checkout legítimo; settles MP sempre gravam `gatewayPaymentId`, então os novos guards de duplicidade não geram falso-positivo em re-entregas do webhook.