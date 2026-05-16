# 01 — Lógica de negócio delegada ao frontend (e por que isso é errado)

> **Contexto.** O graduabjj nasceu como app Flutter direto-no-Firestore. Sem backend dedicado, toda regra de negócio acabou no cliente. Esse documento cataloga **exatamente** onde isso aconteceu, classifica o grau de risco, e indica para qual contexto/endpoint do Tatami cada peça deve migrar.
>
> **Como ler.** Cada seção tem: o que o cliente faz hoje, o arquivo e linhas, **por que isso é problemático** (correção, segurança, custo ou correção concorrente), e o destino no Tatami.

---

## Sumário executivo

| # | Domínio | Onde está hoje | Risco | Destino no Tatami |
|---|---|---|---|---|
| 1 | Elegibilidade de graduação (faixa/grau) | `services/belt_progression_service.dart` | 🔴 Correção + custo | `internal/attendance/domain/eligibility.go` + endpoint dedicado |
| 2 | Geração mensal de mensalidades | ausente — manual no cliente | 🔴 Correção | `financial.Service.GenerateMonthlyFinancials` |
| 3 | Transição `pending → overdue` | `Payment.isOverdue` getter (cliente) | 🟠 Correção | River job diário + status materializado |
| 4 | Validação de QR check-in | `services/qr_attendance_service.dart` | 🔴 Segurança | `attendance.Service.SelfCheckIn` |
| 5 | Decremento de estoque ao pagar pedido | `services/store_service.dart` linhas 718–839 | 🔴 Concorrência | Transação no `store.Service.MarkPaid` |
| 6 | Cálculo de risco de retenção | `services/retention_service.dart` | 🟠 Custo + frescor | Endpoint + MV `mv_academy_kpis` |
| 7 | Relatórios financeiros (MoM, projeção) | `services/financial_report_service.dart` | 🟠 Custo | Views `v_monthly_revenue` + endpoint |
| 8 | Resgate de link-code (multi-write) | `services/link_code_service.dart` | 🔴 Atomicidade | `academy.Service.RedeemLinkCode` (1 tx) |
| 9 | Desbloqueio de milestones de presença | `attendance_service.dart` linhas 659–712 | 🟠 Concorrência | River worker + outbox |
| 10 | Sincronização de contadores denormalizados | `student_service.dart` `syncAttendanceCounts` | 🔴 Custo + correção | Trigger Postgres + MV |
| 11 | Permissões (role, extra_permissions) | espalhado em todas as telas | 🟠 Segurança | RBAC do Tatami (authz) + RLS |
| 12 | Verificação de duplicata de presença | `attendance_service.dart` `isStudentPresent` | 🟠 Concorrência | `UNIQUE (student_id, class_id, date)` |
| 13 | Validação de categoria/peso em competição | ausente — só lógica visual | 🟠 Correção | `competition.Service.Enroll` |
| 14 | Snapshot de `effectiveCountAtPromotion` | `belt_progression_service.dart` linhas 641–649 | 🟠 Correção | Calculado no `promote()` do backend |
| 15 | Detecção de "já fez check-in hoje" | `checkin_service.dart` | 🟠 Concorrência | `UNIQUE (student_id, date)` + retorno 409 |

🔴 = bloqueador para migração (afeta correção ou segurança). 🟠 = importante (afeta custo, performance ou UX).

---

## 1. Elegibilidade de graduação — cliente calcula tudo

**Arquivo:** `lib/services/belt_progression_service.dart`

### O que o cliente faz

```dart
// linhas 469-476 (loop sobre todos os alunos)
for (final student in activeStudents) {
  final weightedCount = await getWeightedAttendanceCount(student.id);
  final fromProgression = await getLastProgression(student.id);
  final effective = weightedCount - (fromProgression?.effectiveCountAtPromotion ?? 0);
  if (effective >= academy.autoGraduationAttendances) {
    eligible.add(student);
  }
}
```

- Carrega TODOS os alunos ativos
- Para cada um, faz uma query de attendance pesada (com soma de `Class.weight`)
- Compara com o threshold da academia (`autoGraduationAttendances`)
- Subtrai o snapshot da última promoção para não contar duas vezes
- Mantém uma `Map<String, int>` local de `stripeRequirements` (regras hardcoded)

### Por que está errado

1. **Custo.** Numa academia de 200 alunos, são 200+ queries em série. No Firestore isso é dinheiro real (cada doc lido cobra). No Postgres, o mesmo cálculo é uma única query agregada.
2. **Inconsistência.** Se a regra de elegibilidade muda (a IBJJF muda o número de aulas por grau), você precisa publicar uma nova versão do app para todo o parque instalado.
3. **Trust.** Um aluno mal-intencionado pode forjar uma chamada da função (ou simplesmente editar a UI) e se auto-graduar. Toda decisão de promoção que se baseia em estado do cliente é vulnerável.
4. **Snapshot frágil.** O campo `effectiveCountAtPromotion` é calculado **no cliente** no momento da promoção. Se duas instâncias do app promovem o mesmo aluno simultaneamente (instrutor 1 marca grau e instrutor 2 cria progression), o snapshot fica inconsistente.

### Destino no Tatami

```
GET  /v1/academies/{academyId}/students/{studentId}/graduation-eligibility
POST /v1/academies/{academyId}/students/{studentId}/belt-progressions
```

- `domain.EvaluateBeltEligibility(currentBelt, attendanceCountSinceLastProgression, threshold)` é uma função pura, testada (já existe em `internal/attendance/domain/eligibility.go`).
- A query de contagem ponderada vira **uma** SQL com `SUM(weight)` filtrada por `student_id` e `> last_progression_date`.
- A promoção é uma transação que persiste `BeltProgression`, atualiza `student.current_belt/current_stripes`, e dispara um achievement — tudo atômico.
- O cliente deixa de saber a regra: chama o endpoint e recebe `{ eligible: true, weighted_count: 47, threshold: 40, next_belt: 'blue' }`.

---

## 2. Geração de mensalidades — ausente, manual

### O que o cliente faz

Hoje, o admin **cria manualmente** cada mensalidade. Não há geração automática. O `Plan` tem `monthlyValue` + `defaultDueDay` + `customValues` por aluno, mas nada gera as faturas mensais.

### Por que está errado

- Trabalho repetitivo: 200 alunos = 200 cliques mensais.
- Esquecimento: admins esquecem de gerar para alguns alunos.
- Inconsistência: se o admin gera no dia 3 ao invés do dia 1, alunos novos ficam de fora.

### Destino no Tatami

```
POST /v1/academies/{academyId}/financials/generate-monthly
  Body: { "reference_month": "2026-06" }
  Header: Idempotency-Key: <client-uuid>
```

- O serviço `financial.Service.GenerateMonthlyFinancials` (já implementado) percorre os planos, resolve `custom_values` por aluno, cria as N faturas em uma única transação.
- Idempotente: chamar duas vezes com o mesmo header devolve a mesma resposta (middleware de idempotency já existe).
- Disparado por **River periodic job** todo dia 1º às 6h. O endpoint manual fica como override administrativo.

---

## 3. Transição `pending → overdue` — getter no cliente

**Arquivo:** modelo `Payment`/`Financial`

```dart
bool get isOverdue =>
    status != PaymentStatus.paid &&
    dueDate.isBefore(DateTime.now());
```

### Por que está errado

- O **estado real** no Firestore continua sendo `pending`. O cliente "vê" overdue mas o banco não.
- Relatórios que rodam server-side (ou cron de cobrança) precisam reimplementar a mesma regra.
- A regra usa o relógio do dispositivo — um celular com data errada exibe valores enganosos.

### Destino no Tatami

- River job diário às 00:30 (BRT) varre `financials WHERE status='pending' AND due_date < CURRENT_DATE` e faz `UPDATE ... SET status='overdue'`.
- O cliente passa a confiar em `status`. O getter `isOverdue` deixa de existir.
- Bônus: o job dispara uma notificação automática (canal `payment_due`) — já modelado em `internal/notification`.

---

## 4. QR check-in — validação client-side

**Arquivo:** `lib/services/qr_attendance_service.dart`

### O que o cliente faz

```dart
// Parse do QR
final payload = jsonDecode(qr) as Map<String, dynamic>;
// Verifica TTL
if (now - payload['t'] > 60) throw 'QR expirado';
// Verifica se o aluno está na classe
if (!cls.studentIds.contains(studentId)) throw 'Não inscrito';
// Marca attendance via Firestore com FieldValue.serverTimestamp()
await attendanceService.markPresent(...);
```

### Por que está errado

- **Forjabilidade.** O QR é JSON em texto plano. Um aluno pode editar o `t` para qualquer valor, "renovar" o token, ou alterar o `academyId`/`classId` e fazer check-in numa aula que não está acontecendo.
- **Janela de tempo.** A regra "30 min antes até 1h depois" é avaliada com o relógio do cliente.
- **Permissão de auto-check-in.** A verificação `cls.studentIds.contains(studentId)` é feita lendo o doc da Class no cliente; um aluno com app modificado pode pular essa checagem.

### Destino no Tatami

```
POST /v1/academies/{academyId}/attendance/self-checkin
  Body: { "class_id": "...", "qr_token": "<assinado>", "scanned_at": "..." }
```

- **QR assinado.** O backend gera o QR como JWT/PASETO assinado com a chave da academia. Curto TTL (60s). O cliente apenas exibe e escaneia; quem valida a assinatura é o backend.
- **Verificação central.** O endpoint:
  1. Decodifica o token e valida assinatura.
  2. Checa que o `caller.uid` é `linked_user_uid` de algum student em `class.student_ids`.
  3. Verifica que a aula tem schedule para agora (com `time.Now()` do servidor + TZ da academia).
  4. Verifica que `(student_id, class_id, date)` não existe (constraint UNIQUE).
  5. Cria attendance com `weight` snapshot + dispara outbox event para `BeltPromotionEligible`.
- Cliente deixa de saber as regras; só envia o token.

---

## 5. Decremento de estoque ao pagar — race condition

**Arquivo:** `lib/services/store_service.dart` linhas 718–839

### O que o cliente faz

```dart
// Quando transição pendingPayment → paid:
for (final item in order.items) {
  // Re-valida estoque
  final product = await getProduct(item.productId);
  if (product.stockQuantity < item.quantity) throw 'Sem estoque';
}
// Loop separado: decrementa
for (final item in order.items) {
  await productRef.update({
    'stockQuantity': FieldValue.increment(-item.quantity),
  });
}
```

### Por que está errado

- **Dois clientes pagando o mesmo produto simultaneamente:** ambos veem estoque suficiente, ambos decrementam, estoque fica negativo. Clássico.
- **Re-validação custosa:** lê o produto duas vezes (uma na criação do pedido, outra no pagamento).
- **Sem transação atômica:** se o app crashar entre o update do pedido e o decremento, o estoque some no espaço.

### Destino no Tatami

```sql
UPDATE store_products
SET stock_quantity = stock_quantity - $1
WHERE id = $2 AND stock_quantity >= $1
RETURNING stock_quantity;
```

- Uma única query atômica. Se `stock_quantity < $1`, o `WHERE` falha, nenhuma linha é atualizada, o serviço retorna `ErrOutOfStock`.
- Tudo dentro da transação que muda `store_orders.status = 'paid'`. Se algo falha, o estoque é preservado.
- Já está modelado em `internal/store/application/ports.go` como `DecrementStockTx`.

---

## 6. Risco de retenção — cálculo client-side

**Arquivo:** `lib/services/retention_service.dart`

### O que o cliente faz

Recebe `List<Student>`, `List<Attendance>`, `List<Financial>` como parâmetros e calcula:
- Queda de frequência (compara últimos 15 dias vs 15 anteriores) — 40 pts
- Inatividade (dias desde última presença) — 30 pts
- Pagamentos atrasados — 20 pts
- Progresso (tempo desde cadastro) — 10 pts
- Soma → score 0–100 → nível `low/medium/high/critical`

### Por que está errado

- O cliente precisa **baixar todo o histórico** de attendance + financials para calcular. Para uma academia de 200 alunos com 2 anos de histórico, isso é facilmente 50k+ docs.
- O cálculo só roda quando a tela abre — não há dashboard live.
- Cada admin que abre o dashboard repete o cálculo.

### Destino no Tatami

```sql
-- view materializada refrescada a cada 10 min
CREATE MATERIALIZED VIEW mv_student_risk_scores AS
SELECT
  student_id,
  academy_id,
  CASE
    WHEN attendance_drop_pct > 50 THEN 40
    ELSE attendance_drop_pct * 0.8
  END
  + CASE
    WHEN days_since_last_class > 30 THEN 30
    ELSE days_since_last_class
  END
  + LEAST(overdue_payments * 5, 20)
  + LEAST(days_since_enrollment / 30, 10)
  AS risk_score
FROM student_metrics;
```

- A MV `mv_academy_kpis` já existe (migração 00013). Estender com `mv_student_risk_scores`.
- Endpoint: `GET /v1/academies/{id}/risk-scores?level=high,critical` → 1ms de latência independente do tamanho.
- Cliente só renderiza.

---

## 7. Relatórios financeiros — projeção e MoM no cliente

**Arquivo:** `lib/services/financial_report_service.dart`

### O que o cliente faz

```dart
// loadAll() — linhas 107-158
final allFinancials = await financialsRef.get();  // SEM limit
final allPlans = await plansRef.get();
_financialsByMonth = groupBy(allFinancials.docs, ...);

// generateMonthlyReport()
final paid = thisMonth.where((f) => f.status == 'paid').sum;
final pending = thisMonth.where((f) => f.status == 'pending').sum;
final overdue = thisMonth.where((f) => f.status == 'overdue').sum;
final collectionRate = paid / (paid + pending + overdue);
final lastMonth = generateMonthlyReport(now.month - 1);
final growthMoM = (revenue - lastMonth.revenue) / lastMonth.revenue;

// projectRevenue()
final last6 = lastSixMonths;
final movingAvg = last6.sum / 6;
final trend = linearRegression(last6);
final projected = movingAvg + trend * n;
```

### Por que está errado

- Carrega **toda** a coleção financials. Em 5 anos de academia isso são dezenas de milhares de docs.
- Faz regressão linear em Dart no thread principal — UI trava se a lista for grande.
- Não há cache; cada vez que o admin abre o relatório, baixa tudo de novo.

### Destino no Tatami

- View `v_monthly_revenue` (já criada em `00013_views_kpis.sql`) entrega `revenue_paid / revenue_pending / revenue_overdue` por (academy, month).
- Endpoint `GET /v1/academies/{id}/reports/revenue?months=12` → `[ { month: '2026-06', paid: ..., pending: ..., overdue: ... }, ... ]`.
- Projeção: opcionalmente, um endpoint dedicado que chama uma função SQL com `regr_slope()` nativa do Postgres.
- Cliente faz só o gráfico.

---

## 8. Resgate de link-code — multi-write sem transação

**Arquivo:** `lib/services/link_code_service.dart`

### O que o cliente faz

```dart
// 1) lê o linkCode
// 2) marca usedAt
// 3) cria a entrada em userAcademyMapping
// 4) atualiza student.linkedUserId
// 5) (cria academy-scoped user doc)
```

### Por que está errado

- **5 writes sem transação.** Se o cliente cai entre o passo 2 e o 3, o código vira "usado" mas o usuário fica sem academia.
- **Race condition em multi-tabs.** Dois dispositivos resgatando o mesmo código simultaneamente — security rules tentam atomicidade mas a verificação `usedAt == null` + write é classicamente vulnerável a TOCTOU.

### Destino no Tatami

```
POST /v1/link-codes/{code}/redeem
```

- Uma transação Postgres com:
  1. `SELECT FOR UPDATE` no linkCode (lock pessimista).
  2. Verifica `used_at IS NULL` e `expires_at > now()`.
  3. UPDATE `linkCode SET used_at, used_by`.
  4. INSERT `user_academy_mapping`.
  5. UPDATE `student.linked_user_uid`.
  6. COMMIT.
- Se duas requisições chegam simultâneas, a segunda espera o lock e depois falha com `ErrLinkCodeAlreadyUsed`.

---

## 9. Milestones de presença — race condition

**Arquivo:** `lib/services/attendance_service.dart` linhas 659–712

### O que o cliente faz

```dart
// Após markPresent:
final newCount = student.attendanceCount + 1;
if ([50, 100, 200, 500, 1000].contains(newCount + initial)) {
  final existing = await achievementService.findByMilestone(studentId, total);
  if (existing == null) {
    await achievementService.create(...);
  }
}
```

### Por que está errado

- Leitura + escrita sem transação. Duas presenças quase simultâneas (bulk mark) podem criar dois achievements para o mesmo milestone.
- Se a criação falha, o aluno perde a conquista silenciosamente.

### Destino no Tatami

- Após cada `attendance INSERT`, o serviço escreve um evento no `outbox_events` (mesma tx).
- Worker `attendance` consome o evento, recalcula o total, faz `INSERT ... ON CONFLICT DO NOTHING` no `achievements`. Idempotente.
- Constraint `UNIQUE (student_id, milestone_key)` em achievements impede duplicação por construção.

---

## 10. `syncAttendanceCounts` — N+1 colossal

**Arquivo:** `lib/services/student_service.dart` linhas 440–454

```dart
for (final student in students) {
  final attendance = await attendanceRef
      .where('studentId', isEqualTo: student.id)
      .get();
  await studentRef.update({ 'attendanceCount': attendance.size });
}
```

- 200 alunos = 200 reads + 200 writes.

### Destino no Tatami

```sql
-- Trigger AFTER INSERT/DELETE em attendance
CREATE FUNCTION update_attendance_count() RETURNS TRIGGER AS $$
BEGIN
  UPDATE students
  SET attendance_count = attendance_count + CASE WHEN TG_OP='INSERT' THEN 1 ELSE -1 END
  WHERE id = COALESCE(NEW.student_id, OLD.student_id);
  RETURN NULL;
END $$ LANGUAGE plpgsql;
```

- O contador é mantido **atomicamente** pelo banco.
- O "sync" deixa de existir; passa a ser desnecessário por construção.

---

## 11. Permissões espalhadas em cada tela

**Padrão recorrente:** 133+ ocorrências de `currentUser.academyId` em `lib/screens/portal/`.

```dart
final currentUser = ref.watch(currentUserProvider).valueOrNull;
if (currentUser?.academyId == null) return EmptyState();
// ... cada tela refaz a checagem
```

### Por que está errado

- Cada `FutureProvider.autoDispose` re-fetcha `userAcademyMapping` ao reabrir a tela.
- Lógica de role (`admin`/`instructor`/`student`/`monitor`) é repetida em cada handler.
- Mudanças de permissão exigem alterar dezenas de telas.

### Destino no Tatami

- **Backend:** middleware `authz.RequireRole` aplicado por rota; resposta 403 padrão.
- **Frontend:** uma única chamada a `GET /v1/me` na inicialização (já existe — `identity.yaml`) retorna o objeto `CurrentUser` com memberships + permissions. Cache em Riverpod com `keepAlive: true`.
- Telas só decidem **renderização** (mostrar ou esconder botões); a autorização é do servidor.

---

## 12. Duplicata de presença — `isStudentPresent` no cliente

**Arquivo:** `lib/services/attendance_service.dart`

```dart
Future<bool> isStudentPresent(String studentId, String classId, DateTime date) async {
  final query = await attendanceRef
    .where('studentId', isEqualTo: studentId)
    .where('classId', isEqualTo: classId)
    .where('date', ...)
    .get();
  return query.size > 0;
}
```

### Por que está errado

- Race: dois clicks simultâneos do botão "Presente" passam pela checagem antes de qualquer um escrever.
- Custa um read antes de cada write.

### Destino no Tatami

```sql
CREATE UNIQUE INDEX attendance_dedup_uidx
  ON attendance(student_id, class_id, date);
```

- A constraint UNIQUE elimina a checagem.
- Endpoint retorna 409 Conflict em caso de duplicata; o cliente trata.

---

## 13. Validação de inscrição em competição — só visual

**Arquivo:** `lib/services/competition_enrollment_service.dart`

### O que falta hoje

- Nenhuma verificação de faixa mínima.
- Nenhuma verificação de categoria de peso (aluno de 50kg inscrito como pesado).
- A categoria de idade é calculada de `student.birthDate` no momento da inscrição (relógio do cliente).

### Destino no Tatami

- Endpoint `POST /v1/academies/{id}/competitions/{cid}/enrollments` valida:
  1. Faixa atual ≥ faixa mínima da competição.
  2. Peso atual encaixa na categoria escolhida.
  3. Idade calculada server-side bate com `age_category`.
- Erros retornam `problem+json` com `errors[]` apontando o campo.

---

## 14. `effectiveCountAtPromotion` — snapshot frágil

**Arquivo:** `lib/services/belt_progression_service.dart` linhas 641–649

```dart
final weightedCount = await getWeightedAttendanceCount(studentId);
final progression = BeltProgression(
  ...
  effectiveCountAtPromotion: weightedCount,
);
```

- O snapshot é lido + escrito em duas operações distintas.

### Destino no Tatami

- O `promote()` do backend faz:
  ```sql
  WITH count AS (
    SELECT COALESCE(SUM(c.weight), COUNT(*)) AS total
    FROM attendance a JOIN classes c ON c.id = a.class_id
    WHERE a.student_id = $1 AND a.date > (SELECT MAX(promotion_date) FROM belt_progressions WHERE student_id = $1)
  )
  INSERT INTO belt_progressions (..., effective_count_at_promotion) VALUES (..., (SELECT total FROM count));
  ```
- Snapshot e progressão são **gravados na mesma transação**, sem janela de inconsistência.

---

## 15. "Já fez check-in hoje?" — read antes do write

**Arquivo:** `lib/services/checkin_service.dart`

### O que o cliente faz

```dart
final existing = await checkinsRef
  .where('studentId', isEqualTo: studentId)
  .where('date', isEqualTo: today)
  .get();
if (existing.size > 0) throw 'Já fez check-in';
await checkinsRef.add({...});
```

### Destino no Tatami

```sql
CREATE UNIQUE INDEX checkins_one_per_day ON checkins(student_id, date);
```

- Mesma estratégia do #12.

---

## O que isso destrava

Quando essas 15 peças saem do cliente:

1. **App fica burro de propósito.** Sem regra de negócio embutida, o app é só uma camada de apresentação. Atualizações de regra (ex.: nova fórmula de graduação) viram um deploy de backend, não um release de loja.
2. **Auditoria fica possível.** Cada decisão (promoção, baixa de mensalidade, marcação de presença) deixa rastro no banco com `created_by_uid` confiável.
3. **Custo cai.** Numa academia média (200 alunos), reduzimos em ~80% o volume de reads do Firestore (e equivalente em egress + CPU client-side).
4. **Concorrência fica resolvida.** Transações Postgres tratam o que hoje é race condition silenciosa.
5. **Segurança fica defensável.** Quem decide se um aluno pode se graduar é o backend, não a UI.

Continua em [`02_MAPEAMENTO_ENDPOINTS_NOVO_BACKEND.md`](02_MAPEAMENTO_ENDPOINTS_NOVO_BACKEND.md) para o mapa concreto Firestore-call → endpoint Tatami.
