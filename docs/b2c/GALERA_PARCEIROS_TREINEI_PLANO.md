# Galera / Parceiros / Treinei — Plano de Evolução (b2c)

> **Escopo**: arquitetura acionável para 4 evoluções do app do LUTADOR. NÃO implementado ainda — este doc é o blueprint.
> **Branch**: `b2c`. **Projeto Firestore**: `arpjj-76350`.
> **Princípio-guia**: dado real e verificado > ego. A peça central é **PARCEIRO DE TREINO** descoberto por co-presença, não "amigo por código".

---

## Resumo executivo — decisões-chave

1. **Parceiros de treino = co-presença verificada, descoberta pelo servidor.** Dois `studentId` com attendance na **mesma turma + mesmo dia** treinaram juntos. Já existe a query de roster (`presentTodayForClass`, `getPresentStudentIds`) e o dado é verificado (chamada do professor). **Decisão de custo/trigger: Cloud Function `onDocumentWritten` na attendance que mantém um contador de par idempotente** — paga o custo 1x no check-in (amortizado por presença), a leitura da Galera vira O(nº de parceiros). O modelo client-side foi **rejeitado** (varreria ~195 presenças × query de roster por abertura de tela = milhares de reads sem teto).
2. **Idempotência é obrigatória** por causa do `bulkMarkPresent` (WriteBatch → N triggers concorrentes que se veem mutuamente). Solução: marcador de sessão `trainingPairs/{pairId}/sessions/{classId}_{YYYYMMDD}` em transação; só incrementa se o marcador não existia. Trigger é `onWrite` (create **e** delete) para fechar o gap de unmark.
3. **Kudos/salve = v1 SEM Cloud Function**, espelhando 1:1 o sistema `follows` já abençoado nas rules. Doc-por-reação `kudos/{giverUid}_{targetKey}` com `targetKey` **determinístico** derivado do espelho público. Contagem por batch `whereIn` no render. Push fica pra v2.
4. **Treinei dois números — o backend JÁ está separado por coleção** (`attendance` = dura; `training_logs` = diário). O medo de "self-log inflando ranking" é **estruturalmente falso hoje**. O trabalho é de **rótulo/UI**: nomear **AULAS VERIFICADAS** (dura, vale ranking+graduação) vs **SESSÕES DE TATAME** (diário, inclui avulsos). Ranking já é 100% verificado por período — só falta o selo de confiança.
5. **Nota de técnica — 70% já existe.** Campo `note` está morto no model (nunca escrito pela UI); tags `techniques` já funcionam via `_patchLog`. Falta: 1 TextField "FOCO DO DIA" + a **biblioteca de técnicas** agregada em `SparringEngine.compute` (reuso zero-read dos 300 logs já carregados).

---

## 1. Parceiros de treino — o MODELO

### O dado já existe e é verificado
- Presença vive em `academies/{academyId}/attendance/{id}` (`Collections.attendance` — `lib/services/firebase_service.dart:41`).
- Modelo `Attendance` carrega `studentId`, `classId`, `date`, `sport`, `weight` (`lib/services/attendance_service.dart:8-61`). **Não há campo `academyId`** — ele é implícito no path da coleção.
- Id do doc é determinístico por dia: `{studentId}_{classId}_{YYYYMMDD}` (`_deterministicAttendanceId`, `attendance_service.dart:630`).
- **Definição de co-presença**: dois `studentId` com attendance no **mesmo `classId` no mesmo dia** treinaram juntos.
- Query de roster pronta e indexada (índice composto `classId ASC, date DESC` já declarado): `presentTodayForClass(classId)` (`attendance_service.dart:615`) e `getPresentStudentIds(classId, date)` (`:280`).
- Turmas (`BJExClass`, `lib/services/class_service.dart:51-167`, `studentIds:57`, `schedule:58`) **não** são necessárias para derivar parceria — a co-presença sai direto da attendance, o que é melhor: captura aula aberta / QR / aula-particular, não só a matrícula.

### Ponte crítica studentId ↔ uid
- attendance e o par usam `Student.id` (doc da academia).
- `fighterProfiles` é chaveado por `uid = Student.linkedUserId` (`lib/models/fighter_profile.dart:202-292`; rule `firestore.rules:302-308`).
- **Cadeia**: meu `studentId` → `trainingPairs` → peer `studentId` → `student.linkedUserId` (`lib/models/student.dart:336/468/523`) → `fighterProfiles/{linkedUserId}`.
- Aluno **unclaimed** (sem app) não tem `linkedUserId` → sem fighterProfile → precisa de **fallback name-only** na Galera (PII ok, mesma academia).

### Arquitetura recomendada: CF `onWrite` agregando contador de par

**Por que NÃO client-side**: montar "seus parceiros" on-demand varreria as ~195 presenças e, para cada `(classId, dia)`, faria uma query de roster (~10-30 docs) → milhares de reads **toda vez** que a Galera abre, custo crescente e sem teto. O trigger paga o custo **uma vez** no check-in (amortizado 1/presença) e a leitura vira O(nº de parceiros).

**Custo por sessão de n alunos**: ~n reads de roster + até C(n,2) writes idempotentes, **uma vez no dia** — vs. milhares de reads por abertura de tela no modelo client-side.

#### Shape do doc de par
`academies/{academyId}/trainingPairs/{pairId}`

- `pairId = "${min(sA,sB)}__${max(sA,sB)}"` — simétrico/ordenado (par não-direcional, 1 doc por dupla).
- Campos:
  ```
  studentIdA, studentIdB          // ordenados (min, max)
  count            : int          // nº de dias que treinaram juntos
  firstTrainedAt   : Timestamp
  lastTrainedAt    : Timestamp
  countBySport     : map<string,int>   // opcional: {bjj, muaythai, ...}
  // DENORMALIZAÇÃO de identidade (evita N reads de student na Galera):
  nameA, nameB
  beltA, beltB
  linkedUserIdA, linkedUserIdB   // null se unclaimed → card name-only
  ```
- Denormalizar identidade dos dois lados permite a Galera renderizar e linkar ao fighterProfile **sem N reads de student**.

#### Marcador de sessão (idempotência)
`academies/{academyId}/trainingPairs/{pairId}/sessions/{classId}_{YYYYMMDD}`
- Existência = "este par já foi contado neste (aula, dia)". Torna o contador imune a ordem de chegada **e** ao `bulkMarkPresent`.

#### Trigger
`onDocumentWritten` em `academies/{academyId}/attendance/{id}` — mesmo padrão de `functions/self_graduation_guard.js:189`.

- **onCreate** (attendance nasceu):
  1. Recompute o roster de `(classId, dia)` via a query de `attendance_service.dart:615` (server-side, Admin SDK).
  2. Para o par `(novo aluno, cada peer já presente)`, dentro de uma **transação**:
     - Se `sessions/{classId}_{YYYYMMDD}` **não** existe → cria o marcador e `count += 1`, atualiza `lastTrainedAt` (e `firstTrainedAt`/denorm na 1ª vez), `countBySport[sport] += 1`.
     - Se existe → no-op (já contado).
  3. Resolve `linkedUserId`/nome/faixa lendo o student doc (`Collections.student` — `firebase_service.dart:75`) **só na 1ª vez** que grava o par (cacheável).
- **onDelete** (unmark — `attendance_service.dart:644/778`):
  - Se o marcador de sessão existe **e** o roster do dia daquele par ficou `< 2` → remove o marcador e `count -= 1`. Fecha o gap de "contador só cresce".

> **Por que `onWrite` e não `onCreate`**: unmark/delete (`attendance_service.dart:644-662`, `:778-821`) precisam decrementar, senão o contador nunca desce.

#### Privacidade (mesma academia)
- `trainingPairs` **nasce sob a academia** → scope automático, impossível cruzar academias por engano.
- Rule (reaproveita helper de `firestore.rules:657`):
  ```
  match /academies/{aid}/trainingPairs/{pairId} {
    allow read: if isOwnStudentRecord(aid, resource.data.studentIdA)
             || isOwnStudentRecord(aid, resource.data.studentIdB);
    allow write: if false;   // só Admin SDK / CF (padrão firestore.rules:324)
  }
  match /academies/{aid}/trainingPairs/{pairId}/sessions/{sid} {
    allow read: if false;    // interno; contador já está no doc-pai
    allow write: if false;
  }
  ```
- **Você só enxerga OS SEUS pares** — imune ao ego, sem vazar o grafo alheio.

#### Como aparece na Galera / Lutador
- 2 queries em `trainingPairs`: `where studentIdA == meuSid` **OR** `where studentIdB == meuSid`, `orderBy count desc`.
- Renderiza **"Você e o Pedro treinaram 47 vezes juntos"** (usar `lastTrainedAt` para "última vez há X").
- Se `peer.linkedUserId != null` → linka a `fighterProfiles/{linkedUserId}` (tap → `/portal/profile/{uid}`).
- Se `null` (unclaimed) → **card name-only** (nome + faixa do próprio doc de par, sem link).

#### Fallback / cross-academy
- O **código de amigo continua** para cross-academy: `follows/{a}_{b}` + `friend_service.dart:112-164`. É **ortogonal** — dentro da academia o app **descobre** o parceiro; fora dela o vínculo é por código.

#### Backfill histórico
- "47 vezes juntos" só nasce a partir do deploy do trigger. Um **script one-off** (padrão `functions/scripts/backfill_instructor_permissions.js`) varre a attendance por academia, agrupa por `(classId, YYYYMMDD)`, gera os pares e escreve `count/firstTrainedAt/lastTrainedAt/denorm`. **Rodar antes de expor a feature.**

### Gaps a fechar (parceiros)
- Idempotência por `(par, classId, dia)` obrigatória por causa do `bulkMarkPresent` (`attendance_service.dart:678`).
- `trainingPairs` é greenfield: coleção, rule e índices novos. CF que escreve dado social também é padrão novo (hoje o dono escreve fighterProfiles client-side).
- Sem `academyId` como campo na attendance → o par **precisa** nascer sob o path da academia.
- Parceiro unclaimed → fallback name-only.
- Backfill obrigatório para o número histórico.
- Trigger `onWrite` (create+delete), nunca só `onCreate`.

---

## 2. Kudos / Salve — modelo + rules + onde aparece + loop

### O social atual (base)
- Grafo: `follows/{followerUid}_{targetUid}` — `friend_service.dart:112-164` (`addFriend`/`getFriends`, whereIn em lotes de 10). Rules `firestore.rules:311-321`.
- Espelho público PII-free: `fighterProfiles/{uid}` (`friend_service.dart:28-92 mirror()`). Rules `firestore.rules:302-308` (read = qualquer autenticado, write = dono).
- Feed derivado: `friendsActivityProvider` (`lib/providers/friend_providers.dart:177-231`) emite `FriendActivity{friend, tipo, date, label}` (`:156-170`) lendo **só a vitrine materializada** — ZERO reads extras. `tipo ∈ graduacao | competicao | treino`.
- Render: `lutador_hub_screen.dart` `_FriendsSection:584` → `_FriendsActivityCard:649` (top 3) → `_ActivityRow:682-745`.
- Galera (`cena_screen.dart`): aba ACADEMIA `_AchievementsFeed`→`_AchRow:509-555`; aba AMIGOS `_amigos():123-211`.

### Problema-chave: itens de atividade são DERIVADOS
Não há doc de atividade nem id estável. **Solução: `targetKey` determinístico** derivado da vitrine pública, calculado idêntico no hub e no service:
- treino: `train_{uid}_{yyyymmdd(lastTrainingDate)}`
- graduação: `grad_{uid}_{yyyymmdd}_{belt}{stripes}`
- competição: `comp_{uid}_{yyyymmdd}_{slug(name)}`

Adicionar getters `targetKey` / `targetType` / `targetUid` em `FriendActivity` (`friend_providers.dart:156`) — **peça load-bearing**. O salve **nunca** aponta pro `training_logs` (privado, rules `firestore.rules:278-282`) — aponta pro `lastTrainingDate` público do espelho. Correto por design.

### Modelo de dados (v1 sem CF)
`kudos/{giverUid}_{targetKey}` — 1 doc por (quem deu, alvo):
```
giverUid          // == auth.uid
targetUid         // dono do item
targetKey
targetType        // treino | graduacao | competicao
createdAt
// DENORM p/ renderizar "SALVES RECEBIDOS" com 0 reads extras:
giverName, giverBelt, giverStripes
```
- **Doc-id composto = idempotência + anti-spam**: 2º salve = overwrite do mesmo doc → 1 salve por par. Sem `update` → contador não forjável.
- **Contagem + "eu já salvei?"**: batch `where('targetKey', whereIn: [até 10 keys visíveis])` por render (hub mostra 3, Galera 6) → 1 leitura em lote, conta client-side, marca `byMe` onde `giverUid == eu`. Mesmo padrão do `getFriends`.
- **Feed recebido (loop)**: `where('targetUid', == meuUid) orderBy createdAt desc limit 20` → 1 leitura bounded; cada linha usa os campos denorm.

### Rules (novo bloco top-level ~`firestore.rules:322`, molde de follows)
```
match /kudos/{kudosId} {
  allow read: if isAuthenticated();
  allow create: if isAuthenticated()
     && request.resource.data.giverUid == request.auth.uid
     && request.resource.data.giverUid != request.resource.data.targetUid
     && kudosId == request.resource.data.giverUid + '_' + request.resource.data.targetKey;
  allow delete: if isAuthenticated() && resource.data.giverUid == request.auth.uid;
  // sem update → contador não forjável; doc-id determinístico → 1 salve/par (anti-spam)
}
```
Autenticado dá e vê; não salva a si mesmo; un-salve = delete do próprio doc.

### Onde aparece
1. **Primário** — `_ActivityRow` do hub (`lutador_hub_screen.dart:740`): pill coração/chama ao lado do ícone de tipo, toggla o salve do item.
2. **Secundário** — `_AchRow` da Galera academia (`cena_screen.dart:509`): mesmo modelo, targetType grad/comp.
3. **Reciprocidade** — nova seção **"SALVES RECEBIDOS"** na aba AMIGOS da Galera (`cena_screen.dart:123`) e/ou linha no hub.

### Loop de reciprocidade
`receivedKudosProvider` (novo, `friend_providers.dart`) → query inbound. Linha: **"{giverName} salvou seu {treino|graduação|competição}"** + faixa + tempo (reusa `_ActivityRow._ago:785`). Tap → `/portal/profile/{giverUid}` → vejo a atividade DELE → salvo de volta. Idempotência por doc-id garante que a retribuição (eu→ele) é um doc distinto e limpo. **Reciprocidade = motivo de voltar ao app.**

### Serviço
Criar `KudosService` (irmão de `FriendService`): `give(giverUid_targetKey + denorm)`, `remove(delete)`, `watchForTargets(keys em lotes de 10)`, `received(targetUid==me, orderBy createdAt desc, limit 20)`. Invalidação otimista análoga a `ref.invalidate(myFriendsProvider)` (`cena_screen.dart:233`).

### Gaps (kudos)
- Sem `targetKey` determinístico o salve não ancora — getter em `FriendActivity` + fórmula idêntica no service.
- Índices: `where(targetKey, whereIn)` e `where(targetUid)+orderBy(createdAt)` em `firestore.indexes.json`.
- Denorm `giverName/giverBelt` fica stale se troca faixa/nome — aceitável (like efêmero); opcional re-hidratar do fighterProfiles no render.
- Escopo de quem salva: rules liberam qualquer autenticado (igual read de follows). "Só amigos" em rules é caro — manter aberto (abuso baixo).
- Granularidade treino = **dia** (não sessão): `lastTrainingDate` colapsa 2 treinos do dia num targetKey. Documentar.
- **Deferir p/ v2**: push de reciprocidade (`users/{uid}/fcmTokens`, `firestore.rules:268` + CF de fan-out no create de kudos) e agregado `kudosCounts/{targetKey}` (caso um item viralize).

---

## 3. Treinei dois números — AULAS VERIFICADAS vs SESSÕES DE TATAME

### O backend JÁ está separado por coleção
Existem hoje **duas famílias**, cada uma numa coleção:

**(A) DURA** — `academies/{id}/attendance` + baseline staff em `student`:
- `student.totalAttendanceCount` = `(initialAttendanceCount ?? 0) + (attendanceCount ?? 0)` (`lib/models/student.dart:545-546`).
  - `attendanceCount` = presença **VERIFICADA**: só sobe via `FieldValue.increment(1)` na chamada do professor (`attendance_service.dart:494/568/734`), desce no unmark (`:812`).
  - `initialAttendanceCount` = **BASELINE DECLARADO PELA ACADEMIA** na migração (`student_form_screen.dart:1694`, `monitor_student_form_screen.dart:199`). Nasce 0, admin edita à mão. Não verificado pelo app, **mas atestado pela casa** — não é self-declarado pelo atleta.
- Usada por **ranking** e **graduação**.

**(B) DIÁRIO** — `users/{uid}/training_logs` (`lib/models/training_log.dart`):
- `source` sempre `'self'`; coração = `sparringCount` (`:45`). Anti-fraude explícito (`:21-26`).
- Alimenta **exclusivamente** `sparringInsightsProvider` (`sparring_providers.dart:17-31`) → `SparringEngine.compute` → card "SEU SPARRING" (`diario_screen.dart:869-925`). O save (`_saveCount:414-476`) **deliberadamente não invalida o showcase** (`:437/:469`).

> **O medo do dono ("self-log inflando ranking") é estruturalmente FALSO hoje.** O ranking (`classRankingProvider` → `RankingService.getRanking` → CF `getAttendanceRanking`, `ranking_service.dart:35-95`) conta **documentos de attendance crus dentro de uma janela de período**. Nunca lê `totalAttendanceCount`, nunca lê `initialAttendanceCount`, nunca lê `training_logs`. Já é 100% verificado e, por ser por-período, imune até ao baseline lifetime. Graduação (`belt_progression_service.dart:872-873/880-886`) = verificado + baseline, **nunca** self-log.

### O trabalho é de rótulo/UI, não backend

**Definir as duas métricas com nome fixo:**

- **AULAS VERIFICADAS** (métrica dura — vale ranking + graduação) = `student.totalAttendanceCount`. A fronteira de fraude é **self vs. academia**, não app vs. migração → manter `initialAttendanceCount` dentro de "oficial". Renomear label **"TREINOS" → "AULAS"** com selo de check/cadeado nas superfícies duras.
- **SESSÕES DE TATAME** (diário — inclui avulsos) = **NOVO agregado derivado** = `dias-com-attendance-verificada ∪ dias-com-self-log` (union por dia), computado **no cliente** a partir do feed que o diário já carrega (verificado `diario_screen.dart:268-282` + self `:285-299`). Vive **só** no Treinei/Jornada, nunca no ranking/graduação.

**Decompor o número duro (honestidade)**: surfar "195 aulas" com breakdown opcional "**X verificadas no app + Y histórico declarado pela academia**" (`attendanceCount` vs `initialAttendanceCount`, ambos já no doc). Zero custo.

**Ranking**: nenhuma mudança de dado. Só adicionar selo **"AULAS VERIFICADAS"** na tela (`ranking_screen.dart:381`, `cena_screen.dart:461`) para comunicar que avulso não conta.

**No Treinei, os dois lado a lado sem confundir**:
- Hero da Jornada = **AULAS VERIFICADAS** (dura, cadeado).
- Logo abaixo linha **"SESSÕES DE TATAME · inclui open mats e avulsos"** (superset, texto seco "não conta pra faixa/ranking").
- Card "SEU SPARRING" (rolas) permanece como camada de textura. A microcopy existente ("AUTO", "não alimenta a jornada") é o modelo de tom.

**Invariante a proteger**: manter `diario_screen.dart:437/469` (self não invalida showcase) e a regra de que ranking/graduação leem attendance, nunca training_logs.

### Superfícies do número duro "TREINOS" (a re-rotular)
`lutador_hub_screen.dart:539/548`; `diario_screen.dart:835` (hero via `fighter_profile.totalTrainings`); `showcase_builder.dart:71/79/129`; `profile_screen.dart:68-71`; `public_profile_screen.dart:650`; `monitor_student_detail_screen.dart:380`; `student_detail_screen.dart:1009`.

### Gaps (dois números)
- Rotulagem ambígua: "TREINOS" esconde a soma silenciosa de baseline (não-verificado-pelo-app) + verificado.
- Sem headline "SESSÕES DE TATAME" unificado hoje.
- "SEU SPARRING" conta **rolas** (`sparringCount`), não **sessões de tatame** — falta o agregado dias-verificados ∪ dias-self.
- Baseline staff editável sem trilha de auditoria (gap menor, não self-fraude).
- Ranking não rotulado como verificado na UI (gap de confiança).

---

## 4. Nota de técnica — campo opcional pós-log + biblioteca

### 70% já existe
- `training_logs` é upsert-por-dia (`TrainingLog` `lib/models/training_log.dart`, `TrainingLogService` `lib/services/training_log_service.dart`).
- `DiarioScreen` tem 3 fases (`_Phase`): idle → count (`_buildCount:2236`) → **reward** (`_buildReward:2532`, pós-save, 100% opcional/pulável). O save (`_saveCount:414`) grava só o count; o botão "FECHOU" (`_doneBar:2827 → _done:551`) só volta a idle sem exigir input.
- **A "pergunta de 5s pós-save" já existe estruturalmente.** Reward tem 4 blocos opcionais: COMO FOI (`:2561`), MODALIDADE (`:2565`), **DRILOU O QUÊ?** (técnicas como TAGS via `_tokenField`, `:2569-2577`) e ROLOU COM QUEM? (`:2579`). Cada edição grava incremental via `_patchLog` (`:497` → `doc.update` + `updatedAt`).
- **A variante "tags de técnica" da nota já está implementada** (`techniques: List<String>`, model `:56-57`).

### O que NÃO existe
1. Campo `note` (texto livre "foco do dia", ≤140) está no model (`:53-54`, `toMap:104`) e aceito pelo service (`upsertForDay` param `note`; `patch` arbitrário `:93`), mas **nunca é escrito nem lido pela UI** — campo morto. `TrainEntry` (`diario_screen.dart:95-125`) nem tem o campo.
2. Nenhuma **agregação de técnicas** — `SparringEngine.compute` (`sparring_engine.dart:108`) só soma `sparringCount` e **ignora `l.techniques`**, mesmo recebendo os logs completos.

### (A) NOTA/FOCO livre (baixo esforço, alto valor narrativo)
- Adicionar 1 seção opcional **"FOCO DO DIA"** (TextField single-line, `maxLength 140`) em `_buildReward`, após "DRILOU O QUÊ?" (após `:2577`).
- Wire via `onSubmitted`/`onChanged` → `_patchLog({'note': v.trim().isEmpty ? FieldValue.delete() : v})`, espelhando `_selectFeeling` (`:513`). **Zero mudança de schema** (campo `note` já existe).
- Round-trip no HISTÓRICO: acrescentar `String? note` em `TrainEntry` (`:95-125`), propagar em `_selfEntry` (`:332`) e no read do feed (`_loadFeed:285-299`), exibir como 3ª linha em `_TrainRow` (após subtitle, `:3058`).
- **Estritamente opcional/pulável** — sem validação; "FECHOU" já dispensa sem input.

### (B) BIBLIOTECA DE TÉCNICAS (a razão de reabrir o app)
- **NÃO criar novas leituras**: `sparringInsightsProvider` (`sparring_providers.dart:22`) já carrega 300 logs com `techniques`.
- Estender `SparringEngine.compute` (`sparring_engine.dart:108`) para emitir `Map<String,int> techniqueFreq` (normalizado `lower+trim`, somando por técnica; opcional `lastDate` p/ "drilada há X").
- Surfar na aba JORNADA como nova seção **"SUA BIBLIOTECA" / "MAIS DRILADO"**, espelhando `_sparringSection` (`diario_screen.dart:869`) — chip-cloud ordenado por frequência com contagem (`"ARMLOCK ·12"`).
- Fecha o loop: cada nota pós-treino enriquece a biblioteca → motivo pra voltar. Anti-fraude intacto: tudo em `training_logs`, nunca toca attendance/graduação.

### Gaps (nota)
- `note` é campo morto na UI; a prosa "o que treinou" não é capturável hoje (só tags).
- Sem biblioteca: técnicas presas dia-a-dia sem agregação.
- **Normalização**: `techniques` é texto livre com `TextCapitalization.words` (`:2756`). "Armlock"/"armlock"/"arm lock" viram entradas distintas → agregação precisa de `lower/trim/canonicalização`.
- Assimetria: `upsertForDay` grava `techniques: const []` no create (`:450`); técnicas só entram via `_patchLog` depois. Se quiser gravar já no save, o service precisa de param `techniques`.
- `techniques` nunca mostrado por NOME em leitura (só contagem "N TÉC", `:3027`; nomes só em modo edição `_openEdit:577`).

---

## 5. Telas afetadas (file:line)

### Parceiros (novo)
- **NOVO** `KudosService`-style `TrainingPairsService` (reader client-side, 2 queries `studentIdA==` / `studentIdB==`).
- Leitura de roster (reuso server-side no CF): `lib/services/attendance_service.dart:615` (`presentTodayForClass`), `:280` (`getPresentStudentIds`).
- Escrita/decremento a observar: `attendance_service.dart:494/568/734` (increment), `:812` (decrement), `:678` (`bulkMarkPresent`), `:644/778` (unmark).
- Path/ponte: `firebase_service.dart:41` (attendance), `:75` (student); `student.dart:336/468/523` (`linkedUserId`); `fighter_profile.dart:202-292`.
- Superfície de UI (novo card "Você e X treinaram N vezes"): `lib/screens/fighter/cena_screen.dart` (aba AMIGOS `:123`) e/ou `lutador_hub_screen.dart` `_FriendsSection:584`.

### Kudos
- `lib/screens/fighter/lutador_hub_screen.dart:740` (`_ActivityRow`, pill primário), `:649-680` (`_FriendsActivityCard`, batch-load), `:584-613` (`_FriendsSection`, host de "salves recebidos").
- `lib/providers/friend_providers.dart:156-170` (`FriendActivity` — getters `targetKey/targetType/targetUid`), `:177-231` (`friendsActivityProvider`).
- `lib/screens/fighter/cena_screen.dart:509-555` (`_AchRow`, alvo secundário), `:123-211` (`_amigos()`, host "SALVES RECEBIDOS"), `:233` (padrão de invalidação).
- `lib/services/friend_service.dart:112-164` (molde do `KudosService`).

### Dois números
- Re-rótulo "TREINOS"→"AULAS" + selo: `lutador_hub_screen.dart:539/548`, `diario_screen.dart:835`, `profile_screen.dart:68-71`, `public_profile_screen.dart:650`, `showcase_builder.dart:71/79/129`, `monitor_student_detail_screen.dart:380`, `student_detail_screen.dart:1009`.
- Selo ranking: `ranking_screen.dart:381`, `cena_screen.dart:461`.
- Novo agregado "SESSÕES DE TATAME" (client): `diario_screen.dart:268-282` (verificado) + `:285-299` (self).
- Fonte: `student.dart:545-546`.

### Nota de técnica
- `diario_screen.dart:2532-2595` (`_buildReward` — add "FOCO DO DIA" após `:2577`), `:497-547` (`_patchLog`/`_addTech`/`_removeTech`), `:95-125` (`TrainEntry` — add `note`), `:332-357` (`_selfEntry`), `:285-299` (`_loadFeed`), `:3058` (`_TrainRow` render), `:869-899` (`_sparringSection` template p/ biblioteca).
- `lib/services/sparring_engine.dart:108-142` (`compute` — add `techniqueFreq`).
- `lib/services/training_log_service.dart:35-58/93-98` (`upsertForDay`/`patch`).
- `lib/models/training_log.dart:53-54/56-57` (`note`/`techniques`).

---

## 6. Rules / CFs / agregados novos

| Item | Tipo | Local | Observação |
|---|---|---|---|
| `academies/{aid}/trainingPairs/{pairId}` | Coleção + rule | `firestore.rules` ~pós `:657` | read se sou um dos dois studentIds (helper `isOwnStudentRecord`); write `false` (só Admin SDK) |
| `.../trainingPairs/{pairId}/sessions/{sid}` | Subcoleção + rule | idem | read/write `false` (interno, idempotência) |
| CF `onPairAttendanceWrite` | **Cloud Function** `onDocumentWritten` | `functions/` (padrão `self_graduation_guard.js:189`) | onCreate incrementa par idempotente (transação + marcador de sessão); onDelete decrementa. **Custo: ~n reads + ≤C(n,2) writes 1x/dia por sessão.** |
| Script backfill de pares | one-off | `functions/scripts/` (padrão `backfill_instructor_permissions.js`) | varre attendance por `(classId,dia)`, popula count/first/last/denorm. Rodar antes de expor. |
| `kudos/{giverUid}_{targetKey}` | Coleção + rule | `firestore.rules` ~`:322` (molde `follows`) | create com `giverUid==auth.uid`, `!=targetUid`, doc-id determinístico; delete pelo giver; read autenticado; sem update |
| Índice `kudos` whereIn(targetKey) | Índice | `firestore.indexes.json` | contagem por render |
| Índice `kudos` targetUid+createdAt | Índice | `firestore.indexes.json` | feed recebido |
| `techniqueFreq` (biblioteca) | Agregado client puro | `SparringEngine.compute` | zero-read (reusa 300 logs já carregados) |
| "SESSÕES DE TATAME" | Agregado client puro | `diario_screen.dart` | union por dia (verificado ∪ self) |

**Sem novo backend para**: dois números (só rótulo), nota livre (campo já existe), kudos v1 (sem CF).
**Único CF novo**: co-presença de parceiros (justificado pelo custo).

---

## 7. Roadmap faseado

### Fase 0 — Dois números + Nota (rótulo/UI, zero backend, menor risco)
- (3) Re-rotular "TREINOS"→"AULAS VERIFICADAS" + selo cadeado nas superfícies duras; breakdown "X verificadas + Y declaradas"; selo no ranking; novo agregado client "SESSÕES DE TATAME" na Jornada.
- (4A) TextField "FOCO DO DIA" em `_buildReward` + round-trip `note` no HISTÓRICO.
- **Por que primeiro**: aditivo, sem migração, sem CF, sem rules — destrava a narrativa "métrica dura" imediatamente.

### Fase 1 — Biblioteca de técnicas
- (4B) `techniqueFreq` em `SparringEngine.compute` (normalizado) + seção "SUA BIBLIOTECA / MAIS DRILADO" na Jornada.
- **Por que**: 1 agregador puro + 1 widget; fecha o loop de reabrir o app. Depende só de (4A) para popular dados.

### Fase 2 — Kudos/salve (v1 sem CF)
- Getters `targetKey/targetType/targetUid` em `FriendActivity` (load-bearing).
- `KudosService` + coleção `kudos` + rules + índices.
- UI: pill otimista em `_ActivityRow` (hub) e `_AchRow` (Galera) + seção "SALVES RECEBIDOS" (loop de reciprocidade).
- **Deferir p/ v2**: push (`fcmTokens`+CF) e agregado `kudosCounts`.

### Fase 3 — Parceiros de treino (CF + backfill — maior peso operacional)
- CF `onPairAttendanceWrite` (`onWrite`, idempotente por marcador de sessão).
- Coleção `trainingPairs` + subcoleção `sessions` + rules.
- **Script backfill** (roda antes de expor a feature — senão "N vezes" começa em 0).
- Reader client + card "Você e o X treinaram N vezes" na Galera; fallback name-only p/ unclaimed; link cross-academy continua em `follows`.
- **Por que por último**: único componente com CF nova + backfill + custo de write; maior superfície de teste (bulkMarkPresent, unmark, ordem de chegada).

**Ordem de deploy de cada fase que toca dados** (padrão do runbook): backfill → rules/índices → app.
