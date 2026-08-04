# Pagamentos — Mercado Pago (integração end-to-end)

> Documentação da **jornada** completa da integração Mercado Pago (MP) usada para
> os recebíveis aluno → academia (mensalidade, loja, assinatura recorrente, aula
> particular). Os relatórios de auditoria (`docs/AUDITORIA_MERCADO_PAGO_2026-06.md`,
> `docs/AUDITORIA_MP_RECURSIVA_2026-06.md`) e a validação E2E
> (`docs/VALIDACAO_PAGAMENTOS_MP_E2E_2026-06.md`) cobrem achados/correções; este
> doc descreve **como o fluxo funciona hoje**.
>
> Todas as referências de código são `arquivo:linha` sobre o branch
> `firebase-production` (em produção, projeto Firebase `arpjj-76350`).

---

## 0. Mapa rápido

- **Backend MP de recebíveis:** `functions/server_functions.js` (a partir de
  `:3010` — o bloco "Mercado Pago — Marketplace / Split").
- **Cliente Flutter:** `lib/services/mercado_pago_service.dart` (gateway),
  `lib/services/payment_service.dart` (mensalidade/loja + mark-paid/cancel),
  `lib/services/subscription_service.dart` (recorrência),
  `lib/services/mp_card_tokenizer.dart` (tokenização PCI-safe do cartão).
- **Distinto** da integração MP do *paywall da plataforma* em `functions/index.js`
  (`createMercadoPagoCheckout` / `mercadoPagoWebhook` = academia → plataforma).
  **Não misturar secrets nem nomes de webhook** (`server_functions.js:3017-3019`).

---

## 1. Modelo de integração (marketplace / OAuth / 0% de taxa)

Cada academia conecta a **própria conta Mercado Pago** via OAuth. As cobranças
são criadas usando o `access_token` da conta do admin, e o dinheiro liquida
**diretamente na conta MP da academia** — sem carteira/float da plataforma e
**sem taxa de plataforma**.

- Header do modelo: `server_functions.js:3010-3027`.
  > "Each academy connects its OWN Mercado Pago account via OAuth. Charges are
  > created on the admin's access_token with application_fee=0, so money settles
  > DIRECTLY into the admin's MP account (0% platform fee, no wallet/float)."

### 1.1. `application_fee` é OMITIDO (= 0% de taxa)

O atributo `application_fee` **não é enviado** nos POSTs de pagamento. O comentário
é explícito: o MP **rejeita `0`** (`"must be positive"`), então o atributo deve ser
**omitido** — só se inclui quando há split positivo. Como ele é omitido, a academia
recebe 100% na própria conta:

- PIX: `server_functions.js:3818-3820`
  > "NÃO enviar application_fee: o MP rejeita `0` ... A academia recebe direto na
  > própria conta (0% de taxa), então o atributo deve ser OMITIDO."
- Cartão: `server_functions.js:4464-4465`.
- Assinatura (preapproval): não há `application_fee` no body do POST
  `/preapproval` (`server_functions.js:5158-5177`).

### 1.2. Como o token da academia é obtido/renovado

- `getMpAccessToken(academyId)` — `server_functions.js:3071-3210`. Lê os tokens de
  `academies/{academyId}/private/mpAuth`, renova quando faltam < 5 min para expirar
  e **persiste o `refresh_token` rotacionado** (o MP rotaciona o refresh a cada
  refresh — `:3066-3070`, `:3106-3108`).
- Concorrência: um **lock** (`academies/{academyId}/private/mpTokenLock`) serializa
  o refresh para evitar **double-refresh** (que invalidaria a conexão) —
  `:3106-3153`. Lock órfão (crash) expira após `LOCK_STALE_MS = 30s` (`:3076`,
  `:3118`).
- Falha irrecuperável de refresh → marca `academies/{academyId}.mpNeedsReauth = true`
  para a UI pedir reconexão (`:3170-3176`, `:3197-3199`). Um token válido limpa a
  flag (`:3091-3102`, `:3202-3205`).

### 1.3. Flags de estado no doc da academia

Escritas no callback OAuth (`server_functions.js:3372-3381`):
`mpConnected`, `mpUserId`, `mpPublicKey`, `mpLiveMode`, `mpConnectedAt`. O connect
também **desliga** os gateways legados (`abacatePayEnabled=false`,
`asaasEnabled=false`) para rotear cobranças novas ao MP.

> Em produção **só o Mercado Pago está ligado**. AbacatePay/Asaas existem no código
> mas estão desligados (ver `payment_gateways_in_use.md`). O cliente usa
> `MercadoPagoService.isEnabled()` (lê `mpConnected`) para escolher o gateway —
> `mercado_pago_service.dart:23-34`.

---

## 2. Unidade monetária — REAIS × CENTAVOS (regra canônica)

> **Esta é a fonte de mais bugs históricos na integração; trate-a como contrato.**

### 2.1. A regra canônica

- **Firestore (`financials.amount`) está em REAIS** (canônico). Ver
  `financial_amount_unit.md` e o uso server-side: o valor da cobrança é
  **derivado** de `fin.amount` (REAIS) e o `transaction_amount` enviado ao MP é
  sempre **REAIS** — `server_functions.js:4065` (`Number(fin.amount)` direto),
  `:4341` (`transactionAmount = expectedCentavos / 100`), `:3812`
  (`transaction_amount: Number(transactionAmount.toFixed(2))`).
- **O cliente envia CENTAVOS** nas callables (legado do contrato AbacatePay). A
  conversão acontece no cliente: `(amount * 100).round()` —
  `mercado_pago_service.dart:67`, `:100`, `:130`, `:236`.
- **O CF cross-checa em CENTAVOS** contra o valor armazenado e **rejeita** se
  divergir (nunca confia no valor do cliente):
  - Mensalidade: `expectedCentavos = Math.round(fin.amount * 100)` e compara com
    tolerância de 1 centavo — `server_functions.js:3987-3991`.
  - Loja: recomputa o total a partir de `storeProducts` (preço autoritativo) →
    `expectedCentavos` — `:4141-4146`.
  - Cartão: idem `:4319-4339`.
- **MP sempre fala REAIS** (`transaction_amount`, `auto_recurring.transaction_amount`).
  O settle compara o `payment.transaction_amount` (REAIS) com `fin.amount` (REAIS)
  — `server_functions.js:6136-6138`.

### 2.2. Resumo por camada

| Camada | Unidade | Onde |
| --- | --- | --- |
| `financials.amount` (Firestore) | **REAIS** | `payment_service.dart`, settle `:6136` |
| Loja: total autoritativo recomputado | **REAIS** | `orderAuthoritativeTotalReais` `:4141` |
| Argumento `amount` das callables | **CENTAVOS** | `mercado_pago_service.dart:67,100,130,236` |
| Cross-check no CF | **CENTAVOS** | `:3987`, `:4143`, `:4336` |
| `transaction_amount` ao MP | **REAIS** | `:3812`, `:4341`, `:4455`, `:5172` |
| `validateAmount(amount)` | **CENTAVOS** (inteiro) | `:2046-2060` |

`validateAmount` (`:2046`) exige `Number.isInteger` — reforça que o argumento
chega em **centavos** (inteiro), nunca em reais fracionários.

> Pegadinha resolvida (auditoria): só se **reusa** um PIX vivo se `pixAmount`
> (REAIS com que o QR foi cunhado, persistido em `:4086`) ainda bate com
> `fin.amount`. Se o admin editou o valor, o QR antigo é descartado/cancelado e
> um novo é cunhado — `:3997-4004`, `:4046-4054`.

---

## 3. Cloud Functions — papel de cada uma

Todas as callables MP rodam com `onCall({ secrets: MP_MKT_SECRETS })`; os webhooks
com `onRequest`. Local: `functions/server_functions.js`.

### 3.1. OAuth / conexão (admin)

| Função | Linha | Papel |
| --- | --- | --- |
| `startMercadoPagoConnect` | `:3225` | Admin inicia o connect. Gera `nonce` (16 bytes) + `state = academyId:nonce`, persiste em `mpAuth` (TTL 10 min) e devolve a URL de autorização do MP. |
| `mercadoPagoOAuthCallback` | `:3253` (`onRequest`, sem-auth) | Recebe o redirect do MP, valida `state`/nonce/anti-replay, troca `code` → tokens, grava `mpAuth` + flags da academia em **batch atômico**, e (na **troca de conta MP**) cancela preapprovals da conta antiga p/ não cobrar cartões órfãos. |
| `disconnectMercadoPago` | `:3420` | Admin desconecta. **Cancela todas as assinaturas ativas no MP antes** de apagar tokens (senão o MP segue cobrando cartões órfãos). Se algum cancel falhar com token vivo, **aborta**; se o token for irrecuperável, libera o disconnect marcando órfãos. |

### 3.2. Cobrança avulsa (aluno paga)

| Função | Linha | Papel |
| --- | --- | --- |
| `createMpPixPayment` | `:3952` | PIX de **mensalidade** (`financialId`). Cunha/reusa QR PIX. |
| `createMpOrderPixPayment` | `:4102` | PIX de **loja** (`orderId`), total recomputado de `storeProducts`. |
| `createMpCardPayment` | `:4258` | Cartão (tokenizado client-side) para **mensalidade OU loja**. Síncrono: liquida inline quando `approved`; webhook é backup p/ 3DS/análise. |
| `createMpPix` (helper) | `:3754` | Cria o pagamento PIX no MP. Self-heal de PIX órfão por `external_reference`; valida QR não-vazio. |
| `cancelMpPix` | `:5583` | Admin cancela um PIX pendente/in_process no MP (não estorna aprovado). |
| `mpCancelPixPayment` (helper) | `:5473` | Cancela qualquer pagamento `pending`/`in_process` (serve p/ cartão também). |
| `mpCancelLivePendingCard` (helper) | `:5507` | Cancela um cartão pendente vivo gravado no doc (anti double-charge). |

### 3.3. Assinatura recorrente (preapproval / card-only)

| Função | Linha | Papel |
| --- | --- | --- |
| `createMpSubscription` | `:5031` | Cria o `/preapproval` (mensal, card-only, `status:authorized` = auto-charge). Termo de N meses imposto pelo app (MP não tem fim nativo). |
| `cancelMpSubscription` | `:5297` | Cancela o preapproval no MP (não best-effort: propaga erro se falhar). |
| `pauseMpSubscription` | `:5339` | Pausa intencional do aluno (`pausedBy:'user'`, distinta de falha de cobrança). |
| `resumeMpSubscription` | `:5385` | Retoma uma assinatura `paused` (revalida o termo antes). |
| `updateSubscriptionCard` | `:5417` | Troca o cartão do preapproval (re-tokeniza client-side). |
| `mpSubSettleCycle` (helper) | `:4600` | Liquida **um** ciclo aprovado: cria 1 financial pago (id determinístico), incrementa `chargesPaid`, cancela o preapproval ao atingir `months`. |
| `mpSubHandleAuthorizedPayment` | `:4820` | Processa `subscription_authorized_payment` do webhook. |
| `mpSubSyncPreapproval` | `:4956` | Sincroniza estado do preapproval (`subscription_preapproval`). |
| `mpSubHealOrphanSubscription` | `:4913` | Adota/concilia preapprovals órfãos. |
| `mpSubHandleReversal` | `:6481` | Estorno/chargeback de um ciclo de assinatura já liquidado. |

### 3.4. Aula particular

| Função | Linha | Papel |
| --- | --- | --- |
| `markPrivateLessonGiven` | `:6228` | Concede a presença manualmente (cash/cortesia); opcional `markPaidCash` marca a cobrança paga (`method:'cash'`) e mata o PIX em aberto. Gated por `attendance:take`. |
| `grantPrivateLessonAttendance` (helper) | `:5844` | Concede **exatamente-uma-vez** a presença de uma aula particular paga (flag `attendanceGranted` + id de presença determinístico). Usado pelo webhook e pelo mark manual. |

### 3.5. Webhook + settle

| Função | Linha | Papel |
| --- | --- | --- |
| `mercadoPagoMarketplaceWebhook` | `:5618` (`onRequest`) | Endpoint do MP. Valida HMAC `x-signature` + frescor de `ts` (anti-replay), roteia por `type` (`payment` / `subscription_preapproval` / `subscription_authorized_payment`) e dispara o settle/estorno. |
| `mpMktSettle` (helper) | `:5900` | Vira financial/pedido para `paid` (transacional, idempotente) + estoque + notifica admin + concede presença de aula particular. |
| `mpMktHandleReversal` | `:6310` | Estorno/chargeback de cobrança avulsa (marca `refunded`/`chargeback`, restaura estoque). |
| `mpMktHandlePartialRefund` | `:6425` | Estorno **parcial** (mesmo paymentId ainda `approved`): registra `refundEvent` + alerta, sem desfazer o pagamento integral. |
| `mpMktRecordUnmatchedPayment` | `:5778` | Registra pagamento órfão/duplicado em `unmatchedPayments/{paymentId}` + alerta de reembolso. |

### 3.6. Crons de resiliência da recorrência

(`onSchedule` com `secrets: MP_MKT_SECRETS` — sem o bind, o branch de cobrança
falha; `:6538-6541`.)

| Cron | Linha | Papel |
| --- | --- | --- |
| `scheduledSubscriptionTermGuard` | `:6644` | Backstop por DATA: encerra/cancela assinatura ~1 ciclo além do termo. |
| `scheduledSubscriptionReconcile` | `:6814` | Concilia preapprovals e drena ciclos perdidos pelo webhook. |
| `scheduledSubscriptionDunning` | `:6922` | Política de dunning (`MAX_DUNNING_RETRIES=3`, backoff `[1,3,7]` dias — `:4532-4533`). |
| `scheduledCardExpiryWarning` | `:7047` | Avisa o aluno do cartão prestes a vencer. |

---

## 4. Secrets / config — e o RISCO de webhook fail-closed

### 4.1. Secrets e URLs

Bloco de doc: `server_functions.js:3021-3026`.

| Secret / env | Onde | Papel |
| --- | --- | --- |
| `MP_OAUTH_CLIENT_ID` | `MP_MKT_SECRETS` (`:3029`) | App ID do app marketplace (OAuth). |
| `MP_OAUTH_CLIENT_SECRET` | `MP_MKT_SECRETS` (`:3029`) | Client secret do app marketplace. |
| `MP_MKT_WEBHOOK_SECRET` | secret do webhook (`:5619`) | Assina/valida o `x-signature` do webhook. |
| `MP_OAUTH_REDIRECT` (env, opcional) | `mpOAuthRedirect()` `:3031` | Deve casar com o redirect registrado no MP e com a URL do `mercadoPagoOAuthCallback`. Default: `https://us-central1-arpjj-76350.cloudfunctions.net/mercadoPagoOAuthCallback`. |
| `MP_MKT_WEBHOOK_URL` (env, opcional) | `mpMktWebhookUrl()` `:3036` | URL de notificação enviada ao MP em cada cobrança (`?acad={academyId}`). Default: `https://us-central1-arpjj-76350.cloudfunctions.net/mercadoPagoMarketplaceWebhook`. |

- `MP_MKT_SECRETS = ['MP_OAUTH_CLIENT_ID', 'MP_OAUTH_CLIENT_SECRET']` — `:3029`.
  Todas as callables MP e as crons de recorrência declaram esses secrets; sem o
  bind, o refresh do token falha.
- O `notification_url` carrega `?acad={academyId}` em cada POST de pagamento
  (`:3817`, `:4463`, `:5168`) — é assim que o webhook sabe **qual academia** dona
  do token vai resolver o pagamento.

### 4.2. RISCO — webhook **fail-closed** sem o secret

O webhook **recusa processar** (HTTP 401) se `MP_MKT_WEBHOOK_SECRET` não estiver
configurado — `server_functions.js:5632-5636`:

```
const secret = process.env.MP_MKT_WEBHOOK_SECRET;
if (!secret) {
  console.error('[mpMktWebhook] MP_MKT_WEBHOOK_SECRET not configured — refusing');
  return res.status(401).json({ error: 'webhook secret not configured' });
}
```

**Consequência operacional:** se o secret estiver ausente/errado no deploy, o MP
recebe 401, e **nenhuma cobrança PIX/assinatura é liquidada** — financials/pedidos
ficam `pending` para sempre mesmo com o dinheiro já na conta MP da academia. (O
cartão síncrono ainda liquida inline em `:4486`, mas a confirmação 3DS/assíncrona
e todo o PIX/assinatura dependem do webhook.) É um trade-off **intencional**:
preferir não liquidar a liquidar com um webhook não autenticado (anti-spoof).
**Checklist de deploy:** garantir `MP_MKT_WEBHOOK_SECRET` setado e idêntico ao
configurado no painel de webhooks do app MP.

---

## 5. Jornada do aluno

> O cliente escolhe o gateway via `MercadoPagoService.isEnabled()` (lê `mpConnected`
> — `mercado_pago_service.dart:23-34`). Em produção é sempre MP.

### 5.1. PIX — mensalidade

`MercadoPagoService.createPixPayment` (`mercado_pago_service.dart:55`) →
`createMpPixPayment` (`server_functions.js:3952`).

1. Valida auth + ownership (`assertCanPayFor`, `:3959`), `validateAmount` (`:3960`),
   política de método (`card_only` rejeita PIX — `:3979-3982`), e o cross-check de
   valor em centavos (`:3987-3991`).
2. **Idempotência / reuso:** se há um PIX vivo (`gatewayPaymentId` + `pixCode` +
   `pixExpiresAt` no futuro) com `pixAmount` ainda casando, **devolve o MESMO QR**
   (`:4003-4012`) — o aluno e o responsável abrindo a mesma cobrança recebem o
   mesmo código.
3. Exige **CPF válido por checksum** (`validateCPF`, `:4022`) e e-mail real
   (resolve via auth se faltar — `:4026-4037`). Regulação do PIX.
4. Anti double-charge: cancela um **cartão pendente vivo** do mesmo doc
   (`mpCancelLivePendingCard`, `:4044`) e um **PIX com valor antigo** (`:4050-4054`).
5. **Lock de mint** transacional (`mpAcquirePixMint`, `:4058`): dois aparelhos
   geram **um** PIX só (o perdedor reusa o do vencedor).
6. Cria no MP (`createMpPix`, `:4063`), persiste `pixCode/pixQrCode/pixTicketUrl/
   gatewayPaymentId/pixExpiresAt/pixAmount` (`:4076-4090`) e devolve o QR.

**Estados (mensalidade):** `pending` (cobrança criada) → PIX cunhado (QR vivo, 24h)
→ aluno paga → webhook → `mpMktSettle` vira `paid` (`:6158`). Expira sem pagar → o
QR morre no MP; o doc segue `pending` e o aluno pode gerar outro.

### 5.2. PIX — loja

`createStoreOrderPayment` (`mercado_pago_service.dart:88`) →
`createMpOrderPixPayment` (`server_functions.js:4102`). Igual ao 5.1, mas o
**total é recomputado server-side de `storeProducts`** (`orderAuthoritativeTotalReais`,
`:4141`) e gravado de volta no pedido (`:4147-4154`) para o settle conferir. Política
da loja recomputada dos produtos (`orderEffectivePolicy`, `:4131`). External
reference: `{academyId}:order:{orderId}`. Settle decrementa estoque (`:6044-6083`).

**Estados (pedido):** `pending` → PIX vivo → pago → webhook `mpMktSettle` →
`paid` + `stockSettled` (`:5988-6013`).

### 5.3. Cartão — mensalidade ou loja

`createCardPayment` / `createStoreOrderCardPayment`
(`mercado_pago_service.dart:120,226`) → `createMpCardPayment`
(`server_functions.js:4258`). O cartão é **tokenizado no cliente** com a
`mpPublicKey` da academia (`MpCardTokenizer.tokenize`, `:263`) — o app **nunca**
envia PAN/CVV ao backend (PCI-safe).

1. Ownership + política (loja exige `storeCreditCardEnabled`, `:4302-4306`;
   mensalidade `pix_only` rejeita cartão, `:4307-4311`).
2. Anti double-charge **triplo**: cancela cartão pendente do mesmo doc
   (`:4349-4367`; se já aprovado → recusa `:4356-4358`) e PIX vivo do mesmo doc
   (`:4375-4413`).
3. Cobra no MP (`POST /v1/payments`, `:4447`) com idempotency key
   `{ref}:card:{cardToken}` (estável no retry do MESMO submit, nova a cada
   tokenização — `:4453`).
4. **Síncrono:** se `approved` → `mpMktSettle` inline (`:4486`). Se `in_process`/
   `pending` (3DS/análise) → grava `cardPendingPaymentId` + validade (~1h) para o
   guard simétrico do PIX e aguarda o **webhook** liquidar (`:4488-4504`).
5. Retorna `{ success, status, statusDetail, transactionId, threeDsUrl }` (`:4506`).

**Estados (cartão):** `approved` → `paid` inline · `in_process`/`pending` →
`cardPending*` no doc, liquida via webhook · `rejected` → `mapMpCardError` devolve
mensagem pt-BR acionável (`:4476-4482`).

### 5.4. Assinatura recorrente (preapproval, card-only)

`SubscriptionService` + `MercadoPagoService.createSubscription`
(`mercado_pago_service.dart:144`) → `createMpSubscription`
(`server_functions.js:5031`). Só para plano **mensal + `card_only`**
(`:5088-5092`).

1. Guarda de duplicidade: rejeita se já existe sub viva (pending/authorized/paused/
   error c/ risco de órfão) do aluno+plano (`:5047-5083`).
2. Deriva o valor mensal server-side (custom por aluno vence, `:5093-5099`), `months`,
   `billingDay` (clamp 1..28, `:5101-5103`), resolve e-mail (`:5105-5125`).
3. Cria o doc `subscriptions/{id}` `pending` (`:5132-5146`) e o `/preapproval` no MP
   com `status:'authorized'` (auto-charge sem página hospedada), `billing_day`,
   `billing_day_proportional:false` (1ª cobrança cheia no dia) e idempotency key
   determinística por alvo numa janela de 15 min (`:5148-5178`).
4. A cada cobrança aprovada o webhook chama `mpSubSettleCycle` (`:4600`): cria 1
   financial pago `sub_{subId}_{paymentId}` (id **determinístico** → nunca liquida
   2x, `:4604`), `referenceMonth` = mês civil da cobrança em America/Sao_Paulo
   (`:4607-4624`), incrementa `chargesPaid`; ao atingir `months`, cancela o
   preapproval.

**Estados (subscription):** `pending` → `authorized` (cobrando) → `completed`
(termo cumprido) | `cancelled` (encerrada manualmente) | `paused` (aluno pausou /
dunning) | `error` (falha na criação). `isActive = authorized|pending`;
`isCompleted` ≠ `cancelled` (`subscription_service.dart:104-108`). Sobre-cobrança
além do termo é gravada como `subscription_overcharge` + `needsRefund`
(`server_functions.js:4633-4665`).

### 5.5. Aula particular (1:1 → concede presença ao pagar)

Cobrança `financials` `type:'private_lesson'`. Quando é **paga** (MP ou cash),
concede **uma presença real** ao aluno (sem turma/plano). Ver `aula_particular.md`.

- Via MP: `mpMktSettle` detecta `type==='private_lesson'` e chama
  `grantPrivateLessonAttendance` após o commit do dinheiro (`:6206-6213`).
- Idempotência: flag `attendanceGranted` + id de presença determinístico que inclui
  o `financialId` (`:5854-5855`) — duas aulas no mesmo dia não colidem.
- Re-entrega tardia do webhook (dinheiro já liquidou, grant crashou) completa só o
  grant (`completeGrant`, `:6125-6131`, `:6181-6187`).

---

## 6. Jornada do professor / admin

### 6.1. Conectar / reconectar

`MercadoPagoService.startConnect` (`mercado_pago_service.dart:294`) →
`startMercadoPagoConnect` (`:3225`) → abre a URL do MP → `mercadoPagoOAuthCallback`
(`:3253`) grava tokens + flags. UI: `lib/screens/admin/mercado_pago_connect_screen.dart`
(considera saudável só `mpConnected && !mpNeedsReauth`, `:123-126`). O callback
faz deep-link `graduabjj://mp-oauth-callback?status=...` de volta ao app
(`:3415`).

### 6.2. Receber (financeiro)

Os recebíveis caem **direto na conta MP da academia** (0% taxa). O app não tem
carteira: o financeiro do app reflete os docs `financials`/`storeOrders` que o
webhook vira `paid`. `requestWithdrawal` (`:2778`) pertence ao fluxo de saque do
gateway legado — não há saque MP porque o dinheiro já está na conta do admin.

### 6.3. Marcar pago manualmente (cash/offline)

`PaymentService.markAsPaid` (`payment_service.dart:629`): tagueia
`paymentGateway:'manual'`, **pré-lê o `gatewayPaymentId`** do PIX antes de apagar
os campos pix*, e chama `cancelMpPix` (best-effort) para **matar o PIX em aberto** e
não deixar a família pagar de novo (`:657-684`). O `gatewayPaymentId` é apagado do
doc (`:663`) para que, se o cancel falhar e o PIX for pago depois, o webhook trate
como **duplicata alertável** (não credita de novo — `server_functions.js:6122-6123`).

Aula particular cash: `markPrivateLessonGiven(markPaidCash:true)`
(`payment_service.dart:601` → `server_functions.js:6228`) faz o mesmo
(cancela PIX, `method:'cash'`) e concede a presença.

### 6.4. Gerar mensalidades

`PaymentService.generateMonthlyTuitions` (`payment_service.dart:858`) e a cron
`scheduledMonthlyTuitionGeneration` (`server_functions.js:1413`) criam os
`financials` `pending` que depois o aluno paga via MP.

### 6.5. Cancelar cobrança

`PaymentService.cancel` (`payment_service.dart:694`): espelha `markAsPaid` — pré-lê
`gatewayPaymentId`, apaga campos pix* e chama `cancelMpPix` (`:721-730`) para o PIX
não ficar pagável.

### 6.6. Assinaturas (cancelar / pausar / retomar / trocar cartão)

`SubscriptionService` → `cancelMpSubscription` (`:5297`) / `pauseMpSubscription`
(`:5339`) / `resumeMpSubscription` (`:5385`) / `updateSubscriptionCard` (`:5417`).
**Cancelar não é best-effort**: se o MP recusar, propaga o erro — não marca
`cancelled` local enquanto o preapproval ainda cobra (`:5311-5333`).

### 6.7. Estornar / chargeback

Não há "estornar pelo app" — o admin estorna **no painel do MP**. O MP re-notifica o
mesmo paymentId com `refunded`/`charged_back`/`cancelled`
(`MP_REVERSAL_STATUSES`, `:6303`) e o webhook reage:
`mpMktHandleReversal` (avulso, `:6310`), `mpSubHandleReversal` (assinatura, `:6481`),
`mpMktHandlePartialRefund` (parcial, `:6425`). Marca o doc `refunded`/`chargeback` e
restaura estoque atômico.

### 6.8. Órfãos / conciliação

- `unmatchedPayments/{paymentId}` — pagamento aprovado sem doc no app
  (`missing_doc`) ou **segundo** pagamento de doc já pago (`duplicate`):
  `mpMktRecordUnmatchedPayment` (`:5778`), dedupe por `create()`, alerta de reembolso.
- `settleMismatch` no doc — valor pago ≠ esperado: NÃO marca `paid`, alerta admin
  (`:5965-5986` pedido, `:6138-6157` financial).
- Preapprovals órfãos (troca de conta / disconnect com token morto):
  `mpHasOrphanPreapprovals` + `mpOrphanPreapprovalIds` no doc da academia
  (`:3335-3346`), `mpSubHealOrphanSubscription` (`:4913`).

---

## 7. Idempotência e proteções

### 7.1. Anti double-charge (família paga 2x)

- **Reuso de PIX vivo** (mesmo QR para todos) — `:4003-4012` (mensalidade),
  `:4163-4172` (loja).
- **Lock de mint transacional** (`mpAcquirePixMint`, `:3882`): dois aparelhos →
  um PIX (`PIX_MINT_STALE_MS=60s`, `:3866`). Sem isso, idempotency keys distintas
  (epoch-millis, `:3764`) mintariam dois PIX pagáveis (`:3857-3865`).
- **Guards cruzados PIX↔cartão** no mesmo doc: cunhar PIX cancela cartão pendente
  (`:4044`); cobrar cartão cancela PIX vivo (`:4375-4413`) e cartão pendente
  (`:4349-4367`). Se não dá pra **garantir** o cancelamento → **recusa** a 2ª
  cobrança (`:4360-4366`, `:4388-4394`).
- **Settle atômico**: o flip para `paid` é transacional; settle inline (cartão) e
  webhook do MESMO pagamento não passam ambos pelo early-return (`:5912-5914`
  pedido, `:6097` financial). Segundo paymentId em doc já pago → `duplicatePayment`
  → conciliação (`:5920-5950`, `:6105-6123`).
- **mark-paid cash vs PIX**: cancela o PIX e apaga o `gatewayPaymentId` antes de
  marcar pago (`payment_service.dart:657-684`); se o PIX for pago depois, é
  duplicata alertável (`server_functions.js:6122`).
- **Assinatura**: guarda de duplicidade (`:5047-5083`) + idempotency key
  determinística por alvo/15 min no `/preapproval` (`:5155-5160`) → criação
  concorrente colapsa em um único preapproval. Settle por financial determinístico
  `sub_{subId}_{paymentId}` (`:4604`) nunca liquida 2x.

### 7.2. Anti-replay / autenticação do webhook

- HMAC `x-signature` (`sha256` sobre `id:...;request-id:...;ts:...;`),
  `timingSafeEqual` — `:5637-5653`.
- **Frescor do `ts`**: rejeita assinatura fora de ~5 min (normaliza s/ms),
  bloqueando replay de assinatura válida capturada — `:5654-5664`.
- **Fail-closed sem secret** — `:5632-5636` (ver §4.2).
- OAuth state: nonce 128 bits single-use, TTL 10 min, consumido em **qualquer**
  desfecho (sucesso/erro) — `:3236`, `:3262-3271`, `:3388-3391`.

### 7.3. Self-heal / recuperação de órfãos

- **PIX órfão por `external_reference`** (crash entre 200 do MP e o update): busca
  um PIX vivo com o mesmo ref e o adota em vez de cunhar 2º — `:3767-3804`.
- **Preapproval órfão**: busca por `external_reference` e adota no catch
  (`:5181-5203`); flag `possibleOrphan` quando a busca falha.
- **`refresh_token` rotacionado perdido**: persistência-primeiro com 1 retry, senão
  `mpNeedsReauth` — `:3177-3201`.
- **Re-entrega tardia do webhook**: `stockSettled:false` completa o estoque
  (`:5954-5957`, `:6079-6083`); `completeGrant` completa a presença de aula
  particular (`:6125-6131`, `:6181-6187`).

### 7.4. Validação de entrada / segurança de valor

- `validateAmount` (centavos inteiros, > 0, ≤ 1e8) — `:2046-2060`.
- `validateCPF` (checksum) no PIX e no cartão — `:4022`, `:4440`.
- Valor **sempre derivado** do servidor (REAIS canônico); o valor do cliente é só
  cross-check (1 centavo) e a divergência **rejeita** a cobrança — `:3987`, `:4143`,
  `:4336`. No settle, valor pago ≠ esperado → `settleMismatch`, sem marcar pago
  (`:5965`, `:6138`).
- Ownership (`assertCanPayFor` no pagamento, `requireAdminOf`/`staffCanWithPermission`
  no admin) — `:3959`, `:3213-3222`, `:6243`.

---

## 8. Referências cruzadas

- `docs/recorrencia-mp-contract.md` — contrato dos campos da assinatura/preapproval.
- `docs/financeiro-recorrencia.md` — arquitetura do módulo de recorrência.
- `docs/VALIDACAO_PAGAMENTOS_MP_E2E_2026-06.md` — validação E2E (roteiro de teste).
- `docs/AUDITORIA_MERCADO_PAGO_2026-06.md` / `docs/AUDITORIA_MP_RECURSIVA_2026-06.md`
  — achados e correções (cancel best-effort no MP + estado terminal local).
- Memória do projeto: `financial_amount_unit.md`, `aula_particular.md`,
  `payment_gateways_in_use.md`, `mp_audit_2026_06.md`.
