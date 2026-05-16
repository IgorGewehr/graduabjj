# 02 — Mapa de migração: Firestore → endpoints do Tatami

> **Como usar este documento.** Para cada `Service` do graduabjj listamos: (a) o que ele faz hoje contra o Firestore, (b) o(s) endpoint(s) equivalente(s) no Tatami, (c) o spec OpenAPI de origem, (d) mudanças de assinatura que o código Dart vai precisar absorver, (e) gotchas de migração (paginação, cursor, idempotency keys, problem+json).
>
> **Convenções.**
> - Todos os endpoints assumem `Authorization: Bearer <firebase-id-token>` (mantemos Firebase Auth — ADR 0002 do Tatami).
> - `{academyId}` é o tenant. Sempre UUID.
> - Listas usam **paginação por cursor**: `?limit=25&cursor=<opaque>`. A resposta traz `{ items, next_cursor, has_more }`.
> - Erros são `application/problem+json` (RFC 7807). Frontend precisa ter um parser único e mostrar `trace_id` em telas de erro.

---

## 0. Setup do cliente HTTP no graduabjj

Antes de mexer em qualquer service, criar uma camada nova `lib/api/`:

```dart
// lib/api/tatami_client.dart
class TatamiClient {
  final String baseUrl;        // TATAMI_BASE_URL via --dart-define
  final Dio _dio;

  TatamiClient(this.baseUrl) : _dio = Dio(BaseOptions(baseUrl: baseUrl)) {
    // Interceptor 1: anexa o Firebase ID token vivo
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final token = await user.getIdToken();
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
    // Interceptor 2: traduz problem+json em TatamiException tipado
    _dio.interceptors.add(_problemInterceptor());
  }
}
```

```dart
// lib/api/tatami_exception.dart
class TatamiException implements Exception {
  final int status;            // HTTP status
  final String type;           // problem.type — "https://tatami.dev/errors/not-found"
  final String title;
  final String? detail;
  final String? traceId;       // mostrar em mensagens de erro para suporte
  final List<FieldError> errors;
  
  // Helpers idiomáticos
  bool get isNotFound => status == 404;
  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isValidation => status == 422;
  bool get isConflict => status == 409;
}
```

Toda chamada de service nova devolve `Future<T>` que lança `TatamiException`. Telas usam `try/on TatamiException`.

---

## 1. Identity & sessão (`/v1/me`, `/v1/users`, `/v1/academies/{id}/memberships`)

**Spec:** `api/openapi/identity.yaml`

### Hoje (Dart)

```dart
// services/auth_service.dart + providers/current_user_provider.dart
final user = FirebaseAuth.instance.currentUser;
final mappingDoc = await FirebaseFirestore.instance
    .collection('userAcademyMapping').doc(user.uid).get();
final academies = mappingDoc.data()?['academyIds'] as List;
// ... busca cada academia em paralelo
```

### Migração

| Operação hoje | Endpoint Tatami | Mudanças |
|---|---|---|
| Login (`signInWithEmailAndPassword`) | **Mantém Firebase Auth** | Nenhuma — o ID token resultante já serve para o Tatami |
| Buscar perfil + memberships | `GET /v1/me` | Substitui a leitura do `userAcademyMapping` + N reads de academias. Retorna `{ user, memberships: [...], primary_academy_id }` em **uma única chamada** |
| Atualizar perfil | `PATCH /v1/me` | Substitui o `users/{uid}` update no Firestore. Body: `{ display_name?, phone?, photo_url?, birth_date?, weight_kg?, is_profile_public? }` |
| Listar membros de uma academia (admin) | `GET /v1/academies/{academyId}/memberships?role=student&limit=50&cursor=...` | Substitui `collectionGroup('users').where('academyId', ...).get()` |
| Buscar usuário por UID (admin) | `GET /v1/users/{uid}` | Substitui `users/{uid}` direto |

### Provider Riverpod recomendado

```dart
final currentUserProvider = FutureProvider<CurrentUser>((ref) async {
  final api = ref.read(tatamiClientProvider);
  return api.get<CurrentUser>('/v1/me');
});

// keep alive: o perfil muda raramente; refresca a cada login
final currentUserProviderRef = currentUserProvider.overrideWith(
  () => Future.value()).select((u) => u);
```

### Gotcha — Firebase Auth continua a fonte de identidade

- O login continua sendo do Firebase. NÃO mude para "login via Tatami".
- O sign-up cria a conta no Firebase **e** depois faz `PATCH /v1/me` para o Tatami criar/upsertar o `GlobalUser`. Esse upsert na verdade já acontece dentro do middleware do Tatami na primeira chamada autenticada (`Service.EnsureUserFromFirebaseToken`), então o `PATCH /v1/me` é só para popular o `display_name` etc.

---

## 2. Academia (`/v1/academies/{id}`, settings, link codes)

**Spec:** `api/openapi/academy.yaml`

### Hoje (Dart)

```dart
// services/academy_service.dart
final academy = await firestore.collection('academies').doc(id).get();
// services/settings_service.dart
final settings = await academy.collection('settings').get(); // todas as keys
// services/link_code_service.dart
final code = generateRandomCode();
await academy.collection('linkCodes').doc(code).set({...});
```

### Migração

| Operação | Endpoint | Notas |
|---|---|---|
| Criar academia (signup do dono) | `POST /v1/academies` | Body: `{ name, slug, cnpj?, email, phone, address... }`. Caller vira owner; o Tatami cria o `user_academy_mapping` com role=admin automaticamente. |
| Buscar academia | `GET /v1/academies/{academyId}` | Substitui o doc read |
| Atualizar academia | `PATCH /v1/academies/{academyId}` | Body parcial: só os campos que mudam |
| Listar settings | `GET /v1/academies/{academyId}/settings` | Retorna mapa key→value |
| Set/update setting | `PUT /v1/academies/{academyId}/settings/{key}` | Body: `{ value: any }` |
| Gerar link-code de aluno | `POST /v1/academies/{academyId}/link-codes` | Body: `{ student_id }` opcional. Retorna `{ code, expires_at }`. TTL 24h. |
| Gerar instructor link-code | `POST /v1/academies/{academyId}/instructor-link-codes` | Mesmo padrão, TTL 30 min. |
| Resgatar link-code | `POST /v1/link-codes/{code}/redeem` | **Endpoint público autenticado** (caller é o usuário Firebase recém-criado que ainda não tem academia). Faz tudo atômico. |

### Gotcha — redenção de link code

A redenção hoje no Dart faz 5 writes não-atômicos. No Tatami é 1 endpoint:

```dart
// services/link_code_service.dart — método REPLACE inteiro
Future<RedeemResult> redeem(String code) async {
  return api.post<RedeemResult>('/v1/link-codes/$code/redeem');
}
```

A resposta inclui `{ academy: {...}, student: {...}, membership: {...} }` — sem precisar de chamadas de "refetch" depois.

---

## 3. Alunos (`/v1/academies/{id}/students/*`)

**Spec:** `api/openapi/student.yaml`

### Hoje (Dart)

`lib/services/student_service.dart` — **a maior fonte de leituras** no app.

```dart
Future<List<Student>> getAll() async { /* .get() sem limit */ }
Future<List<Student>> searchByName(String q) async { /* baixa tudo, filtra em Dart */ }
Future<Student?> getById(String id) async { ... }
Future<void> update(String id, Map<String, dynamic> data) async { ... }
Future<Map<String, dynamic>> getDashboardStats() async { /* loop em memória */ }
Future<void> syncAttendanceCounts() async { /* N+1 brutal */ }
```

### Migração

| Operação hoje | Endpoint Tatami | Mudança |
|---|---|---|
| `getAll()` / `getActive()` | `GET /v1/academies/{id}/students?status=active&limit=50&cursor=...` | **Paginação obrigatória.** UI lista usa `InfiniteScrollList` ou `PaginatedDataTable2`. |
| `searchByName('joao')` | `GET /v1/academies/{id}/students?q=joao&limit=20` | Backend usa `pg_trgm` index. Não baixa tudo. |
| `getById(id)` | `GET /v1/academies/{id}/students/{studentId}` | Idêntico |
| `create(...)` | `POST /v1/academies/{id}/students` | Body validado server-side. Retorna o student criado com id. |
| `update(id, patch)` | `PATCH /v1/academies/{id}/students/{studentId}` | Body só com campos alterados |
| `delete(id)` ou `setStatus(id, removed)` | `DELETE /v1/academies/{id}/students/{studentId}` | Soft delete: status='removed'. Hard delete via flag query `?hard=true` (admin) |
| `updateGrade(id, sport, belt, stripes)` | `POST /v1/academies/{id}/students/{studentId}/belt-progressions` | Cria progression + atualiza student no mesmo tx |
| `getDashboardStats()` | `GET /v1/academies/{id}/kpis` | Lê da `mv_academy_kpis` (já existe na migração 00013) |
| `syncAttendanceCounts()` | **REMOVER** | O contador é mantido por trigger no Postgres |
| `getBeltProgressions(studentId)` | `GET /v1/academies/{id}/students/{studentId}/belt-progressions?limit=20` | Histórico paginado |
| `getAssessments(studentId)` (kids) | `GET /v1/academies/{id}/students/{studentId}/assessments` | Idem |

### Gotcha — `currentBelt` vs `sportData`

Hoje há dois caminhos no model:
- Legacy: `currentBelt`, `currentStripes`
- Multi-sport: `sportData.bjj.currentGrade`, `sportData.bjj.currentStripes`

O Tatami expõe `sport_data` como JSONB. **Recomendação:** numa única release, o frontend para de ler `currentBelt` e passa a sempre olhar `sport_data[primary_sport]`. Backend devolve ambos por compatibilidade durante a transição, mas só `sport_data` deve ser usado.

### Gotcha — paginação

```dart
class StudentListPage {
  final List<Student> items;
  final String? nextCursor;
  final bool hasMore;
}

class StudentRemoteRepo {
  Future<StudentListPage> list({
    String? status,
    String? belt,
    String? category,
    String? query,
    String? cursor,
    int limit = 50,
  }) async {
    final resp = await api.get('/v1/academies/$academyId/students', queryParameters: {
      if (status != null) 'status': status,
      if (belt != null) 'belt': belt,
      if (category != null) 'category': category,
      if (query != null && query.isNotEmpty) 'q': query,
      if (cursor != null) 'cursor': cursor,
      'limit': limit,
    });
    return StudentListPage.fromJson(resp.data);
  }
}
```

Riverpod recomendado:

```dart
// pagination_provider.dart
final studentsPaginatedProvider = AsyncNotifierProvider.family<
    StudentsPaginated, List<Student>, StudentFilter>(
  StudentsPaginated.new,
);
```

---

## 4. Turmas + presença (`/v1/academies/{id}/classes`, `/attendance`)

**Spec:** `api/openapi/attendance.yaml`

### Migração

| Operação hoje | Endpoint | Mudança |
|---|---|---|
| Listar turmas ativas | `GET /v1/academies/{id}/classes?is_active=true` | Filtro server-side |
| Criar turma | `POST /v1/academies/{id}/classes` | Body: `{ name, schedule[], instructor_uid, category, sport, min_belt, max_belt, weight, ... }` |
| Editar turma | `PATCH /v1/academies/{id}/classes/{classId}` | Patch parcial |
| Soft-delete turma | `DELETE /v1/academies/{id}/classes/{classId}` | `is_active=false` |
| Adicionar aluno na turma | `POST /v1/academies/{id}/classes/{classId}/students` | Body: `{ student_id }`. Backend usa `class_students` (tabela join), **não** o `student_ids[]` array. |
| Remover aluno da turma | `DELETE /v1/academies/{id}/classes/{classId}/students/{studentId}` | |
| Marcar presença individual | `POST /v1/academies/{id}/attendance` | Body: `{ class_id, student_id, date }`. Backend snapshota `class.weight` automaticamente. |
| **Bulk mark** (staff marca N alunos) | `POST /v1/academies/{id}/attendance` (body: `[{...}, {...}, ...]`) | Tudo em uma transação. Constraint UNIQUE descarta duplicatas com retorno 207 Multi-Status detalhando quais entraram. |
| **Self check-in via QR** | `POST /v1/academies/{id}/attendance/self-checkin` | Body: `{ qr_token, class_id }`. QR é JWT assinado pelo backend (item 4 do doc 01). |
| Desmarcar | `DELETE /v1/academies/{id}/attendance/{attendanceId}` | |
| Listar attendance | `GET /v1/academies/{id}/attendance?student_id=...&date_from=...&date_to=...&limit=50&cursor=...` | **Sempre com filtro de data** — a tabela está particionada por mês |
| Contagem ponderada | `GET /v1/academies/{id}/students/{studentId}/attendance-weight?since=...` | Substitui `getWeightedAttendanceCount()` que fazia loop client-side |

### Gotcha — gerar o QR

Hoje o cliente gera o QR (JSON em texto plano). No novo fluxo:

```dart
// Admin/instructor pede ao backend um QR para a turma
Future<QrToken> issueQrForClass(String classId) async {
  final resp = await api.post(
    '/v1/academies/$academyId/classes/$classId/qr-tokens',
  );
  return QrToken.fromJson(resp.data); // { token: '...', expires_at }
}
// Mostra o token como QR. Aluno escaneia e chama self-checkin.
```

O endpoint `POST /v1/academies/{id}/classes/{classId}/qr-tokens` ainda **não está no spec** (não foi gerado nos primeiros sprints). Adicionar como sprint pequeno do backend.

---

## 5. Financeiro (`/v1/academies/{id}/{plans,financials,wallet,billing-contacts}`)

**Spec:** `api/openapi/financial.yaml`

### Migração

| Operação hoje | Endpoint | Mudança |
|---|---|---|
| Listar planos | `GET /v1/academies/{id}/plans` | |
| Criar plano | `POST /v1/academies/{id}/plans` | |
| Atribuir alunos a um plano | `POST /v1/academies/{id}/plans/{planId}/students` (body: `{ student_ids[] }`) | Substitui o `arrayUnion` no doc do plano. Backend usa `plan_students` join table. |
| Remover aluno do plano | `DELETE /v1/academies/{id}/plans/{planId}/students/{studentId}` | |
| Listar financials | `GET /v1/academies/{id}/financials?status=overdue&student_id=...&due_from=...&due_to=...&limit=50&cursor=...` | |
| Criar financial manual | `POST /v1/academies/{id}/financials` | |
| Marcar como pago | `PATCH /v1/academies/{id}/financials/{id}` (body: `{ status: 'paid', method, payment_date }`) | Backend faz: `financials.status=paid` + insert em `wallet_transactions` + update do `wallets.balance` em **uma transação** |
| **Geração mensal** | `POST /v1/academies/{id}/financials/generate-monthly` | Body: `{ reference_month }`. Header `Idempotency-Key` obrigatório. Disparado também por River cron no dia 1. |
| Wallet (saldo) | `GET /v1/academies/{id}/wallet` | Read-only |
| Wallet transações | `GET /v1/academies/{id}/wallet/transactions?limit=50&cursor=...` | Particionada por mês |
| Log de contato de cobrança | `POST /v1/academies/{id}/billing-contacts` | Substitui escrita direta em `billingContactLog` |
| Listar logs de contato | `GET /v1/academies/{id}/billing-contacts?student_id=...` | |

### Webhooks de pagamento (sem auth Firebase)

Hoje o app **abre WhatsApp** com link gerado client-side para cobrança. O fluxo de confirmação de pagamento é via webhook recebido por Cloud Function. No Tatami isso vira:

| Provedor | Endpoint Tatami | Auth |
|---|---|---|
| AbacatePay | `POST /v1/webhooks/abacatepay` | HMAC `cfg.Abacate.WebhookSecret` |
| Asaas | `POST /v1/webhooks/asaas` | Header `asaas-access-token` |

O cliente não chama esses endpoints. Eles existem para o Asaas/AbacatePay falarem com o Tatami.

### Gotcha — Asaas sub-accounts

O graduabjj hoje guarda a API key do Asaas **em texto plano** num doc da academia ou similar. No Tatami isso fica criptografado AES-256-GCM. O endpoint `PATCH /v1/academies/{id}` aceita `asaas_api_key` mas só admins podem setar; o backend criptografa antes de salvar.

---

## 6. Competições (`/v1/academies/{id}/competitions/*`)

**Spec:** `api/openapi/competition.yaml`

### Migração

| Operação | Endpoint | Notas |
|---|---|---|
| Listar competições | `GET /v1/academies/{id}/competitions?status=upcoming` | |
| Criar competição | `POST /v1/academies/{id}/competitions` | |
| Atualizar competição | `PATCH /v1/academies/{id}/competitions/{competitionId}` | |
| **Inscrever aluno** | `POST /v1/academies/{id}/competitions/{competitionId}/enrollments` | Validações server-side (item 13 do doc 01) |
| Cancelar inscrição | `DELETE /v1/academies/{id}/competitions/{competitionId}/enrollments/{enrollmentId}` | |
| Listar inscrições | `GET /v1/academies/{id}/competitions/{competitionId}/enrollments?transport=need_transport` | Filtro server-side, substitui o groupBy em memória |
| Registrar resultado | `POST /v1/academies/{id}/competitions/{competitionId}/results` | |
| **Upload de foto (2 passos)** | (1) `POST /v1/academies/{id}/competitions/{competitionId}/photos/upload-url` → recebe presigned URL; (2) PUT direto no storage; (3) `POST /v1/academies/{id}/competitions/{competitionId}/photos` para finalizar | Em vez de subir via Tatami |
| Listar fotos | `GET /v1/academies/{id}/competitions/{competitionId}/photos` | |
| Achievements do aluno | `GET /v1/academies/{id}/students/{studentId}/achievements` | |

### Gotcha — limite de 3 fotos por aluno por competição

Hoje a verificação é client-side. No Tatami há um trigger Postgres que enforces isso; o cliente recebe 409 se exceder.

---

## 7. Loja (`/v1/academies/{id}/store/*`)

**Spec:** `api/openapi/store.yaml`

### Migração

| Operação hoje | Endpoint | Notas |
|---|---|---|
| Listar produtos | `GET /v1/academies/{id}/store/products?category=&active=true` | |
| Criar produto | `POST /v1/academies/{id}/store/products` | |
| Atualizar produto | `PATCH /v1/academies/{id}/store/products/{productId}` | |
| Inativar produto | `DELETE /v1/academies/{id}/store/products/{productId}` | Soft delete |
| **Criar pedido** | `POST /v1/academies/{id}/store/orders` | Body: `{ student_id, items: [{ product_id, quantity, size?, color? }] }`. Backend snapshota preço + decrementa estoque atomicamente. |
| Listar pedidos | `GET /v1/academies/{id}/store/orders?status=&student_id=&limit=` | |
| Detalhe do pedido | `GET /v1/academies/{id}/store/orders/{orderId}` | |
| Atualizar status | `PATCH /v1/academies/{id}/store/orders/{orderId}` | Body: `{ status: 'preparing' }`. Transições válidas enforced server-side. |
| Cancelar pedido | `DELETE /v1/academies/{id}/store/orders/{orderId}` | Restaura estoque atomicamente se já estava paid. |

### Gotcha — `markAsPaid` vai sumir do cliente

Hoje `markOrderAsPaid()` é chamado pelo cliente após confirmar pagamento. No Tatami, o webhook do AbacatePay/Asaas chama o cross-context `store.StoreOrderUpdater.MarkPaid` — o cliente **não precisa fazer essa transição manualmente**. O cliente só vê `status: 'paid'` na próxima leitura/notificação.

---

## 8. Notificações + FCM (`/v1/me/notifications`, `/v1/me/fcm-tokens`)

**Spec:** `api/openapi/notification.yaml`

### Migração

| Operação hoje | Endpoint | Notas |
|---|---|---|
| Listar inbox | `GET /v1/me/notifications?unread_only=true&limit=20&cursor=...` | Substitui `.snapshots()` em `/academies/{id}/notifications` |
| Marcar como lida | `PATCH /v1/me/notifications/{id}/read` | |
| Marcar todas como lidas | `POST /v1/me/notifications/mark-all-read` | Retorna count |
| Registrar token FCM | `POST /v1/me/fcm-tokens` | Body: `{ token, platform: ios\|android\|web }`. Substitui escrita direta em `/users/{uid}/fcmTokens`. |
| Deregistrar token | `DELETE /v1/me/fcm-tokens/{token}` | Ao deslogar |
| Broadcast (admin) | `POST /v1/academies/{academyId}/notifications/broadcast` | |

### Gotcha — push notification arrival

O Firebase Messaging continua sendo o transport. O `FirebaseMessaging.onMessage` listener no Dart **não muda**. O que muda é quem **envia**: hoje uma Cloud Function; amanhã, o worker River do Tatami via `gateway/fcm.go`.

### Gotcha — listener real-time vs polling

Hoje o app usa `.snapshots()` em notifications. No Tatami inicial:
- **Polling otimizado**: a tela de notificações chama `GET /v1/me/notifications` ao abrir, e a cada 30s se em foreground. Com `If-None-Match` (ETag) o backend responde 304 em 90% das vezes.
- Quando a push chega via FCM, o app invalida o cache e força um refetch.
- SSE/WebSocket vem em sprint posterior do backend (vide doc 01, item "real-time subsystem").

---

## 9. Storage de imagens (foto de aluno, certificados médicos, galerias)

**Hoje:** upload direto do cliente para Firebase Storage; URL gravada no doc do student/competition.

**Futuro:** dois passos via Tatami → GCS/S3:

```dart
// 1) Pede ao Tatami um upload assinado
final signed = await api.post('/v1/uploads/sign', data: {
  'purpose': 'student_photo',
  'content_type': 'image/jpeg',
  'size_bytes': bytes.length,
});
// signed: { url, headers, storage_path, expires_at }

// 2) PUT direto no storage (sem proxy)
await dio.put(signed.url, data: bytes, options: Options(headers: signed.headers));

// 3) Atualiza o student com o storage_path
await api.patch('/v1/academies/$academyId/students/$studentId', data: {
  'photo_path': signed.storagePath,
});
```

Para download, o cliente pede uma signed URL temporária:

```dart
final url = await api.get('/v1/uploads/{storage_path}/download-url');
// url.expires em 15 min; o widget Image.network usa essa URL
```

(O endpoint `/v1/uploads/*` ainda precisa ser construído — vide o doc anterior sobre módulos faltantes.)

---

## 10. Map exhaustivo Service → Endpoints

| Service Dart | Métodos relevantes | Endpoint Tatami |
|---|---|---|
| `AuthService` | sign-in/out (Firebase) | mantém — só pega `getIdToken()` para anexar no header |
| `UserService` | `currentUser()`, `update()` | `GET /v1/me`, `PATCH /v1/me` |
| `AcademyService` | `get()`, `update()`, `create()` | `GET/PATCH/POST /v1/academies/{id}` |
| `SettingsService` | `get()`, `set()`, `list()` | `/v1/academies/{id}/settings*` |
| `LinkCodeService` | `generate()`, `redeem()`, `validate()` | `POST /v1/academies/{id}/link-codes`, `POST /v1/link-codes/{code}/redeem` |
| `StudentService` | `list/get/create/update/delete/searchByName/getDashboardStats/syncAttendanceCounts` | `/v1/academies/{id}/students*` + KPIs |
| `BeltProgressionService` | `create/get/checkEligibility/promote/getEligibilitySnapshot` | `POST /v1/academies/{id}/students/{studentId}/belt-progressions` + `GET .../graduation-eligibility` |
| `AssessmentService` | `create/list` | `/v1/academies/{id}/students/{studentId}/assessments*` |
| `ClassService` | `list/get/create/update/delete/addStudent/removeStudent/getWeeklySchedule` | `/v1/academies/{id}/classes*` |
| `AttendanceService` | `markPresent/bulkMarkPresent/getByStudent/getByDateRange/getWeightedAttendanceCount/checkAttendanceMilestone` | `/v1/academies/{id}/attendance*` (milestone agora é via outbox event) |
| `CheckinService` | `create/confirm/list` | dobrar como `/v1/academies/{id}/attendance/self-checkin` |
| `QrAttendanceService` | `processScan` | `POST /v1/academies/{id}/attendance/self-checkin` |
| `PlanService` | `list/get/create/update/delete/addStudent/removeStudent` | `/v1/academies/{id}/plans*` |
| `PaymentService` | `list/get/create/update/markAsPaid/streamByStudent` | `/v1/academies/{id}/financials*` |
| `WalletService` | `getBalance/getTransactions` | `/v1/academies/{id}/wallet*` |
| `BillingContactLogService` | `create/list` | `/v1/academies/{id}/billing-contacts*` |
| `CompetitionService` | `list/get/create/update/delete` | `/v1/academies/{id}/competitions*` |
| `CompetitionEnrollmentService` | `enroll/cancel/list/getTransportStats` | `/v1/academies/{id}/competitions/{cid}/enrollments*` |
| `CompetitionResultService` | `record/list` | `/v1/academies/{id}/competitions/{cid}/results*` |
| `CompetitionPhotoService` | `upload/list/delete` | 2-step com signed URL |
| `AchievementService` | `create/list/getMedalCount/getTimeline` | `/v1/academies/{id}/students/{studentId}/achievements*` |
| `StoreProductService` | `list/get/create/update` | `/v1/academies/{id}/store/products*` |
| `StoreOrderService` | `create/list/markAsPaid/cancel/updateStatus` | `/v1/academies/{id}/store/orders*` (markAsPaid sai do cliente) |
| `NotificationService` | `list/markRead/streamUserNotifications` | `/v1/me/notifications*` |
| `FcmTokenService` | `register/deregister` | `/v1/me/fcm-tokens*` |
| `FinancialReportService` | `loadAll/generateMonthlyReport/projectRevenue/getRevenueByPlan` | `/v1/academies/{id}/reports/*` + MV |
| `RetentionService` | `calculateStudentRisk/getRiskList` | `/v1/academies/{id}/risk-scores` (MV) |
| `AsaasPaymentService` / `AbacatePayService` | criar cobrança | **SAI DO CLIENTE.** Tatami fala com os gateways diretamente; cliente só lê `financials.status` ou recebe push. |

---

## 11. Padrão de erro — único e tipado

Toda chamada pode falhar com `TatamiException`. Padrão recomendado:

```dart
try {
  final list = await studentRepo.list(status: 'active');
  setState(() => students = list.items);
} on TatamiException catch (e) {
  if (e.isUnauthorized) {
    ref.read(authProvider.notifier).signOut();
  } else if (e.isValidation) {
    showSnack('Dados inválidos: ${e.errors.first.message}');
  } else if (e.isForbidden) {
    showSnack('Sem permissão.');
  } else {
    showSnack('Erro inesperado. Suporte: ${e.traceId}');
  }
}
```

A inclusão do `trace_id` em toasts de erro é não-negociável — esse é o pivô para o suporte achar a request no Jaeger.

---

## 12. Idempotency keys onde importam

Operações que mutam dinheiro ou geram efeitos colaterais devem mandar `Idempotency-Key: <uuid>`:

| Endpoint | Por quê |
|---|---|
| `POST /v1/academies/{id}/financials/generate-monthly` | Evita duplicação se o cliente retentar |
| `POST /v1/academies/{id}/store/orders` | Evita comprar duas vezes por toque duplo |
| `POST /v1/academies/{id}/attendance` (bulk) | Evita marcar presença duas vezes em sequência |
| `POST /v1/link-codes/{code}/redeem` | Evita resgatar duas vezes em situação de retry |
| `POST /v1/academies/{id}/students/{studentId}/belt-progressions` | Evita criar duas progressions |

Helper no cliente:

```dart
String newIdempotencyKey() => const Uuid().v4();
api.post(path, data: body, options: Options(headers: {
  'Idempotency-Key': newIdempotencyKey(),
}));
```

Em retries (Dio retry interceptor), **reutilizar a mesma key** — é justamente o que viabiliza o replay seguro.

---

## 13. Ordem de migração sugerida (frontend)

Faseado para evitar release "big bang":

1. **Fase 0 — Setup.** `TatamiClient` + `TatamiException` + interceptor de token + parser de problem+json. Nenhuma tela usa ainda.
2. **Fase 1 — `/v1/me`.** Substituir `currentUserProvider` e remover múltiplas leituras de `userAcademyMapping`.
3. **Fase 2 — Leituras pesadas.** `StudentService.list/searchByName`, `getDashboardStats`. Telas de admin que listam alunos passam a paginar.
4. **Fase 3 — Escritas de baixo risco.** Update de aluno, criação de plano, configurações.
5. **Fase 4 — Financeiro.** `financials*` + dashboards. **Webhooks de pagamento** já podem estar apontando para o Tatami antes.
6. **Fase 5 — Attendance + auto-graduação.** Mudar QR + bulk mark + cálculos de elegibilidade.
7. **Fase 6 — Notificações.** Migrar inbox + FCM registration.
8. **Fase 7 — Store, competições, fotos.** Última, porque envolve storage.
9. **Fase 8 — Limpeza.** Remover dependências Firestore que ainda existem; o Firebase fica só para Auth + (talvez) Storage transitório + FCM.

Cada fase é um release. O Tatami suporta convivência: enquanto a Fase 3 não rodou, o cliente pode misturar leituras Tatami com escritas Firestore — só não fica bonito, mas funciona.

---

Continua em [`03_OTIMIZACOES_GERAIS_APP.md`](03_OTIMIZACOES_GERAIS_APP.md) para as oportunidades de melhoria que o novo backend destrava (caching, image handling, state management, etc).
