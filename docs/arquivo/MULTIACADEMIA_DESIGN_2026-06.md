> **Arquivado (2026-07):** as propostas centrais deste doc (2026-06) — `Student
> Status.transferred`, `applyTransfer`, aprovação de vínculo com "bagagem do
> lutador" — **foram implementadas** (`lib/models/student.dart:9`,
> `functions/index.js:846` `applyTransfer`, `functions/fighter_baggage.js`,
> `decideJoinRequest`). **Gap residual conhecido:** `cross_academy_service.dart`
> (client) ainda só resolve 1 das 3 eras de vínculo conta↔ficha — o backend
> (`fighter_baggage.js`) já trata as 3, o client não. Esse gap está rastreado
> como item ativo em `docs/ANTI_HIDRA_2026-07.md` (achado #6 / roadmap Fase 1).
> Mantido aqui como registro do design original.

# MAPA + DESIGN — Fluxo Multi-Academia / Transferência (GraduaBJJ, branch `firebase-production`)

Base para implementação. Todas as refs são `arquivo:linha` do estado atual.

---

## 1. Resumo

**O que já existe (e funciona):**
- **Modelo multi-academia completo no dado.** `UserAcademyMapping` (`lib/models/user.dart:212-265`) com `academyIds:List`, `primaryAcademyId` e `academyDetails:{academyId -> AcademyDetail}`. Cada `AcademyDetail` (`user.dart:268-308`) carrega `studentId`, `role`, `joinedAt`, `status` (string livre) e `extraPermissions` próprios — **uma ficha independente por academia**.
- **Re-scope barato e correto.** `selectedAcademyIdProvider` (`selected_academy_provider.dart:17`) é a única fonte de verdade; flipar é só trocar uma string. `SelectedAcademyNotifier.selectAcademy/_selectAcademyInternal` (`:81-126`) valida membership e seta `FirebaseService.setAcademyId` (`firebase_service.dart:20-25`). `currentUserProvider` (`auth_provider.dart:69-118`) re-deriva role+studentId por academia. Tudo (ficha, presença, financeiro, loja, timeline) re-escopa porque vive em subcoleções `academies/{id}/...`.
- **Particionamento físico por academia.** `Collections` ancora tudo em `academies/{academyId}` (`firebase_service.dart:30-105`): `students:40`, `attendance:41`, `payments→financials:46`. Histórico nunca se move.
- **Caminho CÓDIGO ponta-a-ponta para academia ADICIONAL.** Admin gera código (`LinkCodeService.generate` `link_code_service.dart:241`, UI `student_detail_screen.dart:4457`), aluno digita (`add_academy_screen.dart`), CF `joinAcademy` (`functions/index.js:143-307`) faz tudo transacional: anti double-join (`:209`), claim de ficha órfã anti-malicioso (`:218-242`), `arrayUnion` em `academyIds`, cria `academies/{W}/users/{uid}`.
- **Isolamento de segurança data-driven e cost-safe.** Helpers de rules resolvem role+membership de **um único doc** `userAcademyMapping/{uid}` (`firestore.rules:21-152`), de-dup por eval. Sem collectionGroup exceto `linkCodes` (indexado).

**O que falta:**
- **Discovery do DUPLO:** o nav gate `multipleAcademies` (`nav_catalog.dart:471-478`, `nav_resolver.dart:147-151`) esconde o menu "Academias" justamente de quem só tem 1 academia e quer adicionar a 2ª.
- **Status nunca é lido na UI:** `AcademyDetail.status` suporta `'pending'/'archived'` como string, mas o switcher (`academy_switcher.dart:360`) e os cards (`academies_screen.dart`) só renderizam role + Principal.
- **SOLICITAÇÃO inexistente:** sem `joinRequests`, sem CF de aprovar, sem UI aluno-pede/admin-aprova (grep confirma zero em `lib/` e `functions/`).
- **TRANSFERÊNCIA inexistente:** não há `StudentStatus.transferred`, não há `leaveAcademy` CF, não há aba "Ex-alunos". Único "sair" é `unlinkFromAcademy` — **destrutivo** ("Você perderá acesso aos dados desta academia", `academies_screen.dart:364`).
- **Custo na validação de código:** `add_academy_screen.dart:366` faz `collection('academies').get()` + N queries em loop (escala com nº de academias).
- **`getCountByStatus` quebra com status novo:** mapa hardcoded de 4 status com `counts[status]! += 1` (`student_service.dart:578-596`) → null-check error com `transferred`.

**Tese central:** o modelo é a fundação certa. Nenhum dos novos fluxos precisa de scoping novo — são **edições no mesmo doc de mapping + `academyDetails[id].status`**, mais uma subcoleção pequena `joinRequests` e 2-3 CFs (Admin SDK) para os writes que as rules de cliente proíbem de propósito.

---

## 2. Caso DUPLO (aluno em Y + W) — o que falta polir

Data-completo hoje: mapping com `academyIds:[Y,W]` já dá duas fichas independentes e mutuamente invisíveis, cada academia lê só sua subcoleção scoped ao próprio `studentId`, custo zero de query cross-academy. **Gap é puramente UX/discovery.**

**Polimentos (pequenos, alto valor):**
1. **Afrouxar o nav gate.** `nav_catalog.dart:477` / `nav_resolver.dart:147`: mostrar a entrada "Academias" sempre (ou expor um CTA "Entrar em outra academia" no perfil/home). Sem isso, o aluno de Y não acha por onde adicionar W.
2. **Surfacing de `status` no switcher.** Promover `AcademyDetail.status` de string para enum tipado (`active | pending | archived`), fazer `userAcademiesInfoProvider`/`AcademyInfo` (`selected_academy_provider.dart:42, 225-248`) carregarem o status, e renderizar badge na tile (`academy_switcher.dart:360`). Hoje `AcademyInfo` carrega id/name/logo/studentId/role mas **não** status.
3. **Seções "Ativas" vs "Histórico"** no `_AcademySelectorSheet` (`academy_switcher.dart:246`) — vira pré-requisito do caso TRANSFERÊNCIA, mas já modelar aqui.

> DUPLO não exige CF nova nem rule nova. Só nav gate + enum status + render.

---

## 3. Entrar na W

### 3a. CÓDIGO (reusa quase tudo) — **PRIORIZAR**

Já funciona para academia adicional, é idempotente e seguro. Reusa:
- CF `joinAcademy` (`functions/index.js:143-307`) — **extrair o miolo transacional em helper compartilhado** (será reusado por `approveJoinRequest`).
- `LinkCodeService.generate` (`link_code_service.dart:241`) + UI admin (`student_detail_screen.dart:396, 4457-4540`).
- `AddAcademyScreen` (`add_academy_screen.dart:1-501`) — input 6 dígitos, confirmação, confetti, invalida providers.
- Wrapper `teamService.joinAcademy` (`team_service.dart:77-85`) — padrão p/ novas callables.

**Ajustes obrigatórios:**
1. **Trocar validação cara** em `add_academy_screen.dart:356-394` (`collection('academies').get()` + loop) por **chamada direta à CF** (já resolve por collectionGroup, 1 query) ou uma callable leve de preview.
2. **Garantir ficha órfã** `academies/{W}/students/{sid}` antes de gerar o código (UX do admin não deixa isso óbvio; sem ficha, o aluno entra com `studentId=null` e fica sem presença/financeiro). Recomendado: "gerar código" a partir de um aluno recém-criado na W.

### 3b. SOLICITAÇÃO (novo) — modelo + CF + UI

Necessária quando o aluno quer entrar na W **sem** um código (descoberta por slug/código curto da academia).

**Modelo** `academies/{W}/joinRequests/{reqId}`:
```
{ userId, name, photoUrl?, message?,
  status: 'pending'|'approved'|'rejected',
  createdAt, decidedBy?, decidedAt? }
```

**CF `approveJoinRequest({academyId, reqId})`** (`functions/index.js`, novo): valida `isStaff(uid, academyId)` server-side, lê a request, **reusa o helper extraído de `joinAcademy`** para escrever mapping (`arrayUnion academyIds` + `academyDetails[W]`) + criar/claim `students/{sid}` (cria ficha órfã com `linkedUserId=request.userId` se não houver) + `academies/{W}/users/{userId}` + marca request `approved`. **CF `rejectJoinRequest`** marca `rejected`.

**UI aluno:** 2º modo em `AddAcademyScreen` — "Solicitar entrada" → busca academia por código/slug público → `sendJoinRequest` callable → estado "Aguardando aprovação".
**UI admin:** lista de pendentes via `StreamBuilder` em `academies/{W}/joinRequests where status=='pending'` (já scoped pela academia selecionada via `FirebaseService.academyId`, custo O(pendentes da W)) com botões Aprovar/Recusar.

**Recomendação de priorização:**
1. **Primeiro: polir CÓDIGO** (ajustes 1 e 2 acima) — entrega DUPLO/entrada-adicional de imediato, baixo risco.
2. **Depois: SOLICITAÇÃO** — maior superfície (modelo + 3 CFs + 2 UIs + rules + descoberta por slug). Requer decisão de produto sobre **identificador público da academia** (não existe slug/código curto hoje).

---

## 4. Caso TRANSFERÊNCIA (sai da Y, Y mantém histórico)

**Princípio:** transferência é mudança de **ESTADO/visibilidade, não de DADOS**. Nada migra. Presenças novas já caem em `academies/W/attendance`; histórico da Y permanece em `academies/Y/*`. O professor da Y mantém acesso porque isso depende do **mapping do STAFF da Y**, não do mapping do aluno (`firestore.rules:46-75`). Remover Y do mapping do aluno só revoga o self-read do aluno (`belongsToAcademy(Y)` → false, `:36-42`).

**Status do aluno (ficha):**
- Adicionar `StudentStatus.transferred` em `lib/models/student.dart:6-49` (enum + value `'transferred'` + label `'Transferido'` + `fromString`; `fromString` já é forward-compatible → desconhecido vira `active`, não crasha).
- **OBRIGATÓRIO:** corrigir `getCountByStatus` (`student_service.dart:578-596`) — mapa hardcoded com `counts[status]! += 1` lança null-check com status novo. Adicionar a chave.
- Opcional (decisão de produto): campo `transferredTo` (nome/id da W) p/ exibir "Transferido para W"; hoje só `statusNote` texto livre.

**Mapping do aluno:**
- `academyDetails.{Y}.status = 'archived'/'transferred'` + `arrayRemove(Y)` de `academyIds`. **Manter o entry `academyDetails.Y`** (com `studentId`) para localizar a ficha histórica.
- **Não usar `unlinkFromAcademy`** (destrutivo, `academies_screen.dart:393`). `selectAcademy` valida só `academyIds.contains` (`:89`) — academia removida some do switcher; se quiser manter ex-aluno consultando o passado da Y em modo read-only, manter Y em `academyIds` e gatear leitura (ver Decisões em aberto).

**Roster ex-alunos:**
- Particionar **client-side** a lista já carregada por `getAll()` (`student_service.dart:532`, usada por `students_list_screen.dart:75`) em "Ativos" (active/injured/suspended) vs "Ex-alunos" (inactive/transferred) — **custo zero** de query extra.
- O chip "Transferido" aparece automaticamente no filtro porque o bottom-sheet itera `StudentStatus.values` (`students_list_screen.dart:1042-1049`).
- Dar case/cor própria em `_buildStatusBadge` (`:907-921`) p/ distinguir ex-aluno de inativo (hoje cai no default cinza).

**Quem dispara (SEMPRE explícito — nunca automático ao entrar na W, pois entrar na W é o DUPLO legítimo):**
- **(a) Professor da Y:** ação "Marcar como transferido" na tela de detalhe (`student_detail_screen.dart:4356-4364`), reusando `updateStatus(sid, transferred, note: destino)` (`student_service.dart:620-633`) — escreve só `academies/Y/students/{sid}.status`. **Para também encolher o mapping do aluno** (tirar Y do switcher dele), precisa de CF (staff não escreve mapping de outro user — `firestore.rules` exige `auth.uid==userId`).
- **(b) Aluno self-service:** novo **CF `leaveAcademy`** espelhando `joinAcademy` — `arrayRemove(Y)` em `academyIds`, `academyDetails.Y.status='transferred'` e (Admin SDK) `academies/Y/students/{sid}.status='transferred'`.

> Soft delete já seta `inactive` (`student_service.dart:432-437`) e hardDelete preserva financeiro pago de propósito (`:453+`) — confirma a doutrina "preservar histórico". `transferred` é um `inactive` semanticamente mais rico.

---

## 5. Rules novas necessárias

Catch-all `match /{document=**}` (`firestore.rules:1301`) **nega tudo não listado** → todo path novo exige bloco explícito.

**Bloco `joinRequests`** (scoped, sem collectionGroup):
```
match /academies/{academyId}/joinRequests/{reqId} {
  // requester é OUTSIDER — NÃO gatear create em belongsToAcademy
  allow create: if isAuthenticated()
                && request.resource.data.userId == request.auth.uid
                && request.resource.data.status == 'pending';
                // pinar status/campos p/ impedir auto-asserção de role/studentId
  allow read:   if resource.data.userId == request.auth.uid   // própria request
                || isAcademyStaff(academyId);                  // staff da W
  allow update: if isAcademyStaff(academyId);  // approve/reject status
  allow delete: if false;
}
```
A escrita real de membership fica **server-only**. Reusar helpers `isAcademyStaff` (`:73`), `isAuthenticated` (`:10`). Modelo de regra: copiar padrão `linkCodes` (`:647-671`).

**(Opcional) "minhas solicitações" cross-academy** — só se o aluno precisar listar requests em várias academias:
```
match /{path=**}/joinRequests/{id} {
  allow read: if resource.data.userId == request.auth.uid;
}
```
E **sempre** consultar com `where('userId','==',uid)` (indexado, bounded — mesmo padrão de `linkCodes` `:1287-1296`). Alternativa sem collectionGroup: espelhar status sob `users/{uid}`.

**Mapping writes:** as rules de cliente **não** permitem (a) editar mapping de OUTRO user, nem (b) adicionar 2ª+ academia como student (só Path C first-join-from-empty / Path D owner, `firestore.rules:273-347`). Logo `approveJoinRequest`, `leaveAcademy` (encolher mapping de outro user iniciado por staff) e qualquer transfer staff-initiated **MUST** rodar em CF (Admin SDK). Documentar para ninguém tentar client-side.

**Manter a branch `isResponsibleForStudent` por último** em qualquer rule nova (`firestore.rules:121-125`): faz `exists()+get()` por doc; só é alcançada após short-circuit de `isAcademyStaff`/`isOwnStudentRecord`, preservando 1-get para staff/own.

**Não precisa mudar:** students update (staff já escreve qualquer campo, incl. `status→transferred`, `:428-457`), attendance (`:542-584`), financials (`:676-726`) — todos já scoped por academia.

---

## 6. Custos — por que é cost-safe + pontos de atenção

**Por que é barato:**
- Membership/role = **1 `get(userAcademyMapping/{uid})`**, de-dup por eval (`belongsToAcademy`+`isAcademyStaff` chamam o mesmo get → ~1 acesso billado).
- Switch de academia = trocar 1 string (`FirebaseService.academyId`), zero query.
- Queries scoped a subtree (`academies/Y/attendance`, `/financials`) retornam só aquela academia — sem scan, sem collectionGroup.
- Transferência = **1 update de ficha + 1 update de mapping**. Zero migração.
- Roster ex-alunos = partição **client-side** do `getAll()` já carregado — custo zero extra.
- `joinRequests`: cada admin assina só a subcoleção da própria W — O(pendentes da W).

**Pontos de atenção:**
1. **Validação de código em `add_academy_screen.dart:366`** é o único ponto que escala com nº de academias (`collection('academies').get()` + loop). **Trocar por CF/collectionGroup.**
2. **`joinRequests` deve ser subcoleção** `academies/{W}/joinRequests` (pequena, scoped) — **NÃO** coleção top-level varrida nem collectionGroup sem filtro. Se precisar de "minhas requests", sempre `where('userId','==',uid)`.
3. **NUNCA implementar transfer como "mover docs"** — leria+escreveria milhares de docs de attendance/financial E destruiria o histórico da Y. Manter docs no lugar, só editar mapping + status.
4. Estados novos ficam como **campos no mapping doc existente**, não novas coleções por academia — preserva o "sem custo extra de query".
5. `isResponsibleForStudent` é per-doc `exists()+get()` — manter por último nas rules.

---

## 7. UX por papel

**Aluno:**
- **Entrar (código):** menu Academias (após afrouxar gate) → "Adicionar Academia" → digita 6 dígitos → confirma → confetti → W aparece no switcher. (`AddAcademyScreen`)
- **Entrar (solicitação):** mesma tela, modo "Solicitar entrada" → busca W por código/slug → envia → tile mostra badge "Aguardando aprovação" (status `pending`). Ao aprovar, vira ativa.
- **Trocar:** chevron no `AcademySwitcher` da AppBar → sheet com seções **Ativas** vs **Histórico**, badge Principal + check na selecionada.
- **Sair (self-service):** ação "Sair desta academia" → CF `leaveAcademy` → Y sai do switcher (ou vira read-only "Histórico", conforme decisão). Avisar que presenças/financeiro passados permanecem com a Y.

**Admin (professor):**
- **Aprovar:** lista de pendentes (`joinRequests where status=='pending'`) na tela da academia → Aprovar (cria/claim ficha + mapping via CF) / Recusar.
- **Gerar código:** detalhe do aluno → "Gerar código" (garantir ficha órfã criada antes).
- **Transferir:** detalhe do aluno → "Marcar como transferido" (`updateStatus`, nota = destino); ficha vai p/ status `transferred`.
- **Ver ex-aluno:** roster com segmento "Ativos" / "Ex-alunos"; ex-aluno com badge "Transferido" (cor própria); histórico de presença/financeiro continua acessível por direito de membership da Y.

> Regra de ouro UX: transferência é **sempre explícita**. Entrar na W jamais dispara saída da Y automaticamente.

---

## 8. Plano de implementação priorizado

**Fase 1 — DUPLO + CÓDIGO (baixo risco, alto valor):**
1. `lib/core/navigation/nav_catalog.dart:471-478` + `nav_resolver.dart:147-151` — afrouxar gate `multipleAcademies` (mostrar Academias sempre ou CTA "entrar em outra academia").
2. `lib/screens/portal/add_academy_screen.dart:356-394` — trocar validação por chamada à CF `joinAcademy`/preview callable (mata o `collection('academies').get()`).
3. `lib/screens/admin/student_detail_screen.dart:4457` — garantir ficha órfã `academies/{W}/students/{sid}` ao gerar código.
4. `functions/index.js:143-307` — **extrair helper transacional** de `joinAcademy` (reuso futuro).

**Fase 2 — TRANSFERÊNCIA:**
5. `lib/models/student.dart:6-49` — `StudentStatus.transferred` (enum + value + label + fromString + 3 switches).
6. `lib/services/student_service.dart:578-596` — **corrigir `getCountByStatus`** (chave nova, senão crasha).
7. `lib/screens/admin/student_detail_screen.dart:4356-4364` — ação "Marcar como transferido" (reusa `updateStatus`, nota = destino).
8. `lib/screens/admin/students_list_screen.dart:75, 907-921` — segmento Ativos/Ex-alunos (partição client-side) + case/cor p/ `transferred` no badge.
9. `functions/index.js` (novo) — **CF `leaveAcademy`** espelhando `joinAcademy`: `arrayRemove(Y)` + `academyDetails.Y.status='transferred'` + `academies/Y/students/{sid}.status='transferred'`.
10. `lib/widgets/academy_switcher.dart:246, 360` + `lib/providers/selected_academy_provider.dart:42, 225-248` — `AcademyInfo`/`userAcademiesInfoProvider` carregam status; sheet com seções Ativas/Histórico; badge.
11. `firestore.rules` — (se ex-aluno consulta read-only) gate de leitura para academia arquivada mantida em `academyIds`.

**Fase 3 — SOLICITAÇÃO:**
12. **Decisão de produto:** identificador público da academia (slug/código curto) — pré-requisito de descoberta.
13. `firestore.rules` (novo bloco) — `academies/{academyId}/joinRequests/{reqId}` (create por uid+pending, read-own+staff, update staff).
14. `functions/index.js` (novos) — `approveJoinRequest` (reusa helper extraído em #4), `rejectJoinRequest`.
15. `lib/services/team_service.dart:77-85` (padrão) — wrappers `sendJoinRequest`, `approveJoinRequest`, `rejectJoinRequest`.
16. `lib/screens/portal/add_academy_screen.dart` — 2º modo "Solicitar entrada".
17. Tela admin de pendentes — `StreamBuilder` em `joinRequests where status=='pending'` (scoped por `FirebaseService.academyId`).
18. (Opcional) collectionGroup rule + índice p/ "minhas solicitações", ou espelho sob `users/{uid}`.

---

## 9. Decisões em aberto

1. **Ex-aluno consulta o próprio histórico da Y?** Se `leaveAcademy` faz `arrayRemove(Y)`, o aluno perde Y no switcher (e o próprio self-read). Requisito mínimo (professor da Y mantém histórico) é atendido de graça. Se quiser que o **ex-aluno** também consulte o passado da Y: manter `academyDetails.Y` + Y em `academyIds` e gatear leitura **read-only** (rule + filtro no switcher "Histórico").
2. **`status` string vs enum tipado.** Recomendado promover `AcademyDetail.status` a enum (`active|pending|archived`). Migração de dados legados? `fromString` já tolera (default→active).
3. **Identificador público da academia** para SOLICITAÇÃO (slug? código curto? busca por nome?). Não existe hoje — bloqueia descoberta.
4. **`transferredTo`** — guardar nome/id da W na ficha p/ exibir "Transferido para W", ou só `statusNote` livre?
5. **`archived` vs `transferred`** — um único estado terminal no mapping, ou distinguir "arquivada" (saiu) de "transferida" (saiu PARA outra academia identificada)?
6. **Nomenclatura/escopo do gate afrouxado** — mostrar "Academias" sempre para todo aluno, ou só expor CTA "entrar em outra academia" (menos poluição para quem nunca terá 2ª)?
7. **`selectAcademy` e academia arquivada** — `:89` valida só `academyIds.contains`. Se manter Y arquivada em `academyIds` (decisão #1), precisa filtro read-only para impedir escrita; se remover, não precisa.
8. **Transfer staff-initiated encolhe o mapping do aluno?** Marcar `status=transferred` na ficha é client-side (staff pode). Mas tirar Y do switcher do aluno exige CF (staff não escreve mapping de outro user). Definir se a ação do professor já dispara essa CF ou só marca a ficha.

---

Refs principais: `lib/models/user.dart:212-308`, `lib/models/student.dart:6-49`, `lib/services/firebase_service.dart:20-105`, `lib/services/student_service.dart:532-633`, `lib/providers/selected_academy_provider.dart:17-248`, `lib/providers/auth_provider.dart:69-118`, `lib/widgets/academy_switcher.dart:12-448`, `lib/screens/portal/add_academy_screen.dart:1-501`, `lib/screens/portal/academies_screen.dart:201-415`, `lib/screens/admin/student_detail_screen.dart:396-4540`, `lib/screens/admin/students_list_screen.dart:75-1049`, `lib/core/navigation/nav_catalog.dart:471-478` + `nav_resolver.dart:147-151`, `functions/index.js:143-307`, `firestore.rules:10-152, 273-347, 428-726, 1287-1303`.