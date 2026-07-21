# Galera — Camada Social de RETENÇÃO (FEED de Parceiros) — Plano (b2c)

> **Status de execução (2026-07):** **implementado e deployado** —
> `feedPosts`, `feed_post.dart`, `feed_posts_service.dart`, `likes` +
> `feed_like_counter.js` (CF), reciprocidade de oss (`oss_providers.dart`).
> A camada de audiência `trainingPairs` (co-presença, Fase 3) continua **não
> construída** — resta como próximo passo.

> **Escopo**: arquitetura ACIONÁVEL da camada social de retenção do app do LUTADOR. NÃO implementado — este doc é o blueprint. READ-ONLY até aqui.
> **Branch**: `b2c`. **Projeto Firestore**: `arpjj-76350`.
> **Evolui**: [`GALERA_PARCEIROS_TREINEI_PLANO.md`](GALERA_PARCEIROS_TREINEI_PLANO.md) — aquele plano fundou PARCEIROS (co-presença → `trainingPairs`) e KUDOS (salve por `targetKey`). Esta rodada **eleva** o kudos-sobre-item-derivado para um **FEED de POSTS materializados**, com **controle de ruído** como decisão central.
> **North star**: RETENÇÃO via loop social — "voltar pra ver/reagir aos parceiros da MINHA academia", sem fricção, denso de sinal, nunca spam.

---

## Resumo executivo — decisões-chave

1. **O feed é materializado, não on-read.** Nasce uma coleção top-level nova `feedPosts/{postId}`. O `friendsActivityProvider` atual (`friend_providers.dart:193-247`) só COLAPSA "1 atividade mais recente por amigo" — estruturalmente insuficiente para múltiplos posts cronológicos, âncora estável de like, flag de exclusão e a aba ACADEMIA. **Substituído por feed de docs reais.**

2. **CONTROLE DE RUÍDO é o coração.** Cinco tipos de post densos de sinal (`graduacao`, `competicao`, `streak_milestone`, `sparring_record`, `weekly_volume`; opcional `mat_milestone`). **JAMAIS 1 post por rola** (5/dia × 10 parceiros = 350/semana = lixo). A rola avulsa e o check-in diário **dobram** dentro do `weekly_volume` agregado (1 card/pessoa/semana). Teto prático em regime: **~1 post/pessoa/semana + marcos raros** ≈ feed DENSO, não spam.

3. **Anti-spam por doc-id DETERMINÍSTICO + create-if-absent.** Cada marco tem id determinístico (`grad_{uid}_{yyyymmdd}_{belt}{stripes}`, `vol_{uid}_{yyyy}W{ww}`, etc.). O produtor só grava se o id AINDA não existe → idempotência + dedupe de marco. Marco é imutável, nunca reescrito. Mesmo truque do `kudos.targetKey`.

4. **Quem produz: o DONO client-side (fase 1-2), reusando o padrão-espelho já provado.** `myShowcaseProvider` (`friend_providers.dart:71-168`) já computa graduações, competições, streak e materializa `fighterProfiles` com gate por hash. Estender esse mesmo pipeline (via novo `FeedPostsService`) para DIFAR os marcos e emitir posts — **ZERO Cloud Function nova** na v1. CF real-time fica para v2, só se a latência owner-driven incomodar. **Exceção**: `weekly_volume` e `academyId` são candidatos naturais a piggyback na CF de parceiros (Fase 3), quando ela existir.

5. **Like reusa o desenho de kudos, agora ancorado a doc real.** Coleção top-level `likes/{postId}_{likerUid}`, doc-id composto anti-spam, sem update. **Excluir o próprio post = FLAG `hiddenByAuthor`** (não delete — o post é regenerável), respeitada pelo produtor via read-before-write.

6. **Amigos-por-código DESCE de centro a canto.** `follows`/`FriendService` continua intacto, mas vira UM papel: adicionar parceiro por CÓDIGO (único caminho cross-academy). O núcleo passa a ser **parceiros auto-populados da própria academia** (colegas de turma + co-presença).

7. **Ordem de valor rápido**: primeiro `graduacao`/`competicao`/`weekly_volume` (dados JÁ computados em `showcase_builder`) → feed vivo com pouco esforço. Depois `streak_milestone`/`sparring_record`. Parceiros por co-presença (`trainingPairs` + CF + backfill) por último — mas a semente **colegas-de-turma** (`class.studentIds`) garante feed não-vazio no dia 1.

---

## 1. Modelo de POST / FEED

### 1.1 Que eventos viram post (e quais NÃO)

**VIRAM POST — 5 tipos densos de sinal (+1 opcional):**

| type | O que celebra | Fonte já existente | Payload |
|---|---|---|---|
| `graduacao` | grau/faixa novos | `ShowcaseBuilder._buildGraduations` (`showcase_builder.dart:142-225`); cada `FighterGraduation` carrega `belt`/`stripes`/`date`/`trainingsToReach`/`monthsToReach` (`:169-180`) | `{belt, stripes, isBeltChange, trainingsToReach, monthsToReach}` → "FAIXA ROXA · 187 AULAS · 14 MESES" |
| `competicao` | pódio/participação | `ShowcaseBuilder._buildCompetitions` (`showcase_builder.dart:232-308`); `FighterCompetitionMark` (name/date/position) | `{name, position}` → "OURO NO OPEN SP" |
| `streak_milestone` | CRUZOU marco de weeks-streak | `computeWeeklyStreak.currentWeeks` (`weekly_streak.dart:65-88`) | `{weeks}` → "8 SEMANAS SEGUIDAS" |
| `sparring_record` | novo recorde pessoal de rolas | `training_log.sparringCount` (`training_log.dart:45`) agregado no owner | `{recorde}` → "MELHOR NOITE: 9 ROLAS" |
| `weekly_volume` | AGREGADO semanal (colapsa toda a atividade da semana) | `attendance` por dia + `sum(sparringCount)` da semana | `{trainings, rolas}` → "3 TREINOS · 14 ROLAS ESSA SEMANA" |
| `mat_milestone` *(opcional)* | tempo-de-tatame/total | `student.totalAttendanceCount` + `firstTrainingDate` | `{marco}` → "250 AULAS" / "1 ANO DE TATAME" |

**NUNCA VIRAM POST:**
- **Rola avulsa individual** (cada save de `sparringCount` em `training_logs`) → 5/dia = spam. Dobra no `weekly_volume`.
- **Cada check-in de attendance / cada training_log diário** → dobra no `weekly_volume`.
- **Streak que só CONTINUA** (sem cruzar marco) → nada.

### 1.2 Onde os posts vivem: coleção MATERIALIZADA, não on-read

**Decisão: coleção top-level `feedPosts/{postId}`, materializada pelo DONO.**

**Por que top-level (não sob `academyId`)**: parceiro por código é cross-academy (`follows`) — mesma razão de `fighterProfiles`/`follows`/`kudos` serem top-level. `academyId` vira **CAMPO** (para a aba ACADEMIA), não path.

**Por que materializada (não on-read)**: on-read (`friendsActivityProvider`, `friend_providers.dart:193-247`) só colapsa 1 atividade/amigo — não suporta múltiplos posts cronológicos, âncora estável de like, flag `hiddenByAuthor`, janela de agregação, nem a aba ACADEMIA.

**Por que o DONO produz (v1, sem CF)**: `myShowcaseProvider` (`friend_providers.dart:71-168`) **já** lê progs/att/comps/streak e materializa `fighterProfiles` com gate por hash (`showcase_builder.dart:37-39`). Estender esse mesmo pipeline para DIFAR os marcos e emitir posts é consistente com a filosofia do plano prévio ("só parceiros justifica CF nova"). Produtor = novo `FeedPostsService` (irmão de `FriendService`, `friend_service.dart:28`), chamado logo após o `mirror()` dentro de `myShowcaseProvider`.

### 1.3 Agregação / anti-spam (o coração)

**Doc-id DETERMINÍSTICO por marco = idempotência + dedupe** (mesmo truque do `kudos.targetKey`, GALERA plan `:126-133`):

```
grad_{uid}_{yyyymmdd}_{belt}{stripes}   // reusa a chave sport|belt|stripes de showcase_builder.dart:181 → 1 post/graduação, nunca duplica
comp_{uid}_{yyyymmdd}_{slug(name)}       // reusa o compKey normalizado de showcase_builder.dart:244-245
streak_{uid}_{weeks}                     // weeks ∈ {4,8,12,26,52} → dedupe por VALOR de marco → bate 1x só
spar_pr_{uid}_{recorde}                  // só quando supera o max anterior
vol_{uid}_{yyyy}W{ww}                    // 1 por autor por semana ISO (_mondayUtc de weekly_streak.dart:52), semana FECHADA
mat_{uid}_{marco}                        // 100/250/500 aulas; 1yr/2yr
```

**Emissão GATED (create-if-absent transacional)**: o produtor só grava um post cujo id determinístico AINDA não existe. Marco imutável → nunca reescreve → nunca des-esconde um post excluído (ver §3).

**Orçamento de ruído em regime**: no máx ~1 post/pessoa/semana (o `weekly_volume`) + marcos raros (graduação a cada meses, streak nos thresholds). Com ~10 parceiros ≈ **10 posts/semana = DENSO**. Contraste: 1-post-por-rola = 5/dia × 10 = **350/semana = lixo**. É o ganho central.

**Thresholds versionados** (constantes p/ dedupe estável — decisão de produto):
```dart
const streakMilestones = [4, 8, 12, 26, 52];       // semanas
const matMilestones    = [100, 250, 500, 1000];    // aulas
const matAnniversaries = [1, 2, 3, 5];             // anos de tatame
```

### 1.4 Campos do post (shape exato)

```
feedPosts/{postId}:
  postId          : string       // == doc-id (determinístico)
  authorUid       : string       // dono do marco (== uid == student.linkedUserId)
  type            : string       // graduacao|competicao|streak_milestone|sparring_record|weekly_volume|mat_milestone
  payload         : map          // type-specific (ver tabela §1.1)
  occurredAt      : Timestamp     // data REAL do evento (grad date, fim da semana ISO...) — ORDENA o feed por acontecimento
  createdAt       : Timestamp     // carimbo do write (serverTimestamp)
  academyId       : string?      // p/ aba ACADEMIA (fan-in por academia); carimbado do student/user na emissão
  hiddenByAuthor  : bool          // default false, SEMPRE gravado no create → filtro server-side confiável
  hiddenAt        : Timestamp?    // quando o autor ocultou
  likeCount       : int           // denorm; mantido por CF onLikeWrite (v2) ou .count() fallback (v1)
  // DENORM de identidade (0 reads no render — padrão trainingPairs/kudos):
  authorName      : string
  authorBelt      : string
  authorStripes   : int
  authorPhotoUrl  : string?
  dedupeKey       : string        // == postId (redundante, documenta idempotência)
```

**Notas de shape:**
- `occurredAt` ordena o feed (o marco importa pela data do ACONTECIMENTO, não do write) — graduação retroativa não fura a ordem.
- `academyId` é CAMPO porque `attendance` não tem `academyId` (é implícito no path, GALERA plan `:23`). O produtor carimba a partir de `user.academyId`/student no momento de emitir.
- Denorm `authorName/Belt` fica stale ao trocar faixa/nome — aceitável (igual kudos); opcional re-hidratar de `fighterProfiles` no render.

---

## 2. Parceiros de treino (a AUDIÊNCIA do feed)

O feed de PARCEIROS lê posts de `authorUid IN [audienceUids]`. A `audienceUids` sai de **duas camadas complementares**, ambas com dado cru já em prod, zero fricção — herdadas do plano prévio.

### 2.1 Camada 1 — Colegas de turma (dia-1, sem espera)

Roster instantâneo de `BJJClass.studentIds` (`class_service.dart:57`, `fromFirestore:120-122`, model `:51-167`). Ler as turmas onde meu `Student.id ∈ studentIds` → a união dos `studentIds` (menos eu) = "minha galera" no primeiro login, **mesmo com `trainingPairs` vazio**. É a semente que garante feed não-vazio enquanto o contador de co-presença amadurece.

### 2.2 Camada 2 — Co-presença verificada (`trainingPairs`, cresce com o tempo)

Definição: dois `studentId` com attendance no MESMO `classId` no MESMO dia treinaram juntos. Agregado `academies/{aid}/trainingPairs/{pairId}` mantido por CF `onDocumentWritten` idempotente (roster via `presentTodayForClass`/`getPresentStudentIds`, `attendance_service.dart:615/280`). **100% greenfield** — coleção, CF, rules, índices e backfill NÃO existem. Detalhe completo do shape/CF/backfill: GALERA plan §1 (`:19-111`). O selo "N vezes juntos" vem daqui.

### 2.3 Ponte studentId ↔ uid (como o feed puxa os posts do parceiro)

`attendance`/`class`/`trainingPairs` usam `Student.id`. `feedPosts`/`fighterProfiles` são chaveados por `uid = Student.linkedUserId` (`student.dart:336/468/523`). Cadeia:

```
meu studentId → trainingPairs (ou class.studentIds) → peer studentId
  → student.linkedUserId → authorUid dos feedPosts
```

Denormalizar `linkedUserIdA/B` no doc de par evita N reads de student ao montar o `whereIn` de `authorUid`. Parceiro **unclaimed** (`linkedUserId == null`) → sem `fighterProfile`, sem posts → aparece só na FAIXA DE PARCEIROS como card name-only (nome+faixa do doc de par), sem link e sem posts.

### 2.4 Demoção do amigos-por-código a cross-academy

Hoje "amigos" é o CENTRO da Galera: enum `_Seg{amigos, academia}` (`cena_screen.dart:40`), aba AMIGOS (`_amigos:123-211`) com card de código preto (`:128-175`), `_bigButton` ADICIONAR AMIGO (`:177-182`), `myFriendsProvider`. Nesta rodada, `follows`/`FriendService` DESCE a UMA função: **adicionar parceiro por CÓDIGO, inclusive cross-academy**. O serviço permanece intacto — `addFriend/removeFriend` (`friend_service.dart:112-129`), `getFriends` (`:136-164`), `findByCode` (`:104-110`). Só reposiciona a UI (ver §4).

**`audienceUids` final (leitor client-side)** = união dedupada por `Student.id`/`uid` de:
- colegas de turma (`class.studentIds` → `linkedUserId`)
- co-presença (`trainingPairs` → peer `linkedUserId`)
- amigos por código (`follows` → `getFriends`, cross-academy)

---

## 3. Like + Excluir

Assimetria ditada pela natureza do post (CF/owner-owned + idempotente): **LIKE = doc real / EXCLUIR = flag**.

### 3.1 LIKE — coleção top-level, doc-id composto (reusa kudos)

```
likes/{postId}_{likerUid}:
  postId      : string   // == doc-id do feedPost
  likerUid    : string   // == auth.uid
  authorUid   : string   // DENORM do post → bloqueia self-like SEM get()
  createdAt   : Timestamp
  likerName   : string   // DENORM p/ "quem curtiu" com 0 reads
  likerBelt   : string
  likerStripes: int
```

**Por que TOP-LEVEL (não subcoleção)**: o feed renderiza N posts de uma vez; com top-level + doc-id determinístico descubro "quais desses eu curti" em **1 leitura batch** `where(FieldPath.documentId, whereIn: ['{p1}_{me}', ... até 30])` — mesmo padrão de `getFriends` (`friend_service.dart:155-161`). Subcoleção quebraria o batch cross-post.

**Contador `likeCount`**: denorm NO DOC do post.
- **v1 (sem CF)**: `.count()` aggregation por post (custa 1 aggregation-read/post; sem did-I-like em lote).
- **v2 (recomendado)**: CF `onLikeWrite` (`onDocumentWritten` em `likes/{id}`: +1 no create, −1 no delete; idempotente por existência do doc), padrão `functions/self_graduation_guard.js:189`. Render O(0) p/ contagem + inforjável (só a CF escreve o post).

**Did-I-like**: sempre o 1 batch `whereIn(documentId)` acima.

**Quem pode curtir**: QUALQUER autenticado que consiga LER o post (parceiro OU academia OU cross-academy) — mesma decisão aberta já abençoada em `follows`/`kudos`. O escopo parceiro-vs-academia fica na QUERY do feed (§4), NÃO na rule (checar `trainingPairs` na rule = `get()` cross-doc caro/frágil).

**Self-like BLOQUEADO** sem `get()`: `authorUid` denormalizado no like doc + rule `likerUid != authorUid`. Cliente poderia mentir o `authorUid` — efeito nulo (só burla o anti-self-like); se quiser rigor, a CF `onLikeWrite` valida vs. o post real e apaga likes forjados.

### 3.2 EXCLUIR o próprio post — flag `hiddenByAuthor`, NÃO delete

Post auto-gerado não pode ser hard-deletado pelo autor: (a) o postId é determinístico/idempotente — se apagasse, a próxima passada do produtor RESSUSCITARIA; (b) padrão de dado CF/owner-owned. Logo "excluir" = o autor levanta uma FLAG durável que o produtor PASSA A RESPEITAR.

- No `feedPost`: `hiddenByAuthor:bool` (default false, gravado no create) + `hiddenAt:Timestamp`.
- **Invariante crítico**: o produtor (`FeedPostsService` / futura CF) faz **read-before-write** — se `hiddenByAuthor == true`, NÃO reescreve. Combinado com create-if-absent (§1.3), a supressão gruda contra regeneração. Reversível, preserva `likeCount`/histórico.
- Feed filtra **server-side** `where('hiddenByAuthor', isEqualTo: false)` → post escondido nunca sai do servidor (economia + privacidade). Exige o campo presente em TODO post → **backfill `hiddenByAuthor:false` nos legados** antes de expor.

### 3.3 Rules

```javascript
// feedPosts — CF/owner materializa; autor só oculta.
match /feedPosts/{postId} {
  allow read: if isAuthenticated();                 // escopo pela QUERY (§4)
  // v1 owner-produz: create pelo próprio autor com id determinístico.
  // v2 CF-produz: trocar para `allow create: if false;` (Admin SDK).
  allow create: if isAuthenticated()
    && request.resource.data.authorUid == request.auth.uid
    && request.resource.data.hiddenByAuthor == false;
  allow delete: if false;                            // nunca hard-delete
  // Update ESTREITO: só o autor, só a flag de ocultar (molde firestore.rules:260-262).
  allow update: if isAuthenticated()
    && resource.data.authorUid == request.auth.uid
    && request.resource.data.diff(resource.data).affectedKeys()
         .hasOnly(['hiddenByAuthor', 'hiddenAt']);
}

// likes — reusa 1:1 o molde de follows (firestore.rules:311-321).
match /likes/{likeId} {
  allow read: if isAuthenticated();
  allow create: if isAuthenticated()
    && request.resource.data.likerUid == request.auth.uid
    && request.resource.data.likerUid != request.resource.data.authorUid
    && likeId == request.resource.data.postId + '_' + request.resource.data.likerUid;
  allow delete: if isAuthenticated() && resource.data.likerUid == request.auth.uid;
  // sem update → contador (no post) não forjável; doc-id composto → 1 like/par (anti-spam)
}
```

> **Nota v1 vs v2**: na v1 (owner-produz) o `create` de `feedPosts` é liberado ao próprio autor — o autor forjar posts falsos sobre SI MESMO tem valor de abuso baixo (é o próprio perfil dele). Na v2 (CF-produz) troca-se para `create: if false` (só Admin SDK, molde `stats` `firestore.rules:288-292`) e `likeCount` passa a inforjável.

---

## 4. Galera 2 abas + Lutador preview 3 posts

Estilo fighter: bone/ink + UM acento blood, eyebrow caps w800, cards white radius 14. Sem emoji. Reusar 100% dos tokens: `_White` (`cena_screen.dart:946`), `_Voice` (`:963`), `_Loading` (`:972`), `_FriendRow`/`_MiniBelt` (`:855-892`), `_eyebrow` (`:37`).

### 4.1 GALERA (`cena_screen.dart`) — 2 abas

Trocar `enum _Seg { amigos, academia }` (`:40`) por `{ parceiros, academia }` e default `_seg = _Seg.parceiros` (hoje `:53` começa em academia). Header 'GALERA' (`:66`) mantém. Segmented `_Segmented` (`:292`) vira `[ PARCEIROS | ACADEMIA ]` (labels `:308-309`). Branch em `:78`: `if (_seg == _Seg.academia) ..._academia() else ..._parceiros()`.

**ABA 1 · PARCEIROS** (novo `_parceiros()`, substitui `_amigos():123-211`), de cima pra baixo:
- **(a) FAIXA DE PARCEIROS** — avatares mini-belt em linha horizontal scrollável (reuso do quadrado belt-color de `_FriendRow:881-892` + `_MiniBelt`), com contagem 'N PARCEIROS'. Auto-populado (§2). Tap → `/portal/profile/{uid}`.
- **(b) AÇÃO SECUNDÁRIA 'adicionar por código'** — slim-row discreta (NÃO o card preto gigante de hoje). Link/botão outline pequeno + chip do meu código copiável. Reusa `_showAddFriend:213` → `_AddFriendSheet:692` + `myFighterCodeProvider:124`. O card preto SEU CÓDIGO (`:128-175`) e o `_bigButton` ADICIONAR AMIGO (`:177-182`) são DEMOVIDOS pra dentro da sheet.
- **(c) FEED** — lista de POST CARDS (`_White` template) via novo `feedPostsProvider`, ordenados por `occurredAt` desc. Cada card:
  - header: quadrado belt-color 44px (initials) + NOME caps w900 + timestamp relativo (reusa `_ActivityRow._ago`, `lutador_hub_screen.dart:845`).
  - corpo: HEADLINE densa. AGREGADO: "PEDRO · 3 TREINOS ESSA SEMANA · 14 ROLAS". MARCO: "SUBIU PRA ROXA" / "8 SEMANAS SEGUIDAS" / "MELHOR NOITE: 9 ROLAS". Ícone tipo à direita (award/medal/flame — switch de `_ActivityRow:750-754`).
  - footer: LIKE PILL (coração/chama outline → filled blood quando byMe) + contagem tabular. Toggle otimista via `ref.invalidate`.
  - SE MEU post: overflow '...' → ação única 'OCULTAR' (seta `hiddenByAuthor=true`).
  - estados: `_Loading`; empty via `_Voice` ("Seus parceiros ainda não postaram. Quando treinarem, graduarem ou baterem marco, aparece aqui.").
- **Query (aba 1)**: `where('authorUid', whereIn: [audienceUids em lotes de 10]) && where('hiddenByAuthor', ==, false) orderBy('occurredAt', desc) limit N`. Índice `(authorUid, hiddenByAuthor, occurredAt desc)`.

**ABA 2 · ACADEMIA** (mantém `_academia():86-120`, reenquadrada como feed amplo):
- RANKING DA ACADEMIA (`_RankingCard:377`), CONQUISTAS DA ACADEMIA (`_AchievementsFeed:475` → `_AchRow:509`), CAMPEONATOS (`:104-119`).
- **De onde vem o feed amplo HOJE**: `academyRecentAchievementsProvider` (`student_provider.dart:269`) → `AchievementService.getRecent(limit:40)` (`achievement_service.dart:350`) já lê a coleção `academies/{id}/achievements` INTEIRA (academy-wide por natureza, sort date desc). O feed "geral da academia" JÁ existe estruturalmente — basta manter.
- **Evolução opcional**: colar o mesmo LIKE PILL no `_AchRow:509` (like em conquista alheia da casa). E/OU migrar para query em `feedPosts`: `where('academyId', ==, meuAcademyId) && where('hiddenByAuthor', ==, false) orderBy('occurredAt', desc) limit N`. Índice `(academyId, hiddenByAuthor, occurredAt desc)`. Migrar só quando o volume de posts justificar; até lá `getRecent` basta.

### 4.2 LUTADOR (`lutador_hub_screen.dart`) — preview dos últimos 3 posts

- `_FriendsSection` (`:644`): título 'AMIGOS' (`:657`) → 'PARCEIROS' (barrinha blood `:655` fica). 'ver tudo' (`:659-666`) já aponta `context.go('/portal/cena')` → abre a Galera em PARCEIROS (default novo) — perfeito.
- `_FriendsActivityCard` (`:709`, hoje top 3 via `friendsActivityProvider`) evolui p/ mostrar os ÚLTIMOS 3 POSTS dos parceiros no MESMO mini-formato, reusando `_ActivityRow` (`:742`) como base (já renderiza nome/label/ago/ícone `:755-804`) — adicionar like pill inline. `take(3)` em `:723` sobre o novo `feedPostsProvider`.
- `_addFriendsCard` (`:675`) e empty (`:714-722`) mantidos, copy 'amigos' → 'parceiros de treino'. Tap num post → `/portal/profile/{uid}` (já em `:756`).

**Loop de retenção**: Lutador (preview 3) → 'ver tudo' → Galera aba Parceiros (feed completo + like) → tap perfil parceiro → volto e reajo. **Fechado sem sair da própria academia.**

---

## 5. Telas / arquivos afetados (file:line)

### Produção do feed (novo)
- **NOVO** `lib/services/feed_posts_service.dart` — `FeedPostsService` (irmão de `FriendService`, `friend_service.dart:28`): `emitIfAbsent(post)` (create-if-absent transacional), `hide(postId)` (update flag), `feedForAudience(authorUids)`, `feedForAcademy(academyId)`, `didILike(postIds)` (`whereIn(documentId)` lotes de 30), `like/unlike`.
- **NOVO** `lib/services/like_service.dart` OU dentro de `FeedPostsService` — `like/unlike` (`likes/{postId}_{likerUid}`).
- Estender `myShowcaseProvider` (`friend_providers.dart:71-168`): após `mirror()` (`:128-145`), DIFAR marcos novos vs. já emitidos e chamar `emitIfAbsent`. Fontes já no escopo: `showcase.graduations` (`:141`), `showcase.competitions` (`:142`), `streak` (`:113/121`), `att` (`:91`) p/ `weekly_volume`, `selfLogs` (`:108`) p/ `sparring_record`.

### Fontes de marco (só leitura — já computadas)
- `showcase_builder.dart:142-225` (`_buildGraduations`; effort/date `:169-180`; chave `sport|belt|stripes` `:181` = base do `grad_` id).
- `showcase_builder.dart:232-308` (`_buildCompetitions`; `compKey` normalizado `:244-245` = base do `comp_` slug).
- `weekly_streak.dart:65-118` (`computeWeeklyStreak`; `currentWeeks:82-88`; `_mondayUtc:52` = semana ISO do `vol_`).
- `training_log.dart:45` (`sparringCount`); `TrainingLogService.recent` (via `friend_providers.dart:108`).

### Leitura / providers (evoluir)
- `friend_providers.dart:172-186` (`FriendActivity`) e `:193-247` (`friendsActivityProvider`) — SUBSTITUÍDOS por `FeedPost` model + `feedPostsProvider` (audience) + `academyFeedProvider` + `likedPostIdsProvider` (irmão).
- `friend_providers.dart:56` (`myFriendsProvider`) — permanece, alimenta a camada `follows` da `audienceUids`.

### UI Galera (`cena_screen.dart`)
- `:40` enum `_Seg{amigos,academia}` → `{parceiros,academia}`; `:53` default → parceiros; `:78` branch; `:292-337` `_Segmented` labels `:308-309`.
- `:123-211` `_amigos()` → novo `_parceiros()` (faixa + slim-row código + FEED). Código preto `:128-175` + `_bigButton:177-182` demovidos.
- `:213` `_showAddFriend` + `:692` `_AddFriendSheet` + `:124` `myFighterCodeProvider` — reuso na sheet.
- `:86-120` `_academia()` — aba 2 (mantida); `:475-575` `_AchievementsFeed`/`_AchRow` — like pill opcional.
- Tokens: `:946` `_White`, `:963` `_Voice`, `:972` `_Loading`, `:855-892` `_FriendRow`/`_MiniBelt`, `:37` `_eyebrow`.

### UI Lutador (`lutador_hub_screen.dart`)
- `:644-673` `_FriendsSection` (título `:657` AMIGOS→PARCEIROS); `:675-705` `_addFriendsCard` (copy).
- `:709-740` `_FriendsActivityCard` (top 3 → últimos 3 POSTS); `:742-864` `_ActivityRow` (+ `_ago:845`, switch ícone `:750`) — base do mini post card + like pill inline.

### Fontes de audiência (parceiros)
- `class_service.dart:57` (`BJJClass.studentIds`), `:120-122`, `:51-167` — colegas de turma.
- `attendance_service.dart:615` (`presentTodayForClass`), `:280` (`getPresentStudentIds`) — roster p/ CF `trainingPairs` (Fase 3).
- `student.dart:336/468/523` (`linkedUserId`) — ponte studentId→uid.
- `friend_service.dart:104-164` (`findByCode`/`addFriend`/`getFriends`) — cross-academy por código.

### Rotas
- `app.dart:665` `/portal` = LutadorHub; `:669` `/portal/cena` = Cena.

---

## 6. Rules / CFs / agregados / índices novos

| Item | Tipo | Local | Observação |
|---|---|---|---|
| `feedPosts/{postId}` | Coleção + rule | `firestore.rules` (top-level, molde `follows` `:311`) | read=autenticado; create pelo autor (v1) ou `false` (v2 CF); delete `false`; update estreito só `hiddenByAuthor`/`hiddenAt` (molde `:260-262`) |
| `likes/{postId}_{likerUid}` | Coleção + rule | `firestore.rules` (molde `follows` `:311-321`) | create `likerUid==auth.uid` && `!=authorUid` && id composto; delete pelo liker; sem update |
| CF `onLikeWrite` *(v2)* | Cloud Function `onDocumentWritten` | `functions/` (padrão `self_graduation_guard.js:189`) | fan-in de `likeCount` no post (+1 create / −1 delete); torna a contagem inforjável |
| CF `onPairAttendanceWrite` *(Fase 3)* | Cloud Function `onDocumentWritten` | `functions/` | mantém `trainingPairs` (co-presença) + candidato a piggyback `weekly_volume`/`mat_milestone` real-time |
| `academies/{aid}/trainingPairs/{pairId}` | Coleção + rule + índice | `firestore.rules` (§ GALERA plan `:81-90`) | read se sou um dos studentIds; write `false` |
| Índice `feedPosts (authorUid, hiddenByAuthor, occurredAt desc)` | Índice | `firestore.indexes.json` | aba PARCEIROS (fan-in `whereIn` 10/lote) |
| Índice `feedPosts (academyId, hiddenByAuthor, occurredAt desc)` | Índice | `firestore.indexes.json` | aba ACADEMIA |
| Backfill `feedPosts` histórico | one-off | `functions/scripts/` (padrão `backfill_instructor_permissions.js`) | semeia graduações/competições do showcase já materializado + grava `hiddenByAuthor:false`; senão o feed nasce ralo |
| `streakMilestones`/`matMilestones` | Constantes versionadas | Dart shared const | dedupe estável dos ids `streak_`/`mat_` |

**Sem novo backend para**: like v1 (`.count()` fallback), excluir (flag client-write). **CFs novas**: `onLikeWrite` (v2, opcional) e `onPairAttendanceWrite` (Fase 3, herdada do plano prévio).

---

## 7. Roadmap faseado (valor rápido primeiro)

### Fase 0 — Reorganização de UI + demoção do amigos (zero backend novo)
- Galera: `_Seg{parceiros,academia}` + default parceiros; `_parceiros()` com FAIXA DE PARCEIROS (de `getFriends` + `class.studentIds`) + slim-row código; aba ACADEMIA mantida.
- Lutador: título AMIGOS→PARCEIROS; copy.
- **Por que primeiro**: aditivo, sem migração, sem rules — reposiciona o app em torno de "parceiros" antes de o feed existir. Feed ainda usa `friendsActivityProvider` transitoriamente.

### Fase 1 — Feed materializado com dados JÁ computados
- Coleção `feedPosts` + rules + índices; `FeedPostsService.emitIfAbsent`.
- Estender `myShowcaseProvider` p/ emitir `graduacao` + `competicao` + `weekly_volume` (tudo já em `showcase_builder`/`att`).
- `feedPostsProvider` + substituir `_FriendsActivityCard`/`_ActivityRow` e o FEED da aba Parceiros por posts reais.
- Backfill histórico (graduações/competições do showcase) — senão feed nasce ralo.
- **Por que**: destrava o FEED real com o menor esforço (fontes prontas). Controle de ruído nasce aqui (`weekly_volume` + dedupe determinístico).

### Fase 2 — Like + Excluir + marcos restantes
- `likes` + rules + índice; like pill em `_ActivityRow` e post cards; did-I-like batch; `.count()` v1 (ou CF `onLikeWrite`).
- Flag `hiddenByAuthor` + rule update estreita + read-before-write no produtor + filtro server-side.
- Emitir `streak_milestone` + `sparring_record` (+ `mat_milestone` opcional) com thresholds versionados.
- **Por que**: fecha o loop de reciprocidade (like) e dá controle ao autor (excluir) sobre o feed já vivo.

### Fase 3 — Parceiros por co-presença (CF + backfill — maior peso)
- CF `onPairAttendanceWrite` (`onWrite` idempotente) + `trainingPairs` + rules + backfill (§ GALERA plan §1, `:327-332`).
- Selo "N vezes juntos" na FAIXA DE PARCEIROS; merge por `Student.id` no leitor; fallback name-only p/ unclaimed.
- Opcional: piggyback `weekly_volume`/`mat_milestone` real-time na CF (elimina a latência owner-driven).
- **Por que por último**: único componente com CF nova + backfill + custo de write; a semente colegas-de-turma (Fase 0) já garante feed não-vazio até aqui.

**Ordem de deploy de cada fase que toca dados** (runbook): **backfill → rules/índices → CF → app**.

---

## 8. Invariantes e gaps a proteger

1. **create-if-absent é sagrado**: o produtor JAMAIS reescreve um id determinístico existente — senão des-esconde um post excluído (`hiddenByAuthor`) e churna o feed. Marco = imutável.
2. **read-before-write respeita `hiddenByAuthor`**: acoplamento único entre produção e exclusão. Documentado como invariante.
3. **`weekly_volume` só da semana FECHADA**: emitir para a semana ISO já encerrada (imutável) → número completo, sem churn. Custo: post aparece com alguns dias de lag.
4. **`academyId` carimbado na emissão**: `attendance` não tem o campo (implícito no path); o produtor resolve de `user.academyId`/student.
5. **`hiddenByAuthor:false` em TODO post**: filtro server-side depende do campo presente → backfill obrigatório nos legados.
6. **Latência owner-driven (v1)**: post de um parceiro só nasce quando ESSE parceiro reabre o app. Aceitável p/ usuários ativos; v2 = CF real-time se incomodar.
7. **Fan-in `whereIn` limitado a 10/lote** (30 p/ `documentId`): batchear `audienceUids` como `getFriends` (`friend_service.dart:155`).
8. **Denorm stale** (nome/faixa do autor/liker): aceitável (igual kudos); opcional re-hidratar de `fighterProfiles` no render.
9. **Unclaimed** (`linkedUserId == null`): sem `fighterProfile`, sem posts → só aparece name-only na faixa, nunca no feed de posts.
10. **Normalização do slug de competição**: reusar `compKey` normalizado (`showcase_builder.dart:244-245`) para o id `comp_` estável.
