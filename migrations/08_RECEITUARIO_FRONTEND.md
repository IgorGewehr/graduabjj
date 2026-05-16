# 08 — Receituário frontend (before/after copy-paste)

> Patterns canônicos que aparecem em **toda** a migração. Cada receita tem o código atual (Firestore) e o código novo (Tatami). Para cada caso de uso recorrente: copia, ajusta nomes, dorme tranquilo.
>
> Use junto com o doc 02 (mapa de endpoints) e o doc 03 (otimizações de arquitetura).

---

## Índice

1. [Cliente HTTP base + interceptor de auth](#1-cliente-http-base--interceptor-de-auth)
2. [Erro tipado `TatamiException` + parser problem+json](#2-erro-tipado-tatamiexception--parser-problemjson)
3. [Idempotency key + retry seguro](#3-idempotency-key--retry-seguro)
4. [Provider Riverpod com paginação + keepAlive](#4-provider-riverpod-com-paginação--keepalive)
5. [Componente `PaginatedList<T>` reutilizável](#5-componente-paginatedlistt-reutilizável)
6. [Optimistic update com rollback automático](#6-optimistic-update-com-rollback-automático)
7. [Listagem com filtros server-side + busca](#7-listagem-com-filtros-server-side--busca)
8. [CRUD básico — criar, ler, atualizar, deletar](#8-crud-básico--criar-ler-atualizar-deletar)
9. [Upload de foto em 2 passos (signed URL)](#9-upload-de-foto-em-2-passos-signed-url)
10. [Polling com ETag (substitui `.snapshots()`)](#10-polling-com-etag-substitui-snapshots)
11. [Estado de erro padrão (`ErrorView`)](#11-estado-de-erro-padrão-errorview)
12. [Loading skeletons em vez de spinners](#12-loading-skeletons-em-vez-de-spinners)
13. [Form de criação/edição (validação cliente + server)](#13-form-de-criação-edição-validação-cliente--server)
14. [Deep-linking com `go_router` + redirect](#14-deep-linking-com-go_router--redirect)
15. [Feature flag local](#15-feature-flag-local)
16. [Telemetria por ação (Sentry + trace_id)](#16-telemetria-por-ação-sentry--trace_id)
17. [Cache local com `drift` (opcional)](#17-cache-local-com-drift-opcional)

---

## 1. Cliente HTTP base + interceptor de auth

**Antes (Firestore — inexistente como camada HTTP, espalhado pelos services):**

```dart
class StudentService {
  StudentService(this.academyId) : firestore = FirebaseFirestore.instance;
  final String academyId;
  final FirebaseFirestore firestore;

  Future<List<Student>> getAll() async {
    final snap = await firestore
      .collection('academies').doc(academyId)
      .collection('students')
      .get();  // sem auth header — Firebase SDK injeta
    return snap.docs.map(Student.fromFirestore).toList();
  }
}
```

**Depois — `lib/api/tatami_client.dart`:**

```dart
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TatamiClient {
  TatamiClient({required this.baseUrl, Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.baseUrl = baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 30);

    // 1) Auth interceptor — anexa o ID token Firebase vivo.
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          // `false` aqui: aceita o cache do Firebase. O SDK refresca
          // automaticamente nos 5 minutos antes de expirar.
          final token = await user.getIdToken();
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // Se for 401 e ainda tivermos um user, força refresh do token e re-tenta UMA vez.
        if (error.response?.statusCode == 401) {
          final user = FirebaseAuth.instance.currentUser;
          final retryFlag = error.requestOptions.extra['__retried_auth'] == true;
          if (user != null && !retryFlag) {
            final fresh = await user.getIdToken(true);  // force refresh
            final opts = error.requestOptions
              ..headers['Authorization'] = 'Bearer $fresh'
              ..extra['__retried_auth'] = true;
            try {
              final r = await _dio.fetch(opts);
              return handler.resolve(r);
            } catch (_) { /* segue para o próximo handler */ }
          }
        }
        handler.next(error);
      },
    ));

    // 2) Problem+json parser — vê §2.
    _dio.interceptors.add(_problemInterceptor());
  }

  final String baseUrl;
  final Dio _dio;

  Future<T> get<T>(String path, {Map<String, dynamic>? params}) async {
    final r = await _dio.get<dynamic>(path, queryParameters: params);
    return r.data as T;
  }

  Future<T> post<T>(String path, {Object? data, Map<String, String>? headers}) async {
    final r = await _dio.post<dynamic>(path, data: data, options: Options(headers: headers));
    return r.data as T;
  }

  Future<T> patch<T>(String path, {Object? data}) async {
    final r = await _dio.patch<dynamic>(path, data: data);
    return r.data as T;
  }

  Future<void> delete(String path) async {
    await _dio.delete<dynamic>(path);
  }
}
```

**Provider Riverpod:**

```dart
final tatamiClientProvider = Provider<TatamiClient>((ref) {
  const baseUrl = String.fromEnvironment(
    'TATAMI_BASE_URL',
    defaultValue: 'https://api.staging.tatami.dev',
  );
  return TatamiClient(baseUrl: baseUrl);
});
```

**`--dart-define` na build:**
```bash
flutter run --dart-define=TATAMI_BASE_URL=https://api.tatami.dev
```

---

## 2. Erro tipado `TatamiException` + parser problem+json

**Antes:**

```dart
try {
  await firestore.collection('students').doc(id).delete();
} catch (e) {
  // e é FirebaseException, PlatformException ou outra coisa qualquer
  showSnack(e.toString());  // mensagens crípticas
}
```

**Depois — `lib/api/tatami_exception.dart`:**

```dart
class FieldError {
  final String field;
  final String message;
  final String? code;
  const FieldError({required this.field, required this.message, this.code});

  factory FieldError.fromJson(Map<String, dynamic> j) => FieldError(
    field: j['field'] as String,
    message: j['message'] as String,
    code: j['code'] as String?,
  );
}

class TatamiException implements Exception {
  final int status;
  final String type;
  final String title;
  final String? detail;
  final String? instance;
  final String? traceId;
  final List<FieldError> errors;
  final Map<String, dynamic> raw;

  const TatamiException({
    required this.status,
    required this.type,
    required this.title,
    this.detail,
    this.instance,
    this.traceId,
    this.errors = const [],
    this.raw = const {},
  });

  factory TatamiException.fromResponse(int status, dynamic data) {
    if (data is! Map<String, dynamic>) {
      return TatamiException(
        status: status,
        type: 'https://tatami.dev/errors/unknown',
        title: 'Unexpected error',
        detail: data?.toString(),
      );
    }
    final errs = (data['errors'] as List?)
      ?.whereType<Map<String, dynamic>>()
      .map(FieldError.fromJson)
      .toList() ?? const <FieldError>[];
    return TatamiException(
      status: data['status'] as int? ?? status,
      type: data['type'] as String? ?? 'unknown',
      title: data['title'] as String? ?? 'Error',
      detail: data['detail'] as String?,
      instance: data['instance'] as String?,
      traceId: data['trace_id'] as String?,
      errors: errs,
      raw: data,
    );
  }

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isNotFound => status == 404;
  bool get isValidation => status == 422;
  bool get isConflict => status == 409;
  bool get isRateLimited => status == 429;
  bool get isServerError => status >= 500;
  bool get isNetworkError => status == 0;

  String forUser({String fallback = 'Algo deu errado. Tente novamente.'}) {
    if (isUnauthorized) return 'Sua sessão expirou. Faça login novamente.';
    if (isForbidden) return 'Você não tem permissão para esta ação.';
    if (isNotFound) return 'Não encontramos o que você procurava.';
    if (isValidation && errors.isNotEmpty) return errors.first.message;
    if (isConflict) return 'Esta operação já foi feita ou conflita com outra.';
    if (isRateLimited) return 'Muitas tentativas. Aguarde um momento.';
    if (isNetworkError) return 'Sem conexão. Verifique sua internet.';
    return fallback;
  }

  @override
  String toString() => 'TatamiException($status $type: ${detail ?? title})';
}

Interceptor _problemInterceptor() => InterceptorsWrapper(
  onError: (error, handler) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return handler.next(error..error = const TatamiException(
        status: 0, type: 'network', title: 'Sem conexão',
      ));
    }
    final response = error.response;
    if (response != null) {
      return handler.next(error..error = TatamiException.fromResponse(
        response.statusCode ?? 500,
        response.data,
      ));
    }
    handler.next(error);
  },
);
```

**Uso:**

```dart
try {
  await api.delete('/v1/academies/$aid/students/$id');
  showSnack('Aluno removido.');
} on DioException catch (e) {
  if (e.error is TatamiException) {
    final t = e.error as TatamiException;
    showSnack(t.forUser());
    if (t.traceId != null) debugPrint('trace_id: ${t.traceId}');
  } else {
    rethrow;
  }
}
```

---

## 3. Idempotency key + retry seguro

```dart
// lib/api/idempotency.dart
import 'package:uuid/uuid.dart';

class IdempotencyKey {
  IdempotencyKey._(this.value);
  factory IdempotencyKey.generate() => IdempotencyKey._(const Uuid().v4());
  final String value;
}

extension TatamiClientIdempotency on TatamiClient {
  Future<T> postIdempotent<T>(
    String path, {
    required Object data,
    required IdempotencyKey key,
  }) => post<T>(path, data: data, headers: {'Idempotency-Key': key.value});
}
```

**Uso (criação de pedido):**

```dart
Future<Order> createOrder(OrderInput input) async {
  // Gera UMA key por operação lógica do usuário. Se retentarmos por timeout,
  // o backend retorna a mesma resposta que daria na primeira vez.
  final key = IdempotencyKey.generate();

  Future<Order> attempt() async => Order.fromJson(
    await api.postIdempotent<Map<String, dynamic>>(
      '/v1/academies/$aid/store/orders',
      data: input.toJson(),
      key: key,
    ),
  );

  try {
    return await attempt();
  } on DioException catch (e) {
    final ex = e.error;
    // Só retentar timeouts; NÃO retentar 4xx (não vão melhorar).
    if (ex is TatamiException && ex.isNetworkError) {
      await Future.delayed(const Duration(seconds: 2));
      return await attempt();
    }
    rethrow;
  }
}
```

---

## 4. Provider Riverpod com paginação + keepAlive

**Antes:**

```dart
final studentListProvider = FutureProvider.autoDispose((ref) async {
  return StudentService(currentUser.academyId).getAll();
});
```

**Depois:**

```dart
// lib/providers/students_provider.dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'students_provider.g.dart';

class StudentFilter {
  final String? status;
  final String? belt;
  final String? category;
  final String? query;
  const StudentFilter({this.status, this.belt, this.category, this.query});

  Map<String, dynamic> toQueryParams() => {
    if (status != null) 'status': status,
    if (belt != null) 'belt': belt,
    if (category != null) 'category': category,
    if (query?.isNotEmpty == true) 'q': query,
  };

  @override
  bool operator ==(Object other) =>
      other is StudentFilter &&
      other.status == status && other.belt == belt &&
      other.category == category && other.query == query;
  @override
  int get hashCode => Object.hash(status, belt, category, query);
}

class StudentPage {
  final List<Student> items;
  final String? nextCursor;
  final bool hasMore;
  const StudentPage({required this.items, this.nextCursor, this.hasMore = false});

  StudentPage append(StudentPage next) => StudentPage(
    items: [...items, ...next.items],
    nextCursor: next.nextCursor,
    hasMore: next.hasMore,
  );

  StudentPage prepending(Student newItem) => StudentPage(
    items: [newItem, ...items],
    nextCursor: nextCursor,
    hasMore: hasMore,
  );
}

@riverpod
class Students extends _$Students {
  @override
  Future<StudentPage> build(StudentFilter filter) async {
    // Mantém em memória por 5 min mesmo sem listeners.
    final link = ref.keepAlive();
    ref.onDispose(() { /* hook opcional para teardown */ });
    return _fetch(filter, cursor: null);
  }

  Future<StudentPage> _fetch(StudentFilter f, {String? cursor}) async {
    final api = ref.read(tatamiClientProvider);
    final academy = ref.read(currentAcademyIdProvider);
    final params = {
      ...f.toQueryParams(),
      'limit': 50,
      if (cursor != null) 'cursor': cursor,
    };
    final raw = await api.get<Map<String, dynamic>>(
      '/v1/academies/$academy/students',
      params: params,
    );
    return StudentPage(
      items: (raw['items'] as List).map((j) => Student.fromJson(j)).toList(),
      nextCursor: raw['next_cursor'] as String?,
      hasMore: raw['has_more'] as bool? ?? false,
    );
  }

  Future<void> loadMore() async {
    final cur = state.valueOrNull;
    if (cur == null || !cur.hasMore || cur.nextCursor == null) return;
    state = const AsyncValue.loading().copyWithPrevious(state);
    final next = await _fetch(filter, cursor: cur.nextCursor);
    state = AsyncValue.data(cur.append(next));
  }

  /// Insere optimisticamente no topo após uma criação remota bem-sucedida.
  void prepend(Student newStudent) {
    state = state.whenData((p) => p.prepending(newStudent));
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;  // espera o re-fetch terminar
  }
}
```

---

## 5. Componente `PaginatedList<T>` reutilizável

```dart
// lib/widgets/paginated_list.dart
class PaginatedList<T> extends ConsumerStatefulWidget {
  final AsyncValue<Page<T>> async;
  final Future<void> Function() onLoadMore;
  final Future<void> Function() onRefresh;
  final Widget Function(BuildContext ctx, T item) itemBuilder;
  final Widget? emptyState;
  final EdgeInsetsGeometry? padding;

  const PaginatedList({
    super.key,
    required this.async,
    required this.onLoadMore,
    required this.onRefresh,
    required this.itemBuilder,
    this.emptyState,
    this.padding,
  });

  @override
  ConsumerState<PaginatedList<T>> createState() => _PaginatedListState<T>();
}

class _PaginatedListState<T> extends ConsumerState<PaginatedList<T>> {
  late final ScrollController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = ScrollController()..addListener(_onScroll);
  }

  void _onScroll() {
    if (_ctrl.position.pixels >= _ctrl.position.maxScrollExtent - 300) {
      widget.onLoadMore();  // o notifier dedupa se já está carregando
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    return widget.async.when(
      data: (page) {
        if (page.items.isEmpty) return widget.emptyState ?? const _DefaultEmpty();
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView.separated(
            controller: _ctrl,
            padding: widget.padding,
            itemCount: page.items.length + (page.hasMore ? 1 : 0),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              if (i >= page.items.length) return const _LoadingTile();
              return widget.itemBuilder(ctx, page.items[i]);
            },
          ),
        );
      },
      loading: () => const _SkeletonList(),
      error: (e, _) => ErrorView(error: e, onRetry: widget.onRefresh),
    );
  }
}
```

**Uso:**

```dart
PaginatedList<Student>(
  async: ref.watch(studentsProvider(filter)),
  onLoadMore: () => ref.read(studentsProvider(filter).notifier).loadMore(),
  onRefresh: () => ref.read(studentsProvider(filter).notifier).refresh(),
  itemBuilder: (ctx, s) => StudentTile(student: s),
);
```

---

## 6. Optimistic update com rollback automático

```dart
extension StudentMutations on StudentsNotifier {
  Future<void> deleteOptimistic(String studentId) async {
    final snapshot = state.valueOrNull;
    if (snapshot == null) return;

    // 1. Remove localmente
    state = AsyncValue.data(StudentPage(
      items: snapshot.items.where((s) => s.id != studentId).toList(),
      nextCursor: snapshot.nextCursor,
      hasMore: snapshot.hasMore,
    ));

    // 2. Chama o backend
    try {
      final api = ref.read(tatamiClientProvider);
      await api.delete('/v1/academies/${ref.read(currentAcademyIdProvider)}/students/$studentId');
    } catch (e) {
      // 3. Rollback se falhar
      state = AsyncValue.data(snapshot);
      rethrow;
    }
  }
}
```

---

## 7. Listagem com filtros server-side + busca

**Antes (todo o filtro no Dart):**

```dart
// monitor_students_screen.dart
void _applyFilters() {
  var filtered = _students.toList();
  if (_statusFilter != null) {
    filtered = filtered.where((s) => s.status == _statusFilter).toList();
  }
  if (_categoryFilter != null) {
    filtered = filtered.where((s) => s.category == _categoryFilter).toList();
  }
  // ...
}
```

**Depois:**

```dart
class StudentListScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends ConsumerState<StudentListScreen> {
  String? _status;
  String? _belt;
  String? _category;
  String _query = '';
  Timer? _debounce;

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() => _query = value);
    });
  }

  @override
  Widget build(BuildContext ctx) {
    final filter = StudentFilter(
      status: _status,
      belt: _belt,
      category: _category,
      query: _query,
    );
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          decoration: const InputDecoration(hintText: 'Buscar aluno...'),
          onChanged: _onQueryChanged,
        ),
      ),
      body: Column(children: [
        FilterBar(
          onStatusChanged: (v) => setState(() => _status = v),
          onBeltChanged: (v) => setState(() => _belt = v),
          // ...
        ),
        Expanded(child: PaginatedList<Student>(
          async: ref.watch(studentsProvider(filter)),
          onLoadMore: () => ref.read(studentsProvider(filter).notifier).loadMore(),
          onRefresh: () => ref.read(studentsProvider(filter).notifier).refresh(),
          itemBuilder: (ctx, s) => StudentTile(student: s),
        )),
      ]),
    );
  }

  @override
  void dispose() { _debounce?.cancel(); super.dispose(); }
}
```

---

## 8. CRUD básico

```dart
// lib/repositories/students_repo.dart
class StudentsRepo {
  StudentsRepo(this._api);
  final TatamiClient _api;

  Future<Student> getById(String academyId, String studentId) async =>
    Student.fromJson(await _api.get('/v1/academies/$academyId/students/$studentId'));

  Future<Student> create(String academyId, StudentCreateInput input) async =>
    Student.fromJson(await _api.postIdempotent(
      '/v1/academies/$academyId/students',
      data: input.toJson(),
      key: IdempotencyKey.generate(),
    ));

  Future<Student> update(String academyId, String studentId, StudentPatch patch) async =>
    Student.fromJson(await _api.patch(
      '/v1/academies/$academyId/students/$studentId',
      data: patch.toJson(),
    ));

  Future<void> softDelete(String academyId, String studentId) =>
    _api.delete('/v1/academies/$academyId/students/$studentId');
}

final studentsRepoProvider = Provider((ref) => StudentsRepo(ref.read(tatamiClientProvider)));
```

`StudentPatch` é uma classe com TODOS os campos `nullable` — campos `null` significam "não tocar". Backend é PATCH parcial.

---

## 9. Upload de foto em 2 passos (signed URL)

```dart
// lib/services/photo_upload_service.dart
class PhotoUploadService {
  PhotoUploadService(this._api);
  final TatamiClient _api;

  /// Retorna o storage_path final para o caller persistir no recurso.
  Future<String> upload({
    required Uint8List bytes,
    required String contentType,   // 'image/jpeg' | 'image/png' | ...
    required String purpose,       // 'student_photo' | 'competition_photo' | ...
  }) async {
    // 1) Pede signed URL ao backend
    final signed = await _api.post<Map<String, dynamic>>(
      '/v1/uploads/sign',
      data: {
        'purpose': purpose,
        'content_type': contentType,
        'size_bytes': bytes.length,
      },
    );

    final url = signed['url'] as String;
    final headers = Map<String, String>.from(signed['headers'] as Map);
    final storagePath = signed['storage_path'] as String;

    // 2) PUT direto no storage. Bytes NÃO passam pelo Tatami.
    final putDio = Dio();  // Dio dedicado, sem auth interceptor
    final r = await putDio.put<dynamic>(
      url,
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {...headers, 'Content-Length': '${bytes.length}'},
      ),
    );
    if (r.statusCode != 200) {
      throw Exception('Upload failed: ${r.statusCode}');
    }

    return storagePath;
  }

  /// URL temporária para o `Image.network` consumir.
  Future<String> downloadUrl(String storagePath, {String? variant}) async {
    final r = await _api.get<Map<String, dynamic>>(
      '/v1/uploads/${Uri.encodeComponent(storagePath)}/download-url',
      params: variant != null ? {'variant': variant} : null,
    );
    return r['url'] as String;
  }
}
```

**Uso:**

```dart
final bytes = await pickedFile.readAsBytes();
final compressed = await FlutterImageCompress.compressWithList(
  bytes, minWidth: 1024, minHeight: 1024, quality: 80,
);
final path = await photoService.upload(
  bytes: compressed,
  contentType: 'image/jpeg',
  purpose: 'student_photo',
);
await studentsRepo.update(academyId, studentId, StudentPatch(photoPath: path));
```

---

## 10. Polling com ETag (substitui `.snapshots()`)

```dart
// lib/providers/etag_poller.dart
class EtagPoller<T> {
  EtagPoller({
    required this.fetcher,
    required this.interval,
    required this.onUpdate,
  });

  final Future<EtagResult<T>?> Function(String? etag) fetcher;
  final Duration interval;
  final void Function(T data) onUpdate;
  Timer? _timer;
  String? _etag;

  void start() {
    _tick();
  }

  void stop() {
    _timer?.cancel();
  }

  Future<void> _tick() async {
    try {
      final result = await fetcher(_etag);
      if (result != null) {
        _etag = result.etag;
        onUpdate(result.data);
      }
    } catch (_) { /* engole; tenta de novo */ }
    _timer = Timer(interval, _tick);
  }
}

class EtagResult<T> {
  final T data;
  final String? etag;
  const EtagResult({required this.data, this.etag});
}
```

E no Tatami client, expor um método raw que vê o status:

```dart
extension TatamiClientEtag on TatamiClient {
  Future<EtagResult<T>?> getWithEtag<T>(
    String path, {
    String? ifNoneMatch,
    required T Function(Map<String, dynamic>) parser,
  }) async {
    final r = await _dio.get<dynamic>(
      path,
      options: Options(
        headers: ifNoneMatch != null ? {'If-None-Match': ifNoneMatch} : null,
        validateStatus: (s) => s != null && (s == 304 || (s >= 200 && s < 300)),
      ),
    );
    if (r.statusCode == 304) return null;  // sem mudanças
    return EtagResult(
      data: parser(r.data as Map<String, dynamic>),
      etag: r.headers.value('etag'),
    );
  }
}
```

**Uso (tela de notificações em foreground):**

```dart
@override
void initState() {
  super.initState();
  _poller = EtagPoller<NotificationsPage>(
    interval: const Duration(seconds: 30),
    fetcher: (etag) => api.getWithEtag(
      '/v1/me/notifications',
      ifNoneMatch: etag,
      parser: NotificationsPage.fromJson,
    ),
    onUpdate: (page) => ref.read(notificationsProvider.notifier).set(page),
  )..start();
}

@override
void dispose() {
  _poller.stop();
  super.dispose();
}
```

---

## 11. Estado de erro padrão (`ErrorView`)

```dart
class ErrorView extends StatelessWidget {
  final Object error;
  final Future<void> Function()? onRetry;
  const ErrorView({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext ctx) {
    final t = (error is DioException && (error as DioException).error is TatamiException)
      ? (error as DioException).error as TatamiException
      : null;

    final message = t?.forUser() ?? 'Algo deu errado. Tente novamente.';
    final trace = t?.traceId;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            if (trace != null) ...[
              const SizedBox(height: 8),
              SelectableText('Código: $trace',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
            const SizedBox(height: 16),
            if (onRetry != null)
              FilledButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
                onPressed: () => onRetry!.call(),
              ),
          ],
        ),
      ),
    );
  }
}
```

---

## 12. Loading skeletons em vez de spinners

Usuários percebem 200ms de skeleton como mais rápido que 200ms de spinner (sensação de "está chegando").

```dart
class _SkeletonList extends StatelessWidget {
  const _SkeletonList();
  @override
  Widget build(BuildContext ctx) {
    return ListView.separated(
      itemCount: 8,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, __) => _SkeletonTile(),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  @override
  Widget build(BuildContext ctx) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(children: [
      _Shimmer(width: 48, height: 48, isCircle: true),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _Shimmer(width: 160, height: 14),
          SizedBox(height: 6),
          _Shimmer(width: 100, height: 12),
        ],
      )),
    ]),
  );
}
```

(Use `shimmer` package para o efeito de brilho — código omitido para brevidade.)

---

## 13. Form de criação/edição (validação cliente + server)

```dart
class StudentFormScreen extends ConsumerStatefulWidget {
  final String? studentId;  // null = criando, populado = editando
  const StudentFormScreen({this.studentId, super.key});

  @override
  ConsumerState<StudentFormScreen> createState() => _StudentFormScreenState();
}

class _StudentFormScreenState extends ConsumerState<StudentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  // ... outros controllers
  Map<String, String> _serverFieldErrors = {};
  bool _saving = false;

  Future<void> _save() async {
    // 1. Validação cliente (cheap)
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _serverFieldErrors = {}; });

    final input = StudentCreateInput(
      fullName: _fullNameCtrl.text.trim(),
      // ...
    );

    try {
      final repo = ref.read(studentsRepoProvider);
      final saved = widget.studentId == null
        ? await repo.create(ref.read(currentAcademyIdProvider), input)
        : await repo.update(ref.read(currentAcademyIdProvider), widget.studentId!, input.toPatch());

      ref.read(studentsProvider(const StudentFilter()).notifier).prepend(saved);
      if (mounted) Navigator.of(context).pop(saved);
    } on DioException catch (e) {
      final t = e.error;
      if (t is TatamiException && t.isValidation) {
        // Reflete erros de campo no formulário
        setState(() => _serverFieldErrors = {
          for (final fe in t.errors) fe.field: fe.message,
        });
      } else if (t is TatamiException) {
        showSnack(t.forUser());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.studentId == null ? 'Novo aluno' : 'Editar')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _fullNameCtrl,
              decoration: InputDecoration(
                labelText: 'Nome completo',
                // Mostra erro do servidor se houver
                errorText: _serverFieldErrors['full_name'],
              ),
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Obrigatório' : null,
            ),
            // ...
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                ? const CircularProgressIndicator()
                : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 14. Deep-linking com `go_router` + redirect

```dart
// lib/router/router.dart
final routerProvider = Provider<GoRouter>((ref) => GoRouter(
  initialLocation: '/portal',
  redirect: (ctx, state) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null && !state.matchedLocation.startsWith('/auth')) {
      return '/auth/login';
    }
    if (user != null) {
      final current = await ref.read(currentUserProvider.future);
      if ((current.memberships).isEmpty &&
          !state.matchedLocation.startsWith('/onboarding')) {
        return '/onboarding/link-academy';
      }
    }
    return null;
  },
  routes: [
    GoRoute(path: '/auth/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/onboarding/link-academy', builder: (_, __) => const LinkAcademyScreen()),
    ShellRoute(
      builder: (ctx, state, child) => PortalShell(child: child),
      routes: [
        GoRoute(
          path: '/portal/:academyId',
          redirect: (ctx, state) {
            final academyId = state.pathParameters['academyId']!;
            // Sincroniza o "ative academia" provider com a URL
            ProviderScope.containerOf(ctx)
              .read(selectedAcademyIdProvider.notifier).select(academyId);
            return null;
          },
          builder: (_, __) => const PortalHomeScreen(),
          routes: [
            GoRoute(path: 'students', builder: (_, __) => const StudentListScreen(), routes: [
              GoRoute(path: ':studentId', builder: (ctx, state) =>
                StudentDetailScreen(id: state.pathParameters['studentId']!)),
            ]),
            // ... outras
          ],
        ),
      ],
    ),
  ],
));
```

**FCM push deep-link:**

```dart
FirebaseMessaging.onMessageOpenedApp.listen((msg) {
  final route = msg.data['route'];  // ex: "/portal/abc-123/students/xyz-789"
  if (route != null) ref.read(routerProvider).go(route);
});
```

---

## 15. Feature flag local

Enquanto o sistema de flag remoto não está implantado, use um helper local:

```dart
// lib/utils/feature_flags.dart
class FeatureFlags {
  static const useTatamiIdentity = bool.fromEnvironment('FF_TATAMI_IDENTITY', defaultValue: false);
  static const useTatamiReads = bool.fromEnvironment('FF_TATAMI_READS', defaultValue: false);
  static const useTatamiWrites = bool.fromEnvironment('FF_TATAMI_WRITES', defaultValue: false);
  static const useTatamiFinancials = bool.fromEnvironment('FF_TATAMI_FINANCIALS', defaultValue: false);
  static const useTatamiAttendance = bool.fromEnvironment('FF_TATAMI_ATTENDANCE', defaultValue: false);
}
```

Build com:
```bash
flutter run --dart-define=FF_TATAMI_READS=true
```

E nos services:

```dart
Future<List<Student>> listStudents() async {
  if (FeatureFlags.useTatamiReads) {
    return await tatamiRepo.list(StudentFilter()).then((p) => p.items);
  } else {
    return await legacyFirestoreService.getAll();
  }
}
```

Quando o sistema remoto entrar, troque `bool.fromEnvironment` por `RemoteConfigService.getBool(...)`.

---

## 16. Telemetria por ação (Sentry + trace_id)

```dart
extension TatamiClientObserved on TatamiClient {
  Future<T> observed<T>(String opName, Future<T> Function() body) async {
    final txn = Sentry.startTransaction(opName, 'http.client');
    try {
      final r = await body();
      txn.status = const SpanStatus.ok();
      return r;
    } on DioException catch (e) {
      final t = e.error;
      if (t is TatamiException) {
        txn.setTag('trace_id', t.traceId ?? 'none');
        txn.setTag('problem.type', t.type);
        txn.setData('status', t.status);
      }
      txn.status = const SpanStatus.internalError();
      rethrow;
    } finally {
      await txn.finish();
    }
  }
}
```

E em chamadas críticas:

```dart
await api.observed('students.list', () => api.get('/v1/academies/$aid/students'));
```

---

## 17. Cache local com `drift` (opcional)

Para telas offline-first (ex.: chamada no tatame sem rede). Implementação completa fica fora do escopo desta receita, mas a estratégia é:

1. Schema local em `drift` espelha os campos mínimos das tabelas críticas.
2. Repositório passa a ter `local` e `remote`. Ordem padrão:
   - `getOnce()` → tenta `remote`; se falhar com network error, cai no `local`.
   - `watch()` → emite o `local` imediatamente e dispara `remote` em paralelo; quando volta, atualiza `local` e emite de novo.
3. Mutations offline ficam em fila local (`pending_mutations` table) com `idempotency_key` gerada. Drain quando volta online.

Esta receita merece um doc próprio quando o trabalho for priorizado.

---

## Apêndice — convenções gerais

- **Sempre** trate erros com `on DioException catch (e)` e cheque `e.error is TatamiException`.
- **Sempre** propague o `trace_id` para Sentry + mostre na UI em erros.
- **Sempre** use `Idempotency-Key` em POSTs que mudam estado (criação, transações).
- **Nunca** confie em horário do dispositivo para regras de negócio — chame o backend.
- **Nunca** valide regras de negócio só no cliente (servidor é a fonte da verdade).
- **Nunca** modele lista paginada sem `next_cursor`.
- **Sempre** mostre skeleton em vez de spinner em listas.
- **Sempre** debounce buscas em 200-300ms.
- **Sempre** filtre `memberships.where(status == 'active')` ao iterar academias.

Quando em dúvida, copie deste doc, ajuste nomes, abra PR.
