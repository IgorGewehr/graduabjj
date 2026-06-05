<!-- Gerado por .claude/workflows/aula-particular-turmas-architecture.js -->

# Blueprint de Implementação — GraduaBJJ

Branch alvo (ambas as features): **`firebase-production`** (Firestore, prod real). Confirmar antes de abrir as tasks; nada disso vai para `migration`.

---

## 1) Visão geral

Duas features de esforço **M**, independentes entre si, ambas com filosofia central de **reaproveitar pipelines existentes sem tocar no gateway nem na schema base**:

| # | Feature | Núcleo da mudança | Risco principal |
|---|---------|-------------------|-----------------|
| A | **Aula particular 1:1** | Reusar `avulsa → MP PIX → webhook settle` 100% intacto; adicionar UM ponto de lógica no settle que concede exatamente uma presença via docId determinístico | Paridade da presença concedida server-side vs roll-call (milestone/auto-promoção) |
| B | **"Adicionar Todos" + filtros categoria/gênero nas Turmas** | Portar o padrão da chamada (`bulkMarkPresent`) para `ClassService.addStudentsBulk`; chips de filtro + CTA batch | Sport-seeding O(N) reads sem prefetch; capacidade (`maxStudents`) |

Princípio comum: **idempotência por id determinístico**. Em A, o id da presença deriva do `financialId`. Em B, `arrayUnion` é naturalmente dedup e o filtro pré-write remove já-matriculados — exatamente como `bulkMarkPresent` filtra `presentIds`.

---

## 2) Aula particular 1:1 (single private lesson)

### 2.1 Modelo de dados

**Payment doc** (`academies/{aid}/financials/{id}`) — reusa o doc avulsa existente. `type` permanece `'avulsa'` (relatórios/queries financeiras continuam funcionando). Campos **adicionados** (todos ausentes em avulsas normais):

| Campo | Tipo | Significado |
|-------|------|-------------|
| `paymentSubtype` | `String` | Marcador `'private_lesson'` (ausente em avulsas comuns) |
| `lessonDate` | `Timestamp` | Quando a aula ocorre (distinto de `dueDate`/`paymentDate`) |
| `instructorId` | `String` | Quem dá a aula → será `verifiedBy` da presença |
| `instructorName` | `String` | Snapshot do nome do instrutor |
| `lessonSport` | `String` | Ex. `'bjj'` — snapshot para `attendance.sport` |
| `lessonWeight` | `double` | Default `2.0` (hint do `classes_screen`: particular = peso 2); determinístico |
| `attendanceGranted` | `bool` | Flag de idempotência/auditoria; `true` quando a presença é escrita |
| `attendanceId` | `String` | Back-reference para o doc de presença criado |

**Attendance doc** (`academies/{aid}/attendances/{id}`) — **SEM mudança de schema**. Escrito na mesma forma que `markPresent` já produz:
- `classId = 'aula_particular'` (constante virtual compartilhada)
- `className = 'Aula Particular'`
- `verifiedBy/verifiedByName = instrutor`
- `weight = lessonWeight`, `sport = lessonSport`
- `notes` opcionalmente referenciando o `financialId`
- `classId`/`className` continuam **non-nullable** — a constante sintética satisfaz o contrato de campo obrigatório SEM editar o model (`attendance_service.dart:14-15`).

**Problema do docId determinístico (crítico).** O id atual é `'{studentId}_{classId}_{yyyymmdd}'` (`attendance_service.dart:550`). Com `classId` compartilhado, duas aulas particulares do mesmo aluno no mesmo dia colidiriam.
**Fix:** para aula particular, derive o id do **Payment id**:

```
docId = 'aula_particular_{financialId}'
```

Globalmente único, idempotente entre webhook + inline + manual settle, e naturalmente uma-presença-por-aula-paga. Requer **param aditivo opcional `docIdOverride` em `markPresent`** (mudança mínima) em vez de um caminho dedicado.

**Classe sintética.** NÃO criar um `BJJClass` real. `'aula_particular'` é uma **constante de `classId` virtual reservada** (definir em `lib/core/sports.dart` ou um pequeno arquivo de constantes). Mantém fora de turmas/roll-call/rosters/openClass QR, e as queries indexadas por `classId` continuam baratas — admin lista todas as particulares com `attendances where classId == 'aula_particular'` (índice `(classId, date DESC)` já existe, `attendance_service.dart:196-216`).

### 2.2 Backend — como a presença é concedida

**Reuso sem mudança alguma:** `createMpPixPayment` / variante cartão (`server_functions.js:2915-3010`), `createMpPix` helper, validação de amount (REAIS canônico, tolerância 1 centavo), webhook marketplace (`3259+`), `mpMktParseRef`. Para o gateway, aula particular é apenas `type=='avulsa'` — o `external_reference` `'{academyId}:fin:{docId}'` já roteia para o branch `fin` de `mpMktSettle` (`server_functions.js:341` monta esse ref).

**UMA mudança focada** em `mpMktSettle`, branch `fin` (`server_functions.js:3384-3416`). Hoje a transação termina em `finSettle.didSettle` e dispara `notifyAdminCF`. Inserir **depois** do gate `if (!finSettle.didSettle) return;` (linha 3416):

```js
// dentro de finSettle: capturar os dados que já estão no snapshot
const finData = snap.data(); // disponível na transação

// APÓS o settle (best-effort, nunca bloqueia o settle):
if (finSettle.didSettle && finData.paymentSubtype === 'private_lesson'
    && !finData.attendanceGranted) {
  await grantPrivateLessonAttendance(academyId, docId, finData).catch(e =>
    console.error('[grantPrivateLesson] non-fatal', docId, e));
}
```

**Nova função `grantPrivateLessonAttendance(academyId, financialId, finData)`** — transação própria que espelha o `markPresent` Dart (`attendance_service.dart:399-409`):

1. `attendanceRef = academies/{aid}/attendances/aula_particular_{financialId}`
2. guard existência (idempotente — se já existe, sai)
3. `tx.set(attendanceRef, payload)` com: `studentId/Name`, `classId='aula_particular'`, `className='Aula Particular'`, `date = finData.lessonDate || now`, `verifiedBy = finData.instructorId`, `verifiedByName = finData.instructorName`, `weight = finData.lessonWeight`, `sport = finData.lessonSport`, `createdAt = serverTimestamp()`
4. `tx.update(studentRef, { attendanceCount: increment(1), updatedAt: serverTimestamp() })`
5. `tx.update(finRef, { attendanceGranted: true, attendanceId: 'aula_particular_{financialId}' })`

**Idempotência dupla:** flag `attendanceGranted` no doc financeiro **E** docId determinístico da presença. Retentativas de webhook / double-settle concedem no máximo uma presença.

**Decisão — gatilho da concessão:**
- **PRIMÁRIO = automático na confirmação do pagamento** (server-side dentro do settle). O aluno ganha a presença no instante em que o PIX/cartão compensa, sem ação de staff. É o mais consistente com "como se marcado na chamada".
- **SECUNDÁRIO/fallback = manual:**
  - **(a) dinheiro offline** via `markAsPaid` (`payment_service.dart:522-576`) — o pagamento manual NUNCA atinge o webhook, então é **obrigatório** adicionar um branch private-lesson aqui que, após o update mark-paid, chama `AttendanceService.markPresent` com `classId='aula_particular'` e `docIdOverride='aula_particular_{financialId}'`. Sem isso: aula paga sem presença (gap silencioso).
  - **(b) botão admin "Marcar presença da aula"** para a política grant-on-lesson-given (ver perguntas em aberto).

Os três caminhos funilam pelo mesmo grant idempotente de docId determinístico — não podem duplicar.

**Paridade milestone/auto-promoção.** O `markPresent` Dart dispara `checkAttendanceMilestone` + `_maybeAutoPromote` (`attendance_service.dart:411-423`). O grant server-side **no mínimo** incrementa `attendanceCount` (do qual ranking/elegibilidade dependem). Para paridade total no caminho automático, **recomendado (i)**: chamar os helpers de notificação + a checagem de auto-promoção de dentro de `grantPrivateLessonAttendance` (espelhar `notifyAdminCF` + auto-promotion como o `attendance_service` faz), evitando divergência comportamental entre chamada e aula particular. Alternativa (ii), mais barata: grant mínimo (count + doc) e confiar no recompute de elegibilidade do client no próximo open — aceita um gap até o app reabrir.

### 2.3 UI por persona

**Admin/Professor — criar aula particular** (`student_detail_screen.dart:~1890-1914`): estender o dialog avulsa OU ação irmã "Agendar aula particular". Campos novos: `price` (default ex. R$150, reusa o campo value), `lessonDate` (data + hora opcional), `instructor` (default usuário atual), `sport` (default esporte primário do aluno), `weight` (default 2, opcional/avançado). No confirm chama `PaymentService.create` com `type:'avulsa'` + novos params **opcionais** threaded por `create()` (`payment_service.dart:455-462`): `paymentSubtype`, `lessonDate`, `instructorId/Name`, `lessonSport`, `lessonWeight`. Label claro para ler como aula, não cobrança genérica.

**Admin — enviar/rastrear:** reusar a row avulsa na lista financeira do aluno; badge **"Aula Particular"** quando `paymentSubtype=='private_lesson'`. Reusar o "gerar/copiar link PIX" (`createMpPixPayment`) para enviar o link direto — **resolve a dor existente "no direct MP checkout from avulsa creation UI"**. Após pago, mostrar "Presença concedida" quando `attendanceGranted==true`.

**Admin — offline/manual:** a ação "marcar como pago" da row agora também concede a presença via branch private-lesson do `markAsPaid`; confirmação "Marcar pago e conceder presença?". Botão separado opcional "Marcar presença da aula" para política give-on-lesson.

**Aluno — pagar:** NENHUMA tela nova. A aula aparece na lista pendente do aluno (`streamByStudent`) como qualquer avulsa com label "Aula Particular"; tocar "Pagar" roda o checkout PIX/cartão existente. Após settle, a presença aparece no histórico/streak/ranking automaticamente (é um doc de presença normal) — reusa widgets de home/profile sem mudança; `classId='aula_particular'` renderiza como "Aula Particular".

**Aluno — visibilidade:** confirmar que histórico/streak renderizam o `className` sintético graciosamente (é só uma string). Sem special-casing.

### 2.4 Casos de borda

- **Duas particulares mesmo dia/aluno:** resolvido por `docId='aula_particular_{financialId}'` — cada aula paga concede sua presença distinta.
- **Double settle (webhook + inline cartão) / retries:** guardado duplamente (flag `attendanceGranted` + existência do docId determinístico). No máximo uma presença.
- **Dinheiro offline:** NUNCA atinge webhook → grant DEVE ser invocado do branch `markAsPaid`. Se pulado: gap silencioso.
- **Estorno/cancelamento após grant:** decisão de política (ver §6). Default seguro: deixar a presença (aula provavelmente foi dada), revogar só se cancelado antes da `lessonDate` (via `unmarkPresent` + decrement).
- **Grant ok mas flag falha (ou vice-versa):** manter set da presença + update da flag na MESMA transação; mesmo se separados, o id determinístico previne duplicatas no retry.
- **Race de auto-graduação:** uma presença de particular pode cruzar o threshold; o grant server-side deve rodar a mesma checagem de elegibilidade da chamada, senão auto-promoção diverge por fonte.
- **Proteção de amount:** `mpMktSettle` já recusa settle se REAIS pago != stored (`server_functions.js:3396-3401`) — protege o preço da aula sem mudança.
- **Aluno sem conta de usuário:** link PIX funciona, presença é concedida no Student doc independente de linkage. Notificações apenas pulam (espelha avulsa atual).
- **lessonDate futura vs pago-agora:** `attendance.date` deve ser `lessonDate` (quando a aula ocorre), não a data de pagamento; default `now` se ausente.
- **Esporte errado:** `lessonSport` capturado no create (default esporte primário). Graduação filtra por esporte — particular de muaythai de um aluno bjj não pode contar para elegibilidade bjj.

---

## 3) Turmas — filtros adulto/kids + gênero + "Adicionar Todos"

### 3.1 Modelo de dados

- **`BJJClass.studentIds` (`List<String>`)** é o único campo persistido tocado — bulk add faz `FieldValue.arrayUnion` no doc da turma (`class_service.dart:397`). `arrayUnion` é idempotente/dedup; re-adicionar matriculado é no-op no Firestore.
- **Side-effects por aluno** de `_enrollStudentInSport` (`class_service.dart:409-467`): `student.sports` (arrayUnion sportValue), `student.sportData.<sport>` (grade default por categoria, legacy-BJJ-aware), `student.primarySport` (set se vazio). **DEVEM rodar para cada aluno novo** — bulk não pode só escrever `studentIds`.
- **Inputs de filtro (read-only) já no Student:** `student.category` (`StudentCategory`, required, `student.dart:52-76`), `student.sex` (`Sex?`, nullable, `student.dart:80-96`), `student.getSports()` (ordenação por afinidade). Sem mudança de schema.
- **Default do chip Categoria:** `cls.category` (`StudentCategory?`, `class_service.dart:45`) — pré-selecionar quando non-null; quando null → "Todos".
- **Sem novas coleções, campos ou security rules** (writes ficam em `classDoc.update` + `student.update`, já permitidos a admins).

### 3.2 Backend

**NOVO: `ClassService.addStudentsBulk(String classId, List<String> studentIds)`** — espelha `AttendanceService.bulkMarkPresent` (`attendance_service.dart:590-680`):

1. **`getById(classId)` uma vez** para `cls.getSport()`/`cls.category` (fail fast se null).
2. **Filtrar** ids já em `cls.studentIds` (dedup pré-write, como `bulkMarkPresent` filtra `presentIds` em ~611-613).
3. **Prefetch dos alunos-alvo** via `whereIn` em chunks de 30 (Firestore limita `whereIn` a 30) — **obrigatório** para rosters grandes; sem isso vira N `.get()` seriais (`_enrollStudentInSport` faz `.get()` por aluno em `class_service.dart:415`) e dá timeout/martela o Firestore.
4. **WriteBatch sharding em 240/batch** (mesma constante/raciocínio sob cap de 500 de `attendance_service.dart:616-621`): um `batch.update` no classDoc com `arrayUnion(ids-do-shard)` + um `student.update` por membro do shard.
5. **Sport seeding em memória:** computar cada update map a partir dos dados pré-fetched, escrever em batches.
6. **Retornar a lista de ids efetivamente commitada** (como `bulkMarkPresent` retorna results) — UI re-sincroniza a partir disso (cobre partial failure).

**Refatorar para helper puro compartilhado** `_buildEnrollmentUpdate(studentData, sport, category, muaythaiVariant)` para que `addStudent` (single) e `addStudentsBulk` semeiem sports/grades de forma idêntica: grade default por categoria via `getGradesForSport`, preservação de `currentBelt` legacy (`class_service.dart:452-457`), ladder Muay Thai (`class_service.dart:438-441`).

**Ladder Muay Thai (`muaythaiGradeSystem`):** ler UMA vez por chamada bulk, não por aluno (hoje `_enrollStudentInSport` relê o academy doc por aluno em `class_service.dart:439`) — hoist para uma única leitura em `addStudentsBulk`.

**NOVO opcional (undo): `ClassService.removeStudentsBulk(classId, studentIds)`** — `arrayRemove` batched. **Undo só reverte `studentIds`**, NÃO remove `sportData`/`primarySport` (não-destrutivos; remover um grade poderia corromper aluno já graduado).

**Sem mudança em Cloud Function** — puro client-side batch, consistente com a chamada (toda a lógica bulk vive em `AttendanceService`, sem CF).

### 3.3 UI (persona única: Admin/Professor — `_ManageStudentsSheet` é admin-gated)

- **Nova linha de chips** abaixo da row Todos/Matriculados existente (`classes_screen.dart:2253-2286`), reusando o widget `_ToggleChip` (`classes_screen.dart:2325-2359`) — visual idêntico aos chips atuais e aos da chamada.
- **Chips Categoria:** `Todos | Adulto | Infantil` (`StudentCategory.values.label`). Default = `cls.category`. State `StudentCategory? _categoryFilter` (null = Todos).
- **Chips Gênero:** `Todos | Masculino | Feminino` (`Sex.values.label`). State `Sex? _sexFilter`. Sex é nullable — com filtro de gênero ativo, alunos com sex null são **excluídos**; mostrar hint para o admin não se surpreender com a contagem menor.
- **Estender `_visibleStudents`** (`classes_screen.dart:2086-2100`) com predicados `s.category == _categoryFilter` e `s.sex == _sexFilter`, compondo com search + showOnlyEnrolled.
- **CTA primário "Adicionar todos (N)"** espelhando o botão da chamada (`attendance_screen.dart:396-400`): N = visíveis NÃO matriculados e NÃO bloqueados por capacidade. Sticky/footer fixo. Disable/hide quando N==0. Estilo `AppTheme.success`.
- **Dialog de confirmação** espelhando `_markAllPresent` (`attendance_screen.dart:382-404`): "Adicionar N alunos a esta turma?" com contexto: "Adicionar todos os 42 alunos Adulto Masculino?".
- **Sucesso:** update otimista de `_enrolledIds` (apenas os ids commitados retornados), `_hasChanges=true`, SnackBar "N alunos adicionados" + **DESFAZER**. Header `'${_enrolledIds.length} alunos'` (`classes_screen.dart:2206`) atualiza na hora.
- **Capacidade:** badge "Lotada" + gate `maxedOut` já existem (`classes_screen.dart:2148, 2267-2284, 2306`). Bulk deve respeitar `cls.maxStudents` — cap ao restante OU bloquear (ver §3.4).
- **Opcional (follow-up): "Remover todos os visíveis"** só na view Matriculados — espelha `_unmarkAllPresent` (`attendance_screen.dart:458`).

### 3.4 Casos de borda

- **Já matriculados:** `arrayUnion` idempotente + pré-filtro contra `cls.studentIds` — N e write excluem matriculados (espelha filtro de `presentIds`, `attendance_service.dart:611`).
- **Capacidade (`cls.maxStudents`, `class_service.dart:49`):** se N excede slots restantes, (a) cap + "Turma lotada — apenas X de N adicionados", ou (b) bloquear com messaging "Lotada". Honrar a mesma regra do single-add (`classes_screen.dart:2306`), não overfill silencioso.
- **Rosters grandes (300+):** sharding 240/batch + **prefetch `whereIn` chunks de 30 obrigatório** — sem ele, 300 `.get()` seriais → timeout.
- **Sex null sob filtro de gênero:** excluídos silenciosamente; hint "alunos sem gênero cadastrado não entram neste filtro".
- **Undo:** DESFAZER reverte **apenas os ids efetivamente adicionados** (lista retornada por `addStudentsBulk`, não o set visível), via `removeStudentsBulk`/`arrayRemove`. NÃO remove `sportData`/`primarySport`.
- **Partial failure mid-batch:** shard pode falhar após shards anteriores. `addStudentsBulk` retorna ids commitados; UI reflete só os commitados + "X de N adicionados", re-sincroniza `_enrolledIds` da lista retornada.
- **Edições concorrentes:** `arrayUnion` é conflict-free no campo; risco único é overshoot de capacidade (ambos passam o check, ambos commitam). Aceitar como baixo risco em v1, ou `runTransaction` re-lendo count (mais pesado; provavelmente não vale v1).
- **Mismatch de categoria** (kids em turma adulto): permitido, mas seeding usa `cls.category` (`class_service.dart:433`) → kids ganha grade adulto. **Manter paridade com single-add** (class.category vence) para evitar divergência — flag em §6.
- **Resultado vazio:** quando não há visível não-matriculado, esconder/disable o botão (espelha "Todos já estavam marcados", `attendance_screen.dart:421-423`).

---

## 4) Reaproveitamento da infra

| Pipeline existente | Onde | Como é reusado |
|---|---|---|
| **Cobrança avulsa end-to-end** | `PaymentService.create` (`payment_service.dart:455`, `type='avulsa'`) | Aula particular É uma avulsa com params adicionais opcionais; zero mudança no fluxo base |
| **MP PIX checkout** | `createMpPixPayment` + `createMpPix` + variante cartão (`server_functions.js:2915-3010`) | Inalterado — aula particular roteia pelo branch `fin` do `external_reference` `{aid}:fin:{id}` |
| **Validação de amount** | `validateAmount`, conversão centavos (`~2942-2945`) | Protege o preço da aula sem mudança |
| **MP webhook + settle** | `mercadoPagoMarketplaceWebhook` (`3259+`), `mpMktParseRef`, branch `fin` de `mpMktSettle` (`3384-3416`) | Estendido in-place com o grant da presença; sem código novo de gateway |
| **Transação idempotente de settle** | `mpMktSettle` fin tx (`3388-3415`) | Padrão copiado/adaptado para `grantPrivateLessonAttendance` |
| **`markPresent`** | `attendance_service.dart:362-427` (tx em `399-409`) | Template do payload + tx; reusado direto no caminho Dart manual e espelhado server-side no automático. Helper de id (`544-550`) estendido com `docIdOverride` |
| **`markAsPaid` offline** | `payment_service.dart:522-576` | Branch private-lesson adicionado para conceder presença em dinheiro |
| **`bulkMarkPresent`** | `attendance_service.dart:590-680` | **Template direto** de `addStudentsBulk`: pré-filtro, sharding 240/batch, write combinado, retorno da lista commitada, follow-ups pós-commit |
| **`_markAllPresent` flow** | `attendance_screen.dart:376-456` | Estrutura do dialog, estilo `AppTheme.success`, toast de sucesso, guard "filter to not-already-done" |
| **`_enrollStudentInSport`** | `class_service.dart:409-467` | Refatorado em helper puro compartilhado entre single e bulk add |
| **`_ToggleChip` / `_visibleStudents`** | `classes_screen.dart:2325-2359 / 2086-2100` | Chips de categoria/gênero + composição de filtros |
| **Enums `StudentCategory`/`Sex`/`Sport`** | `student.dart:52-96` | Labels dos chips + predicados + snapshot de esporte/peso |

---

## 5) Roadmap em fases

### Feature A — Aula particular 1:1

| Fase | Entregável | Esforço | Depende de |
|---|---|---|---|
| A0 | Constante `kPrivateLessonClassId='aula_particular'` em `core/sports.dart`; param opcional `docIdOverride` em `markPresent` + `_deterministicAttendanceId` | S | — |
| A1 | `PaymentService.create` aceita params opcionais (`paymentSubtype`, `lessonDate`, `instructorId/Name`, `lessonSport`, `lessonWeight`) | S | — |
| A2 | UI admin: dialog "Agendar aula particular" + badge "Aula Particular" na row + reuso do "gerar link PIX" | M | A1 |
| A3 | Backend: `grantPrivateLessonAttendance` + hook no branch `fin` de `mpMktSettle` (idempotente, dupla guarda) | M | A0 |
| A4 | Branch private-lesson em `markAsPaid` (caminho dinheiro offline) chamando `markPresent` com override | S | A0 |
| A5 | Paridade: milestone/auto-promoção no grant server-side (recomendado i) | M | A3 |
| A6 | UI "Presença concedida" (lê `attendanceGranted`) + verificação dos widgets aluno renderizando className sintético | S | A2, A3 |

**Caminho crítico mínimo viável:** A0 → A1 → A3 → A2. A5 pode ser fast-follow se aceitarem o recompute do client temporariamente.

### Feature B — Bulk add + filtros

| Fase | Entregável | Esforço | Depende de |
|---|---|---|---|
| B0 | Refatorar `_enrollStudentInSport` → helper puro `_buildEnrollmentUpdate` (single-add passa a usá-lo, sem mudança de comportamento) | S | — |
| B1 | `ClassService.addStudentsBulk` (prefetch `whereIn` 30 + sharding 240 + retorno de ids commitados); ladder Muay Thai lido 1x | M | B0 |
| B2 | Chips Categoria + Gênero em `_ManageStudentsSheet` + extensão de `_visibleStudents` + default `cls.category` | M | — |
| B3 | CTA "Adicionar todos (N)" + dialog + update otimista + SnackBar DESFAZER | M | B1, B2 |
| B4 | `removeStudentsBulk` (undo, studentIds-only) + gating de capacidade (`maxStudents`) | S | B1, B3 |
| B5 | (Follow-up) "Remover todos os visíveis" na view Matriculados | S | B4 |

**Esforço total:** A ≈ M (3-4 dias), B ≈ M (2-3 dias). Independentes; podem rodar em paralelo.

---

## 6) Riscos e perguntas em aberto

### Feature A

1. **Política de timing do grant:** presença na CONFIRMAÇÃO do pagamento (default recomendado, automático) vs na AULA DADA (instrutor marca após). Define se o auto-grant em `mpMktSettle` é o caminho primário ou se o botão "Marcar presença" é. Se "pague-agora-treine-depois" for comum, desacoplar `lessonDate` do grant importa.
2. **Estorno/cancelamento após grant:** revogar presença + decrement `attendanceCount` (+ possível reversão de auto-promoção)? Precisa de regra de negócio explícita. Default seguro: manter, revogar só se cancelado antes da `lessonDate`.
3. **Paridade server-side:** replicar milestone/notif/auto-graduação totalmente, ou só incrementar `attendanceCount` (com recompute do client)? Paridade vs custo. **Recomendação: paridade (i)** para não divergir da chamada.
4. **Peso default:** confirmar `2.0` (hint do `classes_screen`) vs `1.0`, e se instrutores podem sobrescrever por aula.
5. **`type='private_lesson'` próprio vs `'avulsa'`+subtype?** Manter `'avulsa'` preserva relatórios financeiros; type distinto dá analytics mais limpo. Decidir por como os dashboards financeiros agregam. **Recomendação atual: subtype** (menor blast radius).
6. **Escopo:** só cobrança+presença, ou precisa de calendário/agendamento/disponibilidade/payout do instrutor? Plano atual: cobrança+presença apenas.
7. **Aluno pode auto-solicitar/agendar** (criando cobrança pendente) ou criação é admin-only? Plano assume admin-only.
8. **Definição da constante `aula_particular`** e como telas de histórico a rotulam — confirmar que nenhum special-casing de UI quebra.

### Feature B

9. **Estratégia de prefetch (decisão arquitetural principal):** `whereIn` chunks de 30 (recomendado) vs `.get()` por aluno (simples, inutilizável em rosters grandes). **Recomendado: prefetch.**
10. **Fonte da categoria para seeding quando `class.category != student.category`:** paridade com single-add (`class.category` vence) ou preferir `student.category`? **Recomendação: paridade** para evitar divergência.
11. **Overflow de capacidade:** cap-and-partial ("X de N") vs hard-block quando N excede slots — preferência do dono?
12. **Profundidade do undo:** só `studentIds` (recomendado, não-destrutivo) vs também stripar `sportData`/`primarySport` (arriscado para já-graduados). **Confirmar: studentIds-only.**
13. **"Remover todos os visíveis"** nesta iteração ou follow-up?
14. **Chip de gênero com sex nullable:** excluir silenciosamente (recomendado) + hint vs bucket "sem gênero". **Confirmar: exclusão + hint.**
15. **Branch alvo:** confirmar `firebase-production` (não `migration`), conforme memória do projeto.

---

**Notas de verificação:** os anchors de linha foram conferidos contra o código vivo. Confirmados: `markPresent` tx (`attendance_service.dart:399-409`), helper de id determinístico (`544-550`), branch `fin` de `mpMktSettle` com gate `finSettle.didSettle` e `notifyAdminCF` (`server_functions.js:3384-3416`), `external_reference` `{aid}:fin:{id}` (`341`), `addStudent`/`_enrollStudentInSport` (`class_service.dart:392-467`), `PaymentService.create`/`markAsPaid` (`payment_service.dart:455, 522-576`), constante de shard 240 (`attendance_service.dart:616-621`).
