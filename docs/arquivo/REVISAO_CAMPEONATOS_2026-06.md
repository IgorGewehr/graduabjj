> **Arquivado (2026-07):** revisão pontual do módulo de Campeonatos (2026-06).
> Registro histórico dos 24 achados; não confirmado se todos foram corrigidos —
> tratar como ponto de partida para nova varredura se o módulo for revisitado.

The findings match the current code. I have enough verification to produce the report.

## Resumo

Auditoria do módulo de **Campeonatos** (criação/edição/exclusão pelo professor, fluxo de inscrição e resultados do aluno, galeria de fotos e integridade de dados). Foram confirmados **24 achados**, distribuídos em 3 personas/eixos.

O tema dominante é **dupla fonte de verdade não sincronizada**: inscrições vivem tanto no array legado `enrolledStudentIds` (dentro do doc do campeonato) quanto na coleção `competitionEnrollments`, e resultados de competição duplicam estado em `achievements` (medalhas/timeline/gamificação). Nenhuma das duas estruturas tem cascata nem dual-write simétrico, então **contagens divergem da lista**, **excluir campeonato deixa inscrições órfãs**, e **editar/excluir resultado deixa medalhas órfãs ou erradas**. Em paralelo há um eixo de UX/correção de formulário (controllers recriados no build, falta de trava de duplo-toque, validação que bloqueia salvar "Absoluto", status derivado de data que não é recalculado no edit) e um eixo de permissões (UI promete delete ao aluno que o `firestore.rules` nega; aluno pode auto-registrar ouros ilimitados sem aprovação).

Severidades: **1 high** (achievement órfã ao editar/excluir resultado), **9 medium**, **13 low**, **1 info**.

Prioridade de implementação: começar pela sincronização de `achievements` no edit/delete (high, afeta gamificação), depois unificar a fonte de inscrições + cascata de exclusão (3 mediums correlacionados), depois os mediums de formulário (Absoluto + trava de duplo-toque) e o eixo de permissão aluno↔rules.

---

## Professor/Admin (fluxo + UX)

### [MEDIUM] Excluir campeonato deixa inscrições órfãs — o diálogo mente para o admin
`lib/services/competition_service.dart:356-365` · diálogo em `lib/screens/admin/competitions_screen.dart:1363-1369`

`delete(id)` apaga só os `competitionResults` (loop sequencial) e o doc do campeonato. Os docs de `competitionEnrollments` ficam órfãos, mas o diálogo afirma "também removerá todas as inscrições". Corrigir dentro do serviço para que a promessa valha em todos os call sites. Preferir **WriteBatch** (atômico, sem delete parcial em falha), folhando results + enrollments + doc no mesmo commit, chunkando se passar de 500 ops. Ver diff no Plano (#2).

### [MEDIUM] Editar campeonato grava `DateTime` cru e não recalcula status (cai na aba errada)
`lib/screens/admin/competitions_screen.dart:849-859` (update map) vs `create` em `606-622`

No create o status é derivado da data; no edit não. Mudar a data de "futuro" para "passado" (ou vice-versa) mantém o status antigo, e o campeonato aparece na aba errada. Confirmei que `update()` (service:346) faz `update(data)` cru, sem derivar status. Dois bugs no mesmo lugar (este e o de `corretude-dados`, achado #23) — tratar juntos. A correção robusta é derivar status de `data['date']` dentro de `CompetitionService.update` quando não houver `status` explícito; a correção definitiva é parar de persistir status derivado de data e computar `upcoming/completed` em read-time.

### [MEDIUM] Inscrição manual e diálogo de resultado sem trava de duplo-toque / loading
`lib/screens/admin/competitions_screen.dart:1254-1310` (`_showAddEnrollmentSheet`) · botão Salvar do resultado em `competition_detail_screen.dart:1540-1568`

Sem `isSaving`, duplo-toque dispara dois writes; a exceção de duplicata ("já está inscrito") vaza como "Erro: $e" cru. Adicionar `bool isSaving` no `StatefulBuilder`, early-return + `onPressed: isSaving ? null`, spinner no child, reset em `finally` guardado por `mounted`, e tratar a duplicata com mensagem amigável.

### [MEDIUM] Categoria de Peso obrigatória bloqueia salvar resultado de "Absoluto"
`lib/screens/portal/competition_detail_screen.dart:1541` (`onPressed: weightCategory.isEmpty ? null`) · seletor Divisão `1487-1509`

O gate exige `weightCategory` mesmo quando `divisionType == 'absolute'`, que por definição não tem peso → botão fica cinza sem explicação. Tornar a validação condicional à divisão. (Duplicado em `corretude-dados` #21 — mesma linha; consolidar.) Ver diff no Plano (#3).

### [LOW] "Adicionar" resultado pelo admin desabilitado sem explicação quando não há inscritos
`lib/screens/portal/competition_detail_screen.dart:770-781`

Botão depende de `_enrollments` não-vazio mas não comunica isso. Mínimo: SnackBar/tooltip "Inscreva alunos antes de lançar resultados". Melhor: fallback que escolhe aluno ativo direto (`StudentService.getActive`, já usado em `_showAddEnrollmentSheet`) e auto-cria a inscrição ao lançar o resultado.

### [LOW] `TextEditingController` recriados a cada rebuild e nunca dispostos (sheets de resultado e de campeonato)
`lib/screens/portal/competition_detail_screen.dart:1519, 1531` · `competitions_screen.dart:410-412, 694-700`

Controllers inline no `build`/`StatefulBuilder` resetam cursor e vazam. Hoistar para fora do builder (uma vez por sheet) e dispor via `.whenComplete(...)` no future do `showModalBottomSheet`. (Mesmo problema reportado 3x — #6, #10, #24 — é o mesmo padrão em sheets diferentes; corrigir todos juntos.)

### [LOW] Divergência de critério entre aba "Passados" (por data) e serviço "upcoming" (por status)
`lib/screens/admin/competitions_screen.dart:70-71` (past por data) vs `lib/services/competition_service.dart:257-263` (upcoming por status)

Confirmei: tela usa `all.where((c) => c.date.isBefore(now))` para "past", enquanto "upcoming" vem de `getUpcoming()` filtrado por `status==upcoming`. Eixos diferentes → um campeonato com data passada mas status ainda `upcoming` some das duas abas (ou aparece em ambas). Unificar para um único critério (recomendado: **por data**, derivando ambas as listas de `all` e excluindo `cancelled`), o que também elimina a `Future.wait`/`getUpcoming` paralela.

### [LOW] Auto-inscrição ao lançar resultado pode gravar enrollment legado inconsistente sem feedback
`lib/screens/portal/competition_detail_screen.dart:1685-1711` (`_saveResult` auto-enroll)

`catch (_) {}` vazios engolem falha do write legado → drift de contagem invisível. Substituir por log; melhor: derivar a contagem de `competitionEnrollments` e deprecar o array (ver eixo de dados).

---

## Aluno (fluxo + UX)

### [MEDIUM] Aluno vê botão de excluir o próprio resultado, mas `firestore.rules` nega → erro de permissão
`lib/screens/portal/competition_detail_screen.dart:693-697` (`_buildMyResultsCard`) · `competition_service.dart deleteResult` · `firestore.rules:953-954`

A UI oferece "Excluir seu resultado" mas a regra de delete só permite admin/instrutor. Escolher um modelo coerente. **Opção A (preferida):** liberar self-delete no rules espelhando o update (`isOwnStudentRecord(...)`) — o aluno já cria/edita o próprio registro. **Opção B:** esconder o botão (`if (_canManageResults) ...`). A já exige deploy de rules (`firebase deploy --only firestore:rules`, projeto `arpjj-76350`). Ver diff no Plano (#4).

### [MEDIUM] Aluno que competiu mas não se inscreveu antes do término não consegue subir foto nem se inscrever
`lib/screens/portal/competition_detail_screen.dart:326-328` (botão self-enroll) · `lib/widgets/competitions/competition_gallery.dart:253-256` (`_canUpload`)

Galeria exige `isEnrolled`; após `completed` o botão de self-enroll some. Quem tem **resultado** mas nunca se inscreveu fica travado, contradizendo a promessa do admin (`competitions_screen.dart:556`: "Alunos poderão adicionar seus resultados e fotos"). Tratar resultado como participação: `canParticipate = enrollments.any(me) || results.any(me)` e passar isso como `isEnrolled` (ou prop `canUpload` distinta). **Verificar também o rules** do write de foto — se checar enrollment server-side, espelhar o OR-result lá.

### [MEDIUM] Aluno pode auto-registrar resultados ilimitados e escolher "Ouro" livremente
`lib/screens/portal/competition_detail_screen.dart:611-625` (botão Adicionar) · `1426-1443` (seletor de posição) · `1676-1683` (createCompetitionAchievement)

Sem teto, sem confirmação, sem aprovação → medalhas/gamificação infláveis. Cliente é bypassável, então a defesa real é server-side. Mínimo viável: forçar `status:'pending'` para writes de não-staff em `competitionResults`/`achievements` no rules, excluir `pending` das agregações de ranking/medalhas nas Cloud Functions, e deixar staff confirmar. Defesa em profundidade: unicidade por `(competitionId, studentId, modality, divisionType, ageCategory, weightCategory)` via doc ID determinístico, + confirmação na UI.

### [LOW] `TextEditingController` recriado a cada `setSheetState` no diálogo de resultado do aluno
`lib/screens/portal/competition_detail_screen.dart:1519, 1531` (`_showResultDialog`) — mesmo padrão do achado #6, ver Professor/Admin.

### [LOW] Sem feedback quando o usuário do portal não tem registro de aluno (`currentStudentProvider == null`)
`lib/screens/portal/competition_detail_screen.dart:244-246, 326-327` · `lib/providers/student_provider.dart:10`

`student == null` simplesmente some com o botão de inscrição, sem dizer por quê. Distinguir "carregando" de "resolvido-null" lendo o `AsyncValue` direto e, quando `hasValue && value == null`, renderizar linha informativa ("Não foi possível identificar seu cadastro... fale com a recepção"). Repetir no gate da galeria.

### [LOW] Permissão de excluir foto inconsistente entre grade e fullscreen para o dono da foto
`lib/widgets/competitions/competition_gallery.dart:246-248` (`_showFullscreen`) vs `410-417` (`PhotoCard`)

A grade mostra delete para `isAdmin || isOwner`; o fullscreen calcula um booleano estático no open a partir do `index`, que desincroniza ao deslizar (PageController muda `_currentIndex`). Passar `uid`/callback para o viewer e reavaliar por `_currentPhoto.createdBy == currentUserId` a cada página.

### [INFO] Atualização otimista da inscrição não revalida com o servidor
`lib/screens/portal/competition_detail_screen.dart:980-982` (`_selfEnroll`), `1020-1030` (`_cancelEnrollment`)

Após enroll/cancel, revalidar via `_loadData()`/`getByCompetition` em vez de confiar só na mutação local; e parar de engolir a falha do write legado (`catch (_) {}` em 975-978 e 1021-1024) — logar para detectar divergência.

---

## Corretude de dados

### [HIGH] Editar resultado não atualiza a Achievement e excluir não a remove — medalhas/timeline órfãs ou erradas
`lib/screens/portal/competition_detail_screen.dart:1645-1653` (updateResult), `1670-1683` (cria achievement só no add), `1606` (`_deleteResult`) · `lib/providers/student_provider.dart:115-116` · `lib/services/achievement_service.dart:310`

Achievement de competição é criada apenas no **add**. Editar a posição (Ouro→Prata) não toca a achievement, e excluir o resultado deixa a medalha viva → `medalCount` e timeline ficam errados/órfãos, inflando gamificação. **Maior prioridade.** Plano:
1. Em `AchievementService`: `findCompetition`, `updateCompetitionPosition`, `deleteCompetitionAchievement` (query por `studentId` + `type==competition` + `competitionId`).
2. `_saveResult` branch `existingResult != null`: após `updateResult`, chamar `updateCompetitionPosition(...)`; se nenhuma achievement existir (resultado legado), criar para self-heal.
3. `_deleteResult` (1606): chamar `deleteCompetitionAchievement(result.studentId, result.competitionId)`.
4. Robustez: persistir `achievementId` no doc do resultado em `addResult` e ler de volta no edit/delete (sync por id exato, evita ambiguidade quando o aluno tem múltiplos resultados na mesma competição). Sem o id, escopar a query o mais estreito possível (incluir `modality`/`divisionType`).
5. Invalidar `studentMedalCountProvider`/`studentTimelineProvider`/`studentAchievementsProvider` do aluno afetado após edit/delete.

### [MEDIUM] Inscrição em sistema duplo (`enrolledStudentIds` + `competitionEnrollments`) dessincroniza contagem vs lista
`lib/services/competition_service.dart:413-432` (enroll/unenrollStudent) · `competitions_screen.dart:1269-1280` (admin enroll) e `1572` (badge `enrolledCount`) · `competition_detail_screen.dart:963-978`

Admin enroll grava na coleção; badge lê `enrolledCount` (derivado do array). Os dois divergem. **Tornar `competitionEnrollments` a fonte única** e derivar a contagem dela. Fix mínimo de display: pré-computar `Map<String,int>` de contagens em `_loadCompetitions` (uma query agrupando por `competitionId`, nunca async dentro do builder síncrono do card) e renderizar `counts[id] ?? competition.enrolledCount`. Fix de raiz: remover o dual-write legado (`enrollStudent`/`unenrollStudent` em 977, 1023, 1706) e sourcear tudo de `competitionEnrollments`.

### [MEDIUM] Editar data da competição não recalcula status e grava `DateTime` cru
`lib/screens/admin/competitions_screen.dart:849-859` — mesmo bug do achado #2 (Professor/Admin). Centralizar em `CompetitionService.update`: quando o map contém `date` e não há `status` manual, derivar `status = date.isBefore(now) ? completed : upcoming`, preservando override `ongoing`/`cancelled` existente. Usar `Timestamp.fromDate` para paridade com o create.

### [MEDIUM] Salvar resultado bloqueado quando divisão é "Absoluto"
`lib/screens/portal/competition_detail_screen.dart:1541-1542`, `1499-1507` — mesmo bug do achado #4. Gate condicional: `(divisionType == 'weight' && weightCategory.isEmpty) ? null : ...`; esconder/desabilitar o campo de peso quando `absolute` e passar `weightCategory` vazio/null. O read-side (660-665) já distingue absoluto.

### [LOW] `uploadPhoto` nunca grava `photoType` — fotos de equipe dependem do hack `studentId == '__team__'`
`lib/services/competition_photo_service.dart:79-93` · `competition_gallery.dart:115-124` · `lib/models/competition_photo.dart:99`

Adicionar param `String? photoType` em `uploadPhoto`, incluir no `photoData`, e passar `photoType: _uploadPhotoType` no `_handleUpload`. Baixa prioridade (endurece um caminho que hoje só usa o sentinela; sem mudança de comportamento atual).

### [LOW] Self-enroll do aluno ignora `registrationDeadline` (`isRegistrationOpen` definido mas nunca usado)
`lib/screens/portal/competition_detail_screen.dart:326-328` (gate do botão) · `competition_service.dart:156-157`

Adicionar `&& competition.isRegistrationOpen` no gate e short-circuit em `_selfEnroll`. Enforcement real exige Cloud Function/serviço lendo o `registrationDeadline` — `firestore.rules:908-911` não compara tempo-vs-campo limpo e hoje deixa o aluno editar `enrolledStudentIds` incondicionalmente.

### [LOW] Resultado não valida vínculo com competição/aluno existente além do dropdown
`lib/services/competition_service.dart:465-500` (addResult) · `firestore.rules:947-952`

Duas mudanças: (1) **delete atômico** com WriteBatch (mesma correção do achado #1); (2) validação defensiva em `addResult` — `getById(competitionId)` e throw se null, para ids livres não criarem órfãos fora do dropdown. Dado o nível baixo, (1) é o de alto valor; (2) é hardening.

### [LOW] `TextEditingController` recriado a cada rebuild no dialog de resultado
`lib/screens/portal/competition_detail_screen.dart:1519, 1531` — duplicata do padrão de controllers (#6/#10). Corrigir uma vez.

---

## Plano priorizado (file:line + diffs)

Ordem por impacto/risco. Itens correlacionados agrupados para evitar retrabalho.

### P0 — High: sincronizar Achievement no edit/delete de resultado
`competition_detail_screen.dart:1606, 1645-1653` + `achievement_service.dart` (novos helpers)
Sem fonte literal a citar (é adição de método); seguir o plano de 5 passos do achado HIGH acima. **Impacto:** corrige gamificação/medalhas órfãs. Lembrar de invalidar os providers (`student_provider.dart:115-116`).

### P1 — Inscrições: fonte única + cascata atômica (agrupa #1, #16, #23, #8, #15-info)

**(a) Delete atômico com cascata de results + enrollments** — `competition_service.dart:356-365`:
```dart
Future<void> delete(String id) async {
  final results = await _resultsRef.where('competitionId', isEqualTo: id).get();
  final enrollments = await CompetitionEnrollmentService(academyId).getByCompetition(id); // ou query direta
  final batch = FirebaseService.firestore.batch();
  for (final doc in results.docs) { batch.delete(doc.reference); }
  for (final e in enrollments) { batch.delete(/* ref do enrollment */); }
  batch.delete(_collections.competition(id));
  await batch.commit(); // chunkar se > 500 ops; ou Cloud Function p/ atomicidade server-side
}
```
Isso torna o diálogo (`competitions_screen.dart:1363-1369`) verdadeiro.

**(b) Badge por contagem real** — `competitions_screen.dart:1572`: pré-computar `Map<String,int>` em `_loadCompetitions` e renderizar `counts[competition.id] ?? competition.enrolledCount`. Nunca async no builder do card.

**(c) Deprecar dual-write** (cleanup): remover `enrollStudent`/`unenrollStudent` de `competition_detail_screen.dart:977, 1023, 1706` e sourcear contagem/roster de `competitionEnrollments`. Enquanto não removido, trocar `catch (_) {}` (975-978, 1021-1024, 1685-1711) por logging.

### P2 — Status derivado de data (agrupa #2 e #23)
Centralizar em `competition_service.dart:346` (`update`):
```dart
Future<Competition> update(String id, Map<String, dynamic> data) async {
  if (data.containsKey('date') && !data.containsKey('status')) {
    final d = data['date'] is Timestamp ? (data['date'] as Timestamp).toDate() : data['date'] as DateTime;
    data['status'] = d.isBefore(DateTime.now())
        ? CompetitionStatus.completed.value : CompetitionStatus.upcoming.value;
  }
  data['updatedAt'] = FieldValue.serverTimestamp();
  await _collections.competition(id).update(data);
  return (await getById(id))!;
}
```
No edit sheet (`competitions_screen.dart:849-859`) passar `'date': Timestamp.fromDate(selectedDate)`. Opcional/definitivo: tornar as abas date-derived (achado #7) e parar de persistir status derivado.

### P3 — Validação "Absoluto" (agrupa #4 e #21)
`competition_detail_screen.dart:1541`:
```dart
onPressed: (divisionType == 'weight' && weightCategory.isEmpty)
    ? null
    : () => _saveResult(...),
```
+ esconder/desabilitar o campo de peso (`1513-1521`) quando `divisionType == 'absolute'` e passar `weightCategory` vazio nesse caso.

### P4 — Trava de duplo-toque + erros amigáveis (#3)
`competitions_screen.dart:1254-1310` e `competition_detail_screen.dart:1540-1568`: `bool isSaving`, early-return, `onPressed: isSaving ? null`, spinner, `finally` com `mounted`; tratar duplicata (`e.toString().contains('já está inscrito')`) com mensagem amigável.

### P5 — Permissões aluno↔rules (#9 e #13)
**(a)** `firestore.rules:953-954` (Opção A — liberar self-delete):
```
allow delete: if isAcademyAdmin(academyId)
  || (isAcademyInstructor(academyId) && hasExtraPermission(academyId, 'competitions:create'))
  || (belongsToAcademy(academyId) && isOwnStudentRecord(academyId, resource.data.studentId));
```
Deploy: `firebase deploy --only firestore:rules` (projeto `arpjj-76350`).
**(b)** Anti-inflação (#13): forçar `status:'pending'` para writes de não-staff em `competitionResults`/`achievements` no rules e excluir `pending` das agregações de ranking/medalhas nas Cloud Functions.

### P6 — Galeria: participação por resultado + fullscreen ownership (#11, #14)
`competition_detail_screen.dart:929` (`_buildGalleryTab`): `canParticipate = enrollments.any(me) || results.any(me)` → passar como `isEnrolled`/`canUpload`. `competition_gallery.dart:246-248`: passar `uid`/callback ao `PhotoFullscreenViewer` e reavaliar por `_currentPhoto.createdBy`. **Checar rules do write de foto** se filtra enrollment server-side.

### P7 — Cleanup de controllers (#6, #10, #24 — mesmo padrão, fix único)
Hoistar `weightController`/`notesController` (e `name`/`location`/`description` nos sheets de campeonato) para fora do `StatefulBuilder`, instanciar uma vez, dispor via `.whenComplete(...)` no future do `showModalBottomSheet`.

### P8 — Itens menores
`registrationDeadline` no gate (#18, `1519`→ adicionar `&& competition.isRegistrationOpen`); feedback de `student == null` (#12); `photoType` no `uploadPhoto` (#17); hint/fallback no "Adicionar" sem inscritos (#5); validação defensiva em `addResult` (#22).

**Notas de verificação:** confirmei in-place `delete()` (service:356-365) sem cleanup de enrollments; `update()` (346-351) grava map cru sem derivar status; e `past` filtrado por `date.isBefore(now)` (screen:71) enquanto `upcoming` vem de `getUpcoming()` por status — a divergência de eixo do achado #7 procede. Os números de linha do JSON batem com o estado atual do branch `firebase-production`.