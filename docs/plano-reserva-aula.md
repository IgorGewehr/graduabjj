# Plano — A1: Reserva de aula com vaga + lista de espera

> Mini-plano do módulo A1 do `docs/roadmap-modalidades.md`. Camada de
> **ocorrência datada** sobre as turmas recorrentes (`BJJClass.schedule`), com
> capacidade real (`maxStudents`), fila de espera e integridade server-side.

## Decisões de produto (travadas com o dono em 2026-06)

| Tema | Decisão |
|---|---|
| Janela de reserva | **Próximos 7 dias** (configurável, default 7) |
| Cancelamento + fila | **Auto-promove o 1º da espera** (com notificação) + **corte de 1h** antes do início p/ o aluno cancelar (staff cancela sempre) |
| Reserva ⇄ presença | **Separados** — reserva só garante a vaga; presença continua no check-in QR. Permite rastrear **no-show** (reservou e não fez check-in). Não mexe na graduação |
| Limite por aluno | **Configurável**, default **3** reservas futuras ativas (confirmadas+espera) |
| Integridade de vagas | **Cloud Function callables** (atômico, anti-furo). Deploy a partir DESTE repo (graduabjj = fonte canônica) |

## Conceito central: ocorrência

Turmas hoje são **templates semanais** (`schedule: [{dayOfWeek, startTime, endTime}]`,
`studentIds` = matrícula fixa, `maxStudents` só informativo). Uma reserva aponta
para uma **ocorrência** = `(classId, data, slot)`. Não materializamos todas as
ocorrências; geramos sob demanda os próximos 7 dias a partir do `schedule` e
guardamos **só as que têm reserva**.

- **ID determinístico da ocorrência:** `{classId}_{yyyyMMdd}` (1 slot/dia por turma;
  se uma turma tiver 2 horários no mesmo dia, sufixa `_{startTime}` → `{classId}_{yyyyMMdd}_{HHmm}`).
- **ID determinístico da reserva:** `{occId}__{studentId}` (idempotente: 1 reserva
  por aluno por ocorrência; upsert seguro).

## Modelo de dados

### `academies/{academyId}/classOccurrences/{occId}` (contador server-authoritative)
Criado/atualizado **só pelas callables**. Fonte da verdade de capacidade.
```
classId, className, sport, category,
date (yyyyMMdd), slotStart (Timestamp), startTime, endTime, dayOfWeek,
maxStudents (int|null = ilimitado),
confirmedCount (int), waitlistCount (int),
updatedAt
```

### `academies/{academyId}/classBookings/{bookingId}`
```
occId, classId, className, sport,
studentId, studentName,
date (yyyyMMdd), slotStart (Timestamp), startTime, endTime,
status: 'confirmed' | 'waitlist' | 'cancelled',
waitlistSeq (int|null)  // ordem de chegada na fila (serverTimestamp-based)
bookedBy: 'self' | 'responsible' | 'staff',
bookedByUid,
createdAt, updatedAt, cancelledAt
```

## Cloud Functions (additivas, `functions/server_functions.js`)

Mesmo padrão das callables existentes (`onCall` v2, `HttpsError`, guard por
`request.auth.uid` + checagem de academia/aluno como em `createPixPayment`).

### `reserveClassSlot({ academyId, classId, date, startTime })`
Transação atômica:
1. Auth: aluno reserva p/ si (ou responsável p/ dependente), staff p/ qualquer um.
2. Valida elegibilidade (matriculado na turma **ou** turma aberta compatível) e janela (≤ 7 dias, futuro).
3. Valida limite: reservas ativas do aluno < `maxActiveBookingsPerStudent`.
4. Lê/crie o doc da ocorrência. Se `confirmedCount < maxStudents` (ou max null) → `confirmed`, `confirmedCount++`. Senão → `waitlist`, `waitlistCount++`, `waitlistSeq = now`.
5. Upsert idempotente da reserva (reservar de novo o já-confirmado é no-op).
Retorna `{ status, position }`.

### `cancelClassReservation({ academyId, classId, date, startTime })`
Transação atômica:
1. Auth (dono/staff). Se aluno: valida **corte de 1h** (`now < slotStart - 60min`); staff ignora o corte.
2. Marca reserva `cancelled`; decrementa o contador conforme o status anterior.
3. Se era `confirmed` e há fila: **promove** o `waitlist` de menor `waitlistSeq` → `confirmed` (`confirmedCount` estável: −1 cancelado +1 promovido), notifica o promovido.
Retorna `{ promotedStudentId? }`.

> Promoção é feita **dentro da mesma transação** lendo a fila por um índice
> `(occId, status, waitlistSeq)` — query pré-transação p/ achar o candidato,
> re-validação dentro da transação (academia = baixa concorrência).

## Regras Firestore (`firestore.rules`, sob `academies/{academyId}`)

```
match /classOccurrences/{occId} {
  allow read: if isSignedInAcademyMember(academyId);   // aluno vê vagas
  allow write: if false;                               // só callables (admin SDK)
}
match /classBookings/{bookingId} {
  allow read: if isStaffOrMonitor(academyId) || isOwnBooking(...);
  allow write: if false;                               // só callables
}
```
(Escrita 100% via Admin SDK ⇒ integridade garantida; cliente nunca escreve vaga.)

## Settings (`AcademySettings` + `settings_service.dart` + `settings_screen.dart`)
- `bookingEnabled: bool` (default false — feature opt-in por academia)
- `bookingWindowDays: int` (default 7)
- `bookingCancelCutoffMinutes: int` (default 60)
- `maxActiveBookingsPerStudent: int` (default 3)

## Helper puro testável — `lib/core/class_occurrences.dart`
Sem deps de Flutter/Firestore (padrão dos outros `core/`):
- `upcomingOccurrences(schedule, {from, windowDays})` → lista de `(date, dayOfWeek, startTime, endTime, slotStart)` ordenada.
- `occurrenceId(classId, date, startTime, {hasMultiPerDay})`.
- `canCancel(slotStart, now, cutoffMinutes)` → bool.
- `withinWindow(slotStart, now, windowDays)` → bool.
→ testes em `test/class_occurrences_test.dart`.

## Telas

### Portal — `lib/screens/portal/class_booking_screen.dart` (rota `/portal/reservas`)
- Lista de **ocorrências dos próximos 7 dias** das turmas elegíveis (agrupado por dia).
- Por card: nome/horário/instrutor, **vagas X/Y**, estado do aluno.
- Ações: **Reservar** · **Entrar na espera** (quando cheia) · **Cancelar** (respeita corte 1h, desabilita c/ aviso). Mostra **posição na fila**.
- Seção **"Minhas reservas"** (próximas, confirmadas + espera).
- Entrada no portal/home.

### Admin — gestão de ocorrência (em `class_detail`/nova aba ou tela)
- Por ocorrência: lista **confirmados** + **fila**; **adicionar/remover** manual (via callables, bookedBy=staff, ignora corte).
- Indicador de **no-show** pós-aula (confirmado sem `attendance` naquela data) — leitura derivada.

## Fases

1. **Núcleo de integridade** — modelo `class_booking.dart`, helper `class_occurrences.dart` (+testes), callables `reserveClassSlot`/`cancelClassReservation`, `class_booking_service.dart` (client: chama callables + queries de leitura), regras + índices + barrels (`firebase_service.dart`, `services.dart`). **Deploy de Functions/rules/índices = checkpoint do dono.**
2. **Portal do aluno** — `class_booking_screen.dart` + rota + entrada.
3. **Admin + ajustes** — gestão de ocorrência (confirmados/fila/no-show) + 4 settings.
4. **Notificações + auditoria** — confirmação, promoção da fila, (lembrete) via dispatcher; auditoria brutal por fase.

## Fora de escopo (A1)
- Cobrança por aula avulsa / pacotes de créditos.
- Recorrência de reserva ("reservar toda segunda").
- Push real (depende de F2); por ora reaproveita o dispatcher/notification atual.
