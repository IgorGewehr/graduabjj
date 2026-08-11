# 02 — Decomposição do backend Firebase

## 1. Objetivo

Reduzir `functions/server_functions.js` (7.558 linhas) e `functions/index.js`
(2.482 linhas) a composition roots previsíveis, sem mudar o nome das funções
deployadas, o runtime v1/v2 ou o comportamento financeiro durante a extração.

O padrão a copiar já existe em `functions/access_control/`: módulo por domínio,
dependências explícitas, arquivos coesos, adapter separado de regra de negócio e
README local.

## 2. Estrutura-alvo

```text
functions/
  index.js                         # initializeApp + exports, sem regra de negócio
  server_functions.js              # shim temporário de compatibilidade

  shared/
    auth.js                         # requireAuth, tenant/role/permission
    firestore.js                    # db/admin helpers, sem initializeApp duplicado
    validation.js                   # ids, strings, CPF, dinheiro
    money.js                        # reais/centavos e comparação monetária
    time.js                         # timezone e datas BR
    http.js                         # timeout, JSON, erros seguros
    structured_log.js               # correlação + redaction

  notifications/
    client.js                       # único adapter para notification.tensorroot
    recipients.js                   # aluno/responsável/opt-out
    internal_notifications.js

  billing/
    index.js                         # exports do domínio
    stages.js                        # classificação de cobrança
    templates.js                     # defaults e renderização final
    settings.js
    public_links.js                  # token/hash/revogação
    dispatch_service.js              # unidade/lote/cron compartilham este core
    dispatch_jobs.js                 # fan-out e progresso de lotes grandes
    tuition_generation.js
    scheduled_reminders.js
    financial_actions.js             # create/update/pay/cancel/reactivate/delete

  payments/
    academy/
      index.js                       # exports públicos atuais
      config.js
      mp_client.js                   # mpRequest + erros + timeout
      oauth_repository.js            # token/refresh/lock
      oauth_handlers.js              # start/callback/disconnect
      authorization.js               # assertCanPayFor/requireAdminOf
      references.js                  # parse/build external_reference
      checkout_preferences.js        # Checkout Pro
      pix.js                          # direct Pix + locks
      card.js                         # core de cartão tokenizado
      settlement.js                  # mpMktSettle
      reversals.js
      webhook.js
      attempts_repository.js
      subscriptions/
        lifecycle.js
        settlement.js
        dunning.js
        scheduled_jobs.js
    platform/
      checkout.js                    # academia -> assinatura MyDojo
      webhook.js
      entitlement.js
    legacy/
      abacatepay.js                  # não exportado depois do sunset

  public_pay/
    index.js
    resolve_charge.js
    start_checkout.js
    rate_limit.js
    response_projection.js

  bookings/
    occurrences.js
    handlers.js

  test/
    unit/
    contract/
    integration/
```

Não é meta criar arquivos microscópicos. Faixa orientativa:

- domínio/adapters backend: 150–500 linhas;
- arquivos acima de 700 linhas exigem justificativa;
- cada módulo exporta poucas operações públicas e mantém helpers locais.

## 3. Regras de dependência

```text
handler HTTP/callable
  -> application service
    -> domínio puro
    -> repository/adapters (Firestore, MP, notificação)
```

- Domínio puro não importa Firebase nem faz `fetch`.
- Handler não contém regra monetária; apenas parse, autenticação e tradução de
  erro.
- Mercado Pago não conhece widgets, mensagens ou modelos Dart.
- Billing pode pedir um link ao módulo `public_pay`, mas não chama diretamente
  `/v1/payments`.
- `settlement` é o único caminho que transforma aprovação externa em dinheiro
  liquidado no Firestore.
- `index.js` inicializa Admin uma vez e compõe exports.
- Nenhum módulo importa `index.js`.

## 4. Preservação dos exports deployados

Durante a migração:

```js
// functions/index.js
initializeApp();

const academyPayments = require('./payments/academy');
const platformPayments = require('./payments/platform');
const billing = require('./billing');
const publicPay = require('./public_pay');

exports.createMpPixPayment = academyPayments.createMpPixPayment;
exports.mercadoPagoMarketplaceWebhook =
  academyPayments.mercadoPagoMarketplaceWebhook;

// Nome externo legado preservado; nome interno explícito.
exports.mercadoPagoWebhook = platformPayments.platformSubscriptionWebhook;

exports.resolvePublicCharge = publicPay.resolvePublicCharge;
exports.startPublicCheckout = publicPay.startPublicCheckout;
```

O nome da propriedade em `exports` é a identidade da função no Firebase.
Renomear só a função interna remove ambiguidade sem apagar/recriar a função
deployada.

`server_functions.js` vira um shim temporário:

```js
module.exports = {
  ...require('./billing'),
  ...require('./payments/academy'),
  ...require('./bookings'),
  ...require('./legacy/server_triggers'),
};
```

Ele só pode ser removido depois de:

1. inventário automatizado comparar exports antigos e novos;
2. `firebase deploy --only functions --dry-run` não indicar deletes inesperados;
3. staging/emulador carregar todos os módulos;
4. produção observar uma janela sem erro de módulo/cold start.

## 5. Ordem segura de extração

### E0 — rede de segurança

- Adicionar `npm test`, `npm run check` e inventário de exports.
- Criar testes de caracterização dos fluxos financeiros atuais.
- Congelar o contrato de `external_reference`, dinheiro e status.
- Não mover nenhuma função ainda.

### E1 — helpers puros

Extrair e testar:

- dinheiro e tolerância de centavo;
- CPF;
- referência MP;
- estágio de cobrança;
- renderização de template;
- normalização de telefone;
- política de métodos;
- mapeamento de status/método MP.

Esses helpers deixam de ser espelhados em teste por cópia de source.

### E2 — adapter Mercado Pago e OAuth

Mover `mpRequest`, configuração, token repository, refresh lock e handlers OAuth.
Manter secrets e nomes externos. Testar token válido, refresh, double-refresh,
rotação perdida e `mpNeedsReauth`.

### E3 — settle, reversals e webhook

Este é o núcleo mais sensível. Mover sem alterar branches, usando adapters
injetáveis e golden tests de transição. Só depois adicionar suporte ao Checkout
Pro e método canônico.

### E4 — Pix, cartão e assinaturas

Separar cada tipo, reutilizando authorization, dinheiro, attempts e settlement.
O core de cartão deve aceitar contexto autenticado do app ou token público, mas
ambos convergem no mesmo validador server-side.

### E5 — billing e comunicação

Mover templates, settings, cron, unidade/lote e geração de mensalidade. Remover
geração de Pix da função de comunicação e trocar por `getOrCreatePublicPayLink`.

### E6 — plataforma e outros domínios

Extrair paywall da plataforma de `index.js`, depois reservas, membership,
gamificação e triggers legados. O pagamento aluno → academia não deve aguardar
essa fase para entrar em produção.

## 6. Ações financeiras server-only

Novas callables autenticadas:

| Callable | Permissão | Responsabilidade |
|---|---|---|
| `createFinancialCharge` | `financial:create` | valida plano/aluno/valor, cria financial e link público |
| `updateFinancialTerms` | admin | altera valor/vencimento, `version++`, invalida tentativas |
| `markFinancialPaidManual` | admin/staff autorizado | transição atômica, cancela tentativas, registra ator |
| `cancelFinancialCharge` | admin | cancela dívida aberta e tentativas |
| `reactivateFinancialCharge` | admin | recalcula status pelo servidor |
| `deleteFinancialCharge` | admin | apenas sem dinheiro liquidado e sem auditoria necessária |
| `sendBillingReminder` | staff autorizado | resolve destinatário/template/link e envia |
| `createBillingDispatchJob` | staff autorizado | lote com dedup/progresso |

Campos de auditoria comuns:

```yaml
action: mark_paid_manual
actorUid: string
actorRole: string
actorDisplayName: string?
requestId: string
createdAt: timestamp
beforeStatus: string
afterStatus: string
```

O backend não aceita `academyId` sem validar que o caller pertence ao tenant e
possui a permissão da operação.

## 7. Jobs de envio em lote

O loop de centenas de alunos não deve ficar na tela Flutter nem em uma callable
de 120 segundos.

```text
academies/{academyId}/billingDispatchJobs/{jobId}
  status: queued|running|completed|partial|failed
  requestedBy
  filters
  totals

academies/{academyId}/billingDispatchJobs/{jobId}/items/{financialId}
  status: queued|sent|skipped|failed
  channel
  failureCode
```

Fluxo:

1. callable valida e cria job;
2. worker/Task Queue processa chunks limitados;
3. cada item relê estado ao vivo antes de enviar;
4. chave idempotente é `jobId:financialId:channel`;
5. UI observa progresso;
6. retry reprocessa somente `failed`, nunca `sent`.

No primeiro MVP, uma callable limitada pode continuar, desde que o contrato já
seja o de job e exista limite explícito. A evolução para Task Queue não muda a
UI.

## 8. Testabilidade

Factories recebem dependências:

```js
function createStartCheckout({
  linksRepository,
  financialRepository,
  attemptsRepository,
  mercadoPago,
  clock,
  randomBytes,
  logger,
}) { /* handler/core */ }
```

Isso permite testar corrida, expiração e falha parcial sem mockar globalmente o
Firebase Admin nem fazer busca textual no source.

Testes de source ficam apenas para inventário temporário e são removidos quando
o comportamento equivalente estiver coberto.

## 9. Coisas que não devem ser combinadas no mesmo PR

- mover arquivo + mudar regra de negócio;
- decompor + migrar v1 para v2;
- trocar nome externo + trocar secret;
- mudar schema + fechar Rules;
- criar Checkout Pro + reescrever settle;
- remover gateway legado + ativar link público.

Cada combinação dessas torna rollback e revisão financeira desnecessariamente
arriscados.

