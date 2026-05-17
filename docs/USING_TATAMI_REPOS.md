# Usando os repos do Tatami (manual para PRs de wiring)

> Manual prático de "como consumir" a camada `lib/api/*` que foi construída
> nos Sprints 0-7 (FE-only). Este doc é o guia que cada PR de wiring
> (#11, #12, #17-#21 na TaskList) segue. **Não cria código novo no `lib/api/`**
> — só explica como mudar `lib/services/`, `lib/providers/` e `lib/screens/`
> para usar o que já está pronto.

---

## Mapa do que está pronto

```
lib/api/
├── tatami_client.dart           Dio + Firebase ID token + retry 401
├── tatami_exception.dart        problem+json tipado + forUser() PT-BR
├── problem_interceptor.dart     4xx/5xx → TatamiException
├── idempotency.dart             IdempotencyKey + postIdempotent
├── feature_flags.dart           TatamiFlags + tatamiFlagsProvider
├── repositories.dart            Provider Riverpod para cada *Repo
├── domain_providers.dart        Providers de mais alto nível (com flag check)
├── identity_repo.dart           /v1/me + memberships
├── student_repo.dart            students CRUD + belt + assessment + stats
├── plan_repo.dart               plans CRUD + assign
├── class_repo.dart              classes CRUD + roster
├── settings_repo.dart           settings GET/PUT
├── link_code_repo.dart          gerar + redeem atômico
├── financial_repo.dart          financials + payments + monthly + billing
├── wallet_repo.dart             wallet + transactions
├── attendance_repo.dart         attendance + QR HMAC backend-signed
├── notification_repo.dart       inbox + FCM + broadcast
├── store_repo.dart              products + orders (decremento atômico)
├── competition_repo.dart        competitions + enrollments + results + photos
├── dto/                         DTOs 1:1 com OpenAPI (12 arquivos)
└── widgets/
    ├── api_error_view.dart      TatamiException → UI PT-BR
    └── paginated_list.dart      PaginatedList<T> com infinite scroll
```

---

## Receita: PR de wiring de UM contexto

### 1. Ligar a flag (Remote Config)

No Firebase console → Remote Config, criar a flag pertinente com default `false`:

```
useTatamiIdentity         (Sprint 1)
useTatamiReads            (Sprint 2)
useTatamiWrites           (Sprint 3)
useTatamiFinancials       (Sprint 4)
useTatamiAttendance       (Sprint 5)
useTatamiNotifications    (Sprint 6)
useTatamiStore            (Sprint 7)
useTatamiCompetitions     (Sprint 7)
```

No boot da app (`main.dart` depois do `Firebase.initializeApp`), ler os
valores e setar via `tatamiFlagsProvider.notifier.state` ANTES de
`runApp()` — vide pattern no doc 08 §15.

### 2. Trocar o caller (provider OU service)

**Antes (Firestore direto em um provider):**
```dart
final studentsProvider = FutureProvider<List<Student>>((ref) async {
  final firestore = ref.watch(firestoreProvider);
  final academyId = ref.watch(selectedAcademyIdProvider);
  final snap = await firestore
      .collection('academies').doc(academyId)
      .collection('students')
      .where('status', isEqualTo: 'active')
      .get();
  return snap.docs.map(Student.fromFirestore).toList();
});
```

**Depois (com feature flag):**
```dart
final studentsProvider = FutureProvider<List<Student>>((ref) async {
  final flags = ref.watch(tatamiFlagsProvider);
  if (flags.useTatamiReads) {
    // Caminho novo. tatamiStudentsProvider já checa a flag e lança
    // TatamiFlagDisabledError se chegamos aqui errado — boa proteção.
    final page = await ref.watch(
      tatamiStudentsProvider(
        StudentsQuery(
          academyId: ref.watch(selectedAcademyIdProvider) ?? '',
          filter: const StudentFilter(status: ApiStudentStatus.active),
        ),
      ).future,
    );
    return page.items.map(_apiStudentToLegacy).toList();
  }

  // Caminho legacy idêntico ao de antes — não mexer.
  final firestore = ref.watch(firestoreProvider);
  final academyId = ref.watch(selectedAcademyIdProvider);
  final snap = await firestore.collection('academies').doc(academyId)
      .collection('students').where('status', isEqualTo: 'active').get();
  return snap.docs.map(Student.fromFirestore).toList();
});
```

### 3. Adaptador `Api*` → modelo legacy

Cada wiring PR adiciona uma factory ou função `_apiXToLegacy` no model
legacy (ex: `Student.fromApiStudent(ApiStudent)`). Manter os modelos
legacy durante a transição é o que permite trocar o caminho de dados
**sem mexer em telas**.

Identity já tem isso pronto: `AppUser.fromCurrentUserResponse(...)`.

### 4. Tratamento de erro

```dart
try {
  final result = await ref.read(tatamiStudentsProvider(q).future);
  // ...
} on DioException catch (e) {
  if (e.error is TatamiException) {
    final t = e.error as TatamiException;
    if (t.isUnauthorized) {
      // Sessão expirou — sair do app.
    } else if (t.isForbidden) {
      // Mostrar "sem permissão" sem deslogar.
    } else {
      showSnackBar(t.forUser());
    }
  }
}
```

Para telas, o `ApiErrorView` (em `lib/api/widgets/`) faz isso
automaticamente:

```dart
asyncValue.when(
  data: (page) => MyList(page),
  loading: () => const Center(child: CircularProgressIndicator()),
  error: (e, st) => ApiErrorView(
    error: e,
    onRetry: () => ref.invalidate(myProvider),
  ),
);
```

### 5. Paginação infinita

```dart
PaginatedList<ApiStudent>(
  fetcher: (cursor) async {
    final page = await ref.read(studentRepoProvider).list(
      academyId,
      filter: StudentFilter(limit: 50, cursor: cursor),
    );
    return PageView(
      items: page.items,
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
    );
  },
  itemBuilder: (ctx, s, i) => StudentTile(s),
);
```

### 6. Idempotência em criações

```dart
final key = IdempotencyKey.generate();
// Persistir `key.value` em SharedPreferences se quiser tolerância a crash.
final student = await ref.read(studentRepoProvider).create(
  academyId,
  CreateStudentRequest(fullName: name),
  idempotencyKey: key,
);
```

### 7. Test override

```dart
testWidgets('lista mostra erro tratado', (tester) async {
  final container = ProviderContainer(
    overrides: [
      tatamiClientProvider.overrideWithValue(mockClient),
      tatamiFlagsProvider.overrideWith(
        (ref) => TatamiFlags.allOff.copyWith(useTatamiReads: true),
      ),
    ],
  );
  // ...
});
```

---

## Pré-requisitos por sprint (já reflitidos na TaskList)

| Sprint | Tasks | Pré-requisitos externos |
|---|---|---|
| 1 | #11 | staging URL + Remote Config |
| 2 | #12 | #11 + endpoint `/profile` agregado no BE |
| 3 | #17 | #11 + Cloud Function `mirror_to_firestore` por 1 semana |
| 4 | #18 | #11 + webhook cutover (shadow 7d) + KEK key configurada |
| 5 | #19 | #11 + outbox worker rodando staging |
| 6 | #20 | #11 + PR 4 BE mergeado (guardian propagation) |
| 7 | #21 | #11 + PR 6 BE (opcional, `/v1/uploads/sign` genérico) |
| 8 | #9  | tudo acima + >30d estabilidade + 0 rollbacks |

---

## O que NÃO está pronto e fica pra wiring PRs decidir

- **Cloud Functions de mirror dual-write** — fora do FE.
- **SSE stream de notificações** — Sprint 6 wiring decide: polling com
  ETag (doc 03 §8) como caminho rápido, OU integração com
  `event_source` package.
- **Photo upload genérico /v1/uploads/*** — depende do PR 6 BE. Por
  enquanto, per-competition já cobre via `competition_repo`.
- **Storage migrator background** — server-side worker (River
  `migrate_legacy_photos`).

---

## Convenção de commits dos PRs de wiring

```
feat(<contexto>-wiring): Sprint N — ligar X via flag useTatamiY

- Adiciona branch `if (flags.useTatamiY)` em <provider/service>
- Adiciona Adapter ApiX → ModelLegacy quando aplicável
- Mantém branch legacy intacta até Sprint 8

Tests: <int/widget/E2E>.
Rollback: flipar flag para false (Remote Config).
```

Cada wiring PR fecha quando o canary 10% rodar 48h sem regressão.
