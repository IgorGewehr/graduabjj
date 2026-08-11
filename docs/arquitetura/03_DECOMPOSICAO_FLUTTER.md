# 03 — Decomposição do Flutter

## 1. Regra de split

O objetivo não é apenas “tirar widgets do arquivo”. Um split está correto
quando separa:

- estado e orquestração em controller/application;
- leitura em query repository;
- mutação sensível em command backend;
- mapeamento Firebase em data;
- layout em screen/section/widget;
- regras puras em domain.

Um `part` file que continua acessando todo state privado, ou dez widgets que
recebem 30 parâmetros do shell, reduz linhas mas não reduz acoplamento.

## 2. Primeira onda: arquivos que bloqueiam várias áreas

### 2.1. `student_detail_screen.dart` — cerca de 6 mil linhas

Responsabilidades confirmadas: carregamento agregado, header, presença,
frequência, meta, elegibilidade, avaliação física/PDF, info/responsável/turmas,
financeiro, conquistas, comportamento, histórico, promoção, transferência,
link code e hard delete.

Estrutura-alvo:

```text
features/students/
  application/
    student_detail_controller.dart
    student_commands.dart
    student_detail_state.dart
  data/
    student_detail_repository.dart
    firebase_student_detail_repository.dart
  presentation/detail/
    student_detail_screen.dart             # header + tabs, <350
    student_header.dart
    student_overview_tab.dart
    student_attendance_tab.dart
    student_financial_tab.dart             # delega ao domínio payments
    student_achievements_tab.dart
    student_assessments_tab.dart
    student_behavior_tab.dart
    student_history_tab.dart
    sections/
    dialogs/
```

Ordem segura:

1. teste de rota, tabs, permissões e refresh;
2. extrair widgets sem alterar state;
3. extrair tab financeiro conforme plano de pagamentos;
4. extrair avaliação e PDF;
5. extrair presença/conquistas/histórico;
6. mover commands de promoção, link e exclusão para backend;
7. deixar shell apenas coordenar student id, header, tab e reload.

Não criar cópia de `_PaymentCard`, `_AssessmentCard` e `_InfoRow` em outra
tela sem comparar contrato; widgets realmente comuns vão para a feature, não
para `widgets/common` automaticamente.

### 2.2. `diario_screen.dart` — cerca de 4,1 mil linhas

Hoje o mesmo State coordena feed, ordenação, detalhe, editor, contador,
recompensa, vitrine, sparring, graduações/competições autodeclaradas e share.

```text
features/journal/
  domain/
    training_entry.dart
    training_draft.dart
    training_reward.dart
  application/
    journal_controller.dart
    training_editor_controller.dart
    showcase_controller.dart
  data/
    training_log_repository.dart
    self_records_repository.dart
  presentation/
    journal_screen.dart
    showcase/showcase_tab.dart
    history/history_tab.dart
    editor/training_count_step.dart
    editor/training_reward_step.dart
    editor/training_details_sheet.dart
    self_records/graduation_sheet.dart
    self_records/competition_sheet.dart
```

State do editor não pode compartilhar listas mutáveis com vitrine/histórico.
Salvar treino é um use case; celebração/share só ocorre depois de sucesso.

### 2.3. `settings_screen.dart` + `settings_service.dart`

São dois lados do mesmo acoplamento: tela de 3,3 mil linhas e service de mais
de mil com modelo, parse e quase 40 writes.

```text
features/settings/
  domain/academy_settings.dart
  data/academy_settings_mapper.dart
  data/settings_queries.dart
  application/basic_settings_controller.dart
  application/branding_settings_controller.dart
  application/graduation_settings_controller.dart
  application/access_settings_controller.dart
  presentation/settings_screen.dart
  presentation/sections/basic_section.dart
  presentation/sections/branding_section.dart
  presentation/sections/features_section.dart
  presentation/sections/graduation_section.dart
  presentation/sections/access_control_section.dart
```

Pagamentos/KYC vão para suas features. Saves são commands por domínio, nunca um
snapshot monolítico do documento `academies/{id}`. Campos server-owned não
fazem parte do DTO editável.

### 2.4. `classes_screen.dart` + `class_service.dart`

```text
features/classes/
  domain/class_schedule.dart
  domain/class_entity.dart
  application/classes_controller.dart
  application/class_form_controller.dart
  application/class_membership_controller.dart
  data/class_queries.dart
  presentation/classes_screen.dart
  presentation/class_filters.dart
  presentation/class_card.dart
  presentation/class_form_sheet.dart
  presentation/class_detail_sheet.dart
  presentation/manage_students_sheet.dart
```

`ClassSchedule` sai do service. Create/edit form compartilham schema/controller,
não dois dialogs duplicados. Membership chama command backend.

### 2.5. `lib/app.dart` — cerca de 1,5 mil linhas físicas

O arquivo contém refresh/redirect global e dezenas de rotas. Alvo:

```text
app/router/
  app_router.dart          # GoRouter + composição
  route_refresh.dart
  route_guards.dart
  route_transitions.dart
  auth_routes.dart
  portal_routes.dart
  admin_routes.dart
  kiosk_routes.dart
```

Guard recebe snapshot de auth/membership/subscription e retorna decisão pura.
Testes cobrem matriz de redirects sem bombear todas as telas.

## 3. Segunda onda: operação diária do admin

| Arquivo atual | Split recomendado |
|---|---|
| `students_list_screen.dart` (~2 mil) | controller de filtros/paginação, list, card, filter sheet, quick-add, staff check-in action |
| `student_form_screen.dart` (~1,8 mil) | draft/controller, personal/contact/academy/graduation sections, sport grade editor, class selector |
| `attendance_screen.dart` (~1,7 mil) | attendance day controller, class/date selectors, roster, pending check-ins, bulk actions, calendar sheet |
| `reports_screen.dart` (~2,3 mil) | report query/controller, attendance/financial/store/students sections, export job dialog |
| `competitions_screen.dart` (~1,7 mil) | list/controller, form, detail, enrollment sheet, cards |
| `retention_screen.dart` (~1,7 mil) | dashboard, risk card, contact actions, message sheet, contact history |
| `store_screen.dart` (~1,4 mil) | product list, product form, settings/publication, cards |
| `store_orders_admin_screen.dart` (~1 mil) | order detail, transition controller, confirmation sheets |
| `devices_screen.dart` (~1 mil) | device list, config form, one-time provisioning result, secret rotation dialog |

`student_form_screen` não deve salvar student e memberships por conta própria.
O controller envia draft a um use case e recebe resultado parcial estruturado;
após backend commands, não existe parcialidade silenciosa.

## 4. Terceira onda: portal e app do lutador

### `profile_screen.dart` — cerca de 2,3 mil linhas

Separar profile shell, hero, graduation, stats, personal data, address, health,
privacy, academies, account e change-password. Os três editors usam primitives
comuns de form, mas mantêm controllers/drafts próprios.

### `timeline_screen.dart` — cerca de 2,3 mil linhas

Separar journey projection, timeline list/item, rivals, self matches e sheets.
Modelos `_H2H*`, `_MatchDraft` e config de evento não pertencem ao widget file.

### `lutador_hub_screen.dart` — cerca de 2 mil linhas

Separar join/no-academy states, header, check-in, streak/freeze, mission,
graduation, stats e social activity. Check-in chama controller da feature
attendance; social chama feature social, sem repository concreto no card.

### `cena_screen.dart` e `public_profile_screen.dart`

Ambas possuem mais de 20 widgets/classes privadas no mesmo arquivo. Extrair por
section e compartilhar apenas os contratos estáveis de showcase/timeline. A
projeção pública deve continuar sem PII e server-materialized.

### `competition_detail_screen.dart`

Separar info, results, gallery, enrollment e result editor. Escritas oficiais
convergem em commands; upload/gallery permanecem adapter específico.

## 5. Services a desmontar

| Service atual | Problema | Destinos |
|---|---|---|
| `attendance_service.dart` | entidade + queries + stats + 10 mutações | `Attendance`, queries, commands e projections |
| `belt_progression_service.dart` | catálogo, elegibilidade, queries e promoção | graduation domain, queries e backend commands |
| `settings_service.dart` | modelo/parse + dezenas de writes | domain mapper + controllers/repositories por section |
| `store_service.dart` | enums/modelos/produtos/pedidos/estoque/pagamento | commerce domain + product queries + order commands |
| `student_service.dart` | CRUD, search, stats, linking e cascata | student queries, profile commands, deletion job |
| `competition_service.dart` | modelos + CRUD + enrollment + results | domain, queries, official commands |
| `global_user_service.dart` | perfil, mapping, belts e academy users | identity queries + server commands |
| `student_import_service.dart` | parse, mapping, validação e writes | CSV parser/draft + import job client |
| `friend_providers.dart` | composição social e ranking | social repositories/controllers por caso de uso |
| `billing_reminder_service.dart` | coberto pelo plano de pagamentos | feature billing |
| `payment_service.dart` | coberto pelo plano de pagamentos | feature payments |

## 6. Models a separar de Firestore

`models/student.dart` deve virar, incrementalmente:

```text
features/students/domain/
  student.dart
  student_status.dart
  student_profile.dart
  guardian.dart
  emergency_contact.dart
  address.dart
  student_goal.dart
features/retention/domain/student_retention.dart
features/students/data/student_firestore_mapper.dart
```

`models/academy.dart` separa subscription, profile, branding e mapper. Entidade
de domínio não recebe `DocumentSnapshot` nem produz `FieldValue`.

## 7. Providers

- um arquivo por agregado/caso de uso, não por “tudo social”;
- provider conecta dependências e cache, não implementa loops de domínio;
- mutation fica em controller/notifier;
- `.family` recebe ids estáveis e tenant explícito;
- invalidar providers específicos após command;
- evitar `FutureProvider` que emite side effect de materialização ao ser lido;
- selectors reduzem rebuild de telas grandes.

Exemplo social:

```text
features/social/application/
  friends_controller.dart
  feed_controller.dart
  partner_ranking_controller.dart
features/social/data/
  friends_repository.dart
  feed_repository.dart
features/social/presentation/
  friend_providers.dart
  feed_providers.dart
  ranking_providers.dart
```

## 8. Padrões que o split deve eliminar

- método `_showXSheet` com centenas de linhas dentro da screen;
- tela importando `cloud_firestore` ou `http`;
- criação de service concreto dentro de callback;
- model Dart que conhece `DocumentSnapshot` e UI ao mesmo tempo;
- `print` de erro sem correlação/redaction;
- duplicação de cards/fields privados sem contrato comum;
- `setState` contendo resultado de várias operações assíncronas de domínio;
- arquivo `services.dart` exportando todo o mundo;
- helper “common” com dezenas de flags para acomodar telas diferentes.

## 9. Checklist por arquivo

Antes:

- [ ] responsabilidades e call sites listados;
- [ ] state compartilhado desenhado;
- [ ] testes de caracterização criados;
- [ ] rota, copy, analytics e permissões congelados;
- [ ] command sensível já possui contrato backend ou façade.

Depois:

- [ ] shell abaixo de 400 linhas;
- [ ] nenhum destino acima de 600;
- [ ] apresentação sem Firestore/HTTP concreto;
- [ ] analyzer sem issues novas;
- [ ] testes relevantes verdes;
- [ ] `rg` confirma imports/call sites antigos esperados;
- [ ] façade temporária tem TODO com fase de remoção;
- [ ] comparação manual das jornadas críticas concluída.
