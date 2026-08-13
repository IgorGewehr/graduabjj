# Runbook — pagamentos, flag pública e WhatsApp

## Estado publicado

Projeto Firebase: `arpjj-76350`
Hosting: `https://arpjj-76350.web.app`

Functions, Hosting, Rules e índices foram publicados em 2026-08-12. O runtime
é Node.js 22. O segredo `PUBLIC_PAY_TOKEN_SECRET` está no Secret Manager e não
deve ser lido, copiado ou versionado.

O fluxo de link público está protegido pela flag por academia
`academies/{academyId}.publicPaymentLinksEnabled`. Ela começa desligada.

## Rollout da flag de link público

### 1. Pré-requisitos por academia

- OAuth Mercado Pago conectado e sem `mpNeedsReauth`.
- Uma cobrança `pending` ou `overdue` de valor controlado.
- Administrador disponível para acompanhar o resultado.
- App atual publicado para quem enviará/reenviará lembretes.

### 2. Canário

1. No Console do Firestore, abrir `academies/{academyId}` da academia canário e
   definir **somente nela** `publicPaymentLinksEnabled: true`.
2. Criar ou reenviar uma cobrança de teste. Confirmar que nenhum pagamento ou
   PIX Mercado Pago aparece antes do aluno abrir o link e clicar em pagar.
3. Abrir o mesmo link em navegador anônimo, criar uma tentativa, concluir o
   pagamento e conferir `financial.status=paid`, `gatewayPaymentId` e a
   projeção correspondente em `paymentAttempts`.
4. Reabrir/reutilizar o link e deixar uma tentativa expirar. A dívida deve
   permanecer aberta e não pode haver uma tentativa por simples reenvio.
5. Esperar um ciclo do reconciliador (10 minutos) e checar logs das Functions
   `mercadoPagoMarketplaceWebhook` e
   `scheduledPublicPaymentAttemptReconcile`.

### 3. Rollout global

Não existe uma chave global implícita: a proteção é deliberadamente por
academia. Depois de canários sem incidente, habilitar o mesmo campo apenas nas
academias elegíveis, em lotes pequenos e reversíveis. Registre para cada lote:
academia, horário, responsável, primeira cobrança e resultado.

Não habilite academias sem OAuth ativo. Cobranças antigas recebem o novo link
somente quando um lembrete é enviado novamente; não faça backfill que crie
checkouts.

### 4. Rollback

Definir `publicPaymentLinksEnabled: false` na academia afetada bloqueia novos
checkouts públicos. Não apague `paymentAttempts`, não desligue webhook e não
reverta Rules às cegas: eles ainda precisam liquidar transações já iniciadas.

## Bloqueador para rollout global de WhatsApp

O código atual de WhatsApp chama um proxy legado (`notification.tensorroot.com`)
com `WHATSAPP_API_KEY`. Isso não atende à decisão de que todo backend
first-party deve rodar em Firebase Functions. Portanto, **não cadastrar essa
chave nem ligar WhatsApp globalmente**.

Antes do canário WhatsApp, implementar e publicar:

1. Emissor direto em Firebase Functions para `POST
   /{PHONE_NUMBER_ID}/messages` da Meta Cloud API, sem proxy próprio.
2. Secrets no Secret Manager: `META_WHATSAPP_ACCESS_TOKEN`,
   `META_WHATSAPP_PHONE_NUMBER_ID`, `META_WHATSAPP_APP_SECRET` e
   `META_WHATSAPP_WEBHOOK_VERIFY_TOKEN`. O token deve ser de usuário de sistema
   com a permissão de mensageria necessária; nunca entra no Flutter.
3. Binding explícito desses secrets em `sendBillingReminder`,
   `onFinancialCreated`, `scheduledDueSoonReminder` e
   `scheduledOverdueCheck`. Funções de primeira geração também precisam declarar
   os secrets no `runWith`; ter o segredo no projeto não o injeta
   automaticamente.
4. Endpoint público de webhook Meta com verificação de desafio e assinatura,
   para persistir `wamid`, entrega, falha e motivo de rejeição sem registrar
   telefone completo nem token.
5. Templates Meta aprovados, em português, com os mesmos nomes/variáveis de
   `functions/billing_whatsapp_templates.js`; testar cada botão/link e a
   substituição dos parâmetros.
6. Log/auditoria de entrega idempotente e limite de retry. O marcador
   `lastReminderStage` só pode avançar após aceite confirmado da Meta.
7. Opt-in explícito por academia (`billingReminders.whatsappEnabled=true`) e
   respeito a `students.whatsappOptOut=true`.

### Canário WhatsApp após a migração

1. Cadastrar secrets pelo Console/CLI sem expor o valor e publicar somente as
   Functions alteradas.
2. Usar uma academia e um número de teste com opt-in. Enviar uma cobrança de
   teste pelo comando autenticado, conferir template, link estável, `wamid` e
   status de entrega pelo webhook.
3. Repetir o envio e confirmar deduplicação; testar rejeição de template e
   número sem opt-in sem reenvio automático em massa.
4. Esperar ao menos um ciclo dos agendamentos antes de habilitar outra academia.
5. Só então ativar `whatsappEnabled` por academia, em lotes; rollback é definir
   esse campo como `false` na academia afetada.

## Verificação antes de publicar qualquer mudança

```powershell
npm.cmd run check --prefix functions
npm.cmd test --prefix functions
flutter test
firebase.cmd deploy --only functions,hosting,firestore:rules,firestore:indexes --dry-run --project arpjj-76350 --non-interactive
```
