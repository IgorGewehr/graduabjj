I'll write the report directly. The task is to synthesize the provided research data into a structured PT-BR Markdown report. All the data needed is in the prompt.

# Relatório: Scaffold de Integração de Catracas (Controle de Acesso → Presença)

> **Status honesto:** este documento descreve um *scaffold* greenfield. O código compila (`node --check` OK nos 6 arquivos), a Cloud Function está **exportada** mas **não deployada** nem ligada a nenhum device real. Os adapters foram *smoke-tested* contra os payloads de exemplo da pesquisa, mas **nenhum payload foi capturado de um equipamento físico**. Tudo marcado como `FIELD-CONFIRM` / `ASSUMPTION` exige validação em campo antes de produção.

---

## 1. Resumo

O objetivo é registrar **presença do aluno automaticamente quando ele passa na catraca/leitora facial da academia**, sem PC no caminho crítico e sem depender de IP público/port-forward na academia.

A solução adotada é a **Arquitetura C (push para a nuvem)**: o próprio equipamento (que faz o match biométrico/cartão **localmente, embarcado**) abre uma conexão de saída pela internet e faz `POST` dos eventos de acesso para uma única Cloud Function pública (`ingestAccessEvent`). A função normaliza o evento de qualquer fabricante para um formato canônico, resolve o aluno e grava a presença de forma idempotente.

Três fabricantes foram pesquisados e cada um ganhou um **adapter** (tradutor de wire-format → evento canônico):

| Fabricante | Modo push | Formato do payload | Resposta esperada | Adapter |
|---|---|---|---|---|
| **Control iD** (iDAccess/iDBlock/iDFace) | Monitor / standalone push | JSON | (fire-and-forget) | `adapters/controlid.js` |
| **ZKTeco** | ADMS / protocolo "iclock" | key=value / TAB | `text/plain` `"OK"` obrigatório | `adapters/zkteco.js` |
| **Intelbras** (linha Bio-T) | Modo Online | multipart (`--myboundary`) | JSON síncrono `{message,code,auth}` | `adapters/intelbras.js` |

Estado: **núcleo + 3 adapters + wiring aditivo** implementados; revisão de segurança feita (achados abaixo); **pendente field-confirm + deploy**.

---

## 2. Arquitetura (push-cloud)

```
┌─────────────────────┐         POST (saída, HTTPS)        ┌──────────────────────────┐
│  Catraca / Leitora  │ ─────────────────────────────────▶ │  Cloud Function pública  │
│  (match embarcado)  │                                     │   ingestAccessEvent      │
│  Control iD/ZKTeco/ │ ◀──── resposta (texto/JSON) ─────── │  (us-central1)           │
│  Intelbras          │                                     └────────────┬─────────────┘
└─────────────────────┘                                                  │
   • decide localmente                                         1. roteia por vendor
   • notifica a nuvem                                          2. verifyDeviceAuth (fail-closed)
   • NÃO precisa IP público                                    3. adapter.parse() → AccessEvent[]
                                                               4. resolve studentId (device.userMap)
                                                               5. grava idempotente
                                                                          │
                                                                          ▼
                                                       ┌──────────────────────────────┐
                                                       │ Firestore                    │
                                                       │  accessEvents/{dev}_{evId}   │ ← ledger dedupe
                                                       │  attendance/{aluno_turma_dia}│ ← presença
                                                       │  devices/{deviceId}          │ ← secret/userMap
                                                       └──────────────────────────────┘
```

**Por que push e não pull:** o pull (Control iD `load_objects.fcgi`, ZKTeco Pull SDK TCP/4370, Intelbras `eventManager.cgi?action=attach`) exigiria que a nuvem **alcançasse** o device — inviável atrás do NAT/firewall da academia sem VPN/túnel. No push, o device inicia a conexão de saída; só precisa de internet.

**Princípios do núcleo:**
- **Adapter isola o fabricante.** Cada `parse(req, device)` retorna `AccessEvent[] | null`. O núcleo nunca vê campos específicos de fabricante. Registry estático e congelado (`ADAPTER_LOADERS`), indexado por `vendor` — nunca `require(input)`.
- **Idempotência por `accessEvents/{deviceId}_{eventId}`** com `tx.get` + `tx.create` em transação (exactly-once). Reentrega do mesmo acesso vira no-op.
- **Timestamp original preservado** (`occurredAt`), nunca `now()`. O id determinístico de presença `studentId_classId_YYYYMMDD` é uma segunda camada anti-duplicidade.
- **De-para `deviceUserId → studentId`** vive em `device.userMap` (server-authoritative), populado no enroll.

**Modelo de dados `devices/{deviceId}` (server-side, lido via Admin SDK):**
- `secret` (HMAC forte) / `pushCommKey` / token (caminho fraco)
- `userMap` (`deviceUserId → studentId`) — fonte da verdade no caminho crítico
- `portalDirection` (Control iD: `portal_id → in/out`), `methodByRule` (Control iD: regra/identifier → face/finger/card/pin)
- `tzOffsetMinutes` (ZKTeco: hora local sem timezone)
- `ipAllowlist`, `disabled`

**URL do endpoint:**
```
POST https://us-central1-arpjj-76350.cloudfunctions.net/ingestAccessEvent
       ?acad=<academyId>&deviceId=<id>&vendor=<controlid|zkteco|intelbras>&k=<secret>
```

---

## 3. Por fabricante

### 3.1 Control iD (iDAccess / iDBlock / iDFace)

**Push:** modo **Monitor** / standalone. O device faz match local e, ao detectar mudança no log de acesso, faz `POST` autônomo para `hostname:port/{path}/{evento}`. É *fire-and-forget* — o device tem buffer e retenta, mas **dedupe/ordem são responsabilidade do receptor**.

**Sub-paths relevantes** (o device anexa o evento ao `path` base):
- `POST {path}/dao` — mudanças no log de acesso (**evento de presença**: `object="access_logs"`, `type="inserted"`).
- `POST {path}/catra_event` — giro confirmado da catraca (iDBlock): `TURN LEFT/RIGHT`. Confirma passagem física vs só autorização.
- `POST {path}/device_is_alive` — heartbeat (~30s).
- Outros: `/door`, `/secbox`, `/access_photo`, `/template`, `/card`, `/operation_mode`.

**Payload (JSON) — acesso real em `/dao`:**
```json
{
  "object_changes": [{
    "object": "access_logs", "type": "inserted",
    "values": { "id": "519", "time": "1532977090", "event": "12",
                "device_id": "478435", "user_id": "0", "portal_id": "1",
                "card_value": "0", "identification_rule_id": "0" }
  }],
  "device_id": 478435
}
```

**Campos-chave:** `user_id` (→ studentId; `"0"` = não identificado/negado, ignorar), `time` (UNIX **segundos**, original), `event` (código concedido/negado — **FIELD-CONFIRM**, só `"12"` observado), `portal_id` (direção entrada/saída — depende da config física), `id` (sequencial no device → `device_id + id` = eventId de idempotência).

**Adapter `controlid.js`:** roteia por sub-path com fallback por shape. `/dao` → itera `object_changes[]` mantendo só `access_logs`+`inserted`; `/catra_event` → evento *audit-only* (`granted:false`, correlaciona via `access_event_id`); `/device_is_alive` → `[]`. Saídas verificadas: granted `/dao` → `eventId 478435_519`, `occurredAt 2018-07-30T18:58:10Z`; `user_id "0"` → `granted:false`.

**Como configurar (apontar para nós):** PULL via `set_configuration.fcgi` (exige session de `login.fcgi`):
```
POST /set_configuration.fcgi?session=<session>
{ "monitor": { "request_timeout": "5000",
               "hostname": "us-central1-arpjj-76350.cloudfunctions.net",
               "port": "443", "path": "ingestAccessEvent" } }
```
O device passará a postar em `.../ingestAccessEvent/dao`, `/catra_event`, `/device_is_alive`.

**Caveats:** firmware antigo pode só aceitar HTTP/IP (sem TLS/domínio/443) → precisaria de proxy edge na academia; `login.fcgi` exige desabilitar `Expect: 100-continue`; liberação remota/enroll são **pull** (precisam alcançar o device — inviável atrás de NAT sem túnel). Enroll iDFace: `create_objects.fcgi` + `user_set_image.fcgi` (JPEG cru `<2MB`, `octet-stream`); o de-para `device_user_id ↔ studentId` é definido aqui.

### 3.2 ZKTeco (ADMS / "iclock")

**Push:** protocolo **iclock/ADMS**. O device inicia a conexão de saída (sem IP público), faz handshake GET, posta eventos e faz polling de comandos. Texto cru, **não-JSON, não-REST, legado**.

**Paths fixos** (a maioria dos modelos **não** permite path base custom):
- `GET /iclock/cdata?SN=<sn>&options=all` → handshake/registro.
- `POST /iclock/cdata?SN=<sn>&table=rtlog` → **controle de acesso (nosso caso)**, key=value.
- `POST /iclock/cdata?SN=<sn>&table=ATTLOG` → ponto (TAB posicional).
- `POST /iclock/cdata?SN=<sn>&table=OPERLOG` → templates biométricos.
- `GET /iclock/getrequest?SN=<sn>` → device puxa comandos (poll ~10-30s).
- `POST /iclock/devicecmd?SN=<sn>` → ACK de comando.

**Payload (key=value, TAB) — `rtlog`:**
```
time=2017-01-10 11:49:32	pin=1001	cardno=0	eventaddr=1	event=0	inoutstatus=0	verifytype=15	index=42
```
**Resposta:** corpo `text/plain` `"OK"` com HTTP 200. **Não devolver JSON** — senão o device acha que falhou e **re-entrega o lote**.

**Campos-chave:** `time` (hora **local sem timezone** → precisa `tzOffsetMinutes` para UTC correto), `pin` (→ studentId via `pinMap`), `event` (`0`=concedido OK; `>0`=negado/coação/alarme — **FIELD-CONFIRM** Appendix 2), `inoutstatus` (`0`=in/`1`=out), `verifytype` (`0`=senha,`1`=digital,`4`=cartão,`15`=face — varia por firmware), `index` (contador monotônico → eventId).

**Adapter `zkteco.js`:** trata `rtlog` e `ATTLOG`, uma linha = um `AccessEvent`. `eventId = ${deviceId}_${sn}_${index}` (fallback sha256 quando ausente). Aplica `tzOffsetMinutes` (11:49 BRT → 14:49 UTC, verificado). Retorna `null` para tráfego não-acesso (handshake, getrequest, devicecmd, OPERLOG) — núcleo só ACKa.

**Como configurar:** menu do device (Comm/ADMS/Cloud Server): ativar "Domain Name/Server Mode"/"ADMS", Server Address = host, Port (80/443), HTTP(S), habilitar "Realtime", e Communication Key (= `pushcommkey`). Reiniciar.

**Caveats:** path base `/iclock/` fixo → precisa **Express app com rotas `/iclock/*`** ou rewrite no Firebase Hosting/proxy edge; abrir giro tem **latência = intervalo de poll** (não há push server→device garantido); handlers de `getrequest` (drenar comandos) e `devicecmd` (ACK) estão como **TODO**. Enroll do template é melhor presencial na catraca (sobe via `table=OPERLOG`); `pinMap` é a fonte da verdade.

### 3.3 Intelbras (linha Bio-T)

**Push:** **Modo Online**. O device abre conexão de saída e posta **cada tentativa de acesso**, **bloqueando até receber a resposta de autorização** (giro/nega) do servidor — fluxo síncrono. (Não confundir com `eventManager.cgi?action=attach`, que é pull/long-poll.)

**Endpoint:** um único "Path do servidor" configurado no device (ex.: `/ingestAccessEvent/<deviceId>/<token>`) + opcional keep-alive (GET periódico, responder `OK`).

**Payload — MULTIPART (`--myboundary`, não JSON puro):** tipicamente 2 partes (uma `image/jpeg` da face ~200k + uma `text/plain` com o evento). A parte de evento vem como **JSON OU key=value pontilhado** conforme firmware:
```
--myboundary
Content-Type: text/plain

Events[0].EventBaseInfo.Code=AccessControl
Events[0].Type=Entry
Events[0].Status=1
Events[0].Method=15
Events[0].UserID=101
Events[0].RecNo=123
--myboundary
Content-Type: image/jpeg

<jpeg bytes>
--myboundary
```
**Resposta esperada (verbatim do servidor de exemplo oficial):**
```json
{"message":"Seja Bem vindo!","code":"200","auth":"true"}
```
> `auth` é **string** `'true'`/`'false'` (não boolean); a chave de status é `code` (`"200"`). `auth:"true"` libera o giro, `"false"` nega.

**Campos-chave:** `UserID` (→ studentId), `Type` (`Entry`/`Exit` = direção), `Status` (`1`=sucesso), `Method` (enum 0-47: `15`=face local, `1`=cartão, `6`=digital...), `RecNo` (id do registro → eventId), `CreateTime`/`UTC` (epoch **segundos** — **FIELD-CONFIRM** s vs ms).

**Adapter `intelbras.js`:** parseia boundary, extrai a parte text/plain, aceita JSON e key=value. 6-case smoke test OK.

**Como configurar:** no device `GEREN. CONFIG. > Config. Plataforma > Online > Ativar`; preencher Endereço de IP (host), Porta (443), Path do servidor, habilitar HTTPS, opcional Keep Alive + "Tempo limite de autenticação remota". Enroll via HTTP API V3.35 (Digest Auth, server→device): `userManager.cgi?action=addUser`, `FaceInfoManager.cgi?action=add`, `recordUpdater.cgi` (cartão).

**Caveats:** responder **sempre HTTP 200 com veredito rápido** (orçamento ~4s) — se estourar o "Tempo limite de autenticação remota", o device **cai para decisão offline** e ignora o remoto; shape exata (JSON vs key=value) e unidade de tempo **devem ser capturadas com sniffer**; corpo multipart inclui imagem da face (cap de tamanho necessário); o arquivo está com `require/export` **comentado no index.js** até field-confirm; compatibilidade depende de firmware mínimo (ex.: SS 5531 MF W ≥ 20231018) — modelos só-cartão antigos podem exigir controladora/Wiegand.

---

## 4. Segurança (HMAC / idempotência + achados)

**Camadas de auth (fail-closed, em `verifyDeviceAuth`):** nenhum dos firmwares nativos assina HMAC do corpo — a auth nativa é fraca (token compartilhado / `pushcommkey` na query). Por isso a segurança é imposta **no nosso endpoint**:
1. **Forte (preferido):** header `x-device-signature: HMAC-SHA256(device.secret, ts.rawBody)` + `x-device-timestamp` (anti-replay janela ~5min), comparado com `crypto.timingSafeEqual` — mesmo padrão do `mercadoPagoMarketplaceWebhook`. Exige proxy/firmware que assine.
2. **Fraco (nativo):** token no path/query comparado timing-safe contra `device.secret`/`pushCommKey`, **só aceitável atrás de HTTPS + IP allowlist**.
- **Fail-closed:** sem secret/device desconhecido/desabilitado/credencial forjada/timestamp velho → 401/403 sem revelar existência. Secret nunca sai do server.
- **Idempotência:** `tx.get` + `tx.create` em transação Firestore (serializável) = exactly-once; reentrega → no-op; `occurredAt` preservado via `tsOriginal`, nunca `now()` no núcleo.
- **Registry de adapters:** mapa congelado, `getAdapter` guarda com `hasOwnProperty` (bloqueia `__proto__`/`constructor`); `vendor` só **indexa**, nunca `require(input)`.

### Achados da revisão de segurança

**🔴 CRÍTICO**

- **C1 — Path injection via `deviceId`/`eventId` não sanitizados em paths do Firestore.** `deviceId` vem de query controlada pelo atacante e é interpolado cru em `academies/{academyId}/devices/{deviceId}`, no doc-id do ledger `accessEvents/{deviceId}_{eventId}`, em `classId=catraca_{deviceId}` e no `dayId`. O `doc()` do Firestore **não trata `/` nem `..` como no-op**: um `deviceId` `a/b/c` produz um path literal de 6 segmentos (documento diferente), e `eventId` é montado de campos do corpo (`zkteco` `SN`/`index`, `controlid` `values.id`, `intelbras` `RecNo`) igualmente sem sanitização. Pior: a **leitura do device em `ingest.js:371` acontece ANTES do `verifyDeviceAuth` (388)** → a injeção de `/` em `deviceId` é explorável **sem o secret**. Pós-auth, permite redirecionar escritas de idempotência/presença para paths arbitrários, derrotando o dedupe.
  **Fix:** validar todo identificador que vira segmento de path contra `^[A-Za-z0-9_-]{1,128}$` e rejeitar (400/403) — `academyId`/`deviceId` **antes** da leitura (361-371), `eventId` antes de compor o doc-id (218-219), e sanitização defensiva nos adapters (`zkteco:173`, `controlid:194`, `intelbras:377`).

**🟠 ALTO**

- **H1 — Idempotência quebra para eventos Intelbras sem `RecNo` (usa `now()` na base do eventId).** `intelbras.js:371` `parseOccurredAt` retorna `new Date()` como último recurso (o próprio comentário admite violar "nunca now()"). Esse `occurredAt` alimenta `buildEventId`, e **sem `RecNo`** o hash inclui `occurredAt.getTime()` → cada reentrega gera **eventId diferente** → `create()` nunca colide → **presença duplicada**. Também corrompe o timestamp original gravado.
  **Fix:** `parseOccurredAt` deve retornar `null` (como zkteco/controlid, que são descartados/auditados), e remover `occurredAt.getTime()` da base do hash sem-RecNo (id puramente content-derived, estável na reentrega).
- **H2 — Shaping de presença / injeção em `dayId`** — consequência de C1 no caminho de escrita (`dayId = studentId_classId_ymd` com `classId` contendo `deviceId` não-sanitizado). Fechado ao corrigir C1.

**🟡 MÉDIO**

- **M1 — Leitura do device-doc antes da auth** (`ingest.js:371` < `388`): oracle de enumeração `(academyId, deviceId)` e superfície de DoS, uma leitura Firestore por request não-autenticada e parametrizada. Inerente ao HMAC por-device (precisa ler o secret), mas mitigar com a validação de charset de C1 *antes* da leitura + throttle barato pré-auth.
- **M2 — Rate-limit é fail-open e roda depois da leitura do device** (`catch { return true }`): é decisão de disponibilidade (não prender aluno no portão), mas **não é controle de segurança** — não confiar nele para mitigar C1/M1.

**🔵 BAIXO / NOTAS**

- **L1** — regex de detecção multipart no `intelbras.js:211` pode classificar erradamente JSON contendo `--`; preferir o boundary do `Content-Type`. Robustez, não falha de segurança (HMAC é sobre o `rawBody` exato).
- **L2** — anti-replay (timestamp/nonce) só existe no caminho HMAC forte; o token fraco depende só do ledger de idempotência — **aceitável apenas se C1+H1 corrigidos**. Token fraco é bearer estático na URL (logado por proxies/CDN) — documentar tradeoff.
- **L3 — Positivos verificados (sem ação):** auth fail-closed para device ausente/desabilitado/sem-secret/credencial forjada/timestamp velho; idempotência exactly-once correta com `occurredAt` preservado (exceto o caso H1); registry de adapters seguro contra `__proto__`/`require(input)`.

**Ordem de correção:** C1 → H1 → M1/M2.

---

## 5. TODOs antes de produção

**Validação de payload em campo (sniffer no equipamento real):**
- **Control iD:** confirmar `GRANTED_EVENT_CODES` (só `event="12"` observado na doc) por modelo (iDAccess/iDBlock/iDFace); mapear `portalDirection` (portal_id → in/out) e `methodByRule` por device; confirmar `time` sempre em segundos.
- **ZKTeco:** validar `GRANTED_EVENT_CODES` (Appendix 2), `VERIFY_TYPE`, `IN_OUT` (firmwares invertem); setar `tzOffsetMinutes` por device; confirmar se o device posta `rtlog` (preferido) vs só `ATTLOG`.
- **Intelbras:** capturar a shape exata da parte text/plain (JSON vs key=value), unidade de `CreateTime` (s vs ms), estabilidade do `RecNo`, default de direção. `require/export` ainda comentado no `index.js`.

**Decisão de turma / check-in sintético:**
- Definir semântica de presença: **1/dia** vs **por aula/modalidade**. Como o evento da catraca não traz `classId`, hoje usa-se `classId = catraca_{deviceId}` (presença sintética). Decidir com a academia como mapear catraca → turma/horário (janela de aula?) e se presença é concedida na **autorização** (`/dao`, iDFace sem catraca) ou só na **passagem confirmada** (`/catra_event` TURN, iDBlock).
- Política **fail-open vs fail-closed** do giro (Intelbras síncrono): liberar mesmo se a gravação de presença falhar (reconciliação posterior) vs negar — **confirmar com a academia**.

**Enroll:**
- Popular `device.userMap`/`pinMap` (`deviceUserId → studentId`) e `device.secret` por device no enroll, **antes** de produção. Sem o de-para, a presença não resolve o aluno. Definir o fluxo operacional de enroll (presencial na catraca vs server→device, este último limitado por reachability atrás de NAT).

**LGPD / privacidade:**
- O payload da catraca contém **biometria facial** (Intelbras envia JPEG da face ~200k em cada evento) e identificadores pessoais. Definir: **não persistir** a imagem facial no caminho de ingest (descartar a parte `image/jpeg`); base legal/consentimento para tratamento biométrico; retenção e minimização (gravar só o necessário para presença); que o `accessEvents` não vire repositório de fotos. Avaliar DPIA para dado biométrico (sensível sob LGPD).

**Deploy:**
- Corrigir **C1 + H1** (path injection e idempotência Intelbras) **antes** de qualquer deploy.
- A CF está exportada mas **não deployada nem ligada a device live**. Deploy só após field-confirm.
- Se o firmware exigir path base fixo (ZKTeco `/iclock/`), configurar **rewrite do Firebase Hosting ou proxy edge**. Se firmware antigo só suportar HTTP/IP, planejar **proxy edge na academia** que termine TLS e injete `x-api-key`/HMAC.
- Implementar handlers TODO do ZKTeco (`getrequest` drenar comandos, `devicecmd` ACK) se "abrir remoto" for requisito.

**Arquivos relevantes (todos absolutos):**
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/access_control/ingest.js` (núcleo, CF `ingestAccessEvent`)
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/access_control/canonical.js` (contrato `AccessEvent`, `normalizeDirection/Method`)
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/access_control/adapters/controlid.js`
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/access_control/adapters/zkteco.js`
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/access_control/adapters/intelbras.js`
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/access_control/README.md`
- `/Users/igorgewehr/WebstormProjects/graduabjj/functions/index.js` (wiring aditivo: `exports.ingestAccessEvent`)

> **Compilação:** os 6 arquivos passam `node --check` (sem erros de sintaxe). Nada deployado, nada ligado a device real.