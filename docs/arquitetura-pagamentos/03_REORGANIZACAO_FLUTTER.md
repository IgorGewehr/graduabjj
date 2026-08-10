# 03 — Emagrecimento e reorganização do Flutter

## 1. Fronteira correta

Flutter deve:

- renderizar dados;
- coletar intenção do usuário;
- validar formato para UX, sem substituir validação server-side;
- chamar casos de uso;
- observar estado/progresso;
- abrir URL externa e exibir feedback.

Flutter não deve:

- decidir uma transição monetária autoritativa;
- assinar chamada para proxy com segredo;
- montar a mensagem final enviada ao aluno;
- criar Pix em lote;
- derivar valor cobrável confiando no estado local;
- apagar campos de gateway;
- coordenar “atualiza Firestore e depois cancela no MP”.

## 2. Estrutura incremental por feature

Não mover todo o aplicativo. Novos pagamentos entram numa ilha feature-first;
arquivos antigos viram adapters finos e são retirados por etapas.

```text
lib/features/
  payments/
    domain/
      payment.dart
      payment_method.dart
      payment_method_policy.dart
      payment_result.dart
      payment_target.dart
    application/
      payment_actions.dart
      payment_checkout_controller.dart
      payment_providers.dart
    data/
      payment_repository.dart
      firebase_payment_repository.dart
      mercado_pago_gateway.dart
    presentation/
      payment_method_sheet.dart
      pix_payment_sheet.dart
      card_payment_sheet.dart
      payment_status_view.dart

  billing/
    domain/
      billing_stage.dart
      billing_settings.dart
      billing_dispatch.dart
    application/
      billing_controller.dart
      billing_settings_controller.dart
    data/
      billing_repository.dart
      firebase_billing_repository.dart
    presentation/admin/
      billing_screen.dart
      billing_filters.dart
      billing_list.dart
      billing_send_dialog.dart
      billing_bulk_dialog.dart
      billing_settings_dialog.dart
      billing_job_progress.dart
```

Compatibilidade:

- `lib/services/payment_service.dart` reexporta temporariamente os modelos novos;
- providers antigos delegam aos controllers novos;
- telas mantêm suas rotas atuais;
- cada remoção só ocorre depois de `rg` confirmar zero importadores.

## 3. DTOs neutros

`PaymentLink`, `CardData` e `CardPaymentResult` não podem continuar definidos em
`abacate_pay_service.dart`. Mover para `features/payments/domain`:

- `PixPaymentAttempt` para QR/copia-e-cola temporário;
- `HostedCheckout` para `redirectUrl`;
- `CardPaymentInput` para dados que serão tokenizados no cliente;
- `PaymentSubmissionResult` para approved/pending/rejected/3DS.

O nome do provedor só aparece no adapter. Uma tela não importa
`asaas_payment_service.dart` para obter um DTO.

## 4. Migração de PaymentService

### Hoje

`PaymentService` mistura modelo, consultas, relatórios, criação, mutação,
notificação e helper de WhatsApp em 1.293 linhas.

### Alvo

- `PaymentRepository`: streams/queries e parse.
- `PaymentActions`: callables server-only.
- `PaymentQueries`: paginação/consulta por aluno e mês.
- `Payment`/enums: domínio sem Firebase.
- `FinancialSummary`: projeção própria, sem varrer a coleção inteira na tela.
- WhatsApp removido do serviço de pagamento.

Mapeamento:

| Método atual | Destino |
|---|---|
| `create` | callable `createFinancialCharge` |
| `updateTerms` | callable `updateFinancialTerms` |
| `markAsPaid` | callable `markFinancialPaidManual` |
| `cancel` | callable `cancelFinancialCharge` |
| `reactivate` | callable `reactivateFinancialCharge` |
| `delete` | callable `deleteFinancialCharge` |
| `getWhatsAppReminderLink` | removido; backend envia ou retorna share URL |
| `generateReminderPix` | removido; backend retorna link MyDojo |
| queries | repository com índices/paginação |

## 5. Migração de BillingReminderService

### Permanece no Flutter

- modelos de apresentação de settings;
- leitura/edição do formulário;
- controle do job e feedback;
- formatação visual local;
- preview retornado pelo backend.

### Sai do Flutter

- URLs/chaves de notificação;
- `http.post` para WhatsApp/e-mail/bulk;
- templates canônicos;
- renderização final;
- normalização autoritativa do telefone;
- geração de Pix/link;
- dedup de estágio;
- classificação autoritativa usada pelos crons;
- loop de envio em lote.

O serviço cai de 1.737 linhas para adapters/repositories pequenos. A tela pede:

```dart
final job = await billingActions.createDispatchJob(
  financialIds: selectedIds,
  channels: const {BillingChannel.whatsapp},
  stage: selectedStage,
);
```

e observa `jobProvider(job.id)`.

## 6. Split das telas financeiras

### `financial_screen.dart` — 3.452 linhas

Alvo: shell com menos de 350 linhas.

```text
features/payments/presentation/admin/
  admin_financial_screen.dart
  financial_month_selector.dart
  plans_tab.dart
  payments_tab.dart
  plan_form_sheet.dart
  manage_plan_students_sheet.dart
  generate_tuitions_sheet.dart
  edit_payment_sheet.dart
  payment_card.dart
  payment_method_policy_selector.dart
```

Dialogs não acessam Firestore diretamente. Recebem estado e chamam controller.

### `billing_reminders_screen.dart` — 3.156 linhas

Alvo: shell com menos de 300 linhas.

```text
features/billing/presentation/admin/
  billing_screen.dart
  automation_card.dart
  charge_filters.dart
  stage_breakdown.dart
  charge_list.dart
  send_charge_dialog.dart
  bulk_send_dialog.dart
  settings_dialog.dart
  dispatch_job_dialog.dart
```

Eliminar `_runBulkSendCore` da UI. O backend recebe IDs/filtros e retorna job.

### `portal/financial_screen.dart` — 1.665 linhas

Separar:

- `student_financial_screen.dart`;
- `debt_alert_card.dart`;
- `payment_history.dart`;
- `student_checkout_controller.dart`;
- notices de responsável;
- status/gateway error.

O portal autenticado pode continuar oferecendo Pix/cartão direto, mas usa o
mesmo backend e settle do link público.

### `payment_sheets.dart` — 2.166 linhas

Separar:

- `pix_payment_sheet.dart`;
- `card_payment_sheet.dart`;
- `card_form.dart`;
- `payment_pending_view.dart`;
- `payment_success_view.dart`;
- `payment_error_mapper.dart`.

Timer de expiração e listener Firestore pertencem a controllers testáveis, não
a um widget de 2 mil linhas.

### `settings_screen.dart` — 3.541 linhas

Extrair a seção de Mercado Pago para
`features/payments/presentation/admin/payment_settings_section.dart`, usando o
controller de conexão. A tela de settings não deve conhecer callback polling,
tokens ou flags legadas.

## 7. Estado e controllers

- Provider nunca faz mutação no `build`.
- Controller expõe estados `idle/loading/success/error` ou `AsyncValue`.
- UI não reconstrói regras de capacidade do gateway em vários lugares.
- `PaymentGatewayResolver` passa a refletir apenas gateways realmente
  operacionais.
- Política de método pertence ao domínio e é usada por mensalidade, loja,
  portal e link público.
- Erros server-side possuem `code` estável; texto pt-BR fica na apresentação.

## 8. Página pública não entra em `app.dart`

`lib/app.dart` já possui 1.560 linhas e dezenas de rotas autenticadas. Adicionar
`/p/:token` nele causaria:

- download do bundle Flutter para um pagamento simples;
- inicialização Firebase/Auth desnecessária;
- maior tempo até o botão pagar;
- risco de guard redirecionar aluno sem conta;
- exposição a regressões do shell principal.

O site público em `site/pay/` é o produto correto. `app.dart` deve ser reduzido
em outro eixo para route modules, mas não é dependência do MyDojo Pay Link.

## 9. Reuso sem “framework interno” prematuro

Extrair quando houver contrato comum real:

- formatter de moeda/data;
- form fields compartilhados;
- status chip;
- payment method tile;
- async action button;
- confirmation dialog;
- error banner;
- policy selector.

Não unificar widgets só porque têm o mesmo nome privado. Primeiro comparar API,
acessibilidade e variações; então criar componente com poucos parâmetros. Evitar
um “widget universal” com dezenas de flags.

## 10. Critérios de conclusão do Flutter financeiro

- Nenhuma chave do proxy no app ou no build.
- Nenhum write direto em campos monetários/auditoria de `financials`.
- Nenhum Pix gerado em loop pela tela de cobrança.
- Nenhuma tela importa DTO de gateway legado.
- Screens principais abaixo dos limites acordados ou com justificativa.
- Controllers e domínio cobertos por teste.
- Rotas, deep links e UX existentes preservados.

