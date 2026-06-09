# Contrato de Implementação — Resiliência de Recorrência + Mercado Pago

> **PROPÓSITO:** este documento é a fonte única de verdade para a implementação paralela.
> Todos os agentes/raias DEVEM usar EXATAMENTE estes nomes de campos, coleções, funções e estados.
> Não invente nomes. Se algo não estiver aqui, siga o padrão do código existente e registre no fim.

Branch: `feat/recorrencia-resiliencia-mp` (cortada de `main`).
Modelo de dinheiro: marketplace OAuth — cada academia conecta sua conta MP; 0% plataforma.
Princípio: **a UI só decora; a fronteira real é o servidor** (Cloud Functions revalidam política/valor/estado).

---

## DECISÕES DE PRODUTO TRAVADAS (defaults)

1. **1ª cobrança da assinatura:** CHEIA no ato (`billing_day_proportional:false`) — mantém comportamento atual. Sem mudança.
2. **Fim dos N meses:** assinatura vira `status='completed'`, **SEM auto-renovação**. Nada é recriado automaticamente.
3. **Política de pagamento da Loja:** **por produto** (snapshot no pedido na criação). Default `both`.
4. **Dunning:** máximo **3 tentativas**, backoff **[1d, 3d, 7d]** a partir da falha; depois mantém `paused` definitivo + notifica admin e aluno.
5. **Expiração de cartão:** espelhar `cardLast4/cardExpMonth/cardExpYear` (não-PCI); avisar no mês da expiração **antes** do `billing_day`, uma única vez (`expiryNotifiedAt`).
6. **`card_only` NÃO-mensal (trimestral/anual):** mantém cobrança única de período cheio (NÃO é assinatura) + hint explícito na UI.

---

## CONTRATO DE DADOS — Firestore

### `academies/{academyId}/subscriptions/{subId}` — CAMPOS NOVOS

Campos existentes (NÃO renomear): `studentId, studentName, planId, status, recurringValue, billingDay, months, chargesPaid, needsReauth, mpPreapprovalId, nextBillingDate, lastPaymentId, lastEvent, createdAt, updatedAt`.

ADICIONAR:

| Campo | Tipo | Semântica |
|---|---|---|
| `termEndsAt` | Timestamp\|null | `createdAt` + `months` meses (se `months>0`); `null` = open-ended. Setado em `createMpSubscription`. |
| `failedAttempts` | int | default `0`. Incrementa a cada cobrança recusada. Zera ao voltar a `authorized`. |
| `lastFailureAt` | Timestamp\|null | última falha de cobrança. |
| `nextRetryAt` | Timestamp\|null | próximo retry de dunning (backoff). `null` quando não há retry pendente. |
| `cardLast4` | string\|null | espelho não-PCI do cartão (do retorno MP na criação/troca). |
| `cardExpMonth` | int\|null | 1–12. |
| `cardExpYear` | int\|null | 4 dígitos. |
| `expiryNotifiedAt` | Timestamp\|null | última vez que avisamos expiração — evita duplicar aviso. |
| `dunningExhaustedNotifiedAt` | Timestamp\|null | controle de idempotência da notificação de "assinatura suspensa" após esgotar os 3 retries (desacoplado de `nextRetryAt`). Zerado ao recuperar (settle/troca de cartão/volta a `authorized`). |

**Estados de `status` (canônico):** `pending | authorized | paused | cancelled | completed | error`.
- `completed` = concluída após N meses (distinto de `cancelled` = encerrada manualmente). NUNCA rebaixar `completed`.

**Legacy:** assinaturas antigas podem não ter `termEndsAt`. Os crons DEVEM tratar fallback: `termEndsAt ?? (createdAt + months meses)`. Campos numéricos novos ausentes ⇒ tratar como `0`/`null`.

### `academies/{academyId}/storeOrders/{orderId}` — CAMPO NOVO

| Campo | Tipo | Semântica |
|---|---|---|
| `paymentMethodPolicy` | string | `'both' \| 'pix_only' \| 'card_only'`. Snapshot do produto no momento da criação do pedido. Ausente ⇒ `both` (compat). |

### `academies/{academyId}/storeProducts/{productId}` (ou modelo de produto vigente) — CAMPO NOVO

| Campo | Tipo | Semântica |
|---|---|---|
| `paymentMethodPolicy` | string | `'both' \| 'pix_only' \| 'card_only'`. Default `both`. Editável no admin. |

> Confirmar o nome real da coleção/modelo de produto da loja no código; usar o vigente. O nome do CAMPO é fixo: `paymentMethodPolicy`.

### `academies/{academyId}/financials/{...}` — SEM mudança de schema
Liquidação de ciclo de assinatura continua gravando id determinístico `sub_{subId}_{paymentId}`.

---

## CONTRATO DE BACKEND — `functions/server_functions.js`

Reusar infra existente: `getMpAccessToken (:2554)`, `mpRequest (:2530)`, `notifyAdminCF`, `MP_MKT_SECRETS`, molde de cron `scheduledOverdueCheck (:870)` (try/catch por academia, NUNCA deixar uma academia abortar o cron).

### Novas Cloud Functions (nomes FIXOS)

1. **`scheduledSubscriptionTermGuard`** — `onSchedule` diário.
   Para cada academia, para cada `subscription` em `['authorized','paused']` com `months>0`:
   se `chargesPaid >= months` OU `now >= (termEndsAt ?? createdAt+months)` e ainda não `completed`:
   → `PUT /preapproval/{mpPreapprovalId} {status:'cancelled'}` + `subscription.status='completed'`.
   Idempotente (re-rodar não faz nada se já `completed`). Rede de segurança caso o webhook do último ciclo se perca.

2. **`scheduledSubscriptionReconcile`** — `onSchedule` (a cada 6h ou diário).
   Para `subscription` em `['authorized']` com `nextBillingDate` vencida há **>48h** sem `financials` novo do ciclo:
   → `GET /preapproval/{id}` (re-sync `status` + `nextBillingDate`) e `GET` dos `authorized_payments` recentes; para cada `approved` ainda não liquidado, chamar `mpSubSettleCycle` (idempotente por id determinístico). Recupera webhooks perdidos.

3. **`scheduledSubscriptionDunning`** — `onSchedule` diário.
   Para `subscription` em `['paused']` com `needsReauth=true`:
   - se `failedAttempts < 3` e `now >= nextRetryAt` (ou `nextRetryAt` nulo na 1ª): tentar reativar `PUT /preapproval/{id} {status:'authorized'}`; incrementar `failedAttempts`; setar `nextRetryAt = now + backoff[failedAttempts]` (backoff `[1d,3d,7d]`); `lastFailureAt`.
   - se `failedAttempts >= 3`: parar de tentar, manter `paused`, `nextRetryAt=null`, notificar admin (`payment_overdue`) e aluno (via `billing_reminder_service` no app / push). NÃO cancelar a assinatura.
   `MAX_DUNNING_RETRIES=3`, `DUNNING_BACKOFF_DAYS=[1,3,7]` como constantes no topo do bloco.

4. **`scheduledCardExpiryWarning`** — `onSchedule` diário.
   Para `subscription` em `['authorized']` com `cardExpMonth/Year` preenchidos:
   se o cartão expira no mês corrente E hoje é antes do `billing_day` E `expiryNotifiedAt` não é deste mês:
   → notificar aluno ("atualize seu cartão antes da próxima cobrança") + `expiryNotifiedAt=now`.

### Alterações em CFs existentes

- **`createMpSubscription (:3376)`**: ao criar, calcular e gravar `termEndsAt` (se `months>0`); após o `POST /preapproval`, extrair do retorno MP os dados não-PCI do cartão (`card.last_four_digits`, `card.expiration_month`, `card.expiration_year` — confirmar chaves reais no payload) e gravar `cardLast4/cardExpMonth/cardExpYear`. Inicializar `failedAttempts:0`.
- **`updateSubscriptionCard (:3547)`**: ao trocar cartão, re-gravar `cardLast4/cardExp*` do novo cartão e zerar `failedAttempts/nextRetryAt/expiryNotifiedAt`.
- **`mpSubSyncPreapproval (:3339)`**: ao entrar em `paused`, setar `lastFailureAt=now` e, se `nextRetryAt` nulo, agendar o 1º retry (o cron de dunning assume daí).
- **Enforcement de política na LOJA:** no branch de loja de `createMpCardPayment (:3122)` e na CF de PIX de loja, ler `order.paymentMethodPolicy` (ausente ⇒ `both`) e rejeitar o método proibido espelhando os erros existentes `:2942`/`:3161`. Cartão permitido **sse** `policy.allowsCard && academy.storeCreditCardEnabled`. Mensagens: `'Este pedido aceita apenas PIX.'` / `'Este pedido aceita apenas cartao.'`.

> **NÃO** re-checar política de mensalidade no webhook (correto — método já travado na criação).
> **Registrar** todas as novas CFs em `functions/index.js` se for o ponto de export (verificar como as CFs existentes são exportadas).

---

## CONTRATO DE FRONTEND — Flutter

### Enum canônico (reusar, NÃO recriar)
`PaymentMethodPolicy { both, pixOnly, cardOnly }` em `lib/services/payment_service.dart:109`
(`.value` → `both|pix_only|card_only`; `.label`; `allowsPix == !cardOnly`; `allowsCard == !pixOnly`; `fromString()` default `both`).

### Raia B — Recorrência
Arquivos: `lib/services/subscription_service.dart`, `lib/screens/admin/financial_screen.dart`, `lib/screens/portal/financial_screen.dart`, `lib/widgets/payment/payment_method_sheet.dart`, + novo widget de detalhe de assinatura.
- **Model (`subscription_service.dart`):** adicionar os campos novos (`termEndsAt, failedAttempts, lastFailureAt, nextRetryAt, cardLast4, cardExpMonth, cardExpYear, expiryNotifiedAt`) ao parse/model; garantir estado `completed`.
- **Tela de detalhe da assinatura (admin + portal):** progresso `chargesPaid/months`, próxima cobrança (`nextBillingDate`), valor, histórico (`financials` por `subscriptionId`), botões **Cancelar / Pausar / Trocar cartão** (callables já existem: `cancelMpSubscription`, `pauseMpSubscription`, `updateSubscriptionCard`).
- **Banner de dunning (portal):** quando `needsReauth==true` → "Sua cobrança falhou, atualize o cartão" → abre `CardPaymentSheet`/`PaymentMethodSheet` → `updateSubscriptionCard`.
- **Estado visual `completed`** distinto de `cancelled`.
- **Hint `card_only && !mensal`** no editor de plano (admin/financial_screen): "Cobrança única do período — NÃO é assinatura automática".

### Raia C — Loja
Arquivos: `lib/services/store_service.dart`, `lib/providers/store_checkout_provider.dart`, `lib/screens/admin/store_screen.dart`, `lib/screens/admin/store_orders_*.dart`, `lib/screens/portal/store_checkout_screen.dart`, `lib/screens/portal/store_screen.dart`.
- **Produto:** seletor de `paymentMethodPolicy` na config do produto (admin), reusando o componente de chips de política (espelhar `_PaymentMethodPolicySelector` de `financial_screen.dart:3275` — pode extrair/duplicar widget, mas NÃO editar `financial_screen.dart`).
- **`StoreService.createOrder`:** gravar `paymentMethodPolicy` como snapshot do produto no pedido.
- **Checkout (`store_checkout_provider`/`store_checkout_screen`):** gatear `StoreCheckoutMethod {pix, creditCard}` pela `order.paymentMethodPolicy` E pelo flag `storeCreditCardEnabled`. Estado bloqueado claro quando `card_only && !storeCreditCardEnabled` (sem método pagável).

---

## REGRAS DE OURO PARA OS AGENTES

- **Fique na sua raia.** Edite SOMENTE os arquivos da sua raia. Se precisar de algo em arquivo de outra raia, registre no retorno em vez de editar.
- **Aditivo, não destrutivo.** Não reescreva o caminho feliz existente. Apenas adicione.
- **Server é a fronteira.** Nunca confie em valor/política vindos do cliente.
- **Idempotência.** Crons devem ser seguros pra re-rodar. Use os ids determinísticos existentes.
- **Padrão de cron:** copie a estrutura de `scheduledOverdueCheck (:870)` — try/catch POR academia, uma falha não aborta o lote.
- **Verifique antes de retornar:** rode análise estática nos SEUS arquivos (`dart analyze <arquivos>` ou `node -c functions/server_functions.js`) e reporte o resultado.
- **Sem deploy, sem commit.** Apenas escreva o código na branch.
