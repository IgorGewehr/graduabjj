# 00 — Diagnóstico e decisões

## 1. Estado atual confirmado no código

### 1.1. O que já está sólido

O fluxo marketplace do Mercado Pago já contém boa parte do trabalho difícil:

- Cada academia conecta sua conta por OAuth.
- Tokens ficam em `academies/{academyId}/private/mpAuth`, bloqueados pelas
  Firestore Rules.
- A renovação do token possui lock contra double-refresh.
- Mensalidade usa `external_reference = {academyId}:fin:{financialId}`.
- Pedido usa `external_reference = {academyId}:order:{orderId}`.
- O webhook valida HMAC e janela anti-replay, busca o pagamento com o token da
  academia e confere se a referência pertence ao tenant correto.
- O settle é transacional, valida valor e trata reentrega, duplicidade, estorno,
  chargeback, estorno parcial, estoque e aula particular.
- Assinaturas recorrentes já têm reconciliação e dunning.

Essas capacidades vivem principalmente em `functions/server_functions.js`, do
bloco que começa próximo da linha 3113 até os jobs de recorrência.

### 1.2. Como o incidente dos “cancelados” é produzido

`createMpPix` fixa a expiração em 24 horas. A tela de cobrança em lote percorre
as cobranças elegíveis, gera um Pix para cada uma antes de enviar e injeta
`pixCode` e `ticketUrl` na mensagem. Uma cobrança ainda aberta pode, portanto,
acumular tentativas Pix expiradas no Mercado Pago embora o `financial` continue
corretamente `pending` ou `overdue`.

O problema não é a conciliação; é o acoplamento entre **comunicar uma cobrança**
e **criar uma transação bancária temporária**.

## 2. Achados críticos adicionais

### P0.1 — segredo de notificação distribuído no cliente

`build.sh` contém a credencial do servidor de notificação e a injeta por
`dart-define`. Tudo que entra num aplicativo distribuído deve ser considerado
público: a chave pode ser extraída do binário e também já está no histórico Git.

**Ação:** rotacionar a chave, removê-la do build, armazenar a nova somente no
Secret Manager e fazer Flutter → callable autenticada → proxy de notificação.
Não registrar o valor antigo em issue, documento ou log.

### P0.2 — mutações financeiras sensíveis no Flutter

`PaymentService` escreve diretamente em `financials` para:

- criar cobrança;
- editar valor/vencimento;
- marcar como paga manualmente;
- cancelar;
- reativar;
- excluir.

Além da regra de negócio estar duplicada no cliente, operações compostas não são
atômicas: primeiro o Flutter altera o Firestore e depois tenta cancelar o Pix no
Mercado Pago em best-effort. Queda de rede entre os passos deixa estado
divergente e depende dos guards posteriores para ser detectada.

**Ação:** todas essas operações passam para Cloud Functions. Flutter envia
intenção; backend lê valor/estado autoritativos, valida permissão e executa a
transição completa.

### P0.3 — Rules não protegem todos os campos que o comentário promete

As regras de `financials` dizem que o cliente não pode tocar campos de auditoria
do gateway, mas a lista bloqueada cobre somente campos AbacatePay. Campos como
`gatewayPaymentId`, `paymentGateway`, `pixCode`, `pixTicketUrl`, `pixExpiresAt` e
outros continuam mutáveis por um cliente staff. Em `storeOrders`, a criação tem
mais proteção, mas o update também não fecha todo o conjunto de campos de
pagamento.

**Ação:** depois que as ações forem server-only e a versão mínima compatível for
imposta, `financials` passa a ser read-only para clientes; `storeOrders` mantém
somente transições operacionais explicitamente permitidas e campos de pagamento
ficam server-only.

### P0.4 — regras de cobrança duplicadas entre Dart e Node

Há duas implementações de:

- templates padrão;
- classificação D+0/D+1/D+3/D+7/D+15/D+30;
- substituição de placeholders;
- normalização de telefone;
- geração/injeção do link;
- envio unitário e em lote.

Isso permite que preview, envio manual e cron produzam conteúdos diferentes.

**Ação:** renderização final e envio passam a ser responsabilidade única do
backend. Flutter edita configurações e pede preview estruturado, mas não assina
nem despacha diretamente para o proxy.

### P1.1 — dois sistemas Mercado Pago diferentes no mesmo espaço mental

`functions/index.js` contém o pagamento da assinatura SaaS academia → MyDojo.
`functions/server_functions.js` contém recebíveis aluno → academia. Os webhooks
têm nomes muito parecidos, mas secrets, tokens, beneficiários e regras opostas.

**Ação:** separar internamente em `payments/platform/` e
`payments/academy/`. Manter os nomes externos atuais durante a compatibilidade.

### P1.2 — gateways mortos contaminam os contratos vivos

O DTO comum `PaymentLink`, `CardData` e `CardPaymentResult` mora dentro de
`abacate_pay_service.dart`, embora Mercado Pago seja o gateway vivo. O resolver
ainda contém Asaas e AbacatePay, e o Asaas aponta para rotas `/api` que não
existem neste repositório. Sem BaaS aprovado, Asaas não é estratégia de produção.

**Ação:** mover os DTOs para domínio neutro, remover AbacatePay/Asaas da seleção
viva após auditoria de flags em produção e manter adaptadores antigos isolados
por uma janela de remoção.

### P1.3 — testes financeiros frágeis

Parte dos testes Node verifica strings no arquivo-fonte, em vez de executar o
comportamento. `functions/package.json` nem sequer possui script `test`, e o CI
atual não roda testes Flutter ou Node; o analyzer é não bloqueante.

**Ação:** extrair domínio puro e adapters injetáveis, testar comportamento,
adicionar emulator tests e ligar os gates no CI antes dos movimentos grandes.

### P1.4 — página pública ainda não existe

`site/` contém apenas páginas legais estáticas. Não existe rota pública de
pagamento nem proxy same-origin para as Cloud Functions. `lib/app.dart` é o
roteador do aplicativo autenticado e não deve receber essa responsabilidade.

## 3. Decisões arquiteturais

### D1 — Mercado Pago continua como provedor principal

Motivo: OAuth já está implementado e é simples para o professor; KYC e saldo
continuam com o Mercado Pago; webhooks e conciliação já são maduros. Asaas fica
fora do caminho crítico enquanto exigir onboarding manual/subconta sem o BaaS
necessário ao produto.

### D2 — URL estável é do MyDojo, tentativa temporária é do provedor

O WhatsApp nunca mais recebe diretamente `ticket_url` como URL principal. Ele
recebe um token MyDojo que pode gerar outra tentativa enquanto a dívida estiver
aberta. Trocar o provedor no futuro não muda as mensagens já enviadas.

### D3 — GET nunca cria transação

Preview de WhatsApp, crawler e antivírus fazem GET automático. Resolver a página
é read-only. Somente `POST start checkout`, iniciado por botão humano, pode criar
preferência ou Pix.

### D4 — backend é dono do dinheiro e da comunicação

Flutter pode apresentar, coletar intenção e observar resultado. Valor,
transições de estado, criação/invalidação de link, renderização final da cobrança,
envio, conciliação e auditoria são server-side.

### D5 — decomposição não muda comportamento nem runtime no mesmo PR

Primeiro adicionar testes; depois mover código mecanicamente mantendo exports;
por fim evoluir o comportamento. Separar arquivo e migrar v1 → v2 são mudanças
diferentes e não entram juntas.

### D6 — migração aditiva e reversível

Link novo e Pix legado coexistem sob feature flag. Rules só fecham após backend,
app e versão mínima estarem prontos. Rollback troca a flag de envio, sem apagar
dados nem reconectar academias.

## 4. Prioridade real

1. Rotacionar a credencial de notificação exposta.
2. Criar CI e testes de caracterização do fluxo atual.
3. Levar ações financeiras e envio para o backend.
4. Criar MyDojo Pay Link e canário em uma academia.
5. Cortar o envio de Pix bruto.
6. Fechar Rules.
7. Completar decomposição e remover legado comprovadamente sem uso.

