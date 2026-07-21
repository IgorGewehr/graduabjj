# Relatório de Fase — Check-in na turma certa + Bloqueio por inadimplência na catraca

## Resumo

Esta fase adicionou, de forma **greenfield/aditiva e ainda NÃO deployada**, dois comportamentos server-side ao fluxo `ingestAccessEvent` (catraca / controle de acesso), seguindo a Arquitetura C (decisão no servidor, dispositivos burros):

1. **Check-in na turma certa** — quando um aluno passa na catraca, a presença passa a ser registrada na **turma real em andamento** (resolvida pela grade de horários, modalidade, categoria e matrícula), em vez de sempre cair num registro genérico de "Acesso por Catraca". Mantém fallback sintético quando nenhuma turma casa.
2. **Bloqueio por inadimplência** — opcionalmente (por academia, **default desligado**), a catraca **nega o giro** para alunos com mensalidade vencida, sem registrar presença, de forma **fail-open** (qualquer dúvida/erro → libera).

Toda a lógica nova vive em `functions/access_control/` (3 arquivos novos + edição do `ingest.js`), mais 1 índice em `firestore.indexes.json`. `node --check` passa nos 8 arquivos. Os fixes de segurança anteriores (C1 path-injection, H1 idempotência) **não regrediram**.

Arquivos tocados:
- `functions/access_control/class_resolver.js` (novo)
- `functions/access_control/financial_gate.js` (novo)
- `functions/access_control/overdue_util.js` (novo — fonte única de "vencido")
- `functions/access_control/ingest.js` (editado)
- `functions/server_functions.js` (passa a importar de `overdue_util.js`)
- `firestore.indexes.json` (índice composto `financials`)

---

## Check-in na turma

### Algoritmo (`resolveActiveClass`, helper PURO sem I/O)

O handler lê **uma vez por POST** as turmas ativas (`academies/{id}/classes` onde `isActive == true`), **fora da transação**, e passa o array já carregado ao resolver. Para cada turma candidata, o resolver aplica em sequência:

1. **Fuso BR** — `dayOfWeek` e minutos do evento derivados em wall-clock BR (`ymdBR`/`dowBR`/`minutesBR`), já que `process.env.TZ` está pinado em `America/Sao_Paulo`. Isso corrige um bug latente do `ymdUTC` antigo perto da meia-noite (deslocamento de -3h trocava o dia do doc-id).
2. **Modalidade** — se `device.sport` setado, casa só turmas daquele esporte (`sport ?? 'bjj'`); ausente = porta genérica (casa qualquer modalidade).
3. **Categoria** — `device.category` casa turmas com aquela categoria OU `category == null` (wildcard, evita over-filtrar legado).
4. **Matrícula** — espelha `acceptsCheckinFrom` do Dart **verbatim**: `isOpenClass===true` aceita todos; `===false` exige `studentIds.includes`; qualquer outro valor (legado/null) = lista vazia ou aluno na lista.
5. **Janela com tolerância** — PRE=30 / POST=30 min (override por `device.scheduleToleranceMinutes`), com guarda defensiva de meia-noite.

**Desempate determinístico** (crítico para idempotência, pois o `classId` entra no doc-id): `strictIn` (aula em andamento) > `startClosest` (slot mais recente já iniciado) > `enrolledStrict` (aluno na lista) > **`classId` ascendente**. A re-entrega do mesmo evento resolve SEMPRE a mesma turma.

### Fallback

Nenhuma turma casa → resolver retorna `null` → `recordAccessEvent` mantém o comportamento sintético **exato e atual**: `classId = catraca_<deviceId>`, `className = 'Acesso por Catraca'`, `sport = 'bjj'`. O aluno **nunca fica sem presença** por falta de match.

### Idempotência

- Doc-id da presença passou de `studentId_<device>_YYYYMMDD` para **`studentId_<classId>_YYYYMMDD`** → 1 presença por aluno/turma/dia (era 1 por device/dia).
- A barreira atômica continua sendo `tx.create(accessEvents/{deviceId}_{eventId})` — inalterada.
- O `classId` real é revalidado por `isSafeSegment` antes de compor o doc-id (defesa C1); se inseguro, cai para sintético.
- O `accessEvent` carimba `resolvedClassId` + `matchVia: 'schedule' | 'synthetic'` para reconciliação/auditoria.
- `weight` só é persistido quando `!= 1` (espelha `markPresent`).

---

## Bloqueio por inadimplência

### Config por academia (default OFF — deploy é no-op até a academia optar)

```
academies/{id}.accessControl = {
  blockOnOverdue: false,            // default false → feature desligada
  graceDays: 0,                     // dias-calendário BR tolerados após vencer
  blockTypes: ['monthly_tuition'],  // só mensalidade prende
}
```

Lido junto do device, uma vez por POST, e passado ao `recordAccessEvent`.

### Algoritmo (`checkOverdueGate`) — FAIL-OPEN total

Tudo dentro de `try/catch` que retorna `blocked:false` em qualquer falha. Default OFF retorna liberado antes de qualquer I/O. Quando ligado: query `financials` por `studentId` + `status in ['pending','overdue']`, e em memória — só bloqueia se o tipo está em `blockTypes`, **não** é `isOvercharge` (dinheiro devido AO aluno), tem `dueDate` válido, está vencido por `isOverdueBR` E ultrapassou `graceDays`.

Pontos de design:
- **Fonte única de verdade de "vencido"**: `isOverdueBR`/`daysOverdueBR` movidos para `overdue_util.js`, importados tanto pela catraca quanto pelo cron de cobrança (`server_functions.js`). Eles **nunca discordam** de quem está em atraso.
- A checagem usa `occurredAt` (instante do evento) como "agora", coerente com a presença que preserva o timestamp original.
- Só mensalidade prende: avulsa (loja), `private_lesson` e `subscription_overcharge` nunca bloqueiam.

### Resposta ao device (negação)

Novo outcome **`denied_overdue`**: audita idempotentemente (grava `accessEvents`), **sem presença, sem `increment(attendanceCount)`**, e **NÃO** entra no `anyGranted` → o giro não libera.
- **Intelbras** (síncrono): `{ message:'Financeiro pendente - procure a recepcao', code:'200', auth:'false' }`.
- **ZKTeco**: contrato exige `text/plain "OK"` (só ACK do POST); como não recebe comando de liberação, o giro não gira. Mensagem visível no display = extensão futura.
- **Control iD** (push): não envia a action de liberação; responde 200 simples → giro travado.

---

## Segurança

### Status dos fixes anteriores — SEM regressão

- **C1 (path-injection)** — preservado. `academyId`/`deviceId` validados pré-read; `safeDeviceId`/`safeEventId`/`studentId` sanitizados. O **novo `classId` real** é revalidado por `isSafeSegment` no resolver **e de novo** no núcleo antes de compor o doc-id; se inseguro, cai para sintético. `className` é só valor de campo (nunca segmento de path), logo inócuo.
- **H1 (idempotência)** — preservado. `tx.create(eventRef)` com `occurredAt` ORIGINAL continua a única barreira atômica; `denied_overdue` também grava o evento → re-entrega = `duplicate`. Nenhuma leitura de `classes`/`financials` dentro da transação.

### Achados do re-review adversarial

Nenhum **blocker**.

**MAJOR — M1**: em **lote misto** (ZKTeco/Control iD entregam vários eventos por POST), o veredito agregado `anyGranted = OR` pode mostrar "Presenca registrada" mesmo havendo um `denied_overdue` no lote, e a auditoria do log final fica imprecisa. **Não é falha de segurança**: cada `denied_overdue` individual já negou a presença daquele aluno; em catraca de giro físico cada pessoa gira em POST separado. Para vendors de lote a resposta é só ACK (não gateia giro). Para **Intelbras** (resposta síncrona gateia o giro) é material **só se houver >1 evento/POST** — corrigir com guard de 1 evento/POST antes de habilitar Intelbras síncrono.

**MINOR**:
- **m1** — `studentName` lido de `device.userNames` (campo não documentado; adapters só populam `userMap`) → quase sempre `null`. Degradação graciosa, não bug. Documentar ou resolver via doc `students/{id}`.
- **m2** — `checkOverdueGate` faz 1 read de `financials` por evento concedido dentro do loop, sem memoização (ao contrário do `classesCache`). Irrelevante p/ Intelbras (1 evento); desperdício em lote ZKTeco do mesmo aluno. Memoizar por `studentId`.
- **m3** — TOCTOU: o gate é lido pré-transação (por design, p/ não inflar read-set), então o aluno pode quitar entre o read e o `tx.create`. Impacto desprezível (segundos; fail-open favorece o aluno). Aceito.
- **m4** — adapter Intelbras trata `Status` AUSENTE como `granted=true` (único default fail-open entre os 3 adapters). **Field-confirm necessário** antes de produção: se negações chegam sem `Status`, inverter para `granted=false`.

---

## TODOs / decisões antes de produção

1. **Tolerância da janela** — confirmar com a academia se PRE=30 / POST=30 min é o ideal (override por `device.scheduleToleranceMinutes` já suportado).
2. **Granularidade da presença** — confirmar se 1 presença por aluno/turma/dia é a semântica desejada (vs. por entrada/giro).
3. **Quais financials prendem** — default só `monthly_tuition`; confirmar exclusão de avulsa/`private_lesson`/`subscription_overcharge` (override por `cfg.blockTypes`).
4. **Fail-open vs. inadimplente em erro de infra** — confirmar com a academia se erro de infraestrutura deve liberar até um inadimplente confirmado (comportamento atual = sim, por design fail-open).
5. **Deploy** — provisionar o índice composto `financials {studentId ASC, status ASC}` **antes** de ligar o gate; provisionar `academies/{id}.accessControl` e campos opcionais do device (`sport`, `category`, `scheduleToleranceMinutes`) quando a academia optar.
6. **Regras Firestore** — validar que `accessControl` no doc da academia e os novos campos do device estão cobertos/protegidos pelas `firestore.rules` (gravação só admin).
7. **M1 (Intelbras)** — aplicar guard de 1 evento/POST antes de habilitar Intelbras síncrono.
8. **m4 (field-confirm Intelbras)** — confirmar em campo se negações trazem `Status=0` antes de ligar concessão/gate em produção Intelbras.
9. **Testar com device real** — validar resolução de turma, fallback sintético, negação por inadimplência e formato de resposta por fabricante num dispositivo físico antes do rollout.

**Honestidade:** o código satisfaz os 5 requisitos pedidos e preserva os 4 invariantes (idempotência, fail-open do gate, `denied_overdue` sem presença/giro, fallback de turma), mas **não foi validado em hardware real** e tem 1 achado major (M1) + 1 field-confirm (m4) que devem ser resolvidos antes de habilitar o caminho Intelbras síncrono em produção. O gate de inadimplência só liga por opt-in da academia, então o deploy em si é seguro (no-op) até essa decisão.