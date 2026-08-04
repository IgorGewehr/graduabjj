# Integração com Catracas — por fabricante

> **Status geral (jul/2026):** a Cloud Function `ingestAccessEvent` está
> **DEPLOYADA em produção** (v2, us-central1, projeto arpjj-76350 — confirmável
> via `firebase functions:list`), com o modo Online da Control iD e o gate
> financeiro (`financial_gate.js`) prontos e a UI admin de config/enrollment no
> app. O que ainda NÃO aconteceu é o **piloto de campo** com hardware físico:
> cada seção abaixo marca explicitamente os TODOs de **FIELD-CONFIRM** — coisas
> que só a catraca real na mão pode validar (códigos de evento por firmware,
> formato exato de actions, unidades de tempo).

Fonte de verdade: `functions/access_control/` (`ingest.js` = núcleo,
`canonical.js` = contrato, `adapters/{controlid,zkteco,intelbras}.js` = wire
format por fabricante, `README.md` = a documentação mais detalhada que já
existe no repo — este guia resume e organiza por fabricante; para o payload
byte-a-byte, o README do módulo é ainda mais completo).

## Arquitetura (visão geral)

A catraca faz o **match biométrico embarcado** (sem PC no caminho crítico) e
faz um **POST autônomo** direto na Cloud Function `ingestAccessEvent`
(`us-central1-arpjj-76350.cloudfunctions.net/ingestAccessEvent`). O núcleo
(`ingest.js`) resolve `(academyId, deviceId)` pela query, autentica, faz
dispatch para o adapter do vendor (registry estático — nunca `require(input)`),
e grava presença **idempotente** no Firestore via Admin SDK. Para uso em
academias sem alcance direto/HTTPS confiável até a nuvem, existe o gateway
Windows irmão — ver [CATRACA_GATEWAY.md](CATRACA_GATEWAY.md).

Modelo de dados por device: `academies/{academyId}/devices/{deviceId}`, com
campos comuns a todos os fabricantes:

| Campo | Tipo | Descrição |
|---|---|---|
| `vendor` | `'controlid'\|'zkteco'\|'intelbras'` | seleciona o adapter |
| `secret` | string | segredo do device (HMAC ou token fraco). Sem ele ⇒ **401** |
| `enabled` | bool | `false` ⇒ **403** (sem revelar existência) |
| `userMap` | `{ [externalUserId]: studentId }` | de-para device→aluno; sem entrada ⇒ `no_match` |
| `userNames` | `{ [externalUserId]: string }` | opcional, nome no registro de presença |
| `ipAllowlist` | string[] | opcional; vazio = sem filtro |
| `name` | string | nome amigável (aparece em `verifiedByName`) |

## Segurança (o mesmo para os 3 fabricantes)

Ordem fail-closed no núcleo (`ingest.js`):

1. **Método** — só `POST` processa; `GET` = handshake ⇒ `200 OK`.
2. **Identidade** — `academyId`+`deviceId` na query; device existe e
   `enabled != false`.
3. **IP allowlist** opcional.
4. **Rate-limit** naive (60 eventos/10s por device) — **fail-open** em erro
   de infra (nunca prende um aluno por instabilidade do próprio rate-limiter).
5. **Auth do corpo** (timing-safe, espelha o padrão de
   `mercadoPagoMarketplaceWebhook`):
   - **FORTE (preferido):** `x-device-signature = HMAC-SHA256(secret, "${ts}.${rawBody}")`
     + `x-device-timestamp` (epoch ms), anti-replay de 5 min.
   - **FRACO (firmware stock):** token compartilhado no path/query (`?k=`
     Control iD / `pushcommkey`/`key` ZKTeco / `x-device-token`), comparado
     **timing-safe** contra `device.secret`.
   - Sem `secret` configurado ⇒ **401** sempre.

Nenhum dos 3 firmwares stock assina HMAC nativamente — na prática o token
fraco vai em claro na config do device. Use **sempre HTTPS**, **rotacione o
segredo** por device, e considere um proxy/edge que injete `x-device-signature`
quando o cenário permitir.

## Idempotência (estrita, igual para todos)

- Dedupe por `accessEvents/{deviceId}_{eventId}` via `.create()` em transação
  — reentrega do mesmo evento nunca duplica presença.
- `eventId` é **determinístico por adapter** (id sequencial nativo do device
  quando existe; hash de conteúdo como fallback).
- Segunda barreira: presença determinística por dia
  (`attendance/{studentId}_{classId}_{YYYYMMDD}` em wall-clock BR).
- `occurredAt` é **sempre** o timestamp ORIGINAL do device — `now()` nunca é
  usado para datar a presença (mesmo em retry/reentrega tardia).

## Gate financeiro (`financial_gate.js`)

Bloqueio da catraca por inadimplência. **DEFAULT OFF**: sem
`academies/{id}.accessControl.blockOnOverdue === true`, a catraca **nunca**
bloqueia por dinheiro. Config por academia:

```js
academies/{id}.accessControl = {
  blockOnOverdue: false,       // precisa ser true para o gate ligar
  graceDays: 0,                // tolerância em dias após o vencimento
  blockTypes: ['monthly_tuition'], // default: só mensalidade prende
}
```

- Reusa a definição **canônica** de "vencido" (`overdue_util.js`,
  `isOverdueBR`/`daysOverdueBR`) — a mesma usada pelo cron de cobrança
  (`scheduledOverdueCheck`), para que o **portão e a cobrança nunca
  discordem** de quem está em atraso.
- **FAIL-OPEN total**: qualquer erro/timeout/campo malformado ⇒ libera. Nunca
  prende um aluno por falha de infra.
- **Nunca bloqueia** cobrança avulsa (loja), `private_lesson` ou
  `subscription_overcharge` (dinheiro devido *ao* aluno) — só os tipos
  listados em `blockTypes` (default: só `monthly_tuition`) prendem.
- Quando bloqueado: outcome `denied_overdue` — **não grava presença**, giro
  **não libera**, mensagem `"Financeiro pendente - procure a recepcao"`.

## Resolução de turma (`class_resolver.js`)

O giro da catraca não carrega turma — `resolveActiveClass` espelha (verbatim)
a semântica client-side de `class_service.dart`
(`acceptsCheckinFrom`/`getCurrentClass`) para decidir qual turma ativa casa
com o aluno no horário do evento (tolerância padrão 30 min antes/depois,
override por `device.scheduleToleranceMinutes`). Sem turma casando, cai no
fallback **sintético**: `classId = catraca_{deviceId}`, `sport: 'bjj'`. O
desempate é **determinístico** (turma em andamento > horário mais próximo >
aluno matriculado > `classId` ascendente) porque o `classId` resolvido entra
no doc-id de idempotência — a mesma reentrega precisa sempre resolver a mesma
turma.

---

## Control iD (iDAccess / iDBlock / iDFace)

Adapter: `functions/access_control/adapters/controlid.js`.

### Modo Monitor (assíncrono, fire-and-forget)

Configurado via `set_configuration.fcgi` (sessão de `login.fcgi`):

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

O device anexa o sub-evento ao `path` configurado (`.../dao`,
`.../catra_event`, `.../device_is_alive`); o adapter roteia por `req.path`.

- **`POST {path}/dao`** — mudança no log de acesso (`access_logs`). Payload
  real:
  ```json
  { "object_changes": [
      { "object": "access_logs", "type": "inserted", "values": {
          "id": "519", "time": "1532977090", "event": "12",
          "device_id": "478435", "user_id": "0", "portal_id": "1",
          "identifier_id": "0", "identification_rule_id": "0" } } ],
    "device_id": 478435 }
  ```
  `eventId = ${device_id}_${values.id}`; `occurredAt = values.time × 1000`
  (UNIX **segundos**); direção via `device.portalDirection[portal_id]`;
  método via `device.methodByRule`; `granted` só para `event` ∈
  `GRANTED_EVENT_CODES`.
- **`POST {path}/catra_event`** — giro físico confirmado (iDBlock). Não traz
  `user_id` (correlaciona com o `/dao` anterior via `access_event_id`) — hoje
  é só auditoria (`granted: false`), nunca concede presença sozinho.
- **`POST {path}/device_is_alive`** — heartbeat ~30s. Não é evento (`[]`).

**Resposta:** `200 OK` simples (push fire-and-forget; o corpo é irrelevante).

### Modo Online/Pro (síncrono — reconhecimento + veredito no mesmo POST)

O device chama `.../new_user_identified.fcgi` (ou `new_card_identified.fcgi`)
e **fica bloqueado** esperando o veredito na resposta do mesmo POST — é o
modo que reproduz o comportamento de um QR de check-in, mas facial/cartão.
Corpo form-urlencoded (não JSON). O núcleo detecta este sub-path e responde:

```json
{ "result": { "event": 7, "user_id": 101, "actions": [{"action": "door", "parameters": "door=1"}] } }
```

`event: 7` = concedido (com `actions` — abrir porta/`catra`); `event: 6` =
negado (sem `actions`). Ação física configurável por device
(`controlidAction: 'door'|'catra'`, `catraSense`, `portalDoor`).

### Modelo de dados extra (Control iD)

| Campo | Descrição |
|---|---|
| `portalDirection` | `{ [portalId]: 'in'\|'out' }` — deriva direção do `portal_id` |
| `methodByRule` | `{ [ruleOrIdentifierId]: 'face'\|'finger'\|'card'\|'pin' }` |
| `controlidAction`/`catraSense`/`portalDoor` | ação física no modo Online |

### FIELD-CONFIRM pendente (Control iD)

- **`GRANTED_EVENT_CODES`** — só `event="12"` foi observado na doc pública.
  O set completo por firmware (iDAccess/iDBlock/iDFace) precisa de
  confirmação em campo antes de produção.
- Popular `portalDirection` e `methodByRule` por device real.
- Confirmar `values.time` sempre em UNIX segundos e `values.id` sempre
  presente.
- iDBlock: decidir conceder presença na autorização (`/dao`) vs. giro
  confirmado (`/catra_event`) — hoje é `/dao`.
- As chaves de configuração do modo **Online** variam por firmware/modelo e
  **não foram automatizadas** — confira/ajuste manualmente na interface web
  da catraca durante o piloto.

---

## ZKTeco (ADMS / "iclock")

Adapter: `functions/access_control/adapters/zkteco.js`.

### Config no device (menu Comm → ADMS/Cloud Server)

- `Server Address` = host da CF (ou de um rewrite/proxy).
- `Server Port` = 443, HTTP(S).
- **Realtime/Real-Time Push = ON**.
- `Communication Key` = `pushcommkey` (= `device.secret`).

O device manda `SN` (serial) automaticamente em toda chamada.

```
GET  /iclock/cdata?SN=<SN>&options=all&pushver=...           -> handshake
POST /iclock/cdata?SN=<SN>&table=rtlog&acad=<A>&vendor=zkteco -> CONTROLE DE ACESSO (nosso caso)
POST /iclock/cdata?SN=<SN>&table=ATTLOG                       -> ponto (heurístico, sem "negado")
```

Payload `rtlog` (uma transação por linha, **TAB-delimitado**, key=value):

```
time=2017-01-10 11:49:32	pin=1001	cardno=0	eventaddr=1	event=0	inoutstatus=0	verifytype=15	index=42
```

- `externalUserId = pin`.
- `eventId = ${deviceId}_${SN}_${index}` (fallback hash se `index` ausente).
- `occurredAt` = hora **local sem timezone** + `device.tzOffsetMinutes` ⇒ UTC.
  Sem `tzOffsetMinutes` configurado, o horário fica errado.
- `inoutstatus`: 0=in/1=out. `verifytype`: método (15=face, 1=digital, 4=cartão...).
- `granted` só para `event=0` (abertura normal por verificação OK).

> **Resposta obrigatória: `text/plain "OK"` (HTTP 200) — NUNCA JSON.** Se o
> device receber JSON, ele acha que a entrega falhou e **re-entrega o lote
> inteiro**. A idempotência do núcleo absorve isso sem duplicar presença, mas
> é desperdício evitável — o contrato de resposta por vendor em `ingest.js`
> já respeita isso.

### FIELD-CONFIRM pendente (ZKTeco)

- Validar o **Appendix 2** completo do vendor (códigos de evento concedido
  além de `0`; `verifytype`/método; `inoutstatus` — alguns firmwares invertem
  0/1 ou usam 2/3 para leitoras auxiliares).
- Setar `tzOffsetMinutes` por device real.
- Confirmar se o device-alvo posta `rtlog` (preferido) ou só `ATTLOG`.
- Confirmar path base: muitos modelos só aceitam `/iclock/` fixo — pode
  exigir um rewrite do Firebase Hosting ou proxy edge.

---

## Intelbras Bio-T (SS 55xx/35xx MF W, família CAP) — "Modo Online"

Adapter: `functions/access_control/adapters/intelbras.js`.

### Config no device

**GEREN. CONFIG. → Config. Plataforma → Online → Ativar**: `Endereço de IP`
(host da CF), `Porta` 443 (HTTPS), `Path do servidor`:

```
/ingestAccessEvent?acad=<ACADEMY>&deviceId=<DEVICE>&vendor=intelbras&k=<SECRET>
```

Opcional: Keep Alive (heartbeat GET ⇒ `OK`) e "Tempo limite de autenticação
remota" — **responder rápido** dentro desse timeout, senão o device cai para
decisão offline própria.

### Payload (multipart, por tentativa de acesso)

Corpo `multipart/*` com boundary `--myboundary`: uma parte `image/jpeg` (a
face capturada, descartada pelo adapter) + uma parte `text/plain` com o
evento, em JSON **ou** key=value pontilhado estilo Dahua:

```
Events[0].EventBaseInfo.Code=AccessControl
Events[0].UserID=101
Events[0].Type=Entry
Events[0].Status=1
Events[0].Method=15
Events[0].RecNo=123
Events[0].CreateTime=1700000000
```

- `externalUserId = UserID`. `eventId` por `RecNo` (fallback hash se ausente).
- `occurredAt` = `CreateTime` (epoch — assumido **segundos**, com heurística
  de guarda para 10 vs. 13 dígitos) ou `Time` (string).
- `Type` (`Entry`/`Exit`) ⇒ direção; `Method` ⇒ método (tabela parcial
  0–47, ver `METHOD_TABLE` no adapter).
- `Status`: `1` = sucesso, `0` = falhou, **ausente** = tratado como sucesso
  (alguns firmwares só postam concessões).

> **Resposta síncrona — o device BLOQUEIA esperando o veredito:**
> `200 { "message": "...", "code": "200", "auth": "true"|"false" }`.
> `auth` é **string**, não boolean. Responder dentro do "Tempo limite de
> autenticação remota" configurado no device.

### FIELD-CONFIRM pendente (Intelbras)

- Capturar com **sniffer** a shape exata da parte `text/plain` (JSON vs.
  key=value) no firmware alvo — o adapter tenta os dois defensivamente, mas
  não foi validado contra hardware real.
- Confirmar a **unidade de `CreateTime`** (segundos vs. milissegundos).
- Confirmar `Code`/`Method`/`Type`/`Status` reais e a estabilidade de `RecNo`
  entre reinícios do device (se não for estável, `eventId` cai no hash de
  conteúdo, que ainda dedupe reentregas mas perde estabilidade entre sessões).
- Validar a política fail-open/fail-closed do giro com a academia: hoje nega
  giro para não-mapeado (`no_match`), mas libera mesmo se a *gravação* falhar
  (fail-open de infra), reconciliando depois.

---

## TODOs comuns (antes de qualquer piloto em produção)

- **Apontar `device.secret` real** por device e ter um plano de rotação.
  Decidir HMAC forte (exige proxy/firmware que assine) vs. token fraco +
  HTTPS + IP allowlist.
- **Popular `device.userMap`** (e `userNames`) no enroll de cada aluno — sem
  isso todo acesso vira `no_match` e não grava presença.
- Confirmar a semântica de presença desejada: hoje é **1 presença por
  aluno/device/dia na entrada**. Se a academia quiser contar por
  aula/modalidade em vez de por dia, é um ajuste no doc-id de idempotência
  (ponto único de mudança, já isolado em `recordAccessEvent`).
