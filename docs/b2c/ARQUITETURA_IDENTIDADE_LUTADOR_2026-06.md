# ARQUITETURA — Fase do Lutador (Identidade person-level sobre base academy-scoped)

> **Status de execução (2026-07):** os dois blocos "genuinamente novos" que
> este doc pedia — `fighterProfiles/{uid}` (mirror público person-level) e o
> trigger `onAttendanceWrite` (materialização event-driven) — **foram
> construídos e estão em produção**. Motor 1 (cards) também shipped. **Motor
> 2/3 (scoreboards, temporadas, ligas) e a descoberta geo (`academyProfiles`/
> geohash) continuam não implementados** — esta arquitetura permanece a
> referência viva para essa parte pendente.

Branch: `firebase-production` · Firestore `arpjj-76350` · Flutter + Cloud Functions + Firestore. Tudo verificado contra o código real; refs são `arquivo:linha`.

**Tese central.** A fundação pessoa↔fichas **já existe e é cost-safe** (`userAcademyMapping/{uid}` + `students.linkedUserId`, ambos com backfill aplicado). Os **dois únicos blocos genuinamente novos** são: (1) um **mirror público person-level keyed por uid** (`fighterProfiles/{uid}`) — o `publicProfiles` atual é academy-scoped por `studentId` e **não serve** descoberta/passaporte; (2) a **materialização event-driven de agregados** começando por um trigger de attendance que **hoje não existe**. Todo o resto é generalização de `syncHighestBelt`, reuso de `CrossAcademyService` como leitura e da allowlist `buildPublicProfileProjection` como projeção única. Nada move docs; tudo **adiciona** coleção/campo/trigger, preservando o legado em prod.

---

## 1. Princípios

**P1 — Dois id-spaces, ponte explícita.** Existem duas identidades no código e essa separação é a raiz de tudo:
- **`uid` global** — `users/{uid}` (`lib/models/user.dart:73-210`): a *pessoa* portátil (email, displayName, photo, `birthDate/cpf/weight`, `jiujitsuStartDate`, `highestBelt/highestStripes`, `isProfilePublic`).
- **`studentId` academy-scoped** — `academies/{academyId}/students/{studentId}` + operacional (`attendance`, `financials`, `beltProgressions`, `achievements`, `timeline`, `firebase_service.dart:30-100`): a *ficha*.
- **Ponte (ativo mais importante):** `userAcademyMapping/{uid}` (`user.dart:212-308`) = join table de **1 doc** com `academyIds[]` + `academyDetails[academyId].{studentId,role,status}`. Toda travessia cross-academy passa por aqui.

**P2 — Source-of-truth operacional permanece academy-scoped.** A academia é dona do attendance/financeiro/graduação que lança. O nível-uid recebe apenas **(a) agregados materializados** (derivados, recomputáveis, nunca confiados do cliente) e **(b) dados que nascem da pessoa** (logs pessoais, grafo social). **Nenhuma migração destrutiva, nenhum doc movido.**

**P3 — Cost-safe é regra dura, não meta:**
- **Zero `collectionGroup` de scan.** Toda travessia cross-academy é dirigida pela lista `academyIds` do mapping (bounded, ~1-5 academias/pessoa). O único `collectionGroup` permitido é **filtrado por `actorId`** (range indexado — feed).
- **Leitura de produto bate em 1 doc materializado** (`fighterProfiles/{uid}`, `users/{uid}/stats/aggregate`, doc de scoreboard), nunca recomputa.
- **Escrita por evento é O(1)** (`FieldValue.increment`), nunca recount do histórico.
- **Contadores sempre materializados** (followers, rollsTogether) — nunca `count()` em runtime de produto.
- **Self-heal por overwrite de snapshot** + ids determinísticos → re-run idempotente (molde `scheduledGamificationMilestones`, `server_functions.js:1457-1800`).

**P4 — PII-safe por allowlist única.** Tudo público lê de um espelho escrito **só por Admin SDK** (`allow write: if false`). Uma única projeção `buildPublicProfileProjection` / `PUBLIC_PROFILE_SAFE_FIELDS` (`server_functions.js:838-882`) alimenta todos os mirrors — evita drift e vazamento. **Allowlist, nunca denylist.**

**P5 — LGPD by design.** Opt-in granular default `FALSE`; geo de pessoa **só geohash truncado** (~cidade), nunca coordenada exata; menores bloqueados server-side; espelho sem PII; direito ao esquecimento por cascata `onDelete`.

**P6 — Não quebrar legado.** Cada passo só adiciona coleção/campo/trigger. App legado ignora o que não conhece. O switch de academia continua sendo trocar 1 string (`selected_academy_provider.dart:17`); toda leitura academy-scoped (ficha/presença/financeiro) intacta.

---

## 2. Modelo de dados

### 2.1 Classificação GLOBAL vs ACADEMY-SCOPED

| Categoria | Onde | Natureza |
|---|---|---|
| **GLOBAL — perfil de lutador** | `users/{uid}` (estender) | identidade portátil |
| **GLOBAL — agregados materializados** | `users/{uid}/stats/aggregate` (doc único privado) | derivado, CF-written |
| **GLOBAL — espelho público person-level** | `fighterProfiles/{uid}` (raiz, novo) | PII-free, CF-written |
| **GLOBAL — logs pessoais** | `users/{uid}/training_logs/{id}`, `users/{uid}/rolls/{id}` | nascem da pessoa |
| **GLOBAL — grafo social** | `users/{uid}/following`, `/followers`, `partners`, `duels` | person-level |
| **SCOPED — source of truth (inalterado)** | `attendance`, `financials`, `beltProgressions`, `achievements`, `timeline`, `students` PII | dono = academia |

### 2.2 `users/{uid}` — campos novos (no `GlobalUser`, `user.dart:73`, todos opcionais, parser tolerante `fromMap:129`)
```
styleTags: [string]      // 'guardeiro','leglock','competidor' — self-declared
discoverable: bool       // master opt-in p/ descoberta; default FALSE
pinnedBadges: [string]
arsenalSummary: map|null // derivado dos rolls (materializado)
```
> `birthDate/cpf/weight` permanecem privados e **nunca** vão para o espelho público.

### 2.3 `users/{uid}/stats/aggregate` — doc agregado materializado privado (NOVO, núcleo)
1 read serve passaporte/wrapped/streak/estrada:
```
totalAttendance: int                 // SOMA across academias
attendanceBySport: {bjj, muaythai, ...}
totalMatTimeMinutes: int
currentStreakDays, longestStreakDays: int
lastTrainingDay: 'YYYY-MM-DD'
firstTrainingAt
milestonesUnlocked: [string]         // autoKeys disparados (idempotência de push)
beltday: { belt, sinceDate }
perAcademy: { academyId: { attendance:int, lastSyncAt } }   // CHAVE da incrementalidade
medalCount: { gold, silver, bronze }
totalRolls: int
followersCount, followingCount: int
updatedAt
```
**`perAcademy` é o que torna o recompute incremental:** o cron soma sub-totais por academia em vez de reler todo o attendance.

### 2.4 Novas coleções pessoais
```
users/{uid}/training_logs/{logId}  // Diário: { date, academyId?, durationMin, techniques[], partners:[uid], notes, feeling, createdAt }
users/{uid}/rolls/{rollId}         // Tapped: { date, submission, opponentBelt, given|received, logId?, createdAt }
partners/{uidA}_{uidB}             // uidA<uidB ordenado; { rollsTogether:int, lastTrainedAt }
duels/{duelId}                     // { aUid, bUid, metric, window, scoreA, scoreB, status }
```

### 2.5 Agregação across academias SEM scan — três gatilhos (espelham padrões em prod)

**A) CF on-write incremental (O(1)/evento, baixa latência).** Trigger `onCreate/onDelete` em `academies/{academyId}/attendance/{id}` (**não existe hoje** — grep confirma triggers só em financials `:607`, competitions `:652`, students `:776/:892`, timeline `:710`):
1. Resolver `uid` via `students/{sid}.linkedUserId`.
2. `FieldValue.increment(±1)` em `stats.perAcademy[academyId].attendance`, `.totalAttendance`, `.attendanceBySport[sport]` (campo `sport` já no attendance).
3. Recomputar streak **só** desse uid (lê day-keys recentes via janela curta), reusando `computeCurrentStreak` (`server_functions.js:1510`).

Isso **aposenta o anti-pattern `syncHighestBelt` client-side** (`global_user_service.dart:325-399` — roll-up no cliente, N reads, sem idempotência): mover roll-up de faixa para CF on-write em `students/{sid}` (estender trigger existente `:892`, não duplicar) escrevendo `users/{uid}.highestBelt` + espelho.

**B) Cron diário de reconciliação (self-heal).** Estender `scheduledGamificationMilestones` (`:1800`, cron `30 7 * * *`): após o passo per-academia, um passo **per-uid** recomputa `stats` somando `perAcademy` (corrige drift de increments perdidos). Iteração try/catch-por-item (molde `scheduledOverdueCheck`). Marcos novos → push gravando autoKey em `milestonesUnlocked` (idempotência, igual `upsertAutoAchievement` `${studentId}_${autoKey}` + `.create()`).

**C) Mirror person-level (CF on-write).** `syncFighterProfile` espelha `users/{uid}` + `stats` → `fighterProfiles/{uid}`, allowlist-based (`buildPublicProfileProjection`). DENY: cpf, weight, birthDate, phone, email, geo exato. Ranking/feed/descoberta leem **só** este mirror.

**Custo:** check-in = 1 increment-write; produto = 1 read; cron = N_academias×alunos 1×/dia (já é o custo do gamification atual). Zero `collectionGroup`.

---

## 3. Grafo social & descoberta GEO + LGPD

**Achado que muda tudo:** o mirror atual é academia-scoped (`academies/{academyId}/publicProfiles/{studentId}`, `server_functions.js:891`, rule `firestore.rules:539-543`). Serve ranking dentro de uma academia; **não serve descoberta regional** (exigiria `collectionGroup('publicProfiles')` sem partição — proibido e caríssimo). Solução: **dois espelhos GLOBAIS na raiz**, keyed por uid/academyId, escritos só por CF.

### 3.1 `fighterProfiles/{uid}` — espelho global da PESSOA
```
displayName, photoUrl, highestBelt, highestStripes,
primarySport, sports[], yearsTraining (derivado — NUNCA birthDate),
styleTags[], pinnedBadges[], totalAttendanceCount,
followersCount, followingCount,
// descoberta / LGPD
discoverable: bool (master, default FALSE),
geoDiscoverable, allowFollow, allowPartnerFinder, showInLeaderboards: bool,
geohashPublic: string,   // TRUNCADO 5 chars (~4.9km) — NUNCA o exato
geoRegion: string,       // 'curitiba-pr' — fallback coarse sem-geo
isMinor: bool,           // derivado server-side; true ⇒ força discoverable=false
geoUpdatedAt, mirrorUpdatedAt
// PROIBIDO: lat, lng, birthDate, cpf, phone, email, address, financeiro, saúde
```

### 3.2 `academyProfiles/{academyId}` — espelho global da ACADEMIA (Mapa do Tatame)
```
name, logoUrl, city, state, geoRegion, styleTags[],
blackBeltsCount, scheduleSummary, openMat{day,time,price,allBelts},
listed: bool (default FALSE), geohash: string (FULL ~9), lat, lng,
mirrorUpdatedAt
```
**Assimetria deliberada de LGPD:** endereço comercial pode ter geo exato; **pessoa nunca** (academy `address/city/state/zipCode` existe em `academy.dart:274-277`, sem lat/lng — geocodar 1× server).

### 3.3 Grafo social — arestas duplas (sem collectionGroup, contadores atômicos)
```
users/{uid}/following/{targetId}   { type:'fighter'|'academy', createdAt }   // quem EU sigo
users/{uid}/followers/{followerUid}{ createdAt }                              // quem me segue
```
Ambas as pontas + contadores em `fighterProfiles` escritos por **callable `toggleFollow`** numa transação — cliente nunca escreve as duas pontas (consistência + check `allowFollow`).

### 3.4 Timeline de atividade (fonte do feed)
```
fighterProfiles/{uid}/activities/{actId}  { actorId:uid, type:'graduation'|'medal'|'milestone', payload, createdAt }
```
Append-only, PII-free, gerado pelas CFs de gamificação/graduação existentes.

### 3.5 Feed — fan-in (pull), NÃO fan-out — justificativa de custo
**Rejeitar fan-out-on-write** (faixa-preta com 50k seguidores graduando = 50k writes). **Adotar fan-in filtrado:**
1. Cliente lê a própria `users/{uid}/following` (1 read-set).
2. `collectionGroup('activities').where('actorId','in', chunkDe10).orderBy('createdAt','desc').limit(30)`.

Isto é `collectionGroup` **FILTRADO por `actorId`** (range indexado, permitido e barato) — diferente do scan proibido. Maioria segue poucos → 1-3 queries. Cache `users/{uid}/feedCache` por CF fica como otimização futura só para power-followers.

### 3.6 Descoberta GEO — query por raio sem scan (geohash-prefix-range sobre coleção raiz)
```
for prefixRange in geohashNeighborRanges(centerCell, radiusKm):   // ≤9 ranges
  fighterProfiles
    .where('discoverable','==',true)
    .where('primarySport','==','bjj')          // opcional
    .where('geohashPublic','>=', lo).where('geohashPublic','<=', hi)
    .limit(k)
merge ⇒ haversine post-filter no cliente
```
≤9 round-trips bounded, zero collectionGroup. `academyProfiles` idem (`listed==true`, geohash full). **Fallback sem-geo:** `where('geoRegion','==','curitiba-pr').orderBy('followersCount','desc')`.

### 3.7 LGPD — garantias
- **Opt-in granular, default FALSE**; sem opt-in o doc nem nasce discoverable.
- **Raio aproximado:** só `geohashPublic` truncado (5 chars ≈ 4.9km); geohash exato de pessoa **nunca armazenado**. Origem coarse = centro da cidade da `primaryAcademy` (`userAcademyMapping.primaryAcademyId` → `academyProfiles.geohash`), **nunca** endereço residencial.
- **Menores por design:** CF lê `users/{uid}.birthDate`, calcula idade; `<18` ⇒ `isMinor=true`, força `discoverable=false`, não emite geohashPublic. Garantia server-authoritative (rules não têm a idade — a CF é a fronteira).
- **Direito ao esquecimento:** `onDelete users/{uid}` cascateia delete de `fighterProfiles/{uid}`, `activities` e arestas (molde de limpeza de órfãos `server_functions.js:800-810`).

### 3.8 Cloud Functions a adicionar (perto do mirror `:891`)
- `syncFighterProfile` — `onWrite('users/{uid}')` **e** `onWrite('userAcademyMapping/{uid}')`: roll-up cross-academia → projeção allowlist → `fighterProfiles/{uid}` (merge). Molde `mirrorStudentPublicProfile:891-919`.
- `syncAcademyProfile` — `onWrite('academies/{id}')`: geocode address→lat/lng/geohash 1× → `academyProfiles/{id}` quando `listed==true`.
- `toggleFollow` (callable) — transação: valida `allowFollow`, escreve 2 arestas, incrementa contadores.
- `setFighterGeo` (callable) — consentimento + ponto aproximado; trunca p/ geohashPublic; respeita `isMinor`.
- `onDelete users/{uid}` — cascata de erasure.

**Dep nova:** `ngeohash` (Node, functions) + helper neighbor-ranges no Dart (`dart_geohash`). Único bloco genuinamente novo.

---

## 4. Motores reutilizáveis

### Spine comum (3 motores)
- **Chave person-level = `uid`**, nunca `studentId`.
- **PII-safe** via `buildPublicProfileProjection` / `PUBLIC_PROFILE_SAFE_FIELDS` (`server_functions.js:838-882`).
- **Fan-out sem `collectionGroup`:** generalizar `forEachMpAcademy(label, handler)` (`server_functions.js:6587`, já faz batching `CRON_ACADEMY_BATCH` + `Promise.allSettled`) → `forEachAcademy(label, filter, handler)`.
- **Queries scoped+indexed:** range em `attendance(date)` (índice single-field auto) + filtro em memória (padrão `RankingService` / `getAttendanceRanking`, `ranking_service.dart:14-90`).
- **Idempotência:** ids determinísticos (`${studentId}_musculacao_${YYYYMMDD}`, `index.js:984`) + overwrite do snapshot computado (molde `scheduledSubscriptionTermGuard`, `server_functions.js:6644`).
- **Pré-requisito bloqueante:** denormalizar **`uid` no doc de evento** (attendance/rolls) na escrita — o check-in já conhece o uid (`verifiedBy:uid`, `index.js:1003`). Backfill dos legados necessário.

### MOTOR 1 — Cards (render + watermark + deep-link). Híbrido, default client-side.
- **(a) Share in-app (95%) → render no Flutter.** `RepaintBoundary → toImage → PNG → share_plus`. Custo servidor $0, offline, watermark = camada de footer no widget tree. Nenhuma escrita.
- **(b) Unfurl como URL (preview p/ quem não tem app) → CF lazy.** Unfurl precisa `og:image`. CF `cardOgImage` renderiza sob demanda no 1º miss com **node-canvas** (não headless browser — gradiente+texto+barra de faixa+QR), grava PNG **content-addressed** no Storage, serve cacheado para sempre.
- **Spec doc (fonte única dos dois renderers, criado só p/ unfurl):**
```
users/{uid}/cards/{cardId}    // global, person-level
cardId determinístico: grad_{sport}_{beltKey} | roll_{rollId} | milestone_{autoKey} | wrapped_{year} | beltday_{year}_{beltKey}
{ type, uid, displayName, photoUrl, belt, stripes, academyName,
  payload:{...}, theme, shareToken, ogImagePath, visibility, createdAt }
```
**Deep-link:** Dynamic Links descontinuado → App/Universal Links próprio `https://grad.link/c/{shareToken}` (revogável). **Custo:** ids determinísticos, PNG imutável content-hashed → card compartilhado N vezes = 1 render; getOrCreate no `ogImagePath` evita render duplicado.

### MOTOR 2 — Agregação/Placar (eventos → doc público sazonal)
Substrato de Mat Wars, Seleção do Estado, leaderboards, desafios, standings de liga. Tensão: eventos academy-scoped de alto volume vs. placar = 1 doc/escopo → increment ingênuo num doc estoura ~1 write/s (turma 19h, 30 check-ins simultâneos = contenção).

- **Modo SCHEDULED (default, mais barato).** Sem trigger on-write. Cron fan-out via `forEachAcademy`: cada academia faz **UMA** query ranged em `attendance(date)` da janela, agrega em memória; o cron reduz por escopo (academy/state/region) **dedupando por `uid`** e faz overwrite do doc público. Freshness = cadência (Mat Wars 6h, leaderboard diário). Escritas = O(escopos)/tick, **não** O(eventos) → 10k check-ins/dia = ~1 write/escopo. Zero hot-spot.
- **Modo LIVE (opt-in, só escopos quentes).** Contador **sharded** on-write:
```
seasons/{seasonId}/scoreboards/{scopeId}/shards/{shardN}   shardN = hash(uid) % K (K≈10)
onCreate('academies/{academyId}/attendance/{attId}') → increment {points:+w, events:+1} no shard
```
Cron leve (5-15 min) soma os K shards e **recomputa** (overwrite) o doc público → tick perdido/duplicado se auto-cura.
- **Doc público (1 read renderiza a tela, sem PII):**
```
seasons/{seasonId}/scoreboards/{scopeId}:
{ seasonId, scopeId, scopeType:'academy'|'state'|'region'|'league_div',
  periodStart, periodEnd, status:'open'|'closed',
  totals:{points,events,members},
  top:[ {uid,name,photoUrl,belt,points,rank} … ≤50 ],   // projeção SAFE
  opponentScopeId, opponentTotals,                        // Mat Wars head-to-head em 1 read
  updatedAt, version }
```
Sazonalidade sob `seasons/{seasonId}` → temporada nova = parent novo; antigas `status:closed` imutáveis (reset limpo, arquivo nunca re-lido).

### MOTOR 3 — Temporadas/Matchmaking (Liga dos Faixas, CF mensal)
Divisões Bronze→Elite por faixa/categoria, acesso/descenso, reset 30 dias. **Consome o Motor 2** (divisão = `scopeType:'league_div'`); cuida só de colocação e virada.
```
leagues/{leagueId}                       config: divisões, eixo faixa/categoria, regras promo/releg, tamanho
leagues/{leagueId}/seasons/{seasonId}    status:scheduled|active|closing|closed
.../seasons/{seasonId}/members/{uid}     { divisionId, groupId, points, rank, name, photoUrl, belt }
.../divisions/{divisionId}/groups/{groupId}  standings ≤30 linhas (mesmo shape do Motor 2)
```
**CF de virada:** `onSchedule({ schedule:'0 4 1 * *', timeZone:'America/Sao_Paulo', timeoutSeconds:540 })`. Passos idempotentes/resumíveis:
1. **Fecha** anterior: lê standings **já materializados** pelo Motor 2 (O(members) reads — **nunca** varre attendance bruto), ordena, aplica top-X sobe / bottom-Y desce.
2. **Semeia** próxima: atribui `divisionId` + **agrupa em pods de ~30** (`groupId = floor(idx/30)` após sort por chave de matchmaking) → standings ≤30 linhas (competição local viva, nunca "solo numa cidade vazia").
3. **Escreve** member docs + groups em **batches ≤500/commit** (`Promise.allSettled`).

**Custo:** ~12 runs pesados/ano (só bordas); durante a temporada `member.points` é atualizado pelo reducer do Motor 2. Member doc keyed por `{uid}` → re-fire após 540s sobrescreve (resumível). Cada usuário lê **um** group doc ≤30 linhas. Matchmaking determinístico (sort estável + uid tiebreak) → re-run = mesma colocação.

**Encaixe dos 3:** Motor 2 = substrato de agregação; Motor 3 re-embaralha o estado denormalizado do 2 nas bordas; Motor 1 renderiza qualquer um em artefato compartilhável (Wrapped = card sobre `totals` do Motor 2). **Onde codar:** novo `functions/engines/` (cards.js, scoreboard.js, seasons.js) reusando helpers de `server_functions.js`; generalizar `forEachMpAcademy`→`forEachAcademy`. Pré-trabalho bloqueante: denormalizar `uid` em attendance/rolls + backfill.

---

## 5. Ponte de migração

A doutrina de prod: **source-of-truth permanece academy-scoped; person-level é derivado. Nunca mover docs.**

### 5.1 O que JÁ é reusável HOJE
| Ativo | Onde | Estado para a ponte |
|---|---|---|
| Identidade global `users/{uid}` | `user.dart:73-210`; rules `:244-275` | Âncora pronta. **Mas só o dono lê** (`:246`) → não serve de fonte pública |
| Índice `userAcademyMapping/{uid}` | `user.dart:212-308` | 1 doc = lista de fichas. Chave de todo fan-out e backfill |
| Join key `students.linkedUserId` | `student_service.dart:307`; backfill idempotente já aplicado | Reverse pointer ficha→uid. **Pré-condição satisfeita** |
| Rollup de faixa `syncHighestBelt(uid)` | `global_user_service.dart:325-399` | Único rollup person-level; client-triggered → **generalizar p/ event-driven** |
| Agregador on-the-fly `CrossAcademyService` | `cross_academy_service.dart:74-332` | Protótipo de leitura do passaporte (beltProgressions, competitionResults, attendance `count()`, medalCount) — falta materializar |
| Mirror PII-safe + allowlist | `server_functions.js:841-924`; rules `:539-543` | `PUBLIC_PROFILE_SAFE_FIELDS` reusável byte-a-byte |
| Ranking server-side `getAttendanceRanking` | `ranking_service.dart:35-95`; `index.js:845` | Padrão de leaderboard p/ regional/ligas |
| Timeline/jornada (scoped) | trigger `server_functions.js:710`; `timeline_builder.dart` | Eventos modelados — falta unificar person-level |
| Catálogo faixas/esportes | `global_user_service.dart:15-46` (`_beltOrder` 21 faixas); `sports.dart` | Comparador cross-sport pronto |

### 5.2 Backfills (quitar antes de ligar features)
| # | Backfill | Por quê | Fonte → destino | Cost-safety |
|---|---|---|---|---|
| **B4** | `status` tipado em `academyDetails` (`active\|pending\|archived\|transferred`) | Passaporte (ativas vs histórico), Transferência | hoje string livre (`user.dart:272`); passar a escrever enum | zero custo; `fromString` forward-compatible. **Faça 1º (grátis)** |
| **B1** | `fighterProfiles/{uid}` inicial | Passaporte/Descoberta/Ligas leem daqui | iterar `userAcademyMapping` → reusar `CrossAcademyService.getStudentGlobalHistory` → projeção PII-safe + agregados | 1 doc/usuário; batches ≤450 (`backfill_public_profiles.js:81-112`); itera índice, nunca collectionGroup |
| **B2** | Agregados iniciais (`totalAttendance`, `medalCount`, `currentStreak`, `lastTrainingAt`, `firstTrainingAt`) | Streak/Wrapped/Recap/Estrada/Ligas | mesmo fan-out de B1 (`count()` por academia `cross_academy_service.dart:219-231`) | usa `count()` agregado (1 leitura/academia, não/presença); streak histórico = varrer datas 1× no backfill, bounded por academia |
| **B3** | `promotedBy` real (linhagem) — **BLOQUEIA a feature** | hoje `promotedBy:'admin'`/`'Administrador'` **literais hardcoded** (`student_detail_screen.dart:4310-4324`, `graduation_screen.dart:918-919`) | **Não há backfill confiável** | corrigir **escritas novas** (uid+nome do staff logado); lineage só pós-correção; admin-enrich manual opcional |
| **B5** | Catálogo curado de eventos reais (IBJJF/AJP) | Passaporte de Competição | coleção `events/` admin-curada | independente; não bloqueia Fase 1 |

**Ordem:** B4 → B1+B2 (juntos, mesmo fan-out) → B3-correção (antes de qualquer lineage) → B5 (Fase 2). B1/B2 idempotentes (set/merge).

### 5.3 Ordem de implementação cost-safe (sem quebrar prod)
- **Passo 0 — Generalizar rollup event-driven (fundação invisível).** Criar CF `onAttendanceWrite` (não existe hoje) → resolve uid via `linkedUserId` → `increment` em `stats` + recomputa streak O(1) + espelha em `fighterProfiles`. Generalizar `syncHighestBelt` para CF disparada por `students/{sid}` onWrite (**estender** trigger `:892`, não duplicar). Não quebra nada (campos/coleções novos).
- **Passo 1 — Mirror `fighterProfiles/{uid}` + rule.** CF mantém o mirror (allowlist reusada). B1 popula histórico. App legado não lê ainda → zero risco.
- **Passo 2 — Passaporte do Lutador.** Lê `fighterProfiles` + `stats` (1 read); fallback `CrossAcademyService` se mirror faltar. Streak/Estrada/Wrapped derivam de B2.
- **Passo 3 — Descoberta (geohash opt-in) + Feed/Linhagem.** `geohashPublic` truncado opt-in; feed = fan-in filtrado; linhagem só após B3.
- **Passo 4 — Ligas/Mat Wars.** Reusa `getAttendanceRanking` + Motores 2/3. **Por último** (precisa densidade + B2 consistente).

**Regra de não-regressão:** cada passo só **adiciona**. Switch de academia = 1 string. Leitura academy-scoped intacta.

### 5.4 Riscos e mitigação
1. **`users/{uid}` não é fonte pública** (rule só dono, `:246`). Ler de terceiros = `permission-denied`. → Materializar tudo público em `fighterProfiles/{uid}`; **nunca** afrouxar read de `users/{uid}`.
2. **Agregados graváveis pelo dono = inflacionáveis** (`:259-262`). → Streak/total/medalha **CF-written** (Admin SDK); mirror `write:false`. Marcar self-reported vs verificado.
3. **Fan-out de backfill custa por academia** (há academias grandes). → `count()` agregado; batches ≤450; fora de pico; idempotente p/ re-run parcial.
4. **`promotedBy` legado é lixo p/ linhagem.** → Lineage não depende de backfill; corrigir escrita 1º; comunicar como limitação de produto.
5. **Drift de allowlist entre mirrors** (academy + person podem divergir/vazar PII). → **Uma única** `buildPublicProfileProjection` (`:866`, já exportada `:923`) alimenta ambos.
6. **Trigger storm/loop** (`onAttendanceWrite` + rollup). → Escrever em coleção **diferente** da observada (doutrina `:888`); `increment`; short-circuit quando nada relevante mudou (`:780-789`).
7. **LGPD na descoberta** (mais sério). → Opt-in granular, geohash truncado nunca coordenada, menores bloqueados default, mirror sempre sem PII.

---

## 6. Rules novas necessárias

Catch-all nega tudo (`firestore.rules:1301`) → cada bloco abaixo é **obrigatório explícito**. Toda escrita de mirror/agregado/grafo é `if false` (Admin-SDK/CF only), espelhando `:542`/`:882`.

**Raiz, após o bloco `users` (`firestore.rules:272`):**
```
match /fighterProfiles/{uid} {
  // query de descoberta filtra discoverable==true ⇒ cada doc retornado passa a rule;
  // dono sempre lê o próprio. Mesmo padrão de publicProfiles :540-541.
  allow read: if resource.data.discoverable == true
              || (isAuthenticated() && request.auth.uid == uid);
  allow write: if false;                       // só Admin SDK / CF
  match /activities/{actId} { allow read: if true; allow write: if false; }
}
match /academyProfiles/{academyId} {
  allow read: if resource.data.listed == true;
  allow write: if false;
}
match /partners/{pairId} { allow read: if isAuthenticated(); allow write: if false; }
match /duels/{duelId}    { allow read: if isAuthenticated(); allow write: if false; }
match /seasons/{seasonId}/scoreboards/{scopeId} {
  allow read: if isAuthenticated(); allow write: if false;
  match /shards/{shardId} { allow read: if false; allow write: if false; }   // só CF
}
match /leagues/{leagueId} {
  allow read: if isAuthenticated(); allow write: if false;
  match /{document=**} { allow read: if isAuthenticated(); allow write: if false; }
}
```

**Dentro de `match /users/{userId}` (após `:271`):**
```
match /stats/{statId}        { allow read: if request.auth.uid == userId; allow write: if false; }  // CF-written
match /training_logs/{logId} { allow read, write: if request.auth.uid == userId; }   // dado pessoal, igual fcmTokens :270
match /rolls/{rollId}        { allow read, write: if request.auth.uid == userId; }
match /cards/{cardId}        { allow read: if request.auth.uid == userId; allow write: if false; }
match /following/{targetId}  { allow read: if request.auth.uid == userId; allow write: if false; }   // grafo via toggleFollow
match /followers/{followerUid}{ allow read: if request.auth.uid == userId; allow write: if false; }
```

**Por que a rule de descoberta funciona:** a query filtra pelo mesmo campo (`discoverable==true` / `listed==true`) que a rule exige — padrão idêntico ao de `publicProfiles` (`firestore.rules:540-541`).

**Índices novos (`firestore.indexes.json`):**
```jsonc
{ "collectionGroup":"fighterProfiles","queryScope":"COLLECTION","fields":[
  {"fieldPath":"discoverable","order":"ASCENDING"},{"fieldPath":"geohashPublic","order":"ASCENDING"}]},
{ "collectionGroup":"fighterProfiles","queryScope":"COLLECTION","fields":[
  {"fieldPath":"discoverable","order":"ASCENDING"},{"fieldPath":"primarySport","order":"ASCENDING"},{"fieldPath":"geohashPublic","order":"ASCENDING"}]},
{ "collectionGroup":"fighterProfiles","queryScope":"COLLECTION","fields":[
  {"fieldPath":"discoverable","order":"ASCENDING"},{"fieldPath":"geoRegion","order":"ASCENDING"},{"fieldPath":"followersCount","order":"DESCENDING"}]},
{ "collectionGroup":"academyProfiles","queryScope":"COLLECTION","fields":[
  {"fieldPath":"listed","order":"ASCENDING"},{"fieldPath":"geohash","order":"ASCENDING"}]},
{ "collectionGroup":"activities","queryScope":"COLLECTION_GROUP","fields":[
  {"fieldPath":"actorId","order":"ASCENDING"},{"fieldPath":"createdAt","order":"DESCENDING"}]},
// pessoais
{ "collectionGroup":"training_logs","queryScope":"COLLECTION","fields":[{"fieldPath":"date","order":"DESCENDING"}]},
{ "collectionGroup":"rolls","queryScope":"COLLECTION","fields":[{"fieldPath":"date","order":"DESCENDING"}]}
```
(geohash range puro é servido pelo single-field automático; os compostos só combinam com `discoverable`/`primarySport`/`geoRegion`. Tudo single/composite scoped — sem fan-out.)

---

**Arquivos-âncora:** `lib/models/user.dart:73,212,267` · `lib/services/firebase_service.dart:30,102` · `lib/services/global_user_service.dart:15,325` · `lib/services/cross_academy_service.dart:74,219` · `lib/services/ranking_service.dart:14` · `lib/models/academy.dart:274` · `functions/server_functions.js:710,838,891,1457,1510,1800,6587,6644` · `functions/index.js:845,984,1003` · `firestore.rules:244,539,1301` · `firestore.indexes.json`. Novos: `lib/models/fighter_profile.dart`, `lib/models/academy_profile.dart`, `lib/services/discovery_service.dart`, `functions/engines/{cards,scoreboard,seasons}.js`.

> Nota: `docs/b2c/PREP_FASE_LUTADOR_2026-06.md` contém só um resumo de geração (não o conteúdo real) — vale regenerá-lo a partir deste documento.