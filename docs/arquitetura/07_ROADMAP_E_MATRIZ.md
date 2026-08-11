# 07 — Roadmap e matriz de arquivos

## 1. Princípio de execução

Não começar pelos 76 arquivos Dart acima de 600 em paralelo. Cada onda reduz
risco ou abre caminho para a seguinte. Um PR move uma responsabilidade coesa e
preserva comportamento; mudança de domínio vem depois.

## 2. Q0 — rede de segurança

- [ ] adicionar `functions` scripts `check`, `test`, `test:unit` e
  `test:integration`;
- [ ] criar workflow `quality.yml`;
- [ ] criar Rules tests no Emulator;
- [ ] congelar lista de exports Firebase + runtime/região;
- [ ] criar architecture check de linhas/imports;
- [ ] registrar baseline dos 265 issues do analyzer;
- [ ] criar logging/error/requestId compartilhados;
- [ ] publicar matriz de ownership de campos;
- [ ] runbook de deploy detecta deletes inesperados.

Saída: refatoração passa a ser verificável e regressão nova bloqueia CI.

## 3. Q1 — segurança, comércio e identidade

- [ ] provisionamento/rotação de segredo de catraca server-side;
- [ ] Rules de `devices` separam config legível de secret server-owned;
- [ ] `createStoreOrder` e transições de estoque/pedido no backend;
- [ ] bootstrap de academia idempotente;
- [ ] leave/unlink/primary academy por commands;
- [ ] decidir e implementar/remover TOTP/KYC endpoints órfãos;
- [ ] telemetrar caminhos antigos de link codes;
- [ ] testes de corrida/tenant/auditoria completos.

Saída: cliente não coordena segredo, estoque ou identidade multi-documento.

## 4. Q2 — presença, graduação e dados compostos

- [ ] commands server-side de presença unitária/bulk/remove/confirm;
- [ ] preservar contrato selfCheckin e fail-open de acesso físico;
- [ ] promoção/correção/undo transacionais;
- [ ] membership de turma + seed de modalidade atômicos;
- [ ] deletion job com dry-run;
- [ ] student import job com progresso/retry;
- [ ] competição oficial cria resultado + achievement server-side;
- [ ] reconcilers audit-only ativos.

Saída: invariantes acadêmicas não dependem da versão/relógio do Flutter.

## 5. Q3 — decomposição dos maiores bloqueadores

Quick wins concluídos em 2026-08-10:

- [x] QR fixo e imprimivel da academia com selecao server-side de turmas e
  presenca transacional (2026-08-11; ver `09_QR_FIXO_ACADEMIA.md`);

- [x] busca com debounce compartilhado em alunos, turmas, chamada e gestão de
  alunos da turma;
- [x] filtros puros e testáveis para lista de alunos e roster da chamada;
- [x] filtros da lista de alunos em passagem única, sem listas intermediárias;
- [x] resultado filtrado de turmas calculado uma vez por frame;
- [x] chamada deixa de ordenar/mutar a lista-fonte durante o `build`;
- [x] keys estáveis nos cards das três listagens.

Ordem recomendada:

1. `student_detail_screen.dart` por tabs;
2. `diario_screen.dart` por fases/controllers;
3. `settings_screen.dart` + `settings_service.dart` por domínio;
4. `classes_screen.dart` + `class_service.dart`;
5. `app.dart` em route modules;
6. `student_form_screen.dart`, `students_list_screen.dart` e
   `attendance_screen.dart`;
7. `reports_screen.dart`.

Para pagamentos/financeiro, seguir o roadmap específico antes de extrair tabs
financeiras isoladamente.

## 6. Q4 — portal, social e performance

- [ ] `profile_screen.dart` em sections/editors;
- [ ] `timeline_screen.dart` em jornada/timeline/rivais/self matches;
- [ ] `lutador_hub_screen.dart` em check-in/streak/missões/social;
- [ ] `public_profile_screen.dart` e `cena_screen.dart` por sections;
- [ ] `friend_providers.dart` por caso de uso;
- [ ] `CrossAcademyService` substituído por projeção segura;
- [ ] relatório mensal lê snapshot e export usa job;
- [ ] paginação nas listas principais;
- [ ] query budgets medidos.

## 7. Q5 — corte e limpeza

- [ ] impor versão mínima e fechar link code legacy;
- [ ] `storeOrders`, attendance oficial, progressions e commands ficam
  server-write-only conforme rollout;
- [ ] remover endpoints/adapters mortos após auditoria de flags;
- [ ] remover reexports/façades temporários;
- [ ] `index.js` é composition root pequeno;
- [ ] nenhum arquivo de produção novo acima de 600;
- [ ] backlog legado acima do teto cai a zero ou possui exceção justificada;
- [ ] analyzer fatal e CI obrigatório.

## 8. Matriz operacional — backend e segurança

| Arquivo atual | Ação | Destino/resultado |
|---|---|---|
| `functions/index.js` | decompor; preservar exports v2 | composition root + `identity`, `attendance`, `platform`, `trial` |
| `functions/server_functions.js` | seguir plano de pagamentos e extrair domínios restantes | shim pequeno ou removido com inventário |
| `functions/access_control/*` | preservar padrão; adaptar secret versions | módulo de referência |
| `functions/retention_functions.js` | mover para pasta sem mudar fórmula | `retention/` com domínio puro e handlers |
| `functions/push_functions.js` | separar schedule, audience e adapter | `notifications/` |
| `functions/package.json` | adicionar scripts/test tooling | CI Node reproduzível |
| `firestore.rules` | ownership por fase | commands server-only após corte |
| `firestore.indexes.json` | índices das queries/jobs | alinhado aos repositories |
| `.github/workflows/windows.yml` | manter build; remover papel de único CI | depende de quality gates |
| `.github/workflows/quality.yml` | criar | analyze, tests, Rules, architecture checks |

## 9. Matriz operacional — services/providers

| Arquivo | Prioridade | Ação principal |
|---|---:|---|
| `services/store_service.dart` | P0 | produto query + order commands backend |
| `providers/auth_provider.dart` | P0 | Auth client fino + identity commands |
| `services/global_user_service.dart` | P0 | queries + commands server-side; remover writes compostos |
| `services/totp_service.dart` | P0 | implementar backend real ou remover fluxo |
| `services/attendance_service.dart` | P1 | entidade/query/command separados |
| `services/belt_progression_service.dart` | P1 | domínio puro + progression commands |
| `services/student_service.dart` | P1 | queries/profile; hard delete vira job |
| `services/class_service.dart` | P1 | query/CRUD simples; membership command |
| `services/student_import_service.dart` | P1 | parser/preview + job client |
| `services/link_code_service.dart` | P1 | façade temporária; consumo server-only |
| `services/competition_service.dart` | P1/P2 | query + commands oficiais |
| `services/settings_service.dart` | P2 | mappers/controllers por section |
| `services/cross_academy_service.dart` | P2 | substituir fan-out por projeção |
| `providers/friend_providers.dart` | P2 | split social/feed/ranking e remover side effects |
| `services/retention_service.dart` | P2/legacy | confirmar call sites; backend já é autoridade |
| `services/payment_service.dart` | plano pagamentos | não duplicar roadmap aqui |
| `services/billing_reminder_service.dart` | plano pagamentos | não duplicar roadmap aqui |

## 10. Matriz operacional — screens

| Arquivo | Destino resumido |
|---|---|
| `admin/student_detail_screen.dart` | shell + 7 tabs + dialogs/controllers |
| `fighter/diario_screen.dart` | showcase/history/editor/reward/self-records |
| `admin/settings_screen.dart` | sections por domínio; KYC/payment externos |
| `admin/classes_screen.dart` | list/form/detail/manage students |
| `admin/reports_screen.dart` | controller + 4 report sections + export job |
| `admin/students_list_screen.dart` | query/filter/list/quick add/check-in action |
| `admin/student_form_screen.dart` | draft + form sections |
| `admin/attendance_screen.dart` | day controller + roster/checkins/actions |
| `portal/profile_screen.dart` | sections e editores por agregado |
| `portal/timeline_screen.dart` | journey/timeline/rivals/self matches |
| `fighter/lutador_hub_screen.dart` | states/check-in/streak/mission/social |
| `fighter/cena_screen.dart` | sections sociais |
| `portal/public_profile_screen.dart` | showcase/timeline/results/photos |
| `portal/competition_detail_screen.dart` | info/results/gallery/enrollment |
| `admin/retention_screen.dart` | dashboard/contact/card/history |
| `admin/competitions_screen.dart` | list/form/detail/enrollment |
| `admin/devices_screen.dart` | list/config/provision/rotate secret |
| `lib/app.dart` | route modules + guard puro |

## 11. Tamanho esperado após as ondas

- nenhuma screen/shell acima de 400 sem justificativa;
- nenhum widget/section acima de 250;
- nenhum service/controller/repository Flutter acima de 350;
- nenhum módulo backend acima de 500;
- nenhum arquivo de produção acima de 600;
- zero Firestore/HTTP importado por presentation;
- `index.js` e app router principal abaixo de 300 cada.

## 12. Regras de PR

- mover arquivo e mudar regra de negócio: separar;
- decompor Function e migrar runtime: separar;
- criar backend e fechar Rules: separar por rollout;
- remover adapter e mudar UI: confirmar zero uso/flags primeiro;
- máximo uma área crítica por PR;
- diff mecânico deve preservar nomes, copy e analytics;
- toda exceção de tamanho/ownership ganha justificativa e issue/fase.
