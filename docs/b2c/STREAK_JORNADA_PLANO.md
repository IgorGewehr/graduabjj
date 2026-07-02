# Plano: Streak por dias-esperados, Jornada do visitante e Avatar do Lutador

> Documento de ARQUITETURA (não implementado). Base: app do LUTADOR (Flutter + Firebase, branch b2c).
> Escopo READ-ONLY já mapeado — este doc é o roteiro acionável de implementação.
> Convenção de dia canônica adotada em todo o doc: **weekday 1=Seg … 7=Dom** (padrão `DateTime.weekday`).

---

## 0. Resumo executivo

Três mudanças acopladas:

1. **Streak por dias-esperados** (peça central) — substitui o streak ingênuo (dias-calendário consecutivos, que dá 0 pra quem treina só sexta) por um modelo onde o aluno tem um conjunto de **dias de treino esperados** (semanal, ex.: seg/qua/sex). Um dia esperado é "cumprido" se houve treino nele = **attendance verificada OU self-log** (`training_logs`). Streak = nº de dias esperados cumpridos em sequência retroativa; furar um dia esperado quebra; treino extra em dia não-esperado ajuda mas nunca quebra.
2. **Perfil de visitante = JORNADA** — troca as abas `GRADUAÇÕES / COMPETIÇÕES / FOTOS` por **JORNADA** (marcos cronológicos + painel de treino padrão: presença dos últimos 3 dias, "N dias sem faltar", histórico de sparrings, streak) **+ FOTOS**. Tudo lido do espelho `fighterProfiles` (cost-safe, 1 read, sem attendance privada).
3. **Avatar do Lutador** — o header do hub (`lutador_hub_screen.dart`) usa `photoUrl`; iniciais só como fallback.

As três dependem de um mesmo eixo: unir **attendance ∪ training_logs** por dia e materializar sinais novos no espelho. A estratégia é **aditiva** (`fromMap` já tolera legado) e **owner-computa / visitante-lê** (nenhuma query nova no visitante).

---

## 1. Streak por dias-esperados — o modelo formal

### 1.1 Definições

- **Dia esperado**: um dia da semana (1..7) em que o aluno declarou que *pretende* treinar aquele esporte. Conjunto `expectedTrainingDays[sport] : Set<int>`. Default derivado dos horários da turma matriculada; editável pelo aluno; manual pra quem não tem academia no app.
- **Ocorrência de dia esperado**: uma data-calendário concreta no passado cujo `weekday ∈ expectedTrainingDays[sport]`. Ex.: se esperado = {5} (sexta), as ocorrências são cada sexta retroativa.
- **Dia treinado (união)**: `Set<DateTime>` de datas normalizadas a `DateUtils.dateOnly` = `{dateOnly(a.date) : a ∈ attendance}` ∪ `{dateOnly(l.date) : l ∈ training_logs}`. Como é um Set de dateOnly, attendance + self-log no mesmo dia deduplicam sozinhos.
- **Cumprido**: uma ocorrência de dia esperado está cumprida sse seu `dateOnly ∈ dias treinados (união)`.
- **Streak atual**: quantidade de ocorrências de dias esperados **consecutivas** (retroativas a partir da última esperada que já passou) que estão cumpridas. Quebra na primeira ocorrência esperada **não** cumprida.
- **Recorde**: maior run de ocorrências esperadas consecutivas cumpridas em todo o histórico.

### 1.2 Regras

| Situação | Efeito na streak |
|---|---|
| Dia esperado **com** treino (attendance ou self-log) | conta +1, continua |
| Dia esperado **sem** treino (já passou) | **quebra** |
| Dia **não-esperado** sem treino | ignorado (não quebra, não conta) |
| Dia **não-esperado** com self-log (treino extra) | entra na união, mas nenhuma ocorrência esperada o exige → **nunca quebra**; ajuda `totalTrainings` e pode cobrir retroativamente um dia esperado |
| Dia esperado ainda **não passou** hoje (ex.: hoje é sexta e o treino é à noite) | não conta como quebra ainda — janela de graça até o fim do dia |

Nota de "furar quebra": para saber que um dia esperado **já passou sem treino** é preciso um relógio confiável. Client-side com `DateTime.now()` é barato e mantém o padrão atual, porém manipulável e pode divergir do espelho. Decisão recomendada: **começar client-side** reaproveitando `getStreakInfo`, materializar no espelho no mesmo write do dono; migrar para CF (`users/{uid}/stats`) só se aparecer abuso.

### 1.3 Exemplos numéricos

Assuma esporte = bjj em todos.

**Ex. 1 — matriculado só sexta, treinou 4 sextas do mês.**
`expectedTrainingDays = {5}`. Ocorrências retroativas: sex-4, sex-3, sex-2, sex-1 (as 4 últimas sextas). Todas cumpridas (attendance nelas). Ocorrência anterior (sex-5, mês passado) não cumprida → quebra ali.
**Streak = 4.** (Hoje: modelo antigo daria 0 ou no máx. 1.)

**Ex. 2 — 3x/semana (seg/qua/sex) com 1 falta.**
`expectedTrainingDays = {1,3,5}`. Últimas ocorrências: sex (treinou), qua (treinou), seg (**faltou**), sex-ant (treinou)…
Retroativo a partir de hoje: sex✓ → qua✓ → seg✗ → **quebra**.
**Streak = 2.** Se depois recuperar a assiduidade, o recorde guarda a melhor sequência histórica.

**Ex. 3 — extras em dia não-esperado.**
`expectedTrainingDays = {2,4}` (ter/qui). Aluno treinou ter✓, qui✓, e também um self-log num sábado (extra).
O sábado não é ocorrência esperada → não é checado. Ocorrências esperadas ter✓ qui✓ ter-ant✓ … seguem contando.
**Streak = nº de ter/qui cumpridos em sequência**; o sábado só soma em `totalTrainings`/sparrings. Extra = upside puro.

**Ex. 4 — sem academia (muay thai fora do app), dias manuais.**
Sem turma → sem default; aluno declara `expectedTrainingDays[muaythai] = {1,4}` (seg/qui) e só tem **self-logs** (não há attendance). União = só training_logs. Streak roda igual sobre as ocorrências seg/qui cumpridas por self-log.
Se marcou seg✓, qui✓, seg-ant✓ e furou qui-ant → **Streak = 3.**

**Ex. 5 — treino esperado hoje ainda não feito.**
`expected = {1,3,5}`, hoje é sexta 15h, treino é 20h, ainda não treinou; qua✓ seg✓.
A ocorrência de hoje ainda **não passou** (janela de graça até 23:59) → não quebra. Streak conta a partir de qua: qua✓ seg✓ sex-ant✓ …
**Streak não zera** por causa do treino de hoje ainda pendente.

### 1.4 Algoritmo passo-a-passo

Entrada: `expected: Set<int>` (weekday 1..7), `trained: Set<DateTime>` (dateOnly, união attendance ∪ self), `now`.

```
1. Se expected vazio → fallback: comportamento legado (dias-calendário) OU
   derivar expected on-the-fly dos dias já treinados. (Decidir; recomendo
   legado como safety-net pra não zerar quem nunca configurou.)

2. today = dateOnly(now)

3. current = 0
   cursor = a MAIS RECENTE ocorrência esperada com data <= today.
            (retroceder de today até weekday(cursor) ∈ expected)
   // janela de graça: se cursor == today e today ainda não treinado,
   // recua cursor pra ocorrência esperada ANTERIOR (não pune o dia em curso).

4. loop:
     se cursor ∈ trained → current++ ; cursor = ocorrência esperada anterior
     senão → break

5. record = maior run de ocorrências esperadas consecutivas cumpridas,
   varrendo o histórico esperado de firstTrainingDate até today
   (mesma checagem cursor ∈ trained, resetando run no primeiro furo).
   record = max(record, current)

6. weekStrip = para cada dia da semana atual (seg..dom): classificar em
   {esperado-cumprido, esperado-furado, treino-extra, livre} cruzando
   expected × trained × (dia já passou?). Alimenta o novo _StreakCard.
```

Escopo: **por-esporte** (alinha com `getStreakInfo(sport:)` e com o `expectedTrainingDays` por-esporte). A Jornada é primary-centric, então o número do espelho usa o esporte principal.

---

## 2. Dias de treino do aluno

### 2.1 Onde guardar

**Fighter-owned, por-esporte, no doc `users/{uid}`:**

```json
expectedTrainingDays: { "bjj": [1,3,5], "muaythai": [2,4] }
```

- Weekday canônico **1=Seg..7=Dom**. Fallback global quando o esporte não tem entrada.
- Escolha do doc `users/{uid}` (e não `students/{id}`) porque: (a) é config do lutador, sobrevive à troca de academia; (b) o aluno **sem academia** pode não ter `Student` doc, mas sempre tem `users/{uid}`; (c) `training_logs` já são keyed por uid.
- **Não** precisa ir ao espelho `fighterProfiles` (é config privada). O que vai ao espelho é a streak **derivada**.

### 2.2 UI de definição

Nova tela/aba **"Meus dias de treino"**, clonando o esqueleto de `lib/screens/portal/my_sports_screen.dart` (lê `currentStudentProvider` + `classesProvider`, muta via `service.update`):

- **Default** = união dos `schedule[].dayOfWeek` de toda turma onde `class.studentIds.contains(student.id)`, convertido de 0..6 (`ClassSchedule`) para 1..7. Chips seg-dom pré-marcados nesses dias.
- **Editável**: aluno desmarca os dias que não frequenta (ex.: turma dá aula todo dia, ele fica só com sexta). Persiste **só o subconjunto**; se ficar vazio, cai no default (todos os candidatos).
- **Sem academia**: sem turmas candidatas → chips todos vazios, aluno marca 100% manual (padrão auto-declarado de `my_sports_screen`, `_isSelfDeclared`).
- Persistência: `studentService`/novo helper de user-doc → `update(users/{uid}, {expectedTrainingDays: {...}})`.

### 2.3 Rules

**Zero rule nova.** As rules já permitem update do dono em `users/{uid}` exceto `role`/`academyId` (`firestore.rules:260-262`). `expectedTrainingDays` é campo novo owner-writable, coberto pela regra existente.

### 2.4 Providers novos (implementação)

- `enrolledClassesProvider` — filtra `classesProvider` por `student.id` (hoje feito inline em `my_sports_screen.dart:53`; extrair pra reuso).
- Helper `deriveDefaultExpectedDays(classes, sport) : Set<int>` — coleta `schedule[].dayOfWeek` das turmas do esporte, converte 0..6 → 1..7.

---

## 3. Fundir fontes (attendance ∪ self-logs)

### 3.1 Princípio

O streak novo consome uma **união por dia** de duas fontes de escopos diferentes:

- **attendance** — `academies/{academyId}/attendance`, academy-scoped, lida por `AttendanceService.getByStudent(student.id, limit:365)` (`attendance_service.dart:83-101`).
- **training_logs** — `users/{uid}/training_logs`, user-scoped, `TrainingLogService(uid).recent()` (`training_log_service.dart:20-29`). Um dia "treinou" pela **existência** do doc naquele `dateOnly` (não pelo `sparringCount` — musculação grava count=0).

Como ambos viram `Set<DateTime>` de `dateOnly`, a união deduplica sozinha (inclui o caso `linkedAttendanceId`, quando o self-log foi anexado a uma aula real).

### 3.2 Onde fundir

**Na materialização (`myShowcaseProvider`, `friend_providers.dart:66-129`)**, NÃO dentro de `AttendanceService`. Motivo: é o único lugar que já tem `uid` **e** `academyId` na mão. Passo:

- Além de `getStreakInfo(student.id, sport:)`, ler `TrainingLogService(user.id).recent(limit: alinhado a 365)` e passar ambos os conjuntos de `dateOnly` + `expectedTrainingDays[sport]` ao novo cálculo de streak-por-dias-esperados.

### 3.3 Ajustes obrigatórios

- **Janela de lookback alinhada**: `getStreakInfo` lê attendance `limit:365`; `TrainingLogService.recent` default `limit:120` (`training_log_service.dart:26`). Alinhar as duas janelas (ex.: ~365 dias) senão o self-log some antes da attendance.
- **Fighter SOLO (sem academyId)**: `myShowcaseProvider` retorna `null` quando `academyId` vazio (`friend_providers.dart:71`). É exatamente o aluno muay-thai-fora que só tem self-logs. Precisa de **caminho de streak baseado só em `training_logs`** para o solo (branch que não exige academia).
- **Anti-fraude (blindar)**: `training_log.dart:21-26` declara que self-log **nunca** alimenta graduação. A fusão pode alimentar **streak/totais (retenção)**, mas `nextPromotionCard` / `studentSportEligibilityProvider` devem continuar lendo **só attendance verificada** (`diario_screen.dart:1212+`). Não vazar a união pra elegibilidade.

### 3.4 O que materializar no espelho

`ShowcaseData` / `ShowcaseBuilder.build` (`showcase_builder.dart:11-40, 73-133`) hoje grava `currentStreak/recordStreak` (que virão do novo cálculo). Adicionar 3 sinais novos owner-side (com as listas já carregadas + a nova leitura de training_logs):

1. `expectedDaysStreak` (int) + opcionalmente `expectedWeekdays` (List<int>) — o número da decisão #1. (Pode simplesmente sobrescrever `currentStreak` com o novo valor, mantendo o campo; recomendo campo dedicado pra não confundir semânticas legadas.)
2. `recentTrainingDays` — lista compacta dos últimos ~14 dias: `[{date, source:'attendance'|'self', sport}]`. Resolve "presença nos últimos 3 dias".
3. `sparringSummary` — agregado leve: `{totalRolls, rolls30d, recent:[{date, sparringCount, sport}]}` (últimos N logs). Resolve "histórico de sparrings/rolas".

**Idempotência**: `ShowcaseData.hash` (`showcase_builder.dart:37-39`) hoje captura só `totalTrainings|len(grad)|len(comp)|streak|record|medals`. **Precisa incluir** os novos sinais (ex.: `expectedDaysStreak`, hash de `recentTrainingDays`, `rolls30d`) senão "treinou ontem" não re-materializa e o visitante vê dado velho.

Persistência: campos novos opcionais em `FighterProfile` (`fighter_profile.dart:214-221` + `fromMap` tolerante, `:247-277`) e no payload de `friendService.mirror` (`friend_service.dart:28-92`), sob o mesmo gate `showcaseChanged`.

**Cost-safe**: são blobs pequenos, escritos só quando o hash muda; o visitante lê 1 doc. Nenhuma leitura de attendance/training_logs de outra academia.

---

## 4. Perfil visitante = JORNADA

### 4.1 Situação atual

`lib/screens/portal/public_profile_screen.dart` tem **dois** caminhos, ambos com as mesmas 3 abas (`TabController length=3`, `:72`):

- `_buildProfile` (`:159`) — mesma academia, tem `student` doc, resolve uid via `student.linkedUserId`, lê `fighterShowcaseProvider(uid)`.
- `_buildShowcaseOnly` → `_buildFighterShowcase` (`:248/:277`) — amigo cross-academy, id = uid, lê só `fighterShowcaseProvider(uid)`. É o caminho cost-safe canônico.

O espelho já carrega tudo que a Jornada precisa de marcos: `graduations[]`, `competitions[]`, `medals`, `currentStreak`, `recordStreak`, `totalTrainings`, `firstTrainingDate`, `lastTrainingDate`, `photoUrl`.

### 4.2 Nova organização

Reduzir para **2 abas: JORNADA | FOTOS** (`TabController length=2`), aplicado nos **dois** caminhos (`:212-216` e `:299-303` / TabBarView `:219-237` e `:306-324`).

**Aba JORNADA** (scroll único):

1. **Painel TREINO PADRÃO** (topo):
   - Dots dos **últimos 3 dias** (de `recentTrainingDays`) — treinou / não / self vs attendance.
   - Card **"N dias sem faltar nas aulas matriculadas"** = `expectedDaysStreak` (decisão #1).
   - Streak atual + **RECORDE** (`currentStreak`/`recordStreak`).
   - Mini-histórico de **sparrings/rolas** (de `sparringSummary`: total, 30d, últimos logs).
2. **MARCOS** (abaixo): merge cronológico **desc** de `graduations[]` + `competitions[]` (o builder já produz ambos com `source` e datas; falta só **intercalar por data** — helper novo, dado já existe), reusando os tiles `_GraduationMarkTile` / `_CompetitionMarkTile` existentes. Incluir milestones de treino se desejado.

**Aba FOTOS**: mantém o conteúdo atual de fotos.

### 4.3 O que o espelho precisa expor (novo)

Já listado em §3.4: `expectedDaysStreak`, `recentTrainingDays`, `sparringSummary`. Sem esses, a Jornada não reflete self-logs nem "últimos 3 dias" nem sparrings — hoje o espelho só tem `lastTrainingDate` (uma única data max, `showcase_builder.dart:98-105`).

O header já consome `photoUrl` no `_showcaseHeader` (`:340,358`) — avatar do visitante **já funciona**; nada a fazer lá.

---

## 5. Avatar do Lutador (hub)

**Problema**: `_Header` em `lutador_hub_screen.dart:160-213` desenha um quadrado com `beltColor` e as **iniciais** (`_initials`, `:179-187`; render `:204-205`). Não recebe `photoUrl`.

**Mudança**:

1. Adicionar parâmetro `photoUrl` ao `_Header` (`:161-177`). Fonte no `build` do hub: `student?.photoUrl ?? user?.photoUrl` (`student.dart:278` tem `photoUrl`; passar em `_Header(...)` no `:78-92`).
2. No container do avatar (`:196-213`): se `photoUrl != null && isNotEmpty` → renderizar a imagem (`ClipRRect` + `Image.network`/`CircleAvatar` com `borderRadius: 14`, mantendo 54x54 e a borda `beltColor` como anel); **fallback** para o `_initials` atual quando não há foto ou a imagem falha (`errorBuilder`).
3. Manter `_initials` como está — vira o fallback.

Nenhuma mudança de dados; `photoUrl` já existe no modelo e no espelho.

---

## 6. Telas / arquivos afetados (file:line)

**Streak (core)**
- `lib/services/attendance_service.dart:354-386` (`getStudentStreak`) e `:391-441` (`getStreakInfo`) — reescrever o walk `diff==1` para dias-esperados; `getStreakInfo` continua a API única (Lutador + `friend_providers` dependem dela). Ampliar `weekDays` para o novo semântico de 4 estados.
- `lib/services/attendance_service.dart:83-101` (`getByStudent`) — fonte attendance da união.
- `lib/services/training_log_service.dart:20-29` — segunda perna da união (expor Set de `dateOnly`; alinhar janela a 365).
- `lib/models/training_log.dart:32,37,41,45,64` — `date`(dateOnly), `sport`, `sparringCount`, `linkedAttendanceId`.

**Dias esperados (config)**
- Novo campo `expectedTrainingDays` em `users/{uid}` — helper de leitura/escrita (StudentService ou novo user-doc helper).
- `lib/services/class_service.dart:22-48` (`ClassSchedule.dayOfWeek` 0..6 — **converter** p/ 1..7), `:51-167` (`BJJClass.studentIds/schedule`), `:164`/`:265-295` (schedule helpers) — derivar default.
- `lib/providers/portal_providers.dart:21-27` (`classesProvider`) → novo `enrolledClassesProvider`.
- `lib/screens/portal/my_sports_screen.dart` — **template** da nova tela "Meus dias de treino".

**Fusão + materialização**
- `lib/providers/friend_providers.dart:66-129` (`myShowcaseProvider`) — ponto de fusão: ler training_logs + expectedDays, chamar novo streak, passar sinais novos ao mirror. Caminho SOLO (sem academyId) novo.
- `lib/providers/friend_providers.dart:97` — `getStreakInfo` por-esporte (card social) também consome o novo modelo.
- `lib/services/showcase_builder.dart:11-40` (`ShowcaseData` + `hash`), `:73-133` (`build`), `:98-105` (`lastTrainingDate` → incluir self) — adicionar `expectedDaysStreak`, `recentTrainingDays`, `sparringSummary`; atualizar hash.
- `lib/services/friend_service.dart:28-92` (`mirror` payload) — gravar campos novos sob gate por hash.
- `lib/models/fighter_profile.dart:202-241` (campos) + `:247-277` (`fromMap` tolerante) — campos novos opcionais.

**UI de consumo**
- `lib/screens/fighter/lutador_hub_screen.dart:341-448` (`_StreakCard`, montado em `:95`) — número + week-strip 4-estados; `:160-213` (`_Header`) — **avatar** (item 5).
- `lib/widgets/portal/home_hero_card.dart:407` — consumo alternativo do streak.
- `lib/screens/portal/public_profile_screen.dart:72` (`TabController` 3→2), `:212-216`/`:299-303` (abas), `:219-237`/`:306-324` (TabBarView), `:463`/`:620-645` (`_ProfileHeader` stats), `:329`/`:393-401` (`_showcaseHeader`) — Jornada.
- `lib/screens/fighter/diario_screen.dart:222,412,422,813-818,1212+` — feed já funde as fontes (precedente); escrita self-log; `_vitrineHero` lê o espelho; **manter** elegibilidade só-attendance.

---

## 7. Roadmap faseado

**Fase 0 — Fundações de dados (sem UI visível)**
- Adicionar `expectedTrainingDays` (leitura/escrita em `users/{uid}`) + helper `deriveDefaultExpectedDays` (converte 0..6→1..7).
- Expor Set de `dateOnly` no `TrainingLogService`; alinhar janela a 365.
- Definir a função pura de streak-por-dias-esperados (§1.4) — testável isolada.

**Fase 1 — Streak novo no Lutador (client-side)**
- Ligar a fusão attendance ∪ self dentro de `myShowcaseProvider` (e caminho SOLO).
- `getStreakInfo` retorna o novo semântico; `_StreakCard` mostra número correto + week-strip 4-estados.
- Materializar `currentStreak/recordStreak` novos no espelho; atualizar `hash`.
- **Valida os 5 exemplos numéricos.**

**Fase 2 — Tela "Meus dias de treino"**
- Clonar `my_sports_screen`; default da turma + edição + manual (sem-academia).
- `enrolledClassesProvider`.

**Fase 3 — Jornada do visitante**
- Materializar `recentTrainingDays` + `sparringSummary` + `expectedDaysStreak` (mirror + FighterProfile + hash).
- Reorganizar `public_profile_screen` para JORNADA | FOTOS (2 caminhos), painel treino padrão + marcos cronológicos.

**Fase 4 — Avatar do Lutador**
- `photoUrl` no `_Header` do hub, fallback iniciais. (Independente; pode ir em qualquer fase — pequeno.)

**Fase 5 (opcional) — Hardening server-side**
- Migrar recálculo de streak para CF em `users/{uid}/stats` se "furar quebra" exigir relógio confiável / anti-abuso.

---

## 8. Rules / agregados novos

- **`expectedTrainingDays`** em `users/{uid}`: **nenhuma rule nova** — coberto por `firestore.rules:260-262` (owner update exceto role/academyId).
- **`fighterProfiles/{uid}`** campos novos (`recentTrainingDays`, `sparringSummary`, `expectedDaysStreak`): **nenhuma rule nova** — leitura por qualquer auth, escrita só dono já vigente (`firestore.rules:302-307`). São aditivos.
- **`users/{uid}/stats`** (só se Fase 5): já é CF-only (`firestore.rules:290-292`) — sem rule nova.
- **`users/{uid}/training_logs`**: sem mudança (owner-scoped já existente).

Nenhum índice novo previsto para o caminho client (as queries — `getByStudent`, `training_logs.orderBy(date)` — já existem). Confirmar índice se a leitura de training_logs alinhada a 365 mudar o `orderBy`/`limit` existente.

---

## 9. Decisões a cravar antes de codar

1. **Weekday canônico = 1..7** (converter `ClassSchedule.dayOfWeek` 0..6 na fronteira). ✔ recomendado.
2. **Recálculo client-side** (barato, mantém padrão) na Fase 1; CF só se necessário. ✔ recomendado.
3. **Streak por-esporte** (não sport-agnóstico) — alinha com `getStreakInfo(sport:)` e `expectedTrainingDays` por-esporte. ✔ recomendado.
4. **Fallback quando `expectedTrainingDays` vazio**: manter streak legado (dias-calendário) como safety-net pra não zerar quem nunca configurou. ✔ recomendado.
5. **Campo dedicado `expectedDaysStreak`** vs. sobrescrever `currentStreak`: recomendo campo dedicado no espelho pra não quebrar semântica legada de consumidores.
