# Catraca Gateway — ponte Windows entre a catraca e a nuvem

Projeto irmão, repositório separado:
`/Users/igorgewehr/webstormprojects/catraca-gateway` (não faz parte deste
repo — não editar nada lá a partir daqui). Console app em **Dart puro, sem
Flutter**, que roda no PC de balcão de uma academia e fica entre a catraca
**Control iD** (iDFace/iDBlock/iDAccess, na rede local) e a Cloud Function
`ingestAccessEvent` já deployada em produção (ver [CATRACAS.md](CATRACAS.md)).

## Por que ele existe

```
+-----------------+   HTTP puro (LAN)   +-------------------+   HTTPS + HMAC (internet)   +----------------------------+
|  Catraca        |  ----------------->  |  catraca-gateway   |  ------------------------>  |  Cloud Function             |
|  Control iD     |  POST /dao,          |  (roda no PC de    |  POST /ingestAccessEvent/…  |  ingestAccessEvent          |
|  (iDFace/Block/ |  /catra_event,       |  balcão)            |  ?acad=&deviceId=&vendor=   |  (us-central1, arpjj-76350) |
|  iDAccess)      |  /device_is_alive,   |                    |  x-device-timestamp/-signature|                            |
|                 |  new_user_identified |                    |  (HMAC-SHA256)               |                            |
+-----------------+  <-----------------  +-------------------+  <------------------------  +----------------------------+
                        200 OK / veredito                              |
                                                                        v
                                                              +-------------------+
                                                              |  queue/*.json     |
                                                              |  store-and-forward |
                                                              +-------------------+
```

A catraca é configurada apontando **pra este gateway** (hostname = IP do PC
no balcão, path base vazio) — ela nunca fala direto com a internet.

1. **HTTPS + assinatura HMAC que o firmware não oferece.** A catraca fala
   HTTP puro, sem TLS e sem autenticação além do path configurado nela.
   Qualquer coisa na mesma LAN (ou que descubra o IP do PC) poderia forjar
   eventos de presença. O gateway assina **toda** requisição que sai para a
   Cloud Function com `x-device-timestamp` (epoch ms) +
   `x-device-signature` (`HMAC-SHA256(deviceSecret, "<ts>.<rawBody>")`),
   recalculado a cada tentativa — nunca reaproveitado, por causa do
   anti-replay de 5 minutos no servidor (`ingest.js`).
2. **Store-and-forward offline.** Se a internet do PC cair, a catraca não
   pode ficar travada nem os eventos podem se perder. Tudo que não é o fluxo
   síncrono "Online" (isto é, `/dao`, `/catra_event`, e qualquer outro path
   desconhecido) é gravado em `queue/*.json` **antes** de responder `200 OK`
   ao device, e um worker em background reenvia com backoff exponencial (5s
   → 5min). O servidor de ingest é idempotente (dedupe por `eventId`
   determinístico), então reenviar o mesmo evento qualquer número de vezes é
   sempre seguro.
3. **Fallback local no modo Online síncrono.** Em `new_user_identified.fcgi`
   / `new_card_identified.fcgi` a catraca fica **bloqueada** esperando o
   veredito na resposta do mesmo POST. Se a Cloud Function não responder a
   tempo (`onlineTimeoutMs`, default 3500ms), o gateway decide **localmente**
   (libera ou nega, conforme `offlinePolicy`) no mesmo shape JSON que o
   servidor usaria, e enfileira o evento para sincronizar a presença de
   verdade depois. **Filosofia fail-open**: por padrão o gateway libera o
   acesso quando não consegue confirmar com o servidor — nunca tranca um
   aluno do lado de fora por uma instabilidade de rede que não é culpa dele.

## Arquitetura / rotas

Servidor HTTP local (`lib/server.dart`) — é isto que a catraca enxerga como
se fosse o próprio endpoint cloud:

| Rota | Comportamento |
|---|---|
| `GET /status` | JSON com saúde do gateway (uso local/CLI) |
| `GET` qualquer outro path | `200 OK` texto — handshake/keepalive da catraca |
| `POST .../device_is_alive` | `200 OK` **imediato** + forward best-effort **sem fila** (heartbeat ~30s; perder um não importa, o próximo em ~30s já corrige) |
| `POST .../new_user_identified(.fcgi)` ou `new_card_identified(.fcgi)` | Modo **Online síncrono** — tenta a cloud com timeout curto (`onlineTimeoutMs`); se falhar, decide localmente e enfileira |
| `POST` qualquer outro path (`/dao`, `/catra_event`, ...) | **Store-and-forward**: grava na fila em disco e já responde `200 OK` — o worker cuida do envio real em background |

Ponto crítico de correção em `_handlePost`: no caminho store-and-forward,
`queue.enqueue(...)` acontece **antes** de responder `200 OK` — se o processo
morrer entre o `enqueue` e a resposta, o pior caso é a catraca reenviar o
mesmo evento (idempotente do lado do servidor), **nunca perder** o evento.

### Fila durável (`lib/queue.dart`)

Um arquivo JSON por evento em `queueDir/*.json`, escrito com **rename
atômico** (grava em `.tmp` e renomeia — nunca deixa um arquivo parcialmente
escrito se o processo cair no meio do write). `listPending()` sempre relê do
disco (rescan), então qualquer coisa que sobrou de uma execução anterior
(processo caiu, Windows reiniciou) é naturalmente redescoberta no boot.

Classificação do resultado de um envio (`classifyOutcome`):

- **2xx** → `sent` — remove da fila.
- **400/401/403** → `dead` — move para `queue/dead/{id}.json` com o motivo
  anexado. É config errada (secret errado, `academyId`/`deviceId` inválidos)
  — **reenviar infinitamente não resolve**, só polui a fila.
- **qualquer outra coisa** (5xx, sem resposta, timeout) → `retry` — backoff
  exponencial.

### Backoff e rate-limit (`lib/queue_worker.dart`)

O worker usa um **timer periódico de 260ms** que processa no máximo UMA
entrada da fila por tick — isso, na prática, vira o rate-limiter: com tick de
260ms o worker manda no máximo **~4 eventos/s** para a Cloud Function, que é
exatamente o teto que o servidor aplica por device (60 eventos/10s, ver
[CATRACAS.md](CATRACAS.md)). Backoff exponencial 5s → 5min (cap), com jitter
de até 500ms para não sincronizar múltiplas entradas atrasadas martelando o
servidor no mesmo instante.

### Assinatura HMAC (`lib/signer.dart`)

```dart
HMAC-SHA256(secret, "<ts>.<rawBody>")  // hex minúsculo
```

`rawBody` é assinado como **bytes**, não como String reconstruída — evita
diferenças de encoding (BOM, normalização) que quebrariam a assinatura no
servidor de forma silenciosa. Cada chamada de `signRequest` carimba um `ts`
novo — nunca reaproveitar assinatura entre tentativas/retries, porque o
anti-replay de 5 minutos no servidor exigiria isso de qualquer forma.

## `config.json` campo a campo

Copie `config.example.json` → `config.json` (**nunca versionar o `config.json`
real** — tem `deviceSecret` e a senha da catraca):

```json
{
  "cloudIngestUrl": "https://us-central1-arpjj-76350.cloudfunctions.net/ingestAccessEvent",
  "academyId": "academia-principal",
  "deviceId": "catraca01",
  "deviceSecret": "TROCAR",
  "listenPort": 8797,
  "lanIp": "",
  "onlineTimeoutMs": 3500,
  "offlinePolicy": "allow",
  "online": { "action": "door", "door": 1, "catraSense": "clockwise" },
  "device": { "host": "192.168.0.129", "user": "admin", "password": "admin" },
  "queueDir": "queue"
}
```

| Campo | O que é |
|---|---|
| `cloudIngestUrl` | URL base da Cloud Function (já deployada, não mexer) |
| `academyId` / `deviceId` | identificam academia e catraca no servidor (`acad=`/`deviceId=` na query) |
| `deviceSecret` | segredo compartilhado com o servidor para HMAC — **trocar o valor de exemplo** |
| `listenPort` | porta local que o gateway escuta (a catraca aponta pra cá); default 8797 |
| `lanIp` | IP deste PC na LAN, usado por `setup-device`; vazio = autodetecta |
| `onlineTimeoutMs` | timeout do forward síncrono no modo Online antes de cair pro fallback local; default 3500 |
| `offlinePolicy` | `allow` (default, fail-open) ou `deny` — decisão no fallback quando `user_id` é válido mas a cloud não respondeu |
| `online.action`/`door`/`catraSense` | ação física que o fallback local manda executar quando libera |
| `device.host`/`user`/`password` | credenciais da API local da catraca — usadas **só** por `setup-device` e `open-door`, nunca no caminho quente de ingest |
| `queueDir` | onde a fila em disco fica (relativo ao `config.json` se não for absoluto) |

Validação no load (`lib/config.dart`): `cloudIngestUrl` precisa ser uma URI
válida; `offlinePolicy` só aceita `allow`/`deny`; `online.action` só aceita
`door`/`catra`; `listenPort` precisa estar em `1–65535`. Erros de config viram
`ConfigException` com mensagem pensada para quem está no balcão lendo o
console — não para um dev.

## CLI (`bin/catraca_gateway.dart`)

```
catraca-gateway.exe [run]              Sobe o gateway (servidor + fila). Default.
catraca-gateway.exe setup-device       Configura a catraca (modo Monitor) pra apontar pro gateway.
catraca-gateway.exe open-door          Abre a porta/borboleta diretamente na catraca (manual, balcão).
catraca-gateway.exe status             Consulta o /status de um gateway já rodando nesta máquina.

Opção global: --config <path>   (default: ./config.json)
```

- **`run`** — sobe `Forwarder` + `PersistentQueue` + `QueueWorker` +
  `GatewayServer`, escuta `SIGINT` (Ctrl+C) para shutdown gracioso.
  `SIGTERM` só é observado em plataformas que suportam (não Windows).
- **`setup-device`** — loga na catraca (`device.host/user/password`) e
  configura o modo Monitor via `/set_configuration.fcgi` (`/dao`,
  `/catra_event`, `/device_is_alive`) para apontar para o IP:porta deste
  gateway. **Não automatiza** as chaves do modo Online síncrono
  (`new_user_identified.fcgi`) — variam por firmware/modelo; ajustar
  manualmente na interface web da catraca durante o piloto.
- **`open-door`** — aciona a ação `door` diretamente via
  `execute_actions.fcgi`, útil para destravar manualmente no balcão. Só
  `door` foi validado; o parâmetro exato da ação `catra` (catraca giratória)
  ainda não foi confirmado contra hardware real.
- **`status`** — faz `GET http://127.0.0.1:<listenPort>/status` numa
  instância já rodando **nesta máquina** e imprime formatado.

## Como buildar o `.exe`

**Não existe cross-compile de macOS/Linux para Windows no Dart** — `dart
compile exe` sempre gera um binário para a plataforma em que está rodando
(mesma limitação do build Windows do app Flutter — ver
[BUILD_WINDOWS.md](BUILD_WINDOWS.md)). Duas opções:

1. **GitHub Actions (recomendado)** — `catraca-gateway/.github/workflows/windows.yml`
   roda em `windows-latest`, dispara em push/PR para `main` do próprio
   projeto e também manualmente (`workflow_dispatch`):
   ```
   dart pub get
   dart analyze --fatal-infos     # BLOQUEANTE aqui (diferente do app Flutter)
   dart test
   dart compile exe bin/catraca_gateway.dart -o catraca-gateway.exe
   ```
   Sobe como artefato **`catraca-gateway-windows`**: o `.exe` + `config.example.json`
   + `scripts/install-task.ps1` + `scripts/uninstall-task.ps1` + `README.md`
   — tudo que precisa para uma instalação completa vem no mesmo zip.
2. **Num PC Windows** — instale o Dart SDK (ou o Flutter, que já traz o Dart
   — o binário costuma estar em algo como
   `%LOCALAPPDATA%\flutter\bin\cache\dart-sdk\bin\dart.exe`) e rode, na raiz
   do projeto `catraca-gateway`:
   ```
   dart pub get
   dart test
   dart compile exe bin\catraca_gateway.dart -o catraca-gateway.exe
   ```

> **Diferença importante em relação ao build do app Flutter**: aqui
> `dart analyze --fatal-infos` **bloqueia** o build (`.github/workflows/windows.yml`
> do `catraca-gateway`); no app Flutter o `flutter analyze` roda com
> `continue-on-error: true` (não bloqueia). São dois projetos com filosofias
> de CI diferentes — o gateway é um componente pequeno e crítico (caminho de
> presença/segurança), então o padrão aqui é mais estrito.

## Instalação como tarefa + firewall (Windows)

Depois de ter `catraca-gateway.exe` + `config.json` (preenchido) na mesma
pasta, com `scripts\install-task.ps1` e `scripts\uninstall-task.ps1` ao lado
(pasta `scripts\`), abra o **PowerShell como Administrador**:

```powershell
cd caminho\pra\instalacao\scripts
.\install-task.ps1
```

Isso:
- cria a regra de firewall liberando a porta configurada (`listenPort`, lida
  do `config.json`) para entrada TCP — nome sempre começando com `"Catraca
  Gateway (TCP <porta>)"`, o que permite ao script de desinstalação achar e
  remover a regra depois mesmo que a porta tenha mudado entre instalações;
- registra uma Tarefa Agendada (`CatracaGateway`) que roda
  `catraca-gateway.exe run --config "<path>"` **no boot** e **no logon**,
  como **`SYSTEM`** (não depende de ninguém logado no balcão), com reinício
  automático (até 3 tentativas, intervalo de 1 min) em caso de falha, e sem
  limite de tempo de execução (é um processo de longa duração, não uma
  tarefa pontual);
- é **idempotente**: remove uma instalação anterior antes de recriar (rodar
  de novo após mudar config não duplica a tarefa nem falha por "já existe");
- inicia a tarefa imediatamente.

Para remover (tarefa + regra de firewall — `config.json` e `queue\` são
**preservados**):

```powershell
.\uninstall-task.ps1
```

## Troubleshooting

- **Catraca não consegue falar com o gateway.** Confirme mesma rede/VLAN,
  que o Firewall do Windows libera a porta configurada (verificar:
  `netsh advfirewall firewall show rule name=all | findstr "Catraca"`), e
  que o `hostname`/IP configurado na catraca é o IP **atual** deste PC —
  **fixe o IP do PC** (IP estático ou reserva DHCP) para não precisar
  reconfigurar a catraca toda vez que o IP mudar.
- **`GET /status` retorna erro / conexão recusada.** O gateway não está
  rodando nesta máquina, ou está numa porta diferente da consultada. Confira
  `Get-ScheduledTask CatracaGateway` e o histórico da tarefa no Task
  Scheduler.
- **Eventos acumulando em `queue/`.** Sintoma de internet fora do ar ou
  `cloudIngestUrl`/`deviceSecret` errados. `GET /status` mostra `queueDepth`
  e `deadCount`. Itens em `queue/dead/` foram **rejeitados** com 400/401/403
  pelo servidor — geralmente `deviceSecret` errado ou `academyId`/`deviceId`
  inválidos; **não adianta esperar**, corrija o `config.json` e reenfileire
  manualmente (mova o arquivo de volta de `queue/dead/` para `queue/` e
  reinicie o gateway) se o evento ainda for relevante.
- **Rate-limit (60 eventos/10s por device) no servidor.** O worker já se
  limita a ~4 envios/s de propósito — só deveria acontecer com
  `onlineTimeoutMs` baixo demais gerando muitos fallbacks em rajada, ou em
  teste/stress. O próprio backoff exponencial absorve um 429/5xx eventual.
- **Modo Online não libera a catraca mesmo com tudo certo.** As chaves de
  configuração do modo Online variam por firmware — confira na interface web
  da própria catraca se "Identificação Online" está mesmo apontando para o
  gateway (`setup-device` não automatiza esta parte).
- **Quero abrir a porta manualmente (sem passar pela catraca).**
  `catraca-gateway.exe open-door --config config.json`.
