# Access Control — Ingestão de Catracas (Arquitetura C / push-cloud)

> **Status (2026-07):** **DEPLOYADA em produção** (`arpjj-76350`). A CF
> `ingestAccessEvent` está exportada em `functions/index.js` e **wired a
> catraca real** — piloto em modo Online da **Control iD Face**, com o app
> Windows de balcão (`docs/WINDOWS.md`) e as telas admin `AdminDevicesScreen`
> (`lib/screens/admin/devices_screen.dart`, CRUD de `devices/{deviceId}`) e
> `DeviceEnrollmentScreen` (`lib/screens/admin/device_enrollment_screen.dart`,
> UI para popular `userMap`/`userNames` — o enroll **não é mais manual via
> Firestore**). Também existe `lib/screens/kiosk/kiosk_screen.dart` (tela
> IDLE/RECONHECIDO/NEGADO) e `lib/core/access_control/turnstile_registry.dart`.
>
> Duas features aditivas já entraram além do MVP de ingestão: **resolução de
> turma real** (`class_resolver.js` — a presença cai na turma em andamento em
> vez de sempre num registro sintético `catraca_{deviceId}`) e **bloqueio por
> inadimplência** (`financial_gate.js` + `overdue_util.js` — opt-in por
> academia via `academies/{id}.accessControl.blockOnOverdue`, **default OFF**,
> fail-open). Ver seção 7 abaixo.
>
> O que **continua pendente**: os `TODO/FIELD-CONFIRM` marcados nos adapters
> (`GRANTED_EVENT_CODES` por firmware, unidade de `time`/`CreateTime`,
> `portalDirection`/`methodByRule` por device, `inoutstatus`/`verifytype`
> ZKTeco) ainda não foram validados contra hardware de **todos** os
> fabricantes — o piloto em produção é **Control iD**; ZKTeco e Intelbras têm
> os adapters prontos (`node --check` OK) mas aguardam confirmação de campo
> antes do primeiro deploy real nesses vendors. Ver
> `docs/arquivo/CATRACAS_INTEGRACAO_2026-06.md` e
> `docs/arquivo/CATRACAS_TURMA_BLOQUEIO_2026-06.md` para os relatórios de fase
> (histórico, inclusive achados de segurança C1/H1 já corrigidos no código
> atual).

---

## 1. Arquitetura

A catraca faz o **match biométrico/cartão EMBARCADO** (sem PC no caminho
crítico) e, ao conceder/negar acesso, faz um **POST autônomo** direto para uma
única Cloud Function HTTPS — `ingestAccessEvent`. A função valida, normaliza e
grava a presença **server-side, de forma idempotente**, no Firestore (Admin SDK,
server-authoritative).

```
  [Catraca biometria embarcada]  --HTTPS POST-->  ingestAccessEvent (CF v2)
                                                        |
                                  +---------------------+---------------------+
                                  | 1. resolve academyId + deviceId (query)   |
                                  | 2. carrega devices/{deviceId} (secret)    |
                                  | 3. segurança fail-closed (HMAC/token,     |
                                  |    IP allowlist, rate-limit, anti-replay) |
                                  | 4. dispatch -> adapter do vendor          |
                                  | 5. idempotência por eventId + presença    |
                                  |    determinística (preserva occurredAt)   |
                                  | 6. resposta no contrato do fabricante     |
                                  +-------------------------------------------+
```

O **PC não fica no caminho crítico**. Liberação/cadastro remotos (server→device)
são **pull** e exigem reachability reversa ao device (NAT/VPN) — fora do escopo
deste endpoint, que só faz **ingestão (device→cloud)**.

### Arquivos

| Arquivo | Papel |
|---|---|
| `ingest.js` | **Núcleo** + a CF `ingestAccessEvent`. Segurança, idempotência, gravação de presença, contrato de resposta. Único lugar com Firestore/HTTP. |
| `canonical.js` | Forma `AccessEvent` canônica + contrato `parse(req, device)` + helpers `normalizeDirection`/`normalizeMethod`. Módulo **puro**. |
| `class_resolver.js` | Resolve a **turma real** em andamento (grade/modalidade/categoria/matrícula/janela de tolerância) a partir do horário do evento — helper puro, sem I/O. Sem match, cai no fallback sintético `catraca_{deviceId}`. |
| `financial_gate.js` | **Bloqueio por inadimplência** opt-in por academia (`accessControl.blockOnOverdue`, default OFF). Fail-open total: qualquer erro/config ausente libera o giro. |
| `overdue_util.js` | Fonte única de "vencido" (`isOverdueBR`/`daysOverdueBR`), compartilhada entre a catraca e o cron de cobrança (`server_functions.js`) — os dois nunca discordam de quem está em atraso. |
| `adapters/controlid.js` | Wire-format Control iD (`/dao`, `/catra_event`, `/device_is_alive`). **Piloto em produção.** |
| `adapters/zkteco.js` | Wire-format ZKTeco ADMS/iclock (`rtlog`/`ATTLOG`, key=value/tab). Pronto, aguarda field-confirm antes do 1º deploy real. |
| `adapters/intelbras.js` | Wire-format Intelbras Bio-T "Modo Online" (multipart + key=value/JSON). Pronto, aguarda field-confirm antes do 1º deploy real. |

Cada adapter exporta `parse(req, device) -> AccessEvent[] | null` e **só** conhece
o wire format do seu fabricante. O núcleo nunca vê campos específicos de vendor.

---

## 2. Modelo de dados (`academies/{academyId}/devices/{deviceId}`)

| Campo | Tipo | Descrição |
|---|---|---|
| `vendor` | `'controlid'｜'zkteco'｜'intelbras'` | seleciona o adapter (registry estático). |
| `secret` | string | **segredo por device.** Base do HMAC-SHA256 **ou** do token compartilhado fraco. Nunca sai do server. Sem `secret` ⇒ **401** (fail-closed). |
| `enabled` | bool | `false` ⇒ **403** (sem revelar existência). |
| `userMap` | `{ [externalUserId]: studentId }` | de-para device→aluno, populado no enroll. Sem entrada ⇒ `no_match` (sem presença). |
| `userNames` | `{ [externalUserId]: string }` | opcional, nome p/ o registro de presença. |
| `ipAllowlist` | string[] | opcional. Vazio/ausente = sem filtro de IP. |
| `portalDirection` | `{ [portalId]: 'in'｜'out' }` | **Control iD** — deriva direção do `portal_id`. |
| `methodByRule` | `{ [ruleOrIdentifierId]: 'face'｜'finger'｜'card'｜'pin' }` | **Control iD** — deriva método. |
| `tzOffsetMinutes` | number | **ZKTeco** — `rtlog`/`ATTLOG` vêm em hora local SEM tz; offset p/ gravar UTC correto. |
| `name` | string | nome amigável da catraca (aparece em `verifiedByName`). |

Coleções escritas pelo núcleo:

- `academies/{academyId}/accessEvents/{deviceId}_{eventId}` — **ledger de
  idempotência + auditoria**. `.create()` em transação ⇒ re-entrega = no-op.
- `academies/{academyId}/attendance/{studentId}_catraca_{deviceId}_{YYYYMMDD}` —
  presença determinística por dia (espelha `attendance_service.dart` /
  `grantPrivateLessonAttendance`). Preserva `occurredAt` **ORIGINAL** (nunca `now()`).
- `academies/{academyId}/deviceRateLimits/{deviceId}` — janela de rate-limit naive.

---

## 3. Segurança (endpoint PÚBLICO — a catraca **não** faz Firebase Auth)

Ordem fail-closed no núcleo (`ingest.js`):

1. **Método** — só `POST` processa; `GET` = handshake/heartbeat ⇒ `200 OK`.
2. **Identidade** — `academyId` + `deviceId` na query; device existe e `enabled != false`.
3. **IP allowlist** opcional (`device.ipAllowlist`).
4. **Rate-limit** naive por device (60/10s; **fail-open** em erro de infra).
5. **Auth do corpo** (timing-safe, espelha `mercadoPagoMarketplaceWebhook`):
   - **FORTE (preferido):** header `x-device-signature = HMAC-SHA256(secret, "${ts}.${rawBody}")`
     + `x-device-timestamp` (epoch ms), **anti-replay 5 min**. Exige firmware/proxy
     que assine.
   - **FRACO (firmware stock):** token compartilhado no path/query
     (`?k=` Control iD / `pushcommkey`/`key` ZKTeco / `x-device-token`),
     comparado **timing-safe** contra `device.secret`. **Só** atrás de HTTPS.
   - Sem `secret` ⇒ **401**.

> Nenhum dos 3 firmwares stock assina HMAC nativamente. Na prática o token fraco
> vai **em claro** na config do device. Use **sempre HTTPS**, **rotacione o
> segredo**, e prefira um **proxy/edge** (Cloudflare/Run) que termine TLS e injete
> `x-device-signature` quando o cenário permitir.

---

## 4. Idempotência (estrita)

- Dedupe por `accessEvents/{deviceId}_{eventId}` via `.create()` dentro de
  transação. **Evento reentregue NÃO duplica presença.**
- `eventId` é estável e determinístico **por adapter** (id sequencial nativo do
  device quando existe; senão hash do conteúdo).
- Presença determinística por dia (`studentId_catraca_{deviceId}_YYYYMMDD`) é uma
  segunda barreira (`duplicate_day`).
- `occurredAt` é o **timestamp ORIGINAL do device** — `now()` nunca é usado para
  datar presença.

---

## 5. URL da função

```
https://us-central1-arpjj-76350.cloudfunctions.net/ingestAccessEvent
```

**Query obrigatória** (o device é single-tenant; a CF é multi-tenant):

| Param | Origem |
|---|---|
| `acad` (ou `academyId`) | id da academia. |
| `deviceId` (ou `SN`/`sn`) | id do device = doc em `devices/{deviceId}`. ZKTeco manda `SN` automaticamente. |
| `vendor` | opcional — o vendor canônico vem de `device.vendor`; a query é só fallback. |
| `k` / `pushcommkey` / `key` | token fraco quando não há HMAC (= `device.secret`). |

> Se o firmware exigir path base fixo (ex.: ZKTeco `/iclock/`), use um **rewrite
> do Firebase Hosting** ou um **proxy edge** mapeando para a CF e injetando os
> headers/query.

---

## 6. Apontar cada catraca para a CF

### 6.1 Control iD (iDAccess / iDBlock / iDFace) — módulo "Monitor"

O device faz `POST hostname:port/{path}/{evento}` para `/dao` (acesso),
`/catra_event` (giro confirmado, iDBlock) e `/device_is_alive` (heartbeat).

```http
POST /set_configuration.fcgi?session=<session>
Content-Type: application/json

{
  "monitor": {
    "request_timeout": "5000",
    "hostname": "us-central1-arpjj-76350.cloudfunctions.net",
    "port": "443",
    "path": "ingestAccessEvent?acad=<ACADEMY>&deviceId=<DEVICE>&vendor=controlid&k=<SECRET>"
  }
}
```

> O device anexa o sub-evento ao `path`, gerando
> `.../ingestAccessEvent/dao?...`. O adapter roteia por `req.path`
> (`/dao`, `/catra_event`, `/device_is_alive`). `session` vem de `login.fcgi`
> (desabilitar `Expect: 100-continue`).

Payload `/dao` (novo `access_logs`):

```json
{
  "object_changes": [
    { "object": "access_logs", "type": "inserted",
      "values": { "id": "519", "time": "1532977090", "event": "12",
                  "device_id": "478435", "user_id": "0", "portal_id": "1",
                  "identifier_id": "0", "identification_rule_id": "0",
                  "card_value": "0", "log_type_id": "-1" } }
  ],
  "device_id": 478435
}
```

- `eventId = ${device_id}_${values.id}` (id sequencial estável).
- `occurredAt = Number(values.time)*1000` (UNIX **segundos**).
- direção via `device.portalDirection[portal_id]`; método via `device.methodByRule`.
- `granted` só p/ `event` ∈ `GRANTED_EVENT_CODES` (**field-confirm**).

**Resposta:** `200 OK` (push fire-and-forget).

### 6.2 ZKTeco (ADMS / "iclock") — Server/Cloud Mode

No menu **Comm → ADMS/Cloud Server**: `Server Address` = host da CF (ou rewrite),
`Server Port` (443), HTTP(S), **Realtime/Real-Time Push = ON**,
`Communication Key` = `pushcommkey` (= `device.secret`). O device manda `SN`
automaticamente.

```
GET  /iclock/cdata?SN=<SN>&options=all&pushver=...           -> handshake
POST /iclock/cdata?SN=<SN>&table=rtlog&acad=<A>&vendor=zkteco -> CONTROLE DE ACESSO
POST /iclock/cdata?SN=<SN>&table=ATTLOG                       -> ponto (heurístico)
GET  /iclock/getrequest?SN=<SN>                              -> poll de comandos (não usado aqui)
```

Payload `rtlog` (uma transação por linha, TAB-delimitado, key=value):

```
time=2017-01-10 11:49:32	pin=1001	cardno=0	eventaddr=1	event=0	inoutstatus=0	verifytype=15	index=42
```

- `externalUserId = pin`; `eventId = ${deviceId}_${SN}_${index}` (fallback hash).
- `occurredAt` = hora **local** + `device.tzOffsetMinutes` ⇒ UTC.
- `inoutstatus` 0=in/1=out; `verifytype` ⇒ método (15=face…).
- `granted` só p/ `event=0` (**field-confirm Appendix 2**).

> **Resposta:** `text/plain "OK"` (HTTP 200). **Nunca JSON** — JSON faz o device
> achar que falhou e **re-entregar o lote** (a idempotência cobre, mas evite).

### 6.3 Intelbras Bio-T (SS 55xx/35xx MF W) — "Modo Online"

No device: **GEREN. CONFIG. → Config. Plataforma → Online → Ativar**, preencher
`Endereço de IP` (host da CF), `Porta` (443, HTTPS), `Path do servidor`:

```
/ingestAccessEvent?acad=<ACADEMY>&deviceId=<DEVICE>&vendor=intelbras&k=<SECRET>
```

Opcional: Keep Alive (heartbeat GET ⇒ responde `OK`) e "Tempo limite de
autenticação remota". Para **cada** tentativa de acesso o device POSTa um corpo
**multipart** (`--myboundary`) com uma parte `image/jpeg` (face) + uma
`text/plain` com o evento, em JSON **ou** key=value pontilhado:

```
--myboundary
Content-Type: text/plain

Events[0].EventBaseInfo.Code=AccessControl
Events[0].UserID=101
Events[0].Type=Entry
Events[0].Status=1
Events[0].Method=15
Events[0].CardNo=09DDAABB
Events[0].RecNo=123
Events[0].CreateTime=1700000000
--myboundary
Content-Type: image/jpeg

<jpeg bytes>
--myboundary
```

- `externalUserId = UserID`; `eventId` por `RecNo` (fallback hash).
- `occurredAt` = `CreateTime/UTC` (epoch **segundos** — confirmar unidade) ou `Time`.
- `Type` Entry/Exit ⇒ direção; `Method` ⇒ método.

> **Resposta (síncrona — o device bloqueia esperando veredito):**
> `200 JSON { "message": "...", "code": "200", "auth": "true"|"false" }`.
> `auth` é **STRING**. Responder **rápido** (dentro do "Tempo limite de
> autenticação remota") senão o device cai para decisão offline.

---

## 7. Check-in na turma real + bloqueio por inadimplência

Duas features aditivas por cima da ingestão pura, adicionadas em jul/2026
(`class_resolver.js`, `financial_gate.js`, `overdue_util.js`):

**Turma real:** o handler lê as turmas ativas da academia (`isActive == true`)
uma vez por POST e o resolver (`resolveActiveClass`, puro, sem I/O) casa o
evento por modalidade (`device.sport`), categoria (`device.category`),
matrícula (`acceptsCheckinFrom`, mesma regra do check-in por QR) e janela de
tolerância (PRE/POST 30min, override por `device.scheduleToleranceMinutes`),
com desempate determinístico (aula em andamento > slot mais recente > aluno
matriculado > `classId` ascendente — a re-entrega do mesmo evento sempre
resolve a mesma turma). Sem match, cai no fallback sintético de sempre
(`classId = catraca_{deviceId}`). O doc-id de presença passou de
`studentId_{device}_YYYYMMDD` para `studentId_{classId}_YYYYMMDD` (1
presença/aluno/turma/dia). `classId` real é revalidado por `isSafeSegment`
antes de compor o doc-id (defesa contra path injection, achado C1 abaixo).

**Bloqueio por inadimplência:** opt-in por academia via
`academies/{id}.accessControl = { blockOnOverdue: false, graceDays: 0,
blockTypes: ['monthly_tuition'] }` — **default OFF** (deploy é no-op até a
academia optar). Quando ligado, `checkOverdueGate` consulta `financials` do
aluno e nega o giro (`denied_overdue`, sem presença, sem
`increment(attendanceCount)`) se houver cobrança vencida do tipo configurado
(default: só mensalidade — avulsa/`private_lesson`/`subscription_overcharge`
nunca prendem). **Fail-open total**: qualquer erro de query/config libera.
`isOverdueBR`/`daysOverdueBR` são compartilhados com o cron de cobrança
(`server_functions.js`) — portão e cobrança nunca discordam de quem está em
atraso. Índice composto `financials {studentId ASC, status ASC}` já provisionado
em `firestore.indexes.json`.

Achado MAJOR conhecido (não-bloqueante): em lote misto (ZKTeco/Control iD
entregam vários eventos por POST) o veredito agregado pode mascarar um
`denied_overdue` individual na resposta consolidada — sem risco de segurança
(cada evento já foi negado individualmente), mas relevante se/quando o
Intelbras síncrono (que gateia o giro pela resposta) for habilitado com >1
evento por POST — precisa de guard de 1-evento/POST antes disso.

---

## 8. TODOs de validação em campo (antes do 1º deploy real de ZKTeco/Intelbras)

Comuns:

- **Apontar `device.secret` real** por device (e rotacionar). Decidir HMAC-forte
  (proxy/firmware) vs token fraco + HTTPS + IP allowlist.
- ~~Popular `device.userMap` (e `userNames`) no enroll~~ — **resolvido**: UI
  dedicada em `DeviceEnrollmentScreen`
  (`lib/screens/admin/device_enrollment_screen.dart`). Sem entrada mapeada o
  acesso ainda vira `no_match` — é operacional (a academia precisa cadastrar
  cada aluno por device), não uma lacuna de código.
- ~~Semântica de presença 1/dia vs por turma~~ — **resolvido**: ver seção 7
  (check-in na turma real, com fallback sintético).

Control iD (piloto em produção — validar com o hardware real da academia):

- **`GRANTED_EVENT_CODES`**: só `event="12"` foi observado na doc pública.
  Capturar o set real de "acesso concedido" por firmware (iDAccess/iDBlock/iDFace).
- Popular `portalDirection` e `methodByRule` por device.
- Confirmar `values.time` em UNIX **segundos**; `values.id` sempre presente.
- iDBlock: decidir conceder presença na **autorização** (`/dao`) vs **giro
  confirmado** (`/catra_event`) — correlação fica no núcleo/reconciliação.

ZKTeco:

- Validar **Appendix 2** (`event` concedido), `verifytype` (método) e
  `inoutstatus` (alguns firmwares invertem 0/1 ou usam 2/3).
- Setar `tzOffsetMinutes`. Confirmar se o device posta `rtlog` (preferido) vs só
  `ATTLOG`.
- Confirmar path base: muitos modelos só aceitam `/iclock/` fixo ⇒ rewrite/proxy.

Intelbras:

- Capturar com **sniffer** a shape exata da parte `text/plain` (JSON vs key=value)
  e a **unidade de `CreateTime`** (s vs ms).
- Confirmar `Code`/`Method`/`Type`/`Status` e estabilidade de `RecNo`.
- Validar política **fail-open/fail-closed** do giro com a academia (hoje: nega
  giro p/ não-mapeado; libera mesmo se a gravação falhar, reconciliando depois).
