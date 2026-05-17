# 11 — Estado dos wirings (snapshot pós-Sprint 7)

> Mapa de o que está pronto na branch `migration` por Sprint do plano,
> com o command para ativar cada um e o que ainda falta antes do
> Sprint 8 (Encerramento Firestore).

---

## Sprints concluídos (FE-only + wiring com flag default-off)

| Sprint | Contexto | Adapter `LegacyModel.fromApi(...)` | Provider Riverpod legacy-typed | Flag Remote Config |
|---|---|---|---|---|
| 1 | Identity | `AppUser.fromCurrentUserResponse(...)` | `currentUserProvider` (branch interna) | `useTatamiIdentity` |
| 2 | Student reads | `Student.fromApi(ApiStudent)` | `tatamiStudentsLegacyProvider(query)`, `tatamiStudentByIdLegacyProvider(ref)` | `useTatamiReads` |
| 3 | Plan | `Plan.fromApi(ApiPlan)` | `tatamiPlansLegacyProvider(academyId)` | `useTatamiWrites` |
| 3 | Class | `BJJClass.fromApi(ApiClass)` | `tatamiClassesLegacyProvider(query)` | `useTatamiWrites` |
| 3 | Settings | — (mapa key/value) | `tatamiSettingsProvider(academyId)` | `useTatamiWrites` |
| 3 | LinkCode | `LinkCode.fromApi(ApiLinkCode)` | helpers `redeemTatamiLinkCode`, `createTatamiStudentLinkCode` | `useTatamiWrites` |
| 4 | Financial | `Payment.fromApi(ApiFinancial)` | `tatamiPaymentsLegacyProvider(query)` | `useTatamiFinancials` |
| 5 | Attendance | `Attendance.fromApi(ApiAttendance)` | `tatamiAttendanceLegacyProvider(query)` | `useTatamiAttendance` |
| 6 | Notification | `AppNotification.fromApi(ApiNotification)` | `tatamiInboxLegacyProvider(filter)`, `tatamiUnreadCountProvider` | `useTatamiNotifications` |
| 7 | Store | `StoreProduct.fromApi`, `StoreOrder.fromApi`, `StoreOrderItem.fromApi` | `tatamiStoreProductsLegacyProvider`, `tatamiStoreOrdersLegacyProvider` | `useTatamiStore` |
| 7 | Competition | `Competition.fromApi(ApiCompetition)` | `tatamiCompetitionsLegacyProvider(academyId)` | `useTatamiCompetitions` |

**Comportamento default:** todas as flags `false` → app idêntico ao
legacy. Nenhuma chamada para o Tatami acontece em produção até a flag
ser flipada via Remote Config.

---

## Ativação (boot da app)

```dart
// lib/main.dart — após Firebase.initializeApp:
final rc = FirebaseRemoteConfig.instance;
await rc.fetchAndActivate();
container.read(tatamiFlagsProvider.notifier).state = TatamiFlags(
  useTatamiIdentity:     rc.getBool('useTatamiIdentity'),
  useTatamiReads:        rc.getBool('useTatamiReads'),
  useTatamiWrites:       rc.getBool('useTatamiWrites'),
  useTatamiFinancials:   rc.getBool('useTatamiFinancials'),
  useTatamiAttendance:   rc.getBool('useTatamiAttendance'),
  useTatamiNotifications:rc.getBool('useTatamiNotifications'),
  useTatamiStore:        rc.getBool('useTatamiStore'),
  useTatamiCompetitions: rc.getBool('useTatamiCompetitions'),
);
```

Tatami `TATAMI_BASE_URL` deve vir via `--dart-define` no build da app
(default: `https://api.staging.tatami.dev`).

---

## Cobertura

| Métrica | Antes (Sprint 0) | Final |
|---|---|---|
| Arquivos em `lib/api/` | 0 | 33 |
| Arquivos em `test/api/` | 0 | 26 |
| Adapters `*.fromApi` | 0 | 11 |
| Providers Riverpod legacy-typed | 0 | 13 |
| Tests passing | 14 (suite herdada) | **255** |
| Linhas adicionadas vs `feature/multi-sport` | 0 | ~18.500 |

---

## Padrões consolidados (referência rápida)

- **Adapter `fromApi`:** sempre via factory `static`/`factory` no model
  legacy. Parâmetros opcionais `{studentName, planId, ...}` quando o
  campo legacy é denormalizado e não vem na resposta canônica REST.
- **Status mapping:** quando o Tatami tem valores extras (ex.: `removed`
  no student) que o legacy não tem, mapear para o "mais conservador
  semântica" (`inactive`). Documentar no docstring.
- **Decimal-string → double:** `double.tryParse(s) ?? 0.0` é o padrão.
- **Enums casam 1:1 com wire format** (`snake_case`) via
  `// ignore_for_file: constant_identifier_names` quando precisa.
- **Providers que checam flag** usam `_requireFlag(flag, 'name')` e
  explodem com `TatamiFlagDisabledError` se chamados com flag off.
- **Providers legacy-typed** delegam ao provider Tatami original e
  fazem `.map(LegacyModel.fromApi)`. Cache `.family` é compartilhado.
- **Idempotency-Key automática** em POSTs que criam estado;
  `IdempotencyKey.fromString(...)` opcional para persistir entre crashes.

---

## Sprint 8 — gating

Pré-requisitos antes de remover `cloud_firestore` do `pubspec.yaml`:

- [ ] Todas as 8 flags rodando em 100% dos usuários por **30 dias**.
- [ ] Zero rollbacks executados nos últimos 30 dias.
- [ ] Cloud Functions de mirror Firestore (Sprints 3-4) desligadas.
- [ ] Webhook Asaas/AbacatePay apontando 100% para Tatami há ≥7 dias.
- [ ] BE PR 3 (guardian_links), 4 (notif → guardians), 6 (uploads
      genérico) mergeados.
- [ ] Job server-side `migrate_legacy_photos` rodando (Firebase
      Storage → GCS) — pode ainda estar em background; ler legacy
      `photo_url` no FE deixa de ser necessário quando 100% dos bytes
      migrarem.
- [ ] Security rules Firestore aplicadas: `allow read: if true;
      allow write: if false;` por 90 dias antes do export final
      Coldline.

Quando essas condições estiverem cumpridas, Sprint 8 é trabalho
mecânico:

1. Remover `cloud_firestore` do `pubspec.yaml`.
2. Remover `firebase_options.dart` references não-Auth-não-Storage.
3. Para cada provider que tinha `if (flags.X) tatamiPath else
   firestorePath`, remover o `else` (legacy).
4. Remover factories `*.fromFirestore` dos models.
5. Remover services legacy (`student_service.dart`, etc.) — manter só
   o repo Tatami como única source.
6. Remover `firestore.rules`, `firestore.indexes.json`.
7. Remover `TatamiFlags` (flags sem propósito quando só há um path).
8. Pôr a app em release para validar redução de tamanho APK/IPA.

---

## O que NÃO foi feito (e por que)

- **Migração de telas:** wirings adicionam o adapter + provider, mas
  cada screen ainda usa `studentServiceProvider` etc. legacy. Migração
  de cada tela é PR atômico (1-2 dias cada) que troca uma linha
  `ref.watch(legacyProvider)` por `ref.watch(tatamiLegacyProvider)`.
  Pode ser feito *após* flag flipar em canary 10%.
- **SSE stream de notificações:** Tatami expõe SSE com Last-Event-ID
  resume; FE migra de Firestore `.snapshots()` para polling com ETag
  primeiro (doc 03 §8), SSE entra com package `event_source` num PR
  separado.
- **StudentAvatar widget:** doc 03 §3. Pequeno, mas só faz sentido
  quando alguma tela já consome `photo_path` (Tatami) em vez de
  `legacy_photo_url` (Firebase). Adicionar quando essa tela for
  migrada.
- **CompetitionPhoto.fromApi + Achievement.fromApi:** adapter para o
  contexto completo de fotos. Pattern é o mesmo dos outros 11; pode ser
  PR de follow-up cobrindo somente esses dois.
- **Webhook cutover operacional** (Asaas/AbacatePay): trabalho SRE +
  ops, não de FE. Vide doc 06 §Fase 4 e doc 07.

---

## TaskList residual

| # | Task | Estado | Próximo passo |
|---|---|---|---|
| 9 | Sprint 8: Encerramento Firestore | pending | esperar 30d de estabilidade pós-flags-100% |
| — | Migração de telas | implícito | 1 PR por screen, atômico |
| — | SSE notification stream | implícito | swap polling→event_source quando rate > 50/s |
| — | StudentAvatar widget | implícito | adicionar com a primeira screen de fotos migrada |
| — | CompetitionPhoto.fromApi + Achievement.fromApi | implícito | PR de follow-up |
