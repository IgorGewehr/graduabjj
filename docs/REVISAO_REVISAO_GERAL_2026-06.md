All findings confirmed against actual code. The `main.dart` ErrorWidget.builder is confirmed to swallow errors silently (no `FlutterError.presentError`/Crashlytics call). The overcharge findings confirmed (paid branch increments unconditionally, no `isOvercharge` guard). I have enough to write the report.

## Resumo

Estado geral: o branch `firebase-production` (em prod, `arpjj-76350`) está **funcional mas com um crash bloqueante real** no onboarding de professor por convite. Os demais achados são defensivos (RangeError em avatares com nome vazio, parsing de horário sem guarda, cast legado de stripes) e dois de receita (overcharge contado como pago).

O hotfix de tela-branca **confere parcialmente**, e essa é a parte mais importante a entender:

- `lib/main.dart:23-45` instala um `ErrorWidget.builder` que troca o retângulo cinza do Flutter por um card amigável "Algo deu errado ao carregar esta tela". Isso **funciona** como rede de segurança visual.
- **Porém ele NÃO corrige o bug** do onboarding de professor — apenas mascara o crash com um card. O professor que usa convite de 8 dígitos chega no passo de cadastro e bate em `_validatedLinkCode!.studentName` (null em modo instrutor) → o build lança → o usuário vê o card de erro em vez do formulário. Para o usuário final, o fluxo continua **quebrado**.
- Pior: o `ErrorWidget.builder` **engole o erro silenciosamente** — não chama `FlutterError.presentError(details)` nem encaminha para Crashlytics. Crashes determinísticos de build ficam invisíveis em produção.

Conclusão honesta: o hotfix de tela-branca é correto como mitigação de UX, mas foi tratado como se resolvesse o problema. O crash do instrutor precisa ser corrigido na origem (`link_code_screen.dart`), e o builder precisa logar/reportar antes de retornar o card.

---

## Login / onboarding / presença

**1. [ALTO] Onboarding de professor crasha no passo de cadastro** — `lib/screens/auth/link_code_screen.dart:667` (e `:915`)

Confirmado. No passo de validação (`:599-601`) o código já trata os dois modos corretamente (`_isInstructorMode ? _validatedInstructorCode! : _validatedLinkCode!`). Mas o campo "Nome" read-only em `_buildRegisterStep` (`:666-675`) lê `_validatedLinkCode!.studentName` **incondicionalmente**. Em modo instrutor `_validatedLinkCode` é null → null-check operator dispara → ErrorWidget. O instrutor já tem o próprio campo editável "Nome completo" em `:680-691`, então o campo read-only é redundante para ele.

A tela de sucesso (`:915`) tem o mesmo bug: `'...vinculada ao aluno ${_validatedLinkCode!.studentName}'` sem branch de modo. Mesmo se o cadastro do instrutor passasse, ele crasharia no sucesso.

**2. [MÉDIO] Card de presença crasha (RangeError) para aluno com fullName vazio** — `monitor_attendance_screen.dart:1211`, `attendance_screen.dart:1394`, `financial_screen.dart:2513`

Confirmado os três sites: `student.fullName[0].toUpperCase()` sem guarda. O padrão seguro já existe no mesmo arquivo (`attendance_screen.dart:1595-1597`: `s.fullName.isNotEmpty ? s.fullName[0].toUpperCase() : '?'`), só não foi aplicado nestes três. Qualquer aluno cadastrado sem nome derruba a lista de chamada inteira.

---

## Turmas / financeiro

**3. [BAIXO] displayName[0] pode dar RangeError** — `student.dart:520`

Confirmado. `String get displayName => nickname ?? fullName.split(' ').first;`. Se `nickname` for string vazia (não null), `??` não pega; e se `fullName` for vazio, `split(' ').first` retorna `''`. Os call sites de avatar (`classes_screen.dart:2424`, `monitor_students_screen.dart:616`, `students_list_screen.dart:827`) então fazem `[0]` → RangeError. Corrigir na origem resolve todos de uma vez.

**4. [BAIXO] Parsing de horário sem guarda crasha home do aluno + queries de turma** — `class_service.dart:138-139,221-222`, `student_provider.dart:308-345`, `classes_screen.dart:28-31`

Confirmado em `class_service.dart`: `s.startTime.split(':').map(int.parse).toList()` em `isHappeningNow` e `getCurrentClass`. `int.parse` (não `tryParse`) sem checar `length` → um doc de schedule com horário malformado (`""`, `"19"`, `"19:00:00"` parcial) derruba a query inteira. Vale um helper único `_scheduleMinutes` roteando os 5 sites.

**5. [BAIXO] currentStripes legado/double pode quebrar o parse inteiro do Student** — `student.dart:417` e `:582`

Confirmado. `:417` faz `data['currentStripes'] ?? 0` (se vier `double`, o campo `int currentStripes` recebe double → erro de tipo) e `:582` faz `data['currentStripes'] as int?` (cast direto falha se for `double`). O idioma seguro `(data['x'] as num?)?.toInt()` já é usado em `:430` (`monthlyAttendanceGoal`). Um único doc legado com stripes salvo como double quebra o parse e some o aluno da lista.

**6. [INFO] addStudent não-atômico** — `class_service.dart:392-405` + `409-467`

Membership da turma e seeding de esporte são writes separados; falha no seed deixa estado meio-aplicado. Recomendado batch/transaction, ou no mínimo `try/catch` best-effort no `_enrollStudentInSport`.

**7. [INFO] Docs de overcharge contados em paidTotal** — `payment_service.dart:331-334` e `~384+`

Confirmado: o branch `case PaymentStatus.paid:` em `streamStatsByStudent` (e `getStatsByStudent`) incrementa `paidCount`/`paidTotal` **sem** o guard `if (p.isOvercharge) break;` que já é usado em 5+ lugares (`financial_report_service.dart:132`, `payment_service.dart:1057`, `admin/financial_screen.dart:73`, `admin/reports_screen.dart:502`). Cobranças indevidas a reembolsar inflam o "pago" do aluno. Inconsistente com o resto da base.

---

## Saúde geral (riscos de crash / regressão)

- **Risco de crash em produção AGORA:** o item 1 (instrutor) é o único bloqueante ativo — qualquer professor convidado bate nele. Itens 2/3/4/5 são crashes condicionados a dados sujos (nome vazio, horário malformado, stripes double); a probabilidade depende de quão limpa está a base legada — vale auditar antes do próximo release.
- **O ErrorWidget.builder está sólido como UX mas cego como observabilidade.** Confirmado em `main.dart:23-45`: nenhuma chamada a `FlutterError.presentError(details)` nem a Crashlytics. Hoje o item 1 vira um card genérico e ninguém fica sabendo. Manter o hotfix, mas adicionar log/report antes do `return`.
- **Sem regressão de mascaramento perigoso:** o builder não esconde nada que já não fosse um crash — ele melhora o estado anterior (tela branca). A crítica é só que foi tratado como cura, não como curativo.

---

## Plano priorizado

**P0 — Corrigir o crash do instrutor (origem), `link_code_screen.dart`**

`:665-677` — só renderizar o campo read-only para aluno:
```dart
// Name field (read-only, from link code) — student only
if (!_isInstructorMode) ...[
  TextFormField(
    initialValue: _validatedLinkCode!.studentName,
    enabled: false,
    decoration: InputDecoration(
      labelText: 'Nome',
      prefixIcon: const Icon(LucideIcons.user, size: 20),
      filled: true,
      fillColor: AppTheme.surface,
    ),
  ).animate().fadeIn(delay: 300.ms).slideX(begin: -0.1),
  const SizedBox(height: 16),
],
```

`:914-915` — branch na cópia de sucesso:
```dart
Text(
  _isInstructorMode
      ? 'Conta de professor criada e vinculada a academia.'
      : 'Sua conta foi vinculada ao aluno ${_validatedLinkCode!.studentName}',
  ...
)
```
Depois, rodar o happy-path de convite 8 dígitos (validar → cadastrar → sucesso) e regredir o path de aluno 6 dígitos.

**P0 — Tornar o ErrorWidget.builder observável, `main.dart:23`** (dentro do builder, antes do `return Material(...)`):
```dart
FlutterError.presentError(details);
// e/ou FirebaseCrashlytics.instance.recordFlutterError(details);
```

**P1 — Avatares range-safe (RangeError de chamada).** Corrigir `displayName` na origem em `student.dart:520`:
```dart
String get displayName {
  final n = nickname?.trim().isNotEmpty == true
      ? nickname!.trim()
      : fullName.trim().split(' ').first;
  return n.isEmpty ? 'Aluno' : n;
}
```
E nos três sites de `fullName[0]` (`monitor_attendance_screen.dart:1211`, `attendance_screen.dart:1394`, `financial_screen.dart:2513`) aplicar `student.fullName.isNotEmpty ? student.fullName[0].toUpperCase() : '?'` (padrão já em `attendance_screen.dart:1595`).

**P1 — currentStripes defensivo, `student.dart`:**
- `:417` → `currentStripes: (data['currentStripes'] as num?)?.toInt() ?? 0`
- `:582` → `currentStripes: (data['currentStripes'] as num?)?.toInt() ?? 0`
- (mesmo tratamento em `graduation_screen.dart:471/1048`)

**P2 — Helper de parsing de horário.** Em `class_service.dart` adicionar `int? _scheduleMinutes(String hhmm)` (split → `tryParse` → null se inválido) e rotear `isHappeningNow` (`:138-139`), `getCurrentClass` (`:221-222`), `studentNextClassProvider` (`student_provider.dart:308-345`, `continue` em entrada ruim) e `_parseTimeString` (`classes_screen.dart:28-31`, fallback `19:00`).

**P3 — Higiene financeira/atomicidade:**
- Overcharge: em `payment_service.dart:331` (e `getStatsByStudent`), adicionar `if (p.isOvercharge) break;` no topo do `case PaymentStatus.paid:`.
- `addStudent`: `try/catch` best-effort em `_enrollStudentInSport` (`class_service.dart:409`) ou converter membership + seed para um único batch.

Arquivos relevantes (todos verificados): `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/auth/link_code_screen.dart`, `/Users/igorgewehr/WebstormProjects/graduabjj/lib/main.dart`, `/Users/igorgewehr/WebstormProjects/graduabjj/lib/models/student.dart`, `/Users/igorgewehr/WebstormProjects/graduabjj/lib/services/class_service.dart`, `/Users/igorgewehr/WebstormProjects/graduabjj/lib/services/payment_service.dart`, `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/portal/monitor_attendance_screen.dart`, `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/admin/attendance_screen.dart`, `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/admin/financial_screen.dart`, `/Users/igorgewehr/WebstormProjects/graduabjj/lib/providers/student_provider.dart`, `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/admin/classes_screen.dart`.