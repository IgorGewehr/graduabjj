# 03 — Otimizações gerais habilitadas pelo novo backend

> **Premissa.** O Tatami devolve dados paginados, agregações pré-computadas e errors tipados. Isso destrava melhorias no app que não fazem sentido enquanto o backend é Firestore direto. Este documento agrupa essas oportunidades por área, mostrando código-antes / código-depois e estimando impacto.
>
> Ordenado por **payoff / esforço**: os primeiros itens entregam mais com menos refactoring.

---

## 1. State management — Riverpod estruturado com cache + invalidation correta

### Problema hoje

Padrão recorrente em `lib/providers/`:

```dart
final studentListProvider = FutureProvider.autoDispose((ref) async {
  return studentService.getActive();
});
```

- `autoDispose` mata o cache ao fechar a tela; ao voltar, refetch completo.
- Sem `keepAlive`, dois screens lendo a mesma lista fazem **2 fetches**.
- Não há invalidation chamada após mutations — depende de `ref.invalidate(provider)` espalhado nos handlers.

### Solução

Adotar **`AsyncNotifier`** + invalidação explícita por mutation:

```dart
// students_notifier.dart
class StudentsNotifier extends AutoDisposeFamilyAsyncNotifier<
    StudentPage, StudentFilter> {
  
  @override
  Future<StudentPage> build(StudentFilter filter) async {
    ref.keepAlive(); // mantém em memória mesmo sem listeners por 5 min
    final repo = ref.read(studentRepoProvider);
    return repo.list(
      status: filter.status,
      belt: filter.belt,
      cursor: filter.cursor,
    );
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;
    state = AsyncValue.data(
      current.appendNext(
        await ref.read(studentRepoProvider).list(cursor: current.nextCursor),
      ),
    );
  }
  
  Future<void> create(StudentCreateInput input) async {
    final repo = ref.read(studentRepoProvider);
    final created = await repo.create(input);
    // Optimistic: pré-pendemos o novo aluno
    state = state.whenData((page) => page.prepend(created));
    // Servidor é fonte da verdade — invalida depois para reconciliar contagem total
    ref.invalidateSelf();
  }
}

final studentsProvider = AsyncNotifierProvider
    .autoDispose.family<StudentsNotifier, StudentPage, StudentFilter>(
  StudentsNotifier.new,
);
```

### Impacto

- Cache funciona entre navegações.
- Optimistic updates dão sensação de instantaneidade.
- Invalidation explícita evita "tela mostrando dado obsoleto" depois de mutation.

---

## 2. Paginação universal — `InfiniteScrollList` reutilizável

### Problema hoje

`monitor_students_screen.dart` carrega 200+ alunos em memória, aplica 4 passes de filtro client-side, sort, e renderiza tudo de uma vez em um `ListView`. Sem `ListView.builder` lazy.

### Solução

Componente único `PaginatedList<T>`:

```dart
class PaginatedList<T> extends ConsumerStatefulWidget {
  final AsyncNotifierProviderBase<dynamic, Page<T>> provider;
  final Widget Function(BuildContext, T) itemBuilder;
  final Widget? emptyState;
  final Widget? loadingFooter;
  // ...
}

class _PaginatedListState<T> extends ConsumerState<...> {
  final scrollCtrl = ScrollController();
  
  @override
  void initState() {
    super.initState();
    scrollCtrl.addListener(_onScroll);
  }
  
  void _onScroll() {
    if (scrollCtrl.position.pixels >= scrollCtrl.position.maxScrollExtent - 300) {
      // Próximos 50 itens
      ref.read(widget.provider.notifier).loadMore();
    }
  }
  
  @override
  Widget build(BuildContext ctx) {
    final async = ref.watch(widget.provider);
    return async.when(
      data: (page) => ListView.builder(
        controller: scrollCtrl,
        itemCount: page.items.length + (page.hasMore ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i >= page.items.length) return const _LoadingTile();
          return widget.itemBuilder(ctx, page.items[i]);
        },
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorState(error: e as TatamiException),
    );
  }
}
```

Usado em **todas** as listas (alunos, attendance, financials, pedidos, achievements).

### Impacto

- Listas de 1000+ itens não travam o app.
- Tempo até primeiro byte cai (paginação server-side é rápida no Postgres com índice composto).
- Custo de transferência cai (50 docs vs. 1000).

---

## 3. Image caching e thumbnailing

### Problema hoje

```dart
CachedNetworkImage(imageUrl: student.photoUrl)
```

- Sem `cacheWidth`/`cacheHeight`. Foto de 5 MP é renderizada em 48×48 → desperdício de RAM e CPU.
- A URL do Firebase Storage não tem variantes de tamanho.
- Cache padrão dura indefinidamente (sem invalidation se a foto muda).

### Solução

1. **Backend gera variantes** ao receber upload finalizado (ver doc 02 §9): `original`, `thumb_128`, `medium_512`. Worker River (`store/photo_processor.go`, ainda a criar) usa `imaging` em Go ou chama serviço externo.
2. **Cliente pede a variante apropriada** via signed URL: `GET /v1/uploads/{path}/download-url?variant=thumb_128`.
3. **Widget unificado:**

```dart
class StudentAvatar extends StatelessWidget {
  final String? storagePath;
  final double size;
  const StudentAvatar({this.storagePath, this.size = 48});

  @override
  Widget build(BuildContext ctx) {
    final variant = size <= 64 ? 'thumb_128' : size <= 256 ? 'medium_512' : 'original';
    return FutureBuilder<String>(
      future: ref.read(uploadsRepoProvider).downloadUrl(storagePath!, variant: variant),
      builder: (ctx, snap) => CachedNetworkImage(
        imageUrl: snap.data ?? '',
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(ctx)).round(),
        cacheHeight: (size * MediaQuery.devicePixelRatioOf(ctx)).round(),
        // ...
      ),
    );
  }
}
```

### Impacto

- Memória do app cai significativamente em telas com listas de avatares.
- 90% menos bytes transferidos para listagens.
- Cache invalida quando o `storage_path` muda (não a URL — a URL é regenerada).

---

## 4. Eliminação de denormalização redundante

### Problema hoje

`Attendance` armazena `studentName` + `className` snapshot. `Achievement` armazena nome do aluno. Esses snapshots:
- Ficam obsoletos quando o aluno muda de nome.
- Custam bytes em cada doc.
- O cliente "confia" no snapshot — mas se o snapshot está errado, a tela mostra errado.

### Solução

O Tatami **não denormaliza nomes** em tabelas de eventos. As listagens fazem JOIN:

```sql
-- backend: list attendance
SELECT a.*, s.full_name AS student_name, c.name AS class_name
FROM attendance a
JOIN students s ON s.id = a.student_id
JOIN classes  c ON c.id = a.class_id
WHERE a.academy_id = $1 AND a.date BETWEEN $2 AND $3;
```

A resposta JSON traz o nome **atual** sempre. Cliente para de receber nomes desatualizados.

### Para snapshots LEGÍTIMOS (ex.: valor pago em `wallet_transactions.amount`)

Esses ficam — são fatos imutáveis sobre o passado. A regra é: **denormalize fatos, normalize nomes**.

### Impacto

- Bug de "renomeou aluno e antiga conquista mostra nome velho" some.
- Reduz tamanho de cada row de attendance em ~80 bytes (40k attendances = 3 MB poupados).

---

## 5. Lazy-load por seção em `student_detail_screen`

### Problema hoje

`screens/admin/student_detail_screen.dart` faz 8 fetches em paralelo com `Future.wait`:

```dart
final futures = await Future.wait([
  studentService.getById(...),
  attendanceService.getByStudent(...),  // SEM limit
  paymentService.getByStudent(...),     // SEM limit
  storeService.getOrdersByStudent(...),
  beltService.getByStudent(...),
  achievementService.getForStudent(...),
  assessmentService.getByStudent(...),
  planService.getPlansForStudent(...),
]);
```

- Carrega histórico inteiro para abrir uma tela.
- Tabs invisíveis (achievements, assessments) já vêm carregadas.

### Solução A — Endpoint agregador (rápido)

```dart
final profile = await api.get('/v1/academies/$aid/students/$sid/profile');
// Retorna:
// {
//   student: {...},
//   attendance_recent: [...10 itens],
//   payments_open: [...10 itens],
//   orders_recent: [...5 itens],
//   belt_progression_summary: { current: 'blue/1', last_promotion: '2025-12-10' },
//   achievements_count: 12,
//   assessments_count: 6,
//   active_plan: { id, name }
// }
```

Tela renderiza header com isso. Cada **tab** dispara um provider separado quando o usuário clica nela:

```dart
final attendanceTabProvider = AsyncNotifierProvider.family<
    AttendanceTab, AttendanceTabState, String>(...);

// só ativa quando o usuário toca a tab 'Presença'
```

### Solução B — Endpoint dedicado por tab

Mais granular: cada tab tem seu endpoint `GET /v1/.../attendance?student_id=...&limit=20`. A vantagem é não acoplar.

### Impacto

- Tempo de abertura da tela cai pela metade (header pronto antes do 8º fetch).
- Tabs nunca acessadas não custam nada.

---

## 6. Search com `pg_trgm` no backend

### Problema hoje

`StudentService.searchByName(query)`:

```dart
final all = await getAll();
return all.where((s) =>
  s.fullName.toLowerCase().contains(query.toLowerCase()) ||
  (s.nickname?.toLowerCase().contains(query.toLowerCase()) ?? false)
).toList();
```

Baixa tudo, filtra em Dart. Para academias com 500+ alunos isso vira lentidão perceptível ao digitar.

### Solução

Backend tem **GIN trigram index** em `students.full_name` (já planejado na migração `00004_student.sql`). Query:

```sql
SELECT * FROM students
WHERE academy_id = $1
  AND (full_name ILIKE '%' || $2 || '%' OR nickname ILIKE '%' || $2 || '%')
ORDER BY full_name
LIMIT 20;
```

Tempo: <5ms para uma academia com 5000 alunos.

Cliente:

```dart
class StudentSearchField extends ConsumerStatefulWidget {
  // debounce 300ms, então:
  Future<void> _search(String q) async {
    final results = await ref.read(studentRepoProvider).list(
      query: q, limit: 20,
    );
    setState(() => suggestions = results.items);
  }
}
```

### Impacto

- Search instantânea, sem download massivo.
- Acentos: `pg_trgm` é case e accent-insensitive com `unaccent` extension.

---

## 7. Dashboards e relatórios — leitura única de MV

### Problema hoje

`getDashboardStats()`, `FinancialReportService.loadAll()`, `RetentionService.calculateStudentRisk()` — todos carregam coleções inteiras e fazem agregação em Dart. Custo de abrir dashboard:
- 1 read de toda lista de students
- 1 read de toda lista de financials
- 1 read de toda lista de attendance dos últimos 30 dias
- Cálculos em memória

### Solução

Backend já provê:
- `mv_academy_kpis` — refrescada a cada 10 min, leitura ~1ms
- `v_monthly_revenue` — view regular
- `v_belts_distribution` — view regular
- `v_attendance_rate_30d` — view regular

Endpoint `GET /v1/academies/{id}/kpis?include=revenue_12m,belts_dist,attendance_30d` retorna tudo em uma única payload.

Cliente:

```dart
class DashboardScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext ctx, WidgetRef ref) {
    final kpis = ref.watch(dashboardKpisProvider);
    return kpis.when(
      data: (k) => Column(children: [
        KpiCard(label: 'Alunos ativos', value: k.activeStudents),
        KpiCard(label: 'Receita 30d',  value: k.revenuePaid30d.toCurrency()),
        KpiCard(label: 'Inadimplência', value: k.revenueOverdue.toCurrency()),
        BeltDistributionChart(data: k.beltsDistribution),
        RevenueLineChart(data: k.revenue12Months),
      ]),
      // ...
    );
  }
}
```

### Impacto

- Dashboard abre em <100ms (vs. segundos hoje).
- Sem dependência do tamanho da academia.

---

## 8. Eliminação de listeners Firestore desnecessários

### Problema hoje

`streamByStudent()`, `streamOrders()`, `streamPendingOrders()` — listeners vivos enquanto a tela está aberta. Custo Firestore:
- 1 read inicial + 1 read por documento modificado
- Se 200 admins têm o painel aberto, são 200 listeners

### Solução

**Default = polling otimizado com ETag.** Real-time só onde realmente importa (chamada de presença ao vivo).

```dart
class PollingNotifier<T> extends AutoDisposeAsyncNotifier<T> {
  Timer? _timer;
  String? _etag;
  
  @override
  Future<T> build() async {
    ref.onDispose(() => _timer?.cancel());
    _scheduleNextPoll();
    return _fetch();
  }
  
  void _scheduleNextPoll() {
    _timer = Timer(const Duration(seconds: 30), () async {
      try {
        final result = await _fetch(etag: _etag);
        state = AsyncValue.data(result);
      } on NotModifiedException { /* 304: estado mantido */ }
      _scheduleNextPoll();
    });
  }
}
```

Endpoint Tatami retorna `ETag` no header; cliente manda `If-None-Match` na próxima request; 304 em 90% das vezes (resposta de bytes ~0).

### Impacto

- Custo de tráfego cai (304 vs. payload completo).
- Sem listeners vagos consumindo reads.
- Real-time pode evoluir para SSE quando o backend tiver — sem mudar a UX.

---

## 9. Erro tipado em UX

### Problema hoje

`try { await firestoreCall() } catch (e) { showSnack(e.toString()) }` — mensagens crípticas tipo `PERMISSION_DENIED: Missing or insufficient permissions.`. Para o usuário final isso é tóxico.

### Solução

`TatamiException` já vem com `title`, `detail`, `errors[]`, `trace_id`. Padrão UX:

```dart
class ErrorView extends StatelessWidget {
  final TatamiException error;
  final VoidCallback? onRetry;
  
  String get _userMessage {
    if (error.isUnauthorized) return 'Sua sessão expirou. Faça login novamente.';
    if (error.isForbidden)    return 'Você não tem permissão para esta ação.';
    if (error.isNotFound)     return 'Não encontramos o que você procurava.';
    if (error.isValidation)   return error.errors.first.message;
    return 'Algo deu errado. Tente novamente.';
  }
  
  Widget build(BuildContext ctx) => Column(children: [
    Icon(Icons.error_outline, size: 48),
    Text(_userMessage),
    SizedBox(height: 8),
    Text('Código de erro: ${error.traceId}',
      style: TextStyle(fontSize: 11, color: Colors.grey)),
    if (onRetry != null) FilledButton(onPressed: onRetry, child: Text('Tentar novamente')),
  ]);
}
```

### Impacto

- Usuário entende o que aconteceu.
- Suporte tem o `trace_id` para investigar no Jaeger/Tempo.

---

## 10. Offline-first leve com `drift` (opcional)

### Quando faz sentido

Telas que o instrutor usa no tatame **sem internet** (chamada, anotação rápida de aula). Hoje o app é online-only.

### Solução

1. SQLite local via `drift` (sucessor do moor) para mirror de:
   - Lista de alunos (raramente muda)
   - Turmas do dia
2. Mutations enquanto offline ficam em uma fila local com Idempotency-Key gerada.
3. Quando conectividade volta, o cliente faz drain da fila chamando o Tatami; a Idempotency-Key garante que retentativas não duplicam.

### Impacto

- App funciona no tatame mesmo com rede ruim.
- Idempotency-Key + transações Postgres tornam isso seguro.

**Custo:** não trivial. Avaliar depois das fases 1-5 da migração.

---

## 11. `go_router` com guards centralizados

### Problema hoje

Cada tela faz `if (user?.academyId == null) return EmptyState()`. 133+ ocorrências.

### Solução

```dart
final router = GoRouter(
  refreshListenable: GoRouterRefreshStream(
    FirebaseAuth.instance.authStateChanges(),
  ),
  redirect: (ctx, state) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null && state.matchedLocation.startsWith('/portal')) {
      return '/login';
    }
    if (user != null) {
      // Pega CurrentUser do cache do Riverpod
      final cu = ProviderScope.containerOf(ctx).read(currentUserProvider);
      final memberships = cu.valueOrNull?.memberships ?? [];
      if (memberships.isEmpty && state.matchedLocation.startsWith('/portal')) {
        return '/link-academy';
      }
    }
    return null;
  },
  routes: [...],
);
```

Telas internas assumem que `academyId` existe. Sem checagem repetida.

### Impacto

- ~133 verificações redundantes somem.
- Comportamento de redirect é centralizado e testável.

---

## 12. Deep-linking + URLs estáveis com `go_router`

### Bônus arquitetural

Com URLs estáveis (`/portal/students/123`), notificações push e e-mails podem linkar direto para a tela certa. Hoje o app abre na home e o usuário navega manualmente.

```dart
GoRoute(
  path: '/portal/students/:id',
  builder: (ctx, state) => StudentDetailScreen(id: state.pathParameters['id']!),
),

// FCM payload com data: { route: '/portal/students/123' }
// Notification handler:
FirebaseMessaging.onMessageOpenedApp.listen((msg) {
  final route = msg.data['route'];
  if (route != null) GoRouter.of(navKey.currentContext!).push(route);
});
```

### Impacto

- Notificações ficam acionáveis.
- E-mails do tipo "novo pedido na loja" abrem o pedido direto.

---

## 13. Telemetria client-side básica

### Problema hoje

Não há instrumentação. Quando um usuário reporta "tela X está lenta", não temos métricas.

### Solução

Sentry Performance (free tier serve para começar):

```dart
await SentryFlutter.init((options) {
  options.dsn = const String.fromEnvironment('SENTRY_DSN');
  options.tracesSampleRate = 0.1;  // 10% das transações
  options.environment = const String.fromEnvironment('ENV');
});

// Em cada chamada de API:
final txn = Sentry.startTransaction('students.list', 'http.client');
try {
  final r = await api.get('/v1/academies/$id/students');
  txn.status = SpanStatus.ok();
  return r;
} catch (e) {
  txn.status = SpanStatus.internalError();
  rethrow;
} finally {
  await txn.finish();
}
```

E quando o backend devolve um erro, propagar o `trace_id`:

```dart
Sentry.captureException(error, withScope: (scope) {
  scope.setTag('trace_id', error.traceId);
});
```

### Impacto

- Tempo real de visibilidade de quais telas estão lentas.
- O `trace_id` linka exceção do app à trace do backend no Tempo.

---

## 14. CI básico para Flutter

Hoje provavelmente não há. Adicionar `.github/workflows/flutter.yml`:

```yaml
name: flutter-ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { channel: stable }
      - run: flutter pub get
      - run: dart format --output=none --set-exit-if-changed lib test
      - run: flutter analyze
      - run: flutter test
```

Adicionar `dart_code_metrics` ou `very_good_analysis` para regras mais rigorosas.

---

## 15. Resumo prioritizado

| # | Otimização | Esforço | Impacto |
|---|---|---|---|
| 1 | `TatamiClient` + `TatamiException` + interceptor | S | ⭐⭐⭐⭐⭐ destrava tudo |
| 2 | Riverpod `AsyncNotifier` com keepAlive | M | ⭐⭐⭐⭐ |
| 3 | `PaginatedList<T>` reutilizável | M | ⭐⭐⭐⭐⭐ |
| 4 | Dashboard via MV | S | ⭐⭐⭐⭐⭐ |
| 5 | Search via `pg_trgm` | S | ⭐⭐⭐⭐ |
| 6 | Polling com ETag em vez de listeners | M | ⭐⭐⭐⭐ |
| 7 | Erro tipado + `ErrorView` único | S | ⭐⭐⭐ UX |
| 8 | Image thumbnailing server-side | M | ⭐⭐⭐ |
| 9 | `go_router` com guard central | M | ⭐⭐⭐ |
| 10 | `student_detail_screen` lazy-tabs | S | ⭐⭐⭐ |
| 11 | Sentry Performance | S | ⭐⭐⭐ visibilidade |
| 12 | CI Flutter | S | ⭐⭐ saúde |
| 13 | Deep-linking | M | ⭐⭐⭐ |
| 14 | Offline-first com drift | L | ⭐⭐⭐ (avaliar) |
| 15 | Remoção de denormalização | M | ⭐⭐ tech-debt |

`S = small (1-2 dias)`, `M = medium (3-5 dias)`, `L = large (>1 semana)`.

---

## 16. Métricas para acompanhar a migração

Antes de iniciar, instrumentar e capturar baseline:

- **TTI** (time to interactive) da tela de listagem de alunos
- **P95 latência** das principais chamadas
- **Custo Firestore** mensal (Firebase console → Usage)
- **Crashes / erros** por tela (Sentry)
- **Tamanho do bundle** (`flutter build apk --analyze-size`)
- **Memória** em telas pesadas (DevTools)

Depois de cada fase, comparar. A meta é:
- TTI < 500ms em todas as telas listadas.
- P95 latência < 300ms em queries paginadas.
- 80% redução de reads Firestore após Fase 3.
- Bundle < 25 MB.

---

## Conclusão

A migração não é só "trocar Firebase por Tatami". É a chance de **arrumar dívida arquitetural** que se acumulou pela ausência de backend dedicado. Os itens 1-7 desta lista deveriam vir junto com a Fase 0/1 da migração — não num "segundo round". O resto pode aguardar fases posteriores.

Os três documentos juntos:
- [`01_LOGICA_DELEGADA_AO_FRONTEND.md`](01_LOGICA_DELEGADA_AO_FRONTEND.md) — o que sair do cliente
- [`02_MAPEAMENTO_ENDPOINTS_NOVO_BACKEND.md`](02_MAPEAMENTO_ENDPOINTS_NOVO_BACKEND.md) — onde cada coisa vai
- [`03_OTIMIZACOES_GERAIS_APP.md`](03_OTIMIZACOES_GERAIS_APP.md) — este aqui, o que dá pra melhorar de quebra

formam o plano de migração frontend → Tatami. Cada um é independente o suficiente para ser revisado/implementado por uma pessoa diferente, mas convergem no mesmo destino: um app Flutter mais rápido, mais barato, mais seguro e mais fácil de evoluir.
