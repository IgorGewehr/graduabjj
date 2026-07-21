> **Arquivado (2026-07):** o achado CRÍTICO (leitura pública do doc bruto de
> `students/{studentId}` com `isProfilePublic==true`, vazando toda a PII) foi
> **corrigido** — `firestore.rules:579-584` documenta a remoção desse read
> público; o acesso público hoje é só via `publicProfiles` (espelho sem PII).
> Os demais achados (gates de permissão client-only, faixa errada no monitor
> multimodal) não foram reverificados; registro histórico.

The key claims are verified against the actual code. The critical Firestore rule (line 444), the unguarded `as int?` cast (line 582), the ungated admin menu (lines 308-380), and the getGrade null-return all confirm. Producing the report.

# Auditoria do Perfil do Aluno — GraduaBJJ

## Resumo

Foram confirmados **16 achados** em três superfícies (perfil portal, detalhe admin, monitor) mais privacidade/multimodalidade. A gravidade se concentra em dois temas:

1. **Privacidade (1 CRÍTICO):** a regra Firestore `students/{studentId}` expõe o **documento bruto com toda a PII** quando `isProfilePublic == true`, anulando completamente o design do espelho `publicProfiles` sem PII. Correção é de 1 linha e deve ir para produção imediatamente.
2. **Permissões admin (2 HIGH):** o menu de ações do detalhe do aluno (Graduar / Desativar / Apagar / Gerar código) **não tem nenhum gate de permissão** no cliente — qualquer staff vê e dispara. E a tela de monitor renderiza **faixa errada** para alunos multimodais (usa `currentBelt` legado + mapa de nomes só-BJJ).

Tema transversal de **multimodalidade**: várias telas ainda leem os campos legados `currentBelt`/`currentStripes` em vez de `getGrade(sport)` por esporte, produzindo faixas erradas para não-BJJ e ignorando esportes secundários. Esportes de presença (boxe/MMA/musculação, `GradeSystem.none`) renderizam um rótulo "white" sem sentido.

Distribuição: 1 critical · 3 high · 4 medium · 6 low · 2 info.

Verificações feitas no código atual: `firestore.rules:444` (regra pública confirmada), `student.dart:582` (`as int?` confirmado), `student_detail_screen.dart:308-380` (menu sem gate confirmado), `student.dart:579` (`getGrade` retorna `null` confirmado).

---

## Perfil do aluno (portal)

| # | Sev | Achado | Local |
|---|-----|--------|-------|
| 1 | medium | Perfil mostra só a faixa do esporte **primário** — multimodalidade invisível ao aluno | `profile_screen.dart:455-505`; `public_profile_screen.dart:215-298` |
| 2 | medium | Editar "Email" no perfil atualiza só o doc do aluno, **nunca o email de login do Firebase Auth** | `profile_screen.dart:1028-1033` + `_save:969-1002` |
| 3 | medium | Rótulo de faixa sem sentido ("white") para esportes de presença no hero | `profile_screen.dart:487-505` |
| 4 | low | Check de propriedade do perfil público usa só `currentUser.studentId` — aluno via `linkedUserId` vê o próprio perfil como "privado" | `public_profile_screen.dart:110-121` |
| 5 | low | Resumo de "Dados Pessoais" desalinhado com `_isPersonalDataEmpty` — birthDate/CPF/RG some do resumo, mostra "Nenhum dado" indevidamente | `profile_screen.dart:227-237` vs `265-273` |
| 6 | low | Hero belt renderiza "faixa branca" para `GradeSystem.none` (boxe/MMA/musculação) | `profile_screen.dart:487-505` |
| 7 | info | Copy do toggle de privacidade subestima exposição (foto, idade, timeline, competições, fotos) | `profile_screen.dart:891-902` |

**Achado #2 (Email vs Auth)** é o mais perigoso desta seção: o campo "Email" é editável e persiste via `studentService.update`, mas **não existe `verifyBeforeUpdateEmail`/`updateEmail` em nenhum lugar de `lib/`**. O aluno acredita que mudou o login, mas continua autenticando com o email antigo — divergência silenciosa entre identidade da conta e doc. Mínimo: tornar o campo read-only com nota; ideal: rotear via reauth + `verifyBeforeUpdateEmail`.

---

## Detalhe do aluno (admin)

| # | Sev | Achado | Local |
|---|-----|--------|-------|
| 8 | **high** | Ações do AppBar (Graduar / Desativar / Apagar / Gerar código / editar) **NÃO são gated por permissão** | `student_detail_screen.dart:308-380`; ações em `:4150/:4286/:4312/:4389` |
| 9 | **high** | Monitor usa `currentBelt` legado + mapa de nomes só-BJJ → faixa/cor/rótulo errados para não-BJJ e multi-esporte | `monitor_student_detail_screen.dart:194-343`, `_getBeltColor:1545` |
| 10 | medium | Dialog de graduação **finge sucesso** (confete + "Graduação realizada!") para esportes sem graduação (Boxe/MMA/Musculação) | `student_detail_screen.dart:4150-4271` |
| 11 | low | Pencil de valor-custom/dia-de-vencimento do plano **não gated por permissão financeira** | `student_detail_screen.dart:1846-1853` → `_showCustomValueDialog:2477` |
| 12 | low | Avatar do monitor chama `fullName.substring(0,1)` sem guarda → `RangeError` em nome vazio | `monitor_student_detail_screen.dart:247-250` |
| 13 | low | **Observações médicas** exibidas a student-monitors read-only (exposição de dado sensível) | `monitor_student_detail_screen.dart:433-453` |

**Achado #8** é defesa-em-profundidade crítica: o gate de cliente sozinho é bypassável, então as **Cloud Functions e regras Firestore correspondentes** (status, hard-delete cascade, escrita de graduação, geração de código) precisam impor as mesmas permissões server-side. Achado #11 tem nuance: a escrita já é admin-only em `firestore.rules:610`, então o gate correto é `currentUser.isAdmin` (não `financial:create`) para evitar `PERMISSION_DENIED` num instrutor financeiro.

---

## Privacidade e multimodalidade

| # | Sev | Achado | Local |
|---|-----|--------|-------|
| 14 | **critical** | Regra Firestore expõe o doc do aluno com **TODA a PII** publicamente quando `isProfilePublic == true` (anula o espelho) | `firestore.rules:442-444` |
| 15 | low | `getGrade()` faz cast `currentStripes as int?` → `CastError` se Firestore retornar double/num | `student.dart:581-582` |
| 16 | low | Mirror usa `merge:true` — campo removido do source não é apagado do espelho público | `server_functions.js:910-914` |
| — | info | `getGrade` retorna `null` para esporte graduado sem `sportData` — depende de todo call site aplicar `?? white` | `student.dart:573-584` |

(Os HIGH/MEDIUM de multimodalidade — monitor com faixa errada e perfil próprio com "white" — são os achados #9, #3 e #6 já listados acima; mesma raiz: leitura de campos legados em vez de `getGrade(sport)`.)

---

## Plano priorizado (file:line + diffs)

### P0 — Deploy imediato

**[#14 · critical] Remover leitura pública do doc do aluno** — `firestore.rules:444`

```diff
        // Public read of opted-in profiles (public fighter profile / public site).
        // Gated by the per-student isProfilePublic flag (default false).
-       allow read: if resource.data.isProfilePublic == true;
```

O acesso social continua via `publicProfiles` (regra `firestore.rules:522-525` já cobre público). Nenhuma outra mudança de código — ranking provider e student_service já leem o espelho. Deploy: `firebase deploy --only firestore:rules`.

### P1 — Permissões e dados errados

**[#8 · high] Gatear ações do AppBar admin** — `student_detail_screen.dart:308-380`

Ler `ref.watch(currentUserProvider).valueOrNull` e construir condicionalmente:
- `edit` → `isAdmin || hasPermission('students:edit')`
- `promote` → `isAdmin || hasPermission('graduation:manage')` (também gatear o botão "Graduar agora" em `:655`)
- `toggle_status` → `isAdmin || hasPermission('students:manage')`
- `generate_code` → `isAdmin || hasPermission('students:manage')`
- `delete` → `isAdmin || hasPermission('students:delete')`
- Omitir o `PopupMenuButton` inteiro se a lista resultar vazia.
- Defesa em profundidade: no-op em `_showPromoteDialog`/`_toggleStatus`/`_showHardDeleteConfirmation`/`_generateLinkCode` quando faltar permissão **+ verificar rules/CFs server-side**.

**[#9 · high] Monitor: usar grade por esporte** — `monitor_student_detail_screen.dart:194-343`

```dart
final sport = _student!.getPrimarySport();
final grade = _student!.getGrade(sport);
final gradeId = grade?.currentGrade ?? 'white';
final stripes = grade?.currentStripes ?? 0;
```
- `backgroundColor`/gradient (`194,220-221`): `_getBeltColor(gradeId, sportId: sport)`.
- Checks de texto branco (`195,254,271,323,334,364`): `gradeId == 'white'` em vez de `_student!.currentBelt == 'white'`.
- `_buildBeltBadge` (`298-343`): remover mapa `beltNames` hardcoded → `getGradeLabel(sport, gradeId)`, usar `stripes`.
- Ideal: iterar `_student!.getSports()` e renderizar um badge por modalidade (espelhar `student_detail_screen.dart:474-501`).

### P2 — Multimodalidade no perfil + correctness

**[#10 · medium] Dialog de graduação: não fingir sucesso** — `student_detail_screen.dart:4150-4271`
- Dropdown: filtrar para `getSport(s).gradeSystem != GradeSystem.none` (espelhar `:137-139`).
- Botão Confirmar: mover `Celebration.confetti` + "Graduação realizada com sucesso!" **para dentro** dos branches que de fato chamaram o service (ou usar flag `bool didPromote`).
- Caso single-sport com sport `GradeSystem.none`: não abrir o dialog.

**[#3/#6 · medium/low] Perfil próprio: gatear belt em `grade != null`** — `profile_screen.dart:487-505`

```dart
if (grade != null) ...[
  // AnimatedBelt + GradeBadge (como public_profile_screen.dart:292-296)
],
```
Substituir fallbacks `?? 'white'` por `grade.currentGrade`/`grade.currentStripes`. Para esportes de presença (grade null), chip de modalidade em vez de faixa vazia.

**[#1 · medium] Mostrar esportes secundários** — `profile_screen.dart:455-505` + `public_profile_screen.dart:215-298`
Após o hero do esporte primário, iterar `student.getSports().where((s) => s != primarySport)`: `GradeBadge`/`AnimatedBelt` compacto via `student.getGrade(s)` (pular se null); para `GradeSystem.none`, chip de presença. Aplicar igual nas duas telas.

**[#2 · medium] Email vs Auth** — `profile_screen.dart:1028-1033` + `_save:969-1002`
Mínimo: campo read-only com nota "não altera o email de login" + validação de formato. Ideal: reauth (`reauthenticateWithCredential`, já em `auth_provider.dart:294`) → `user.verifyBeforeUpdateEmail(newEmail)` → atualizar doc só após confirmação.

### P3 — Robustez / hardening

**[#15 · low] Cast seguro de stripes** — `student.dart:582`

```diff
-     currentStripes: data['currentStripes'] as int? ?? 0,
+     currentStripes: (data['currentStripes'] as num?)?.toInt() ?? 0,
```

**[info] `getGrade` retornar default não-nulo p/ graded sports** — `student.dart:579`

```diff
-     if (data == null) return null;
+     if (data == null) return (currentGrade: 'white', currentStripes: 0);
```

**[#16 · low] Projeção completa do mirror** — `server_functions.js:910-914`
Iterar toda a `PUBLIC_PROFILE_SAFE_FIELDS` emitindo `null` (ou `FieldValue.delete()`) para campos ausentes, para que `merge:true` limpe valores removidos.

**[#4 · low] Ownership via currentStudentProvider** — `public_profile_screen.dart:110-113`

```dart
final viewerStudentId = ref.watch(currentStudentProvider).valueOrNull?.id
    ?? ref.read(currentUserProvider).valueOrNull?.studentId;
```

**[#12 · low] Guarda no avatar do monitor** — `monitor_student_detail_screen.dart:248-250`
`Text((_student!.fullName.isNotEmpty ? _student!.fullName[0] : '?').toUpperCase(), ...)`

**[#13 · low] Gatear PII médica no monitor** — `monitor_student_detail_screen.dart:417-453`
Envolver notas médicas (432-453) e info do responsável (417-430) em `canSeePII = isAdmin || isInstructor || hasPermission('students:manage')`.

**[#5 · low] Alinhar resumo de dados pessoais** — `profile_screen.dart:227-237`
Em `_getPersonalDataSummary`, fallback quando `parts.isEmpty` mas há birthDate/cpf/rg/weight (idade, CPF mascarado), para nunca cair em "Nenhum dado" quando `_isPersonalDataEmpty` é false.

**[#7 · info] Expandir copy do toggle de privacidade** — `profile_screen.dart:898`
"Outros alunos verão sua foto, idade, faixa, linha do tempo, competições e fotos" (ou ícone-info com sheet).

---

Arquivos centrais para a implementação (todos caminhos absolutos):
- `/Users/igorgewehr/WebstormProjects/graduabjj/firestore.rules`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/models/student.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/portal/profile_screen.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/portal/public_profile_screen.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/portal/monitor_student_detail_screen.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/admin/student_detail_screen.dart`
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/server_functions.js`