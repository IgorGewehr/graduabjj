# 09 — Glossário & convenções

> Quando um time grande passa meses numa migração, **drift de vocabulário** é a primeira fonte de bug que ninguém vê chegando. Alguém vai chamar o que aqui é `belt_progressions` de "graduations" porque o produto fala assim em reunião. Pior: alguém vai mandar PR renomeando algo "para padronizar" sem checar o resto.
>
> Este doc fixa o vocabulário PT-BR ↔ EN, define convenções de campos / endpoints / commits / erros, e serve de árbitro em PRs.

---

## 1. Glossário bilíngue (a fonte da verdade)

Coluna **Código** é o que aparece em Go, Dart, SQL, API. Coluna **PT-BR (produto)** é o que aparece para o usuário final em UI, e em conversa com PO/comercial. **NÃO** misture os dois mundos.

### 1.1 Domínio BJJ

| PT-BR (produto) | Código (canônico) | Aliases proibidos | Observação |
|---|---|---|---|
| Academia | `academy` | gym, school, escola | Tenant root |
| Aluno | `student` | member, atleta | Domínio scoped à `academy` |
| Faixa | `belt` | rank, color | Enum: `white \| blue \| purple \| brown \| black \| kids_grey \| kids_yellow \| kids_orange \| kids_green` |
| Grau (estrela) | `stripes` | degree, ponteira | Inteiro 0–4 |
| Promoção / graduação | `belt_progression` | promotion, graduation, evolução | Cada mudança é um row imutável no histórico |
| Conquista | `achievement` | medal, badge | Tipos: `graduation \| stripe \| competition \| milestone` |
| Marca / marco | `milestone` | conquista (este é genérico demais) | Sub-tipo de `achievement` |
| Avaliação (kids) | `assessment` | evaluation, prova | JSON com scores |
| Turma | `class` | aula, training session | Em Dart usar `bjjClass` (palavra reservada) |
| Aula (instância) | `attendance` | session, presença | Row em `attendance` representa **uma presença** num dia |
| Chamada | "marcar attendance" | check-in (já usado para outra coisa) | "Fazer a chamada" é a operação UI |
| Self check-in | `self_checkin` | QR check-in | Operação especial via QR token |
| Esporte | `sport` | modalidade | Default `bjj`; multi-sport via `sport_data` |
| Categoria | `category` | tipo, faixa-etária | Enum: `kids \| adult` |
| Plano | `plan` | mensalidade (que é o **valor**, não o plano) | Template de mensalidade |
| Mensalidade / fatura | `financial` (de tipo `monthly_tuition`) | invoice, bill, cobrança | Row de cobrança |
| Saldo | `wallet` | balance, caixa | 1 row por academia |
| Transação | `wallet_transaction` | entrada/saída, lançamento | Imutável |
| Pagamento | "marcar financial como `paid`" | payment | É um **estado** do financial, não um aggregate separado |
| Competição | `competition` | torneio, championship, evento | Domain aggregate |
| Inscrição | `competition_enrollment` | registration, matrícula | "Matrícula" significa outra coisa (entrada na academia) |
| Resultado | `competition_result` | placing, classification | |
| Pedido (loja) | `store_order` | order, compra | |
| Produto | `store_product` | item, mercadoria | |
| Notificação | `notification` | alert, aviso | |
| Tutor / responsável | `guardian` | parent, responsável legal | Role |
| Monitor | `monitor` | aluno-líder, aux instrutor | Role / permission |
| Instrutor | `instructor` | professor, mestre | Role |
| Admin | `admin` | dono, owner | Role |

### 1.2 Domínio técnico (multi-tenant + auth)

| Conceito | Código | Observação |
|---|---|---|
| Tenant | `academy` | Não use "tenant" no domínio; só em discussões internas de infra |
| Identidade global | `global_user` | 1 row por Firebase UID |
| Vínculo (user × academy) | `user_academy_mapping` / membership | Indistintamente |
| Papel | `role` | Enum: `admin \| instructor \| student \| monitor \| guardian` |
| Permissão | `permission` | String do catálogo (vide doc 04 §6) |
| ID do Firebase | `uid` (text, **não** UUID) | Sempre referenciado como `uid`, nunca `user_id` |
| ID interno | `id` (UUID v7) | Tudo que não é uid |
| ID Stripe / Asaas / etc | `external_id` | Conexão com sistemas externos |

### 1.3 Domínio operacional

| Conceito | Código | Observação |
|---|---|---|
| Erro retornado pelo backend | `problem` (RFC 7807) | Sempre `application/problem+json` |
| ID de rastreamento | `trace_id` | OpenTelemetry; aparece no `problem.trace_id` |
| Chave de idempotência | `Idempotency-Key` | Header. UUID gerado pelo cliente |
| Paginação | "cursor pagination" | NUNCA "page/offset" |
| Filtro de listagem | query param | Não use POST com body para listagem |
| Webhook | `webhook` | Sempre verificado por HMAC ou access-token header |

---

## 2. Convenções de naming

### 2.1 Schemas SQL / Postgres

- `snake_case` em **tabelas, colunas, índices, constraints, views, funções**.
- Tabelas no **plural**: `students`, `attendance` (irregular — mantém singular pois é incontável em PT-BR e EN), `belt_progressions`.
- IDs: `id UUID PRIMARY KEY` (gerado por `gen_random_uuid()` ou `uuidv7()`); FKs `<entity>_id`. Exceções: `uid TEXT` (Firebase UID), `external_id TEXT` (Asaas/AbacatePay).
- Timestamps: `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`, `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()` mantido por trigger `set_updated_at()`.
- Soft delete: `status` enum incluindo `removed`, **não** `deleted_at` (a história de quando foi removido vai no audit log).
- Enums: representados como `TEXT` + `CHECK constraint`. Postgres `CREATE TYPE` é caro em migrações.
- Índices nomeados: `<table>_<cols>_idx` (e.g., `students_academy_status_idx`).
- Unique indexes: `<table>_<cols>_uidx`.
- FK constraints: `<table>_<col>_fk` (e.g., `attendance_student_id_fk`).
- RLS policies: `<table>_tenant_isolation`.

### 2.2 OpenAPI / endpoints REST

- Resource paths em **plural** `kebab-case` em PT/EN neutro: `/v1/academies/{academyId}/store-products`.
- IDs no path em **camelCase**: `{academyId}`, `{studentId}` (vai como `path_parameters` no Dart sem ajuste).
- Sub-resources são paths aninhados: `/students/{studentId}/belt-progressions`.
- Verbos:
  - `GET /resources` → list (sempre paginado com cursor)
  - `GET /resources/{id}` → read
  - `POST /resources` → create
  - `PATCH /resources/{id}` → update parcial (NUNCA `PUT` para entidades — só para settings key/value)
  - `DELETE /resources/{id}` → soft-delete (status='removed')
- Filtros: query params em `snake_case` (`?status=active&due_from=2026-01-01`).
- Paginação: `?limit=50&cursor=<opaque>`; resposta `{ items, next_cursor, has_more }`.
- Operações que não mapeiam para CRUD viram sub-paths verb-like:
  - `POST /financials/generate-monthly` (não "generate-monthly-financials" como handler isolado)
  - `POST /attendance/self-checkin`
  - `POST /link-codes/{code}/redeem`

### 2.3 Go

- Package names: lowercase, sem underscores. `internal/identity`, `internal/student`, não `internal/student_management`.
- File names: `snake_case`. `belt_progression.go`, `firebase_authenticator.go`.
- Types: `PascalCase`. `Student`, `BeltProgression`, `IdempotencyKey`.
- Functions: `PascalCase` se exportadas, `camelCase` se privadas.
- Interfaces: nome substantivo (não terminar em `-er`). `StudentRepo`, **não** `StudentRepository` (verbose) nem `StudentReader` se o contexto deixa claro.
- Errors: `Err<Description>`. `ErrStudentNotFound`, `ErrBeltSequenceInvalid`. Sentinel exportado.
- Context é sempre o primeiro parâmetro. Convention: `(ctx context.Context, ...)`.

### 2.4 Dart

- Files: `snake_case.dart`.
- Classes: `PascalCase`.
- Constants: `lowerCamelCase` (estilo Dart, não `SCREAMING_SNAKE`).
- Privates: prefixo `_`.
- Provider names: terminam em `Provider`. `studentsProvider`, **não** `studentList`.
- Repositórios: `<Entity>Repo`, **não** `<Entity>Repository` (curto, dedo cansa).
- Models: campo em `camelCase` no Dart; `fromJson` converte de `snake_case` da API.
- Exceptions: `<Domain>Exception`. `TatamiException`, `ValidationException` (se rolar).

### 2.5 SQL queries (sqlc inputs)

- Cada query tagueada `-- name: <Name> :one|:many|:exec`.
- Nome em `PascalCase`: `-- name: GetStudent :one`.
- Comentários acima descrevendo o caso de uso quando não óbvio.

---

## 3. Convenções de datas, horas, fusos

- **Armazenamento**: sempre `TIMESTAMPTZ` (timestamp with time zone) em UTC.
- **API wire**: ISO 8601 com offset `Z` ou `+00:00`. Exemplo: `2026-05-16T18:30:00Z`.
- **Cliente**: converte UTC → timezone do dispositivo na hora de exibir, usando `intl` no Dart.
- **Date-only fields** (`birth_date`, `attendance.date`): `DATE` (sem hora). Wire: `2026-05-16`.
- **Year-month** (`financials.reference_month`): `TEXT 'YYYY-MM'`. Mais simples que um DATE com dia ignorado.
- **Backend valida** que `date` < amanhã para attendance (corner case do fuso); o app **nunca** confia no relógio do dispositivo para regras de negócio.
- TZ padrão para academia: armazenada em `academies.timezone` (IANA: `America/Sao_Paulo`). Reports usam essa TZ; UI do aluno usa a TZ do dispositivo.

---

## 4. Convenções de dinheiro

- **NUNCA** float. Sempre `NUMERIC(12, 2)` no Postgres, `shopspring/decimal` no Go, `Decimal` (package `decimal`) no Dart.
- API envia como **string** (não JSON number — float64 perde precisão):
  ```json
  { "amount": "129.90", "currency": "BRL" }
  ```
- Currency sempre presente, mesmo em prod onde só usamos BRL. Futureproof.
- Centavos vs reais: API expõe **reais** (com decimal). Conversões para centavos (Asaas API) acontecem no gateway adapter.

---

## 5. Convenções de erros (problem types)

Sempre `application/problem+json` com `type` URI estável. Catálogo canônico:

| Tipo URI | Status | Quando usar |
|---|---|---|
| `https://tatami.dev/errors/unauthorized` | 401 | Token ausente, inválido, expirado |
| `https://tatami.dev/errors/forbidden` | 403 | Autenticado mas sem permissão |
| `https://tatami.dev/errors/membership-removed` | 403 | Specialização: a membership do usuário foi removida |
| `https://tatami.dev/errors/not-found` | 404 | Recurso não existe (ou existe noutro tenant) |
| `https://tatami.dev/errors/validation` | 422 | Corpo da requisição falhou validação. Sempre com `errors[]` |
| `https://tatami.dev/errors/conflict` | 409 | Concorrência, duplicata, estado inválido |
| `https://tatami.dev/errors/idempotency-conflict` | 422 | Idempotency-Key colidiu com hash diferente |
| `https://tatami.dev/errors/link-code-already-used` | 409 | Specialização do conflict |
| `https://tatami.dev/errors/out-of-stock` | 409 | Loja: produto sem estoque |
| `https://tatami.dev/errors/rate-limited` | 429 | Rate limit por IP / usuário |
| `https://tatami.dev/errors/payment-required` | 402 | Reservado — não use sem ADR |
| `https://tatami.dev/errors/internal` | 500 | Erro interno (genérico) |
| `https://tatami.dev/errors/service-unavailable` | 503 | Gateway/dependência fora |

Novos tipos precisam de uma ADR antes de irem a produção. Não criar URIs novas no impulso.

---

## 6. Convenções de status (state machines)

Estados como **strings enum** com `CHECK` constraint. Transições válidas documentadas no domínio.

### 6.1 Aluno

```
created (implicit on insert) → active ⇄ injured / inactive / suspended → removed
```

- `removed` é terminal (soft delete; ressuscita exige novo cadastro ou unsetar via admin).

### 6.2 Financial

```
pending → paid (via webhook ou marcação manual)
pending → overdue (job diário) → paid (recuperado)
pending → cancelled (admin)
overdue → cancelled
```

- `paid` é terminal.
- Transição `paid → pending` proibida por código (estorno cria nova `wallet_transaction` de `refund`).

### 6.3 Store order

```
pending_payment → paid → preparing → ready → delivered
pending_payment → cancelled
paid → cancelled (restaura estoque)
```

### 6.4 Competition enrollment

```
enrolled → confirmed (admin) → checked_in (no dia)
enrolled → cancelled
```

---

## 7. Convenções de versionamento de API

- Path-based: `/v1/`, `/v2/` quando houver breaking change.
- **Adições** (novos campos opcionais, novos endpoints) **NÃO** são breaking — vão no mesmo `/v1/`.
- **Breaking changes**: novo campo obrigatório, mudança de tipo, remoção de campo, mudança de semântica → `/v2/`.
- Deprecation: campo continua em `/v1/` por 6 meses após criação do `/v2/`; backend retorna header `Deprecation: true` + `Sunset: <date>`.
- Nunca quebrar `/v1/` enquanto qualquer cliente em prod estiver consumindo.

---

## 8. Convenções de commits e branches

### 8.1 Commits

[Conventional Commits](https://www.conventionalcommits.org/) é o padrão. Mas escopo curto.

```
<type>(<scope>): <imperative description>

[body opcional]

[Refs opcional]
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `migration`.
Scope: nome do contexto/feature em uma palavra: `identity`, `attendance`, `etl`, `mig-fase-3`.

Exemplos:

```
feat(student): add belt-progression endpoint
fix(financial): debounce duplicate webhook from Asaas
docs(mig): add 05_MIGRACAO_DE_DADOS
migration(fase-3): dual-write students
```

### 8.2 Branches

- `main` — só código que pode ir pra prod.
- `feat/<scope>-<short>` — features.
- `fix/<scope>-<short>` — bugs.
- `migration/fase-N-<short>` — branches dedicadas para uma fase da migração.

### 8.3 PR sizing

- Idealmente < 500 linhas trocadas. Acima disso, dividir.
- Sempre com **checklist** no template: tests, exit criteria, docs atualizados, breaking change flag.

---

## 9. Convenções de logs

### 9.1 Backend (slog)

- Sempre `slog` (Go 1.21+); nunca `fmt.Print*` em produção.
- Atributos canônicos sempre presentes:
  - `request_id` (chi middleware)
  - `trace_id` (OTel)
  - `uid` (do contexto autenticado)
  - `academy_id` (quando aplicável)
- Mensagens em **inglês** (porque ferramentas de log lidam melhor com inglês padrão).
- Níveis:
  - `DEBUG`: detalhes verbose para dev; **não** em prod.
  - `INFO`: ações de negócio (created student, marked paid).
  - `WARN`: degradação (retry, fallback).
  - `ERROR`: falhas com `error` field como atributo.

### 9.2 Frontend (Sentry breadcrumbs)

- Adicionar breadcrumb em cada chamada de API: `Sentry.addBreadcrumb(message: 'GET /v1/...', category: 'http', data: {...})`.
- Capturar exceção apenas em paths inesperados (não em validation errors esperados).
- Sempre adicionar `trace_id` da response como tag para correlação.

---

## 10. Convenções de testes

### 10.1 Naming

- Go: `Test<TypeOrFunc>_<Scenario>` ou `TestIntegration_<Context>_<UseCase>`.
- Dart: `test/<scope>/<name>_test.dart`, dentro: `test('does X when Y', () { ... })`.
- Integration tests: prefixo `TestIntegration_`; build tag `integration`.

### 10.2 Estrutura

- AAA: Arrange / Act / Assert. Comentários `// arrange`, `// act`, `// assert`.
- Table-driven em Go quando aplicável.
- Cada teste é independente — sem `t.Run` aninhado dependendo de side-effect de teste anterior.

### 10.3 Fixtures

- Builders por bounded context em `internal/<ctx>/testkit/fixtures.go`.
- Builders no Dart em `test/fixtures/`.

---

## 11. Convenções de feature flags

Naming pattern: `useTatami<Domain>` para flags da migração.

```
useTatamiIdentity         (Fase 1)
useTatamiReads_<screen>   (Fase 2; pode ser por tela)
useTatamiWrites_<scope>   (Fase 3)
useTatamiFinancials       (Fase 4)
useTatamiAttendance       (Fase 5)
useTatamiNotifications    (Fase 6)
useTatamiStore            (Fase 7)
```

- Default em prod: `false` até o release.
- Flag deletada quando a fase fecha (limpeza obrigatória).

---

## 12. Anti-padrões a rejeitar em PR review

Lista para revisor cole no template de PR:

- [ ] Não há `await` em loop com I/O (N+1).
- [ ] Não há `await firestoreCall()` para coisas que deveriam ir via Tatami.
- [ ] Não há string em português dentro de identificadores de código (`belt: 'azul'`).
- [ ] Não há `print()` esquecido — `slog` no backend, `debugPrint` no Dart.
- [ ] Não há TODO sem owner + ticket.
- [ ] Não há novo endpoint sem spec OpenAPI atualizado.
- [ ] Não há nova entidade sem entry no glossário (este doc).
- [ ] Não há mudança de tipo de campo Postgres sem migration two-phase.
- [ ] Não há cliente novo sem `Idempotency-Key` em POST de mutation.
- [ ] Não há `cloud_firestore` direto em código de tela (deve passar pelo repo).
- [ ] Não há listener Firestore vivo após `dispose()`.

---

## 13. Quando o glossário muda

Mudanças neste doc requerem:

1. PR no repo `graduabjj` (este arquivo) e no Tatami (se backend afetado).
2. Discussão em ADR se for um conceito novo (não só renomear).
3. Comunicação no canal `#tatami-migration` com link para o PR.
4. Atualização nos demais docs em `migrations/` se algum termo era usado lá.

**Renomear** é o tipo de mudança mais perigosa em codebase grande — combina lockstep entre tabelas, queries, endpoints, frontend, docs, e às vezes contratos com clientes. Por isso o doc 02 existe (mapa congelado) e este doc (vocabulário congelado).

Quando o produto pede um termo novo em UI, **traduza** para o canônico no código (`'graduação' → belt_progression`), não introduza um terceiro nome.
