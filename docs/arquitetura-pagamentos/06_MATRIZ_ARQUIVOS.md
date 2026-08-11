# 06 — Matriz arquivo por arquivo

Esta matriz é a lista operacional de onde mexer. “Modificar” não significa que
tudo deve entrar no mesmo PR; seguir as fases de rollout.

## 1. Backend existente

| Arquivo atual | Ação | Destino/resultado |
|---|---|---|
| `functions/server_functions.js` | Decompor incrementalmente; preservar exports e runtime; substituir geração Pix do reminder por link público | vira shim/aggregator pequeno conforme `02_DECOMPOSICAO_BACKEND.md` |
| `functions/index.js` | Manter `initializeApp`; extrair paywall MP e domínios; tornar composition root | exports explícitos de `payments/platform`, `payments/academy`, `billing`, `public_pay` |
| `functions/package.json` | adicionar `check`, `test`, `test:unit`, `test:integration`; dev dependencies de teste/emulador | CI executável e reproduzível |
| `functions/package-lock.json` | atualizar mecanicamente após package.json | lock consistente |
| `functions/test/mp_pix_payer_validation.test.js` | substituir source-grep por teste do helper real e contracts | `test/unit/validation` + `test/contract/pix` |
| `functions/test/private_lesson_grant.test.js` | manter caracterização até existir integration test real | testar exatamente-once no emulator |
| `functions/test/gamification_*.test.js` | preservar; mover somente quando o runner novo estiver funcionando | não misturar com mudança financeira |
| `functions/scripts/` | adicionar backfill idempotente e auditoria de flags legadas | scripts com dry-run default |
| `functions/.env` | não documentar valores; deixar local/gitignored | secrets reais no Secret Manager |

## 2. Novos módulos backend

| Arquivo novo | Responsabilidade |
|---|---|
| `functions/shared/auth.js` | autenticação, tenant e permissões reutilizáveis |
| `functions/shared/validation.js` | ids/path segments, CPF e strings |
| `functions/shared/money.js` | reais/centavos, arredondamento e tolerância |
| `functions/shared/time.js` | datas BR/timezone/clock injetável |
| `functions/shared/structured_log.js` | logs correlacionados e redaction |
| `functions/notifications/client.js` | único consumidor do secret do proxy |
| `functions/notifications/recipients.js` | aluno/responsável, telefone e opt-out |
| `functions/billing/stages.js` | classificação canônica da régua |
| `functions/billing/templates.js` | defaults, placeholders e render final |
| `functions/billing/settings.js` | leitura e compatibilidade dos settings |
| `functions/billing/public_links.js` | get/create/revoke link estável |
| `functions/billing/dispatch_service.js` | envio unitário reutilizado por manual/cron/job |
| `functions/billing/dispatch_jobs.js` | lote, dedup, progresso e retry |
| `functions/billing/financial_actions.js` | create/edit/pay/cancel/reactivate/delete server-only |
| `functions/billing/tuition_generation.js` | geração mensal idempotente |
| `functions/billing/scheduled_reminders.js` | crons e due-soon/overdue |
| `functions/payments/academy/mp_client.js` | REST MP, timeout, erro seguro |
| `functions/payments/academy/oauth_repository.js` | token, refresh e lock |
| `functions/payments/academy/oauth_handlers.js` | connect/callback/disconnect |
| `functions/payments/academy/references.js` | build/parse external reference |
| `functions/payments/academy/authorization.js` | pagar por si/dependente/staff |
| `functions/payments/academy/pix.js` | Pix direto pós-clique e app autenticado |
| `functions/payments/academy/card.js` | cartão tokenizado e 3DS |
| `functions/payments/academy/checkout_preferences.js` | Checkout Pro |
| `functions/payments/academy/attempts_repository.js` | lifecycle de tentativa |
| `functions/payments/academy/webhook.js` | validação/roteamento do webhook |
| `functions/payments/academy/settlement.js` | settle único |
| `functions/payments/academy/reversals.js` | refund/chargeback/unmatched |
| `functions/payments/academy/subscriptions/*` | ciclo, settle, dunning, crons |
| `functions/payments/platform/*` | assinatura SaaS do MyDojo, isolada |
| `functions/payments/legacy/abacatepay.js` | quarentena temporária, sem novos call sites |
| `functions/public_pay/resolve_charge.js` | projeção pública read-only |
| `functions/public_pay/start_checkout.js` | validação/lock/criação do checkout |
| `functions/public_pay/rate_limit.js` | limites por link/IP |
| `functions/public_pay/response_projection.js` | allowlist de resposta sem PII |

## 3. Firebase, dados e segurança

| Arquivo | Mudança |
|---|---|
| `firestore.rules` | adicionar link/attempt/job server-only; fase intermediária bloqueia gateway fields; fase final torna financial write server-only |
| `firestore.indexes.json` | índices para attempts por target/status/createdAt, jobs por status/createdAt e consultas financeiras paginadas |
| `firebase.json` | adicionar emulator config/test setup se necessário; não adicionar Firebase Hosting se Netlify permanecer decisão |
| `.firebaserc` | sem mudança funcional prevista |
| `.gitignore` | confirmar secrets/env/artefatos; nunca ignorar documentação ou tests |

Campos de Rules a proteger explicitamente durante a fase intermediária:

```text
paymentGateway, gatewayPaymentId, externalPaymentId,
pixCode, pixQrCode, pixTicketUrl, pixExpiresAt, pixAmount,
cardPendingPaymentId, cardPendingExpiresAt,
paymentDate, paidAt, method,
financialVersion, publicPaymentLinkHash, lastCheckoutAttemptId,
refundEvent, refundedAmount, stockSettled
```

## 4. Site e deploy web

| Arquivo | Mudança |
|---|---|
| `site/netlify.toml` | rewrite `/p/*`; proxy `/api/public-pay/*`; CSP, no-store/no-referrer específicos |
| `site/index.html` | atualizar marca BJJEasy/MyDojo apenas em PR de branding; não misturar com checkout |
| `site/css/style.css` | manter legal; estilos do pagamento em arquivo próprio |
| `site/pay/index.html` (novo) | shell sem auth/segredo |
| `site/pay/pay.js` (novo) | resolve, start, redirect e status; sem lógica autoritativa |
| `site/pay/pay.css` (novo) | mobile-first/acessível |
| `site/pay/robots.txt` ou headers | `noindex,nofollow` para `/p/*` |

Não reutilizar `API_BASE_URL=https://bjjeasy.netlify.app/api` como prova de que
uma API existe: hoje não há implementação dessas rotas neste repo. Os proxies
precisam ser criados e testados explicitamente.

## 5. Flutter — domínio e serviços

| Arquivo atual | Ação |
|---|---|
| `lib/services/abacate_pay_service.dart` | retirar DTOs comuns; mover adapter para legacy; remover após auditoria |
| `lib/services/asaas_payment_service.dart` | remover do live resolver; quarentena/sunset sem BaaS |
| `lib/services/mercado_pago_service.dart` | virar adapter fino; atualizar comentário “PIX only”; usar DTO neutro e callables novas |
| `lib/services/payment/payment_gateway_resolver.dart` | refletir somente providers operacionais; remover precedência fictícia |
| `lib/services/payment_service.dart` | separar modelo/query/actions; substituir writes por callables; remover WhatsApp/Pix reminder |
| `lib/services/billing_reminder_service.dart` | separar models/repository; remover keys, HTTP, templates finais, Pix e bulk loop |
| `lib/services/mp_card_tokenizer.dart` | preservar tokenização PCI-safe; reutilizar no adapter de cartão |
| `lib/services/subscription_service.dart` | manter, mover para feature payments em fase posterior |
| `lib/services/store_service.dart` | manter criação de pedido compatível; política continua snapshot, servidor valida |
| `lib/services/services.dart` | reexports temporários e posterior remoção de legacy |
| `lib/providers/payment_providers.dart` | delegar a controllers/repositories novos |
| `lib/providers/billing_provider.dart` | expor dashboard/job/settings, sem regra duplicada |
| `lib/providers/subscription_provider.dart` | manter; migrar imports de domínio |
| `lib/providers/store_checkout_provider.dart` | usar política/métodos neutros |
| `lib/core/constants.dart` | adicionar URL pública somente se necessária; remover API routes mortas após auditoria; não guardar secrets |

## 6. Flutter — telas e widgets

| Arquivo atual | Ação |
|---|---|
| `lib/screens/admin/billing_reminders_screen.dart` | split por seções/dialogs; remover pré-geração Pix e `_runBulkSendCore`; observar job backend |
| `lib/screens/admin/financial_screen.dart` | split tabs/sheets/cards; ações por controller server-only |
| `lib/screens/admin/settings_screen.dart` | extrair payment settings/connect section |
| `lib/screens/admin/mercado_pago_connect_screen.dart` | manter UX OAuth; controller compartilhado e polling testável |
| `lib/screens/admin/subscriptions_screen.dart` | migrar DTOs/imports; sem dependência do link público inicial |
| `lib/screens/admin/student_detail_screen.dart` | extrair tab financeiro junto do split geral; nunca duplicar ações financeiras |
| `lib/screens/portal/financial_screen.dart` | split; usar repository/controller e mesmo backend |
| `lib/screens/portal/store_checkout_screen.dart` | DTO neutro e gateway real |
| `lib/screens/portal/store_orders_screen.dart` | DTO neutro e retry controlado |
| `lib/widgets/payment_sheets.dart` | dividir Pix/card/status/forms/controllers |
| `lib/widgets/payment/payment_method_sheet.dart` | mover para feature, manter façade temporária |
| `lib/widgets/payment/payment_target.dart` | mover para domínio neutro |
| `lib/widgets/payment/subscription_detail_sheet.dart` | separar em fase posterior, preservar contrato |
| `lib/widgets/onboarding/billing_activation_step.dart` | mudar copy/config para “link de pagamento” e backend dispatch |
| `lib/app.dart` | não adicionar rota pública; extrair route modules no roadmap geral |

## 7. Build e CI

| Arquivo | Mudança |
|---|---|
| `build.sh` | remover credenciais e defines de notificação; manter apenas configuração pública |
| `.github/workflows/windows.yml` | não usar como único CI; remover `continue-on-error` após baseline |
| `.github/workflows/quality.yml` (novo) | analyze, Flutter tests, Node tests e Rules/emulator |
| `pubspec.yaml` | somente dependências necessárias à nova organização; site público não adiciona pacote Flutter |
| `pubspec.lock` | atualização mecânica se pubspec mudar |

## 8. Testes Flutter atuais

| Arquivo | Evolução |
|---|---|
| `test/services/billing_inject_pix_test.dart` | migrar para link MyDojo e preview retornado pelo backend |
| `test/services/billing_template_test.dart` | lógica final migra para Node; Flutter testa apenas view model/preview |
| `test/services/payment_gateway_resolver_test.dart` | retirar capabilities de gateway não operacional |
| `test/services/payment_link_test.dart` | importar DTO neutro; testar hosted checkout e Pix attempt |
| `test/widgets/payment_method_sheet_test.dart` | preservar truth table e adicionar políticas/guest flow |
| `test/widgets/payment_target_test.dart` | migrar import de domínio |

Novos testes Flutter:

```text
test/features/payments/domain/
test/features/payments/application/
test/features/payments/presentation/
test/features/billing/application/
test/features/billing/presentation/
```

## 9. Documentação

| Arquivo | Mudança |
|---|---|
| `docs/PAGAMENTOS_MP.md` | manter como “estado atual” até corte; depois reescrever para arquitetura implementada |
| `docs/recorrencia-mp-contract.md` | atualizar imports/paths após extração, sem mudar contrato por acidente |
| `docs/ANTI_HIDRA_2026-07.md` | preservar como diagnóstico histórico; este plano é a execução atualizada |
| `docs/INDEX.md` | linkar esta pasta |
| `CLAUDE.md` | atualizar convenções de module boundaries quando a primeira fase for implementada |

## 10. God-files fora do núcleo de pagamentos

| Arquivo | Tamanho auditado | Split recomendado |
|---|---:|---|
| `lib/screens/admin/student_detail_screen.dart` | 6.274 | shell + tabs info/presença/financeiro/conquistas/avaliação/comportamento/histórico |
| `lib/screens/fighter/diario_screen.dart` | 4.307 | controller + vitrine/histórico/count/reward + sheets de registros |
| `lib/screens/admin/settings_screen.dart` | 3.541 | tabs academia/financeiro/features + editors por domínio |
| `lib/screens/admin/financial_screen.dart` | 3.452 | shell + tabs + sheets + widgets |
| `lib/screens/admin/billing_reminders_screen.dart` | 3.156 | shell + filtros/lista/envio/config/job |
| `lib/screens/admin/classes_screen.dart` | 2.608 | list/schedule + form + details + membership sheet |
| `lib/screens/portal/profile_screen.dart` | 2.450 | sections + edit sheets + account |
| `lib/screens/portal/timeline_screen.dart` | 2.433 | timeline + journey + self-record actions |
| `lib/screens/admin/reports_screen.dart` | 2.410 | query/controller + seções de relatório |
| `lib/widgets/payment_sheets.dart` | 2.166 | Pix/card/form/status/controllers |
| `functions/index.js` | 2.482 | composition root + módulos membership/checkin/platform/trial |
| `functions/server_functions.js` | 7.558 | módulos descritos neste plano |

O split de um god-file só começa quando seus comportamentos críticos possuem
testes. PR mecânico move uma seção por vez, preservando rota, estado e copy.

