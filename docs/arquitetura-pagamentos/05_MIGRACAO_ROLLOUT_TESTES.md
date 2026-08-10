# 05 — Migração, rollout e testes

## 1. Princípios

- Nenhum big bang em dinheiro.
- Cada fase termina com critério objetivo e rollback.
- Mover código preserva comportamento; mudar comportamento vem depois.
- Produção começa com uma academia canário e um valor controlado.
- Backfill → backend → app/site → observação → Rules, nunca o inverso.
- Versão antiga do app é tratada explicitamente, não presumida inexistente.

## 2. Flags

No documento da academia ou configuração server-owned:

```yaml
paymentArchitectureVersion: 1 | 2
publicPaymentLinksEnabled: false
billingDispatchBackendEnabled: false
legacyPixMessageEnabled: true
publicCardCheckoutEnabled: false
```

Uma configuração global de kill switch deve conseguir:

- impedir novos checkouts públicos sem afetar webhook/settle;
- voltar mensagem para link Pix legado durante canário;
- suspender lote automático mantendo envio manual;
- nunca desligar processamento de pagamento já criado.

## 3. Fases

### Fase 0 — contenção e segurança

- [ ] Rotacionar a chave do notification server exposta no build.
- [ ] Disponibilizar a chave nova apenas para backend.
- [ ] Remover chaves de `build.sh` e `dart-define`.
- [ ] Aumentar temporariamente a expiração do Pix legado para ao menos três dias.
- [ ] Evitar pré-gerar Pix de cobranças futuras fora da janela operacional.
- [ ] Registrar “tentativa Pix expirada” sem confundir com dívida cancelada.

**Saída:** credencial antiga revogada e app ainda consegue enviar via backend.

**Rollback:** backend usa secret anterior somente durante janela controlada; não
recolocar segredo no cliente.

### Fase 1 — CI e caracterização

- [ ] `npm run check` executa syntax/lint básico.
- [ ] `npm test` executa `node --test`.
- [ ] `flutter analyze` e `flutter test` rodam em CI.
- [ ] Congelar inventário de exports de Functions.
- [ ] Testes de caracterização de Pix, cartão, webhook, settle, reversals,
  manual paid/cancel, cobrança unitária/lote e subscriptions.
- [ ] Firebase Emulator para Rules críticas.

**Saída:** toda extração posterior falha CI se quebrar contrato.

### Fase 2 — server-only actions e comunicação

- [ ] Implementar callables financeiras.
- [ ] Flutter novo delega create/update/pay/cancel/reactivate/delete.
- [ ] Implementar `sendBillingReminder` e job de lote.
- [ ] Templates/render final no backend.
- [ ] App deixa de chamar proxy diretamente.
- [ ] Telemetrar uso de versão antiga/direct writes.

**Saída:** app corrente funciona sem chave e sem mutação financeira direta.

**Rollback:** manter adapter Flutter anterior atrás de flag somente até a versão
mínima; nunca reativar segredo distribuído.

### Fase 3 — decomposição mecânica

- [ ] Extrair helpers puros.
- [ ] Extrair MP client/OAuth.
- [ ] Extrair webhook/settle/reversals.
- [ ] Extrair Pix/card/subscriptions.
- [ ] Extrair billing.
- [ ] `server_functions.js` vira shim.
- [ ] `index.js` vira composition root.
- [ ] Mesmo inventário de exports e mesmos triggers/runtimes.

**Saída:** testes e staging confirmam comportamento idêntico.

### Fase 4 — MyDojo Pay Link backend/site

- [ ] Criar schema/rules/indexes.
- [ ] Gerar token opaco e hash.
- [ ] Implementar resolve/start/status.
- [ ] Criar Checkout Pro e Pix dinâmico pós-clique.
- [ ] Criar site público responsivo e acessível.
- [ ] Configurar rewrites/proxy Netlify.
- [ ] Atualizar webhook para tentativas/métodos sem alterar settle.
- [ ] Smoke tests sandbox.

**Saída:** link de teste funciona sem login e paga um financial de teste.

### Fase 5 — canário

Academia inicial sugerida: Drakkar, por ter reproduzido o incidente e ter
conciliação observada.

- [ ] Ativar para professor/equipe informados.
- [ ] Enviar pequeno lote de cobranças reais abertas.
- [ ] Conferir abertura, checkout, pagamento e settle um a um.
- [ ] Testar reenvio do mesmo link.
- [ ] Testar expiração e regeneração.
- [ ] Testar pagamento manual enquanto tentativa está aberta.
- [ ] Observar no mínimo um ciclo operacional completo sem unmatched/mismatch.

**Rollback:** `publicPaymentLinksEnabled=false` volta envio ao modo anterior;
links já enviados mostram indisponível, mas webhooks continuam processando
tentativas existentes.

### Fase 6 — expansão gradual

- [ ] 5% das academias elegíveis.
- [ ] 25%.
- [ ] 50%.
- [ ] 100%.
- [ ] Cada degrau exige métricas saudáveis e zero perda de conciliação.
- [ ] Academias com `mpNeedsReauth` ficam fora até reconectar.
- [ ] `card_only` só entra quando fluxo público de cartão estiver homologado.

### Fase 7 — fechamento e limpeza

- [ ] Impor versão mínima compatível do app.
- [ ] Fechar Rules de `financials` e gateway fields.
- [ ] Desativar `legacyPixMessageEnabled`.
- [ ] Parar de persistir Pix bruto no `financial` novo.
- [ ] Auditar `asaasEnabled`/`abacatePayEnabled` em produção.
- [ ] Isolar/remover gateways sem uso confirmado.
- [ ] Remover adapters e reexports temporários.
- [ ] Atualizar `PAGAMENTOS_MP.md` para estado final.

## 4. Matriz de testes

### 4.1. Unitários de domínio Node

- token: geração, hash, formato e revogação;
- referência MP build/parse;
- reais/centavos/tolerância;
- política de método;
- status/método MP canônico;
- classificação de cobrança com timezone;
- template e placeholders legados/novos;
- projeção pública sem PII;
- reutilização de tentativa por versão/valor/expiração;
- máquina de estados do financial;
- rate-limit e idempotência.

### 4.2. Contrato com adapters

Com fake HTTP Mercado Pago:

- preference criada com token da academia correta;
- fee omitida;
- notification/back URLs corretas;
- timeout e erro sanitizado;
- dois POSTs com mesmo requestId não criam duas tentativas;
- crash depois do MP e antes do Firestore é reconciliado;
- valor alterado não reutiliza checkout stale.

### 4.3. Emulator/integration

- autenticação/permissão por tenant;
- ação financeira atômica;
- Rules de financial/link/attempt/job;
- job dedup por item;
- aluno/responsável e opt-out;
- webhook reentregue;
- pagamento aprovado durante cancel/manual paid;
- amount mismatch/unmatched;
- estorno/chargeback/partial refund;
- private lesson/estoque continuam exatamente-once.

### 4.4. Flutter

- DTOs e mappers;
- controllers loading/error/retry;
- tela não gera Pix ao carregar lote;
- job mostra progresso e falhas;
- ação usa callable e não write direto;
- `PaymentMethodPolicy` em mensalidade/loja;
- cartão pendente/3DS não vira recusa;
- rotas atuais continuam válidas.

### 4.5. Site público

- mobile 320px, acessibilidade e teclado;
- token inválido/revogado;
- open/paid/cancelled/unavailable;
- GET/preview não cria attempt;
- clique duplo cria uma attempt;
- retorno success/pending/failure;
- sem cache e sem token em referrer/log/analytics;
- link pago bloqueia nova tentativa;
- valor alterado exige refresh/version nova.

### 4.6. Sandbox Mercado Pago

- convidado sem conta MyDojo;
- Checkout Pro Pix e cartão;
- Pix expirado e regenerado;
- cartão aprovado, recusado, pending e 3DS;
- assinatura HMAC real/simulada;
- OAuth de duas academias garante isolamento;
- refund/chargeback;
- preferência expirada/atualizada.

### 4.7. Produção controlada

- R$ mínimo permitido entre contas de teste reais autorizadas;
- conferência no MP da academia;
- Firestore `paid` e recibo;
- notificação ao admin;
- dashboard/relatório sem duplicidade;
- estorno controlado e reconciliação.

## 5. Gates de CI

Workflow novo `quality.yml`:

```text
job flutter:
  flutter pub get
  flutter analyze
  flutter test

job functions:
  npm ci --prefix functions
  npm run check --prefix functions
  npm test --prefix functions

job rules/integration:
  emulators:exec ...
```

Introdução:

1. registrar baseline;
2. inicialmente bloquear apenas erros novos;
3. pagar warnings por módulo tocado;
4. tornar analyze/test completamente bloqueantes antes do split financeiro.

Testes financeiros e segurança nunca ficam `continue-on-error`.

## 6. Deploy

Ordem por release:

1. migração/backfill idempotente com `--dry-run`;
2. índices;
3. backend compatível;
4. site público ainda com flag off;
5. app;
6. ativação por flag;
7. Rules restritivas somente após versão mínima;
8. monitoramento e runbook de rollback.

Antes de deploy de Functions:

- confirmar secrets no Secret Manager;
- confirmar `functions/.env` local conforme convenção do repo, sem confiar nele
  como fonte de produção;
- comparar lista de funções a criar/alterar/excluir;
- nenhum delete não planejado;
- smoke test de webhook e refresh OAuth.

## 7. Backfill

Preferência: criação lazy do link quando a cobrança for enviada/aberta. Isso
evita escrever milhões de tokens sem necessidade.

Script opcional para cobranças abertas:

```text
functions/scripts/backfill_public_payment_links.js
  --academy=<id>|--all
  --status=pending,overdue
  --dry-run obrigatório por default
  --execute explícito
  --resume-from=<cursor>
```

Invariantes:

- idempotente;
- não cria tentativa MP;
- não muda status/valor;
- não inclui `test` ou cobrança não coletável;
- registra contagens, nunca tokens brutos.

## 8. Rollback financeiro

Rollback nunca:

- apaga pagamentos/tentativas;
- desliga webhook;
- restaura Rules incompatíveis às cegas;
- troca token OAuth;
- marca lote como não enviado sem conferir itens.

Rollback apenas impede novas criações/envios pelo caminho novo. Tudo que já pode
receber dinheiro continua conciliável até estado terminal.

