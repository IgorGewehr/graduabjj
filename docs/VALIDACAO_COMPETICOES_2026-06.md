Confirmed. `request.resource.data.createdBy` is never validated against `request.auth.uid` on create. Now I have everything verified. Writing the report.

The findings are accurate, with one important correction: the visualization bug AND the instructor-permission fixes are already implemented in the working tree (uncommitted) — they only need committing/deploying. The real outstanding code work is in `storage.rules` plus two `firestore.rules` hardenings.

---

# Relatório de Validação — Competições (GraduaBJJ)

## Resumo

Validei os 9 achados contra o código real (branch `firebase-production`). Situação:

- **Bug de visualização (high)**: CONFIRMADO como causa-raiz, mas o **fix já está aplicado no working tree (não commitado)**. Falta apenas commitar e deployar. Idem para a liberação de permissões do instrutor.
- **Permissões do aluno promovido (instrutor)**: as `firestore.rules` de `competitions` / `competitionResults` **já contemplam** `competitions:create` para instrutores no working tree. A barreira de UI (`isAdmin` hardcoded) **já foi corrigida** tanto na lista admin quanto na tela de detalhe. Não há barreira pendente para liberar create/edit de competições e resultados — só falta deploy.
- **Rules de fotos (high/medium/low)**: CONFIRMADOS e **ainda não corrigidos**. Este é o trabalho de código real que resta. O furo crítico é `storage.rules:113` (`allow delete: if isStaff(academyId) || authed()` → qualquer autenticado apaga foto de qualquer academia).

Os dois achados duplicados sobre delete de Storage (`storage.rules:113`/`:118`) referem-se ao **mesmo bloco** — no arquivo real é a **linha 113**, não 118. Tratar como um único fix.

Prioridade de execução: (1) commitar/deployar o que já está no working tree; (2) fechar os furos de Storage; (3) hardening de ownership no Firestore.

---

## Bug de visualização (causa-raiz + fix exato)

**Causa-raiz (confirmada):** `_loadData()` lia `ref.read(selectedAcademyIdProvider)` diretamente. Em sessão admin/professor, o `AdminShell` nunca faz bootstrap desse provider (ele permanece `null`), então `_loadData` caía em `_error = 'Academia nao selecionada'` para **qualquer** competição aberta pela lista admin. "Tentar novamente" não resolvia porque o provider continuava `null`.

**Status:** o fix **já está no working tree** (`git diff` mostra o diff não commitado em `lib/screens/portal/competition_detail_screen.dart`), exatamente como o achado recomenda:

- Adicionado `String _resolveAcademyId()` (linhas 73-76) com cadeia de fallback: `selectedAcademyIdProvider ?? currentUserProvider...academyId ?? FirebaseService.academyId` — mesmo padrão de `student_detail_screen.dart`.
- `_loadData` (linha 90) usa `_resolveAcademyId()` + `if (academyId.isEmpty)`.
- `build()` (linha ~141) usa `ref.watch(selectedAcademyIdProvider) ?? _resolveAcademyId()`.
- `_selfEnroll` (linha ~957) também migrado.

**Ação:** nenhuma edição de código nova. Apenas garantir que esse diff seja **commitado e deployado** em `firebase-production`. Verificar com `git diff --stat` antes do commit.

---

## Permissões do aluno promovido (instrutor)

Objetivo: instrutor promovido (com `competitions:create`) consegue **criar/editar competições E resultados**. Mapeamento das barreiras e estado real:

| Barreira | Local | Estado |
|---|---|---|
| Rule `competitions` create/update/delete | `firestore.rules:881-886` | **JÁ LIBERADO** — `isAcademyAdmin \|\| (isAcademyInstructor && hasExtraPermission(academyId, 'competitions:create'))` |
| Rule `competitionResults` create/update/delete | `firestore.rules:927-941` | **JÁ LIBERADO** — mesmo padrão, preservando o self-record do aluno (`isOwnStudentRecord`) |
| UI da lista admin: `isAdmin` hardcoded ao navegar | `competitions_screen.dart:911-919` | **JÁ CORRIGIDO** — `canManage = isAdmin \|\| hasPermission('competitions:create')` |
| UI da tela de detalhe: ações gated por `widget.isAdmin` | `competition_detail_screen.dart` (vários) | **JÁ CORRIGIDO** — novo getter `_canManageResults` (linhas 82-87) substitui `widget.isAdmin` em team result card, botão registrar, editar/deletar resultado e título |

**Conclusão:** não resta barreira de permissão para o instrutor. Todo o fluxo create/edit de competições e resultados está liberado no working tree. Falta **deploy das rules** (`firebase deploy --only firestore:rules`) e release do app.

**Nota de revisão (low, sem ação obrigatória)** — `firestore.rules:889-892`: o branch de self-enroll permite que qualquer membro adicione/remova **qualquer** id em `enrolledStudentIds`. Não afeta o instrutor. Hardening opcional: validar que o diff de `enrolledStudentIds` contém apenas o próprio `studentId`.

---

## Rules de fotos (buracos + fix)

Todos confirmados no arquivo real. O Storage está **mais permissivo que o Firestore**, criando inconsistência doc-vs-blob (galeria com thumbnails quebrados, sem rastro de quem apagou).

### 1. (HIGH) `storage.rules:113` — qualquer autenticado deleta qualquer foto, cross-academy
```
allow delete: if isStaff(academyId) || authed();   // <- furo: authed() solto
```
Qualquer aluno ou conta de outra academia apaga fotos alheias direto no Storage, contornando o Firestore (`firestore.rules:980-982`, que exige `isAcademyStaff` ou `createdBy == auth.uid`). **Causa direta de fotos sumindo.**

**Fix mínimo:** exigir pelo menos pertencer à academia →
```
allow delete: if isStaff(academyId) || belongs(academyId);
```
**Fix ideal:** restringir Storage a `isStaff(academyId)` apenas e rotear delete de foto de aluno por uma Cloud Function que leia `createdBy` do doc (espelhando o bloco de `assessments`, `storage.rules:100-102`).

### 2. (MEDIUM) `storage.rules:112` — qualquer membro sobrescreve foto de qualquer outro
```
allow write: if authed() && belongs(academyId) && isImage() && sizeUnderMb(10);
```
Não dá pra separar create/update só pelo path. Defacement: trocar conteúdo da foto alheia sem mexer no doc, então a UI continua atribuindo ao aluno original.

**Fix recomendado:** prefixar o path com o uid do uploader e amarrar no write — `.../photos/{uploaderUid}/{photoId}` com `request.auth.uid == uploaderUid`. Isso elimina a sobrescrita cruzada (cada uid só escreve no seu prefixo). **Atenção:** exige mudar o `storagePath` gerado em `competition_photo_service.dart` (ver Plano).

### 3. (LOW) `firestore.rules:948` — create não amarra `createdBy` ao `auth.uid`
Confirmado: nenhum `request.resource.data.createdBy == request.auth.uid` no create. Ownership forjável; como update/delete dependem de `createdBy`, quebra a invariância.

**Fix:** adicionar `&& request.resource.data.createdBy == request.auth.uid` à condição de create.

### 4. (LOW) `firestore.rules:953` — `storagePath` não validado contra o escopo
Permite persistir um `storagePath` apontando pra arquivo fora do escopo da foto. Baixo isoladamente, mas vetor indireto combinado com delete aberto.

**Fix:** validar formato com `.matches('academies/' + academyId + '/competitions/' + request.resource.data.competitionId + '/photos/.*')`.

### 5. (LOW) `photoType` é dead-data; galeria de equipe usa sentinela `'__team__'`
Confirmado: `photoData` (`competition_photo_service.dart:79-92`) **não persiste `photoType`**, mas `team_gallery_view.dart` e o model filtram por ele. Fotos de equipe dependem de `studentId == '__team__'` (não é studentId real), o que na prática só staff conseguem criar (não passam em `isOwnStudentRecord`). Decidir junto com o fix #3: ou persistir `'photoType': studentId == '__team__' ? 'team' : 'student'`, ou remover o campo morto do model.

---

## Plano priorizado (file:line + diffs)

### P0 — Deploy do que já está pronto (sem novo código)
1. Commitar o working tree (visualização + permissões instrutor já implementados) e deployar:
   - `lib/screens/portal/competition_detail_screen.dart`, `lib/screens/admin/competitions_screen.dart`, `firestore.rules`
   - `firebase deploy --only firestore:rules` + release do app Flutter.

### P1 — Fechar furo crítico de delete no Storage (HIGH)
**`storage.rules:113`**
```diff
-      allow delete: if isStaff(academyId) || authed();
+      allow delete: if isStaff(academyId) || belongs(academyId);
```
(Ideal de longo prazo: trocar por `if isStaff(academyId);` e rotear delete de aluno por Cloud Function — registrar como follow-up.)

### P2 — Hardening de ownership no Firestore (LOW, baixo risco, alto valor)
**`firestore.rules:948`** (no bloco `create` de `competitionPhotos`, junto às validações de `!= null`):
```diff
                      && request.resource.data.storagePath != null
+                     && request.resource.data.createdBy == request.auth.uid
+                     && request.resource.data.storagePath.matches('academies/' + academyId + '/competitions/' + request.resource.data.competitionId + '/photos/.*')
```
Pré-requisito de código: `competition_photo_service.dart` já preenche `'createdBy': createdBy` (`:91`) — confirmar que `createdBy` passado é sempre `FirebaseAuth.currentUser.uid`, senão o create passa a falhar.

### P3 — Eliminar sobrescrita cruzada no Storage (MEDIUM, requer mudança de path)
1. **`competition_photo_service.dart`** (~`:60` e `:75`): mudar o `storagePath` para incluir o uid:
   `academies/$academyId/competitions/$competitionId/photos/$uid/$photoId.jpg`
2. **`storage.rules:110-112`**: ajustar o match para `.../photos/{uploaderUid}/{photoId}` e:
```diff
-      allow write: if authed() && belongs(academyId) && isImage() && sizeUnderMb(10);
+      allow write: if authed() && belongs(academyId) && request.auth.uid == uploaderUid && isImage() && sizeUnderMb(10);
```
3. Ajustar o `.matches(...)` do P2 para o novo formato de path. **Migração:** fotos antigas ficam no path velho; manter compat de read (read já é `if true`) ou migração one-shot. Avaliar antes de mexer — pode ficar como follow-up isolado.

### P4 — `photoType` (LOW, limpeza)
Decidir: persistir `'photoType'` em `photoData` (`competition_photo_service.dart:79`) **ou** remover o campo do model e ajustar `team_gallery_view.dart:44`. Recomendo persistir, é mais barato e destrava futura distinção team/student sem sentinela.

---

**Arquivos relevantes:**
- `/Users/igorgewehr/WebstormProjects/graduabjj/storage.rules` (linhas 110-114)
- `/Users/igorgewehr/WebstormProjects/graduabjj/firestore.rules` (competitions 877-892; results 924-941; photos 945-983)
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/portal/competition_detail_screen.dart` (fix já no working tree)
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/admin/competitions_screen.dart` (linhas 911-919, fix já presente)
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/services/competition_photo_service.dart` (upload ~60-100; delete ~226-240)
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/widgets/competitions/team_gallery_view.dart` (filtro por photoType)