All findings are confirmed against the code. Here is the validated report.

---

# Validação — Jornal + Eventos (Admin/Professor & Aluno)

## Resumo

Validei os 9 achados contra o código no branch `firebase-production`. **Todos se confirmam.** O sistema de Jornal/Eventos sofre de uma **conflação central**: a flag `journalVisibleToStudents` (visibilidade do feed para alunos) é reusada como gate da entry de **gestão** do admin/professor (`nav_catalog.dart:233`). Consequência: ao esconder o jornal dos alunos, o próprio staff perde acesso à criação/edição — exatamente o cenário de rascunho onde a gestão é mais necessária.

Há também um **vazamento de visibilidade simétrico**: a tela de detalhe (`/portal/eventos/:id`) não aplica o guard que o feed (`jornal_screen.dart:37`) aplica, então o aluno acessa posts via deep-link/push mesmo com o Jornal desligado.

No modelo de permissões há **inconsistência tripla**: `events:manage` é o único `requiresPermission` que não é concedível (não está nas allowlists GRANTABLE server/dart), funcionando hoje só por ser default do instrutor. E o roteamento (`app.dart:521`) não considera `events:manage` ao decidir AdminShell vs Portal, então um professor-aluno com gestão de jornal fica preso no portal sem alcançar a tela.

Severidades: **1 high** (gate de gestão conflado), **3 medium** (vazamento de visibilidade no detalhe ×2 + roteamento professor-aluno), **3 low**, **1 info**.

---

## Admin / Professor / Permissões (criar/editar)

### [HIGH] Desligar "Jornal para alunos" bloqueia o admin/professor de gerenciar o jornal
**`lib/core/navigation/nav_catalog.dart:227-237`** · `nav_resolver.dart:75-84` · `admin_shell.dart:541-544`

A entry `admin_jornal` carrega `feature: FeatureId.journal` + `lockable: true`. Em `resolveAdminCatalog` (nav_resolver.dart:75-84), feature OFF + lockable → estado `locked`, e no `admin_shell.dart:541-544` o tap de uma entry `locked` redireciona para Settings em vez da tela. Como `FeatureId.journal` mapeia para `journalVisibleToStudents` (nav_resolver.dart:14-15), **a mesma flag que esconde o feed do aluno trava a gestão do staff**. A rota `/admin/jornal` ainda existe e funciona por URL direta, mas a navegação a esconde. Gestão de rascunhos fica inviável.

**Fix:** Espelhar `admin_ranking` — remover `feature: FeatureId.journal` e `lockable: true` da entry, mantendo só o gate por permissão. A flag `journalVisibleToStudents` deve gatear apenas as entries do portal (via `resolvePortalCatalog`), nunca a gestão.

```dart
// nav_catalog.dart:227
NavEntry(
  key: 'admin_jornal',
  label: 'Jornal da Academia',
  icon: LucideIcons.newspaper,
  route: '/admin/jornal',
  section: NavSection.gestao,
  // feature: FeatureId.journal,   <- REMOVER
  // lockable: true,               <- REMOVER
  requiresPermission: 'events:manage',
  adminBypassesPermission: true,   // ver achado [INFO] abaixo
),
```

### [MEDIUM] Professor promovido de aluno (sem financeiro/competição/graduação) é roteado para /portal e nunca alcança a gestão
**`lib/app.dart:521-523`** · `user.dart:441`

Em `app.dart:521-523`, `hasAdminOnlyManagement` só checa `competitions:create` e `graduation:manage`. Um instrutor com `studentId != null`, sem financeiro e sem esses dois, cai no ramo `app.dart:528` e vai para `/portal` — onde `/portal/jornal` é só leitura. Mesmo tendo `events:manage` (default de todo instrutor, user.dart:441), nunca chega a `/admin/jornal`.

**Fix:**
```dart
// app.dart:521
final hasAdminOnlyManagement =
    user.hasPermission('competitions:create') ||
    user.hasPermission('graduation:manage') ||
    user.hasPermission('events:manage');
```
Como `events:manage` é default de todo instrutor (user.dart:441), na prática isto roteia **todo** professor-aluno para o AdminShell. Se a intenção for manter alguns no portal-monitor, então `events:manage` precisa virar opt-in (ver achado abaixo) antes de usar este critério.

### [LOW] `events:manage` não está nas allowlists GRANTABLE (server + dart)
**`functions/index.js:48-59`** · `instructor_link_code_service.dart:18-39` · `user.dart:440-451`

`events:manage` é o único `requiresPermission` ausente de `GRANTABLE_EXTRA_PERMISSIONS` (index.js:48) e `kGrantableExtraPermissions` (service:18). Funciona só por estar em `_instructorDefaultPermissions` (user.dart:441). Qualquer refactor que remova o default deixa o admin sem como conceder gestão do jornal; e impede granularidade (não dá para ter professor SEM gestão de jornal).

**Fix — decidir o modelo:**
- **(A) Concedível/opt-in:** adicionar `'events:manage'` em index.js:48 e em service:18 (com label/descrição), e **remover** de `_instructorDefaultPermissions` (user.dart:440-442). Sincroniza as 3 fontes e dá granularidade.
- **(B) Sempre default:** remover `requiresPermission:'events:manage'`+`adminBypassesPermission:false` de nav_catalog.dart:235-236, gateando só por role (igual `admin_ranking`), documentando que todo staff gere o jornal.

> Recomendação: **(B)** é o caminho de menor atrito se o produto quer "todo professor gere o jornal" — alinha com o fix HIGH e elimina a inconsistência tripla de uma vez. **(A)** só se houver requisito real de professor sem gestão.

---

## Aluno (visualização / visibilidade)

### [MEDIUM] Deep-link ao detalhe ignora `journalVisibleToStudents` — vazamento de visibilidade
**`lib/screens/portal/event_detail_screen.dart:20-25,52-75`**

(Os achados "aluno-visualizacao" e "modelo-rules" sobre o detalhe são o **mesmo bug** — consolidados aqui.) `eventDetailProvider` (event_detail_screen.dart:20-25) só checa `isPublished`; não lê `journalVisibleToStudents`. O feed (`jornal_screen.dart:37`) bloqueia com `_JornalUnavailableState`, mas o detalhe não — então via push entregue, histórico ou link compartilhado o aluno abre o conteúdo mesmo com Jornal desligado. O comentário em jornal_screen.dart:23 ("even reachable via deep link… stays hidden") promete uma garantia que o detalhe quebra.

**Nuance de produto:** `home_screen.dart:609` mostra `PostType.event` (eventos reais) independente do Jornal. O guard do detalhe deve bloquear `news`/`seminar`, OU bloquear tudo — alinhar com a regra desejada antes de implementar. Idealmente liberar preview para staff.

**Fix** em `_EventDetailBody.build` (event_detail_screen.dart:52):
```dart
final journalVisible = ref.watch(academySettingsProvider.select(
    (s) => s.valueOrNull?.journalVisibleToStudents ?? true));
final isStaff = ref.watch(currentUserProvider).valueOrNull?.isInstructor ?? false;
// dentro de data: (event), antes de _EventLoaded:
if (event != null && !journalVisible && !isStaff
    && event.postType != PostType.event) {
  return const _JornalUnavailableState(); // reaproveitar de jornal_screen
}
```
Alternativa mais robusta: gatear a rota `/portal/eventos/:id` em `app.dart` com redirect quando `journalVisible == false`.

### [LOW] Estado de erro do detalhe mascara permission-denied/rede como "Evento não encontrado"
**`lib/screens/portal/event_detail_screen.dart:61-71`**

O branch `error` (linha 61-63) e `data==null` (66-70) mostram a **mesma** mensagem "Evento não encontrado.". Erros transitórios de rede/permissão viram "inexistente" permanente, sem retry.

**Fix:** No `error`, mostrar mensagem de falha + botão "Tentar novamente" com `ref.invalidate(eventDetailProvider((academyId: academyId, eventId: eventId)))`; reservar "Evento não encontrado." só para `data==null`. Logar `error/stack` para observabilidade.

---

## Modelo e Rules

### [LOW] WRITE de events sem validar campos obrigatórios nem `academyId`
**`firestore.rules:846-851`** · `academy_event.dart:93`

`allow write: if isAcademyStaff(academyId)` (rules:850) não valida nada. Um doc malformado (ex.: `startDate` ausente) derruba o parse de **todo** o feed: `academy_event.dart:93` faz `(data['startDate'] as Timestamp).toDate()` — cast não-anulável (contraste com createdAt:103 que usa `?? DateTime.now()`). Um único doc ruim joga o feed inteiro no error state.

**Fix (defesa dupla):**
```
// firestore.rules:850
allow create: if isAcademyStaff(academyId)
              && request.resource.data.academyId == academyId
              && request.resource.data.title is string
              && request.resource.data.startDate is timestamp
              && request.resource.data.isPublished is bool;
allow update: if isAcademyStaff(academyId)
              && request.resource.data.startDate is timestamp;
```
```dart
// academy_event.dart:93 — parse resiliente
startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
```

### [LOW] Qualquer instrutor edita/apaga evento alheio sem trilha de autoria
**`firestore.rules:850`** · `event_service.dart:100-151` · `academy_event.dart`

Nenhum `createdBy` é gravado (event_service.dart:104-106 não seta autor). Qualquer instrutor altera/apaga post de outro sem rastro. Aceitável para equipe pequena, mas sem accountability.

**Fix (se desejado):** Adicionar `createdBy` ao modelo, gravar em `EventService.create` (event_service.dart:104) com `FirebaseService.currentUserId`. Opcionalmente restringir delete:
```
allow delete: if isAcademyAdmin(academyId)
  || (isAcademyInstructor(academyId)
      && resource.data.get('createdBy', null) == request.auth.uid);
```
No mínimo persistir `createdBy` para auditoria.

### [INFO] `adminBypassesPermission:false` no Jornal é inócuo
**`nav_catalog.dart:235-236`** · `nav_resolver.dart:49-52` · `user.dart:444-451`

`hasPermission` retorna `true` incondicionalmente para admin (user.dart:445), então `adminBypassesPermission:false` não tem efeito — admin sempre vê o jornal. É inconsistência de intenção que confunde manutenção (tentar "remover events:manage de um admin" não terá efeito).

**Fix:** Trocar para `adminBypassesPermission: true` (default) em nav_catalog.dart:236 para alinhar com o comportamento real. (Já incorporado no diff do achado HIGH.)

---

## Plano priorizado

| # | Sev | Arquivo:linha | Ação |
|---|-----|---------------|------|
| 1 | **HIGH** | `nav_catalog.dart:233-236` | Remover `feature: FeatureId.journal` + `lockable: true` da entry `admin_jornal`; trocar `adminBypassesPermission` para `true`. Resolve HIGH + INFO juntos. |
| 2 | **MED** | `event_detail_screen.dart:52-75` | Adicionar guard `journalVisibleToStudents` (com bypass staff + exceção `PostType.event`) antes de `_EventLoaded`. Consolida os 2 achados de detalhe. |
| 3 | **MED** | `app.dart:521-523` | Incluir `events:manage` em `hasAdminOnlyManagement` (depende da decisão do #5). |
| 4 | **LOW** | `event_detail_screen.dart:61-71` | Separar branch `error` (retry + log) de `data==null`. |
| 5 | **LOW** | `index.js:48` / `service:18` / `user.dart:440` | **Decidir modelo (A concedível vs B default-only)** e alinhar as 3 fontes. Bloqueia a forma final do #3. |
| 6 | **LOW** | `firestore.rules:850` + `academy_event.dart:93` | Endurecer rule de write (validar `academyId`/`startDate`/`title`/`isPublished`) + parse resiliente do `startDate`. |
| 7 | **LOW** | `event_service.dart:104` + `academy_event.dart` + `rules:850` | (Opcional) Persistir `createdBy`; restringir delete a admin/autor. |

**Ordem sugerida:** decidir #5 (modelo de permissão) primeiro pois governa #1 e #3 → depois #1 (desbloqueia gestão, maior impacto) → #2 (fecha o vazamento) → #6 (robustez do feed) → #3/#4/#7.

**Diffs-chave já especificados acima** nos achados #1 (nav_catalog), #2 (event_detail guard), #3 (app.dart), #6 (rules + academy_event.dart:93).

**Arquivos a editar:**
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/core/navigation/nav_catalog.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/portal/event_detail_screen.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/app.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/models/user.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/services/instructor_link_code_service.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/index.js`
- `/Users/igorgewehr/WebstormProjects/graduabjj/firestore.rules`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/models/academy_event.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/services/event_service.dart`