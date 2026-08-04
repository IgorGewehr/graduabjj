<!-- Gerado por .claude/workflows/financeiro-recorrencia-architecture.js -->

> **Arquivado (2026-07):** este era o blueprint PRÉ-implementação da assinatura
> recorrente (MP Preapproval). **Já foi implementado** — `server_functions.js`
> tem o fluxo completo (`POST /preapproval`, `auto_recurring`, os 4 crons
> `scheduledSubscriptionTermGuard/Reconcile/Dunning/CardExpiryWarning`). Para o
> contrato vivo do que foi construído, ver `docs/recorrencia-mp-contract.md` e
> `docs/PAGAMENTOS_MP.md`. Mantido aqui só como registro do design original.

## ✅ Decisões do dono (travadas)
- **1ª cobrança da assinatura:** valor **cheio no dia da assinatura**, depois mensal no mesmo dia.
- **Cancelamento no meio do período:** **sem reembolso** — para as próximas cobranças (estilo Netflix).
- **"Somente cartão" + mensal ⇒ assinatura automática:** marcar um plano mensal como cartão-only **já ativa** o auto-charge recorrente (MP Preapproval), sem toggle extra.
- **Seleção de método:** **por plano** (v1) — sem override por aluno nesta versão.

# Blueprint Financeiro GraduaBJJ — Assinatura Recorrente + Seleção de Método + Avulsa

Branch alvo: `firebase-production` (produção). Unidade monetária canônica: **REAIS** em `financials.amount` e `Subscription.recurringValue` (ver `financial_amount_unit`). Liquidação: **conta conectada da academia via OAuth** (0% de taxa, sem `application_fee`).

---

## 1) Diagnóstico do Mercado Pago hoje

### Já funciona (marketplace por academia — é o que vamos estender)
- **Token OAuth por academia**: `getMpAccessToken(academyId)` (`server_functions.js:2554`) com refresh-lock. Toda cobrança de aluno roda na conta da academia.
- **Wrapper HTTP único**: `mpRequest(method, path, {body, token, idempotencyKey})` (`:2530`) — usaremos para `/preapproval`, `/authorized_payments`, `/v1/payments`, e o `PUT` de cancel.
- **PIX marketplace**: `createMpPix` (`:2863`) + callable `createMpPixPayment` (`:2915`) — POST `/v1/payments` com `payment_method_id:'pix'`, deriva valor do doc `financials` server-side.
- **Cartão marketplace**: `createMpCardPayment` (`:3114`) — token client-side + `installments`, 3DS opcional, settle inline se `approved`. **Já deriva o valor server-side e rejeita tampering** (`:3155-3165`).
- **Tokenização PCI**: `MpCardTokenizer.tokenize` (`lib/services/mp_card_tokenizer.dart`) — backend nunca vê o PAN. Token é **single-use**.
- **Webhook marketplace**: `mercadoPagoMarketplaceWebhook` (`:3259`) com roteamento `?acad=`, **HMAC fail-closed** (`:3273-3294`). Hoje só processa `type === 'payment'` (`:3299`).
- **Settle atômico**: `mpMktSettle` (`:3322`) — `db.runTransaction` read-guard-update, tolerância de 1 centavo, idempotente em `status==='paid'`. Para `financials` usa campos `amount`(REAIS), `method`, `paymentDate`, `gatewayPaymentId`.
- **Parser de referência**: `mpMktParseRef` (`:3252`) — `split(':')` com `docId = parts.slice(2).join(':')`. **Já aceita o formato `acad:sub:subId` sem mudança** (type passa a ser `sub`).

### O que falta para recorrência verdadeira (Netflix-style)
- **Sem auto-charge de cartão para mensalidades de aluno.** Cada mês é gerado offline (`generateMonthlyTuitions`, manual) e o aluno paga na mão.
- **Sem `/preapproval` no marketplace.** O único preapproval existente é o **paywall SaaS** em `functions/index.js` (`createMercadoPagoCheckout`), que roda **na conta da PLATAFORMA** — conta e propósito errados. **NÃO reusar.**
- **Sem fim-após-N-meses.** Plano não tem `endDate`/`totalMonths`.
- **Sem dunning/retry.** `subscription_renewal_refused`/`failed` citados em comentário mas não implementados.
- **Sem restrição de método por plano/cobrança.** Método é puramente gateway-driven (MP=cartão+PIX, Asaas/AbacatePay=PIX).
- **Sem job agendado** de geração/conciliação.

---

## 2) Assinatura recorrente tipo Netflix

### 2.1 Mecanismo exato no Mercado Pago

Usar **Assinaturas (Preapproval) SEM plan template**, criada na conta conectada da academia, passando o **cartão tokenizado + `status:'authorized'`** — isso é o que faz o MP cobrar sozinho todo mês, sem página hospedada e sem ação do usuário após o primeiro subscribe. (Diferente do paywall, que usa `status:'pending'` e deixa o MP coletar o cartão na página dele.)

```
POST /preapproval        (token = getMpAccessToken(academyId))
{
  reason: "Mensalidade <Plano> — <Academia>",
  external_reference: "<academyId>:sub:<subscriptionId>",
  payer_email: "<email do aluno>",
  card_token_id: "<token do MpCardTokenizer>",   // single-use
  status: "authorized",                          // <-- auto-charge sem ação
  back_url: "<url>",
  notification_url: mpMktWebhookUrl() + "?acad=" + academyId,
  auto_recurring: {
    frequency: 1,
    frequency_type: "months",
    transaction_amount: <valor mensal em REAIS, derivado do plano>,
    currency_id: "BRL",
    billing_day: <plan.billingDay 1..28>,
    billing_day_proportional: false   // 1ª cobrança cheia (decisão de produto — ver §7)
  }
}
```

- **Dia de cobrança**: `auto_recurring.billing_day` (1–28). Sempre **clampar >28 para 28** para evitar fevereiro errático.
- **Fim após N meses (requisito central)**: o MP **não tem fim nativo** em `/preapproval` ad-hoc. Nós impomos o termo: a cada `subscription_authorized_payment` aprovado, incrementamos `chargesPaid`; quando `chargesPaid >= months`, fazemos `PUT /preapproval/{id} {status:'cancelled'}` e marcamos `status:'completed'`.
- **Por que ad-hoc e não `preapproval_plan`**: o plan template é por-conta e por-valor; precisamos de **valor custom por aluno** (`customValues`), então o `/preapproval` ad-hoc é o caminho. Termo imposto por nós (ver §7 open question).
- **Cancelar/pausar**: `PUT /preapproval/{id} {status:'cancelled'|'paused'}`.
- **Próxima cobrança**: `GET /preapproval/{id}.next_payment_date` → `nextBillingDate`.

### 2.2 Modelo de dados

**Plan** (`academies/{academyId}/plans/{planId}`) — novos campos em `lib/services/plan_service.dart` (constructor, `copyWith`, `fromFirestore`, `create`/`toMap`):
- `recurring: bool` (default `false`)
- `recurringMonths: int?` (termo N; `null`/`0` = sem fim)
- `billingDay: int` (1–28; clamp >28 → 28)
- `paymentMethodPolicy: PaymentMethodPolicy` (ver §3 — quando `recurring==true`, forçar `cardOnly`)
- `recurringValue: double` = `monthlyValue` (REAIS) para planos recorrentes

**Subscription** — nova coleção `academies/{academyId}/subscriptions/{subscriptionId}`:
```
{
  studentId, planId,
  mpPreapprovalId,           // preapproval.id — CHAVE de ligação
  status,                    // pending | authorized | paused | cancelled | completed
  recurringValue,            // REAIS
  billingDay, months,        // termo N
  chargesPaid: int,          // contagem de cobranças liquidadas
  nextBillingDate: Timestamp,
  cardLastFour, cardExpiryHint,
  needsReauth: bool,         // cartão recusado/expirado -> banner dunning
  createdAt, updatedAt, lastEvent, lastPaymentId
}
```
Fonte da verdade do termo e do dunning. **Não persistir o `card_token`** (single-use; o MP guarda o cartão atrás do preapproval). Guardar só `cardLastFour` + hint de expiração para re-tokenização.

**Financial** (`academies/{academyId}/financials/{id}`) — **reusar schema existente** (campo canônico é `amount` em REAIS, `status`, `dueDate`, `referenceMonth`, `studentId`, `planId`, `method`, `paymentDate`, `gatewayPaymentId`). Adicionar:
- `subscriptionId` (link)
- `recurringCycle: int` (1..N)
- `type: 'monthly_tuition'`, `paymentGateway: 'mercadopago'`

Cada cobrança mensal mint/settle **um** doc financial → a tela financeira do aluno mostra o histórico sem mudança.

**external_reference**: `"<academyId>:sub:<subscriptionId>"` — já roteado pelo parser existente (`parts.slice(2).join(':')`), com `type === 'sub'`.

### 2.3 Cloud Functions + Webhooks (em `server_functions.js`, secrets `MP_MKT_SECRETS`)

**NOVO callable `createMpSubscription`**
- Args: `{academyId, planId, studentId, studentName, cardToken, payerCpf, payerEmail}`.
- `assertCanPayFor(request, academyId, studentId)` (`:2797`).
- Carrega plano; **assert `plan.recurring===true` e `policy` permite cartão** (card-only server-side).
- **Deriva o valor mensal server-side** do plano (`customValues[studentId] ?? recurringValue`) — nunca confiar no client (mesma defesa de `createMpCardPayment`).
- `token = getMpAccessToken(academyId)`.
- Cria `Subscription` (`status:'pending'`) → `POST /preapproval` com `card_token_id + status:'authorized' + billing_day` → grava `mpPreapprovalId`, `cardLastFour`, `status` da resposta, `nextBillingDate`. Idempotência: `idempotencyKey = 'sub:'+subscriptionId`.
- Retorna `{subscriptionId, status, nextPaymentDate}`.
- Erro tipado se token consumido (`token-consumed` → o card sheet pede re-digitar cartão).

**ESTENDER `mercadoPagoMarketplaceWebhook`** (`:3259`) — trocar o gate da linha 3299 por um switch de `type`, **mantendo o branch `payment` intacto** e o HMAC fail-closed:
```js
// hoje (3299): if (type && type !== 'payment') { skip }
// passa a:
if (type === 'subscription_preapproval')        return mpSubSyncPreapproval(acad, dataId, res);
if (type === 'subscription_authorized_payment') return mpSubHandleAuthorizedPayment(acad, dataId, res);
if (type && type !== 'payment') { /* skip 200 */ }
// ... branch payment existente segue igual
```

**NOVO `mpSubHandleAuthorizedPayment(acad, authPayId)`**
- `GET /authorized_payments/{authPayId}` (token da academia) → `payment.id` → `GET /v1/payments/{paymentId}`.
- Parse `external_reference` `acad:sub:subId` via `mpMktParseRef`.
- Em `db.runTransaction`: carrega Subscription; se `payment.status==='approved'` **e** `gatewayPaymentId` ainda não registrado: **mint/settle** o financial do ciclo `chargesPaid+1` (`type:'monthly_tuition'`, `amount=recurringValue`, `status:'paid'`, `referenceMonth`, `subscriptionId`, `recurringCycle`, `paymentDate`, `method:'card'`), incrementa `chargesPaid`, atualiza `nextBillingDate`, `lastPaymentId`. Reusar o padrão de `mpMktSettle` (guard + tolerância + idempotente).
- **APÓS o commit**: se `chargesPaid >= months` → `PUT /preapproval/{id} {status:'cancelled'}` + `Subscription.status='completed'`.
- Se `payment.status` em `rejected`/`cancelled` → dunning (não liquida; mês fica em aberto/vencido).
- Idempotente em `gatewayPaymentId`.

**NOVO `mpSubSyncPreapproval(acad, preapprovalId)`**
- `GET /preapproval/{id}`; mapeia `authorized→authorized`, `paused→paused` (past_due/dunning), `cancelled→cancelled`; atualiza `Subscription.status` + `nextBillingDate`.
- Se virou `paused` por renovação falha → marca `needsReauth=true`, dispara notificação dunning (aluno + admin).

**NOVOS callables**
- `cancelMpSubscription {academyId, subscriptionId}`: admin da academia **ou** aluno dono → `PUT /preapproval status:'cancelled'` → `status='cancelled'`. Meses já pagos permanecem pagos. Sem reembolso/proração (política documentada).
- `pauseMpSubscription`: idem com `status:'paused'`.
- `updateSubscriptionCard {academyId, subscriptionId, cardToken}`: `PUT /preapproval/{id} {card_token_id:<novo>}` → limpa `needsReauth`. Recuperação de cartão expirado.

**Job agendado (`onSchedule` diário — recomendado, rede de segurança)**
- Para subscriptions `authorized`/`paused`: `GET /preapproval/{id}`, reconcilia `chargesPaid` vs financials liquidados, e **auto-cancela** as que atingiram o termo mas o MP não parou (defensivo, já que o fim depende de webhook). Resolve o gap "no scheduled generation".

### 2.4 Fluxo do app

- **Service** (`lib/services/mercado_pago_service.dart`): novo `createSubscription(...)` envolvendo o callable (paralelo a `createCardPayment`).
- **Editor de plano (admin)**: toggle "Plano recorrente (cobrança automática no cartão)" → ao ligar, força `paymentMethodPolicy=cardOnly`, mostra "Duração (meses)" (`recurringMonths`, ou "sem fim") e "Dia da cobrança" (`billingDay` 1–28). Persiste no save do Plan.
- **Checkout do aluno** (`lib/widgets/payment/payment_method_sheet.dart` + card sheet): quando o plano é recorrente, **esconde PIX**, mostra só cartão com copy "Assinatura — R$X/mês por N meses, cobrança automática todo dia D". O card sheet tokeniza via `MpCardTokenizer` e chama `createMpSubscription` (em vez de `createMpCardPayment`).
- **Tela financeira do aluno** (`lib/screens/portal/financial_screen.dart`): card "Minha assinatura" com status (Ativa/Pausada/Encerrada), `nextBillingDate`, cobranças restantes (`months - chargesPaid`), `cardLastFour`, botão "Cancelar assinatura". Meses auto-cobrados aparecem como itens pagos na lista existente (zero mudança de UX).
- **Admin** (`lib/screens/admin/student_detail_screen.dart`): status da assinatura + meses restantes; cancelar/pausar.
- **Dunning UI**: quando `paused`/`needsReauth`, banner vermelho "Pagamento recusado — atualize seu cartão" → re-tokeniza → `updateSubscriptionCard`.

---

## 3) Seleção de método de pagamento (cartão / PIX / ambos)

### 3.1 Enum único `PaymentMethodPolicy`
Em `lib/services/payment_service.dart`, ao lado do `PaymentMethod` existente, espelhando o padrão `BillingPeriod.fromString`:
```dart
enum PaymentMethodPolicy { both, pixOnly, cardOnly }
// fromString (default = both para ausente/desconhecido) + .value
```
**Aditivo e retrocompatível**: campo ausente = `both` (comportamento atual, zero regressão).

### 3.2 Modelo de dados
- **Plan**: `paymentMethodPolicy` (default `both`) através de constructor/`copyWith`/`fromFirestore`/`create`. v1 = **nível-plano** (sem override por aluno; ver §7).
- **Payment**: `paymentMethodPolicy` (default `both`), lido em `Payment.fromFirestore` do campo `paymentMethodPolicy`. É **snapshot** da política do plano no momento da geração — edição posterior do plano **não** muda cobranças já geradas.
- `PaymentService.create()` / `generateMonthlyTuitions()`: carimba cada cobrança com a política (avulsa pega do dialog). Sem migração: ausência = `both`.

### 3.3 Enforcement (defesa em profundidade)
A UI esconde, mas o **server-side é o enforcement real**:
- **`createMpPixPayment`** (`:2915`): após carregar `fin` (`:2931`), se `fin.paymentMethodPolicy==='cardOnly'` → `HttpsError('failed-precondition','Esta cobranca aceita apenas cartao.')` **antes** de chamar o MP.
- **`createMpCardPayment`** (`:3134`): junto ao gate `storeCreditCardEnabled` (`:3147`), se `recData.paymentMethodPolicy==='pixOnly'` → `failed-precondition`.
- **`createMpSubscription`**: rejeita se a política não permite cartão (preapproval é intrinsecamente card-only).
- **Preference SaaS hospedada** (`functions/index.js createMercadoPagoCheckout`): injeta `payment_methods.excluded_payment_types` — `cardOnly` exclui `[{id:'ticket'},{id:'bank_transfer'},{id:'atm'}]`; `pixOnly` exclui `[{id:'credit_card'},{id:'debit_card'}]`. **Validar os ids exatos no sandbox** (PIX aparece sob bank_transfer/account_money conforme tipo de conta). Esta é a **única** superfície que usa lista de exclusão; os charges marketplace já fixam um método (gate allow/deny, não exclusão).

> **Nota MP**: `mpMktSettle` é method-agnostic; **webhook e external_reference não mudam**.

### 3.4 UI
- **PaymentMethodSheet** ganha param `PaymentMethodPolicy policy` (default `both`). PIX renderiza só quando `policy != cardOnly && gateway.pixEnabled`; Cartão só quando `policy != pixOnly && _cardEnabled` (o `_cardEnabled` da linha 68 segue ANDado). Se sobra exatamente 1 método, opcionalmente auto-abrir (1-tap).
- **PaymentTarget** (`lib/widgets/payment/payment_target.dart`): adicionar `paymentMethodPolicy`; `financial_screen` passa `policy: payment.paymentMethodPolicy`.
- **Editor de plano**: ChoiceChips "Formas de pagamento aceitas": PIX e Cartão | Somente PIX | Somente Cartão. "Somente Cartão" em plano mensal → dica de auto-renovação; "Somente PIX" → assinatura recorrente indisponível.
- **Empty-state guard**: se a política deixa zero métodos pagáveis no gateway conectado (ex.: `cardOnly` mas gateway é Asaas/AbacatePay, `cardSupported=false`) → "Pague diretamente com a academia" (reusar degrade `PaymentGateway.none`). Recomendado: **bloquear admin de salvar `cardOnly` quando MP não é o gateway conectado** (ou avisar claramente).

---

## 4) Cobrança avulsa — confirmar/consertar ligação com MP

### Estado real (confirmado no código)
A avulsa **já está corretamente ligada** ao checkout marketplace. O gap "avulsa não conectada ao MP" da auditoria é **impreciso**: a confusão é que a auditoria olhou o webhook **SaaS** (`index.js mercadoPagoWebhook`), que de fato só trata assinatura da academia. Mas a avulsa não usa esse caminho — ela usa o **marketplace**:

- Avulsa é criada como doc `financials` (`type:'avulsa'`, `planId=null`) — `student_detail_screen.dart` `_showAvulsaPaymentDialog`.
- O aluno paga via `PaymentMethodSheet` → `createMpPixPayment`/`createMpCardPayment`, que carregam o doc por `financialId` (`:2928`/`:3131`), **independente de `type`**. external_reference = `academyId:fin:<financialId>`.
- Settle: `mercadoPagoMarketplaceWebhook` (`?acad=`) → `mpMktParseRef` → `mpMktSettle` branch `fin` → flip para `paid`. **Funciona para avulsa e mensalidade igualmente.**

### Ações concretas
1. **Verificar (sandbox)** que uma avulsa PIX e uma avulsa cartão liquidam ponta-a-ponta: doc `financials` `type:'avulsa'` vira `paid` pelo webhook marketplace. (Alta probabilidade de já funcionar — mesmo path da mensalidade.)
2. **Aplicar a política de método (§3)** na avulsa: o `_showAvulsaPaymentDialog` ganha o picker de 3 opções; `PaymentService.create()` carimba `paymentMethodPolicy` (default `both` se admin não escolher).
3. **Idempotência de retry de cartão** (gap real): se cartão de avulsa/mensalidade falha e o aluno tenta de novo, o doc fica `pending` — o `createMpCardPayment` já é idempotente por `idempotencyKey=externalReference:card`; garantir que o card sheet reabre o mesmo doc sem criar duplicata. Sem mudança de schema.
4. **Não** tocar `index.js mercadoPagoWebhook`/`createMercadoPagoCheckout` — são paywall SaaS (conta da plataforma).

---

## 5) Reaproveitamento da infra existente

| Infra | Local | Uso na recorrência |
|---|---|---|
| `getMpAccessToken(academyId)` | `server_functions.js:2554` | Token OAuth da academia p/ `/preapproval` |
| `mpRequest(...)` | `:2530` | `/preapproval`, `/authorized_payments`, `/v1/payments`, PUT cancel |
| `mercadoPagoMarketplaceWebhook` | `:3259` | **Estender** o switch de `type` (não criar 2º webhook); HMAC fail-closed reusado |
| `mpMktParseRef` | `:3252` | Já aceita `acad:sub:subId` (slice(2).join(':')) — só reconhecer `type==='sub'` |
| `mpMktSettle` (padrão) | `:3322` | Copiar read-guard-update + tolerância + idempotente p/ o financial mensal |
| `MpCardTokenizer.tokenize` | `lib/services/mp_card_tokenizer.dart` | `card_token_id` PCI-safe para `/preapproval` |
| `assertCanPayFor` / `validateAmount` | `:2797` | Auth + amount guards em `createMpSubscription` |
| Schema `financials` + `financial_screen` | — | Meses auto-cobrados renderizam sem mudança |
| `PaymentMethodSheet` / `PaymentTarget` | `lib/widgets/payment/` | Gate card-only + swap de callable + param `policy` |
| `BillingPeriod.fromString` / `PaymentMethod` enum | `plan_service.dart` / `payment_service.dart` | Espelhar para `PaymentMethodPolicy` |
| Gate `storeCreditCardEnabled` | `createMpCardPayment:3147` | Copiar verbatim p/ os gates de política |

**NÃO reusar**: `index.js createMercadoPagoCheckout` / `mercadoPagoWebhook` (paywall SaaS — conta e propósito errados).

---

## 6) Roadmap em fases

**Fase 0 — Validação de capacidade (bloqueante, 1–2 dias)** · Esforço S
- Confirmar no **sandbox MP** com token de academia conectada: `/preapproval` aceita `card_token_id` + `status:'authorized'` em conta OAuth; conta tem **Assinaturas habilitadas** (gap "chargeability check"); ids exatos de `excluded_payment_types` que escondem cartão mantendo PIX.
- **Dependência de tudo.** Se `/preapproval` não aceitar `card_token_id` em conta conectada → re-arquitetar (passo separado de add-card).

**Fase 1 — Seleção de método (cartão/PIX/ambos)** · Esforço M · independente
- Enum `PaymentMethodPolicy`, campos em Plan/Payment, gates server-side nos 3 callables, picker no editor de plano e no avulsa dialog, param `policy` no sheet/target, empty-state guard.
- Entrega valor sozinha e prepara o terreno (card-only) para a recorrência.

**Fase 2 — Conserto/validação avulsa** · Esforço S · depende de Fase 1 (picker)
- Teste sandbox ponta-a-ponta da avulsa PIX/cartão; aplicar política na avulsa; garantir retry idempotente.

**Fase 3 — Backend de assinatura recorrente** · Esforço L · depende de Fase 0 + Fase 1
- Modelo `Subscription`, campos recorrentes no Plan, `createMpSubscription`, extensão do webhook (`mpSubHandleAuthorizedPayment`, `mpSubSyncPreapproval`), `cancel`/`pause`/`updateCard`, settle do financial mensal com termo N.

**Fase 4 — App de assinatura** · Esforço M · depende de Fase 3
- `createSubscription` no service, toggle recorrente no editor de plano, fluxo card-only no checkout, card "Minha assinatura" + cancelar, view admin, banner de dunning.

**Fase 5 — Reconciliação agendada + dunning completo** · Esforço M · depende de Fase 3/4
- Job `onSchedule` diário (reconcilia termo/chargesPaid, auto-cancela órfãs), notificações dunning aluno+admin em `paused`.

Esforço total: **XL** (recorrência) + **M** (seleção) — alinhado à estimativa dos planos.

---

## 7) Riscos, edge cases e perguntas em aberto

### Riscos e mitigação
- **Falha de cobrança / retry**: MP auto-retenta internamente por dias; se falha de vez → preapproval vira `paused` → marcamos `Subscription.status='paused'`, **não** liquidamos o mês, notificamos (dunning), mês fica vencido. Em `updateSubscriptionCard` o MP retoma.
- **Expiração de cartão**: falha → paused → banner → aluno re-tokeniza → `PUT card_token_id` → retoma. Guardar só `cardLastFour`; **nunca** persistir token.
- **Cancelamento**: aluno/admin → `PUT status:'cancelled'` → sem cobranças futuras. Meses pagos permanecem pagos. **Sem reembolso/proração** (política documentada).
- **Fim após N (requisito central)**: contador `chargesPaid`; após o N-ésimo aprovado → `PUT cancelled` + `completed`. Job diário é a rede de segurança se o N-ésimo webhook se perder.
- **Webhook double-delivery/retry**: idempotente em `gatewayPaymentId` dentro de `db.runTransaction`; `chargesPaid` só incrementa quando o financial realmente vira `paid`. Webhook retorna **500 em erro** para o MP retentar.
- **Race fim-do-termo vs cobrança em voo**: cancelar via `PUT` **só após** o commit do settle; se o MP já cobrou N+1 antes do cancel, reembolso/crédito está **fora de escopo** — minimizar janela cancelando imediatamente ao atingir N.
- **billing_day em meses curtos**: clamp ≤28 (evita fevereiro).
- **Token single-use reusado**: erro tipado → card sheet pede re-digitar cartão.
- **Tampering de valor**: valor derivado server-side do plano/`customValue`; ignorar valor do client (espelha `createMpCardPayment`).
- **Conversão de aluno com mensalidades manuais prévias**: `chargesPaid` começa em 0; só conta auto-charges (sem double-count).
- **`cardOnly` + gateway sem cartão (Asaas/AbacatePay)**: fallback "pague direto com a academia"; bloquear save de `cardOnly` sem MP.
- **Política editada após gerar cobranças**: cobranças mantêm o snapshot; novas usam a nova.
- **Segurança inconsistente do paywall SaaS** (gap real): `index.js` webhook permite request sem secret (fail-open) enquanto o marketplace é fail-closed. Recomendação: **alinhar o paywall para fail-closed em produção** (fix paralelo, fora do escopo recorrência mas mesmo arquivo).

### Perguntas em aberto (decisões de produto/validação)
1. **Capacidade Assinaturas** na conta conectada da academia — alguns tipos de conta não criam `/preapproval`. Checar antes do subscribe (Fase 0).
2. **Política da 1ª cobrança**: `billing_day_proportional:true` (1º ciclo proporcional) vs cobrança cheia no dia 1 vs cheia no próximo `billing_day`. Recomendação inicial: **cheia no dia do subscribe** (`proportional:false`), depois mensal no `billing_day`. **Decisão de produto.**
3. **ad-hoc `/preapproval` + termo por app** (recomendado, suporta valor custom por aluno) vs `preapproval_plan` com `repetitions` nativo (template por valor). Confirmar ad-hoc.
4. **MP aceita `card_token_id` no create em conta OAuth?** Validar no sandbox antes de construir a UI (Fase 0).
5. **Reembolso/proração** em cancel antecipado e no race de overcharge no fim do termo — proposta atual: **sem reembolso**. Confirmar com produto.
6. **PIX recorrente** (Pix Automático) futuro — fora de escopo (card-only), mas o modelo `Subscription` não hardcoda cartão para extensão.
7. **Política nível-plano vs override por aluno** (`customPaymentPolicies` espelhando `customValues`) — recomendado **nível-plano em v1**.
8. **ids exatos de `excluded_payment_types`** na Preference SaaS (PIX sob bank_transfer vs account_money varia por conta) — validar sandbox.
9. **`cardOnly` deve auto-ligar recorrência?** ou recorrência é toggle explícito separado? Recomendação: **toggle explícito** (recorrência é decisão distinta de "só aceito cartão").
10. **Default da avulsa**: `both` ou herdar default por-academia. Recomendação: `both`.

---

### Arquivos-chave para implementação (caminhos absolutos)
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/server_functions.js` — `createMpSubscription`, extensão do webhook (`:3259`/`:3299`), `mpSubHandleAuthorizedPayment`, `mpSubSyncPreapproval`, gates de política em `createMpPixPayment` (`:2931`) e `createMpCardPayment` (`:3134`).
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/services/plan_service.dart` — campos recorrentes + `PaymentMethodPolicy` no Plan.
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/services/payment_service.dart` — enum `PaymentMethodPolicy` + campo em Payment + carimbo em `create`/`generateMonthlyTuitions`.
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/services/mercado_pago_service.dart` — `createSubscription`.
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/widgets/payment/payment_method_sheet.dart` — param `policy` + gate card-only (`_cardEnabled` `:68`).
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/widgets/payment/payment_target.dart` — campo `paymentMethodPolicy`.
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/portal/financial_screen.dart` — card "Minha assinatura" + dunning.
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/admin/student_detail_screen.dart` — view/cancel/pause admin + picker no `_showAvulsaPaymentDialog`.
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/services/mp_card_tokenizer.dart` — reuso para `card_token_id`.
- **NÃO tocar** `/Users/igorgewehr/WebstormProjects/graduabjj/functions/index.js` `createMercadoPagoCheckout`/`mercadoPagoWebhook` (paywall SaaS) — exceto, opcionalmente, alinhar o HMAC do webhook SaaS para fail-closed.
