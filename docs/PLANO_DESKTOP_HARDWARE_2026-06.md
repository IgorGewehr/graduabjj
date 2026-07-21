Confirmado: `firebase_options.dart:19-33` lança `UnsupportedError` para macOS/Windows/Linux, e `main.dart:20` chama `Firebase.initializeApp` + `main.dart:40` chama `pushNotificationService.initialize()` incondicionalmente, com `setPreferredOrientations(portrait)` em `main.dart:57-60`. As premissas batem. Segue o plano.

---

> **Status de execução (2026-07):** **F0-F3 executadas** (com escopo Windows —
> Mac ainda não). App Windows de balcão em produção (`docs/WINDOWS.md`,
> `lib/core/fns.dart` para Cloud Functions via HTTP), guardas de plataforma em
> `main.dart`, CI GitHub Actions builda o `.exe`. Catraca Control iD Face em
> modo Online **deployada em produção** (`ingestAccessEvent`,
> `functions/access_control/README.md`), com UI admin
> (`AdminDevicesScreen`/`DeviceEnrollmentScreen`) e MODO KIOSK
> (`lib/screens/kiosk/kiosk_screen.dart`). **F4 (enroll facial + LGPD) e F5
> (Local Agent B + ZKTeco/Intelbras/Henry/Topdata) continuam NÃO
> implementadas** — field-confirm de firmware ainda pendente para
> ZKTeco/Intelbras (ver `functions/access_control/README.md` §8). macOS
> continua greenfield (só Windows foi construído). Este plano permanece a
> referência viva para F4/F5 e para macOS.

# Plano de Arquitetura — GraduaBJJ Desktop (Windows/Mac) + Catracas e Biometria

## Resumo executivo

O GraduaBJJ é hoje um app Flutter **exclusivamente mobile** (Android+iOS): não existem as pastas `windows/`/`macos/`, o boot trava em desktop por três pontos duros e **não há uma única linha de código de hardware/catraca/biometria** — essa parte é greenfield total. O salto é grande, mas a fundação ajuda: o backend (Cloud Functions no projeto `arpjj-76350`) já tem os padrões exatos que vamos reusar (gravação de presença server-side idempotente e endpoints `onRequest` autenticados por `x-api-key`), e o `AdminShell` já é a única prova-de-conceito responsiva (breakpoint 768px com sidebar).

**Recomendação central de arquitetura de hardware: começar pela Arquitetura C (push-cloud) como piloto e evoluir para B (local-agent) onde a confiabilidade 24/7 ou um fabricante DLL-only exigir.** Os julgamentos pontuam C=41, B=36, A=28. A vence em latência de UI mas é *not-recommended* porque acopla o gateway de hardware ao processo de UI — anti-padrão direto para o requisito inegociável "a catraca não pode parar". C tira o PC do caminho crítico (a catraca POSTa direto para uma Cloud Function; a presença sobrevive ao PC desligado), é o menor volume de código e tem paridade Mac real para o caminho facial. B é a evolução natural de robustez (daemon headless 24/7 + fila durável + drivers Windows-only isolados), ao custo de DevOps mais pesado (dois binários assinados/notarizados).

**A jogada certa é sequenciar**: "construir na forma de C, com contrato pronto para virar B". O caminho de gravação é o **mesmo** Cloud Function HTTPS nos dois — só muda *quem* faz o POST (a catraca direto em C; um Agent local em B). Isso permite começar barato e rápido sem reescrever o caminho crítico depois.

Paralelo a isso, a UI/UX desktop é uma **camada responsiva nova quase do zero**, mas barata por um motivo arquitetural: navegação e gate já são *catalog-driven* (`kAdminNavCatalog`/`kPortalNavCatalog`), então trocar o **shell** adapta o app inteiro sem reescrever as ~65 telas.

---

## Estado atual e lacunas

### Desktop — três bloqueadores duros (verificados no código)

1. **Faltam as plataformas desktop.** O repo só tem `android/` e `ios/`; o `.metadata:14` só registra esses dois. Sem `flutter create --platforms=windows,macos .` o `flutter build windows/macos` nem reconhece o target.
2. **`firebase_options.dart` aborta o boot.** `currentPlatform` lança `UnsupportedError` explícito para macOS/Windows/Linux (`firebase_options.dart:19-33`, confirmado). Como `main.dart:20` chama `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` incondicionalmente, o app crasha no boot em desktop.
3. **`firebase_messaging` sem guarda.** `main.dart:40` chama `await pushNotificationService.initialize()` incondicionalmente. FCM **não existe em desktop nenhum** (nem Windows nem macOS). Precisa de guarda `if (!kIsWeb && (Platform.isAndroid||Platform.isIOS))`.

Bloqueadores secundários: `setPreferredOrientations(portrait)` (`main.dart:57-60`, no-op mas mobile-centric); plugins sem desktop usados sem guarda — `image_cropper` (settings/store) e `mobile_scanner` (qr_scan); ausência de empacotamento desktop (`build.sh:7-10` só faz aab/apk/ipa); nenhuma gestão de janela (`window_manager`/kiosk).

### Firebase desktop é PARCIAL — a restrição central

Verdade oficial do FlutterFire (https://firebase.google.com/docs/flutter/setup):
- **macOS**: produção-OK para `firebase_core`/`auth`/`firestore`/`storage`/`functions`.
- **Windows**: "**not intended for production use cases, only local development workflows**". `cloud_firestore-windows` existe desde o plugin v4.10.0 (nov/2023) mas é dev-only. `firebase_auth` no Windows é reimplementação Dart/REST (Identity Toolkit), não o SDK nativo.
- **`firebase_messaging` (FCM)**: ausente em **todo** desktop.
- A alternativa pure-Dart `firedart` está abandonada (sem updates desde abr/2021) — não é fundação.

**Consequência arquitetural:** a camada de dados de produção no Windows **não pode** depender de `cloud_firestore-windows`. Escritas vão por Cloud Functions HTTPS (Admin SDK Node, server-authoritative). Isso casa com o padrão idempotente já existente (`markPrivateLessonGiven` em `server_functions.js`, `markPresent`/doc-id determinístico em `attendance_service.dart:375/540`).

### Responsividade — quase inexistente

- **Um único breakpoint no app inteiro**: `width<768`, e só no `admin_shell.dart:68,168,187`. Nenhuma classe de breakpoints, nenhum `isDesktop`, nenhum `NavigationRail`.
- **`PortalShell` (aluno) é 100% mobile** em qualquer largura (`portal_shell.dart:277-300`): sempre BottomNav, conteúdo coluna-única no meio da tela larga vazia.
- **Telas esticam edge-to-edge**: `students_list_screen.dart:327-733` é ListView de Rows sem `maxWidth`. Os poucos `maxWidth` existentes são inconsistentes (480/512/1024/1080/1280) e quase todos em modais.
- **Grids com `crossAxisCount` fixo** (loja=2, KPIs=4) que não adaptam colunas à largura.
- **Zero affordances desktop**: grep por `Shortcuts/LogicalKeyboardKey/FocusableActionDetector` = 0. Sem atalhos, hover real ou foco.
- **Sidebar estática** de 250px fixos (`admin_shell.dart:306-308`), sem colapsar nem virar rail no degrau intermediário (768–1100px aperta).

### Hardware — zero hoje

Grep por `dart:ffi/serial/Wiegand/turnstile/kiosk/catraca/biometric/facial` em `lib/` = **nada**. O fluxo de check-in mais próximo é `qr_session_screen.dart` (o admin mostra um QR para o **aluno** escanear) — exatamente o **inverso** do necessário (um totem na catraca recebendo o evento de hardware). É greenfield completo.

---

## Desktop (Windows/Mac)

### 1. Habilitar as plataformas (pré-requisito de tudo)

```
flutter create --platforms=windows,macos .
flutterfire configure   # adiciona apps macOS + Windows no projeto arpjj-76350
```

Isso gera os runners nativos (CMake/Win32, Xcode/AppKit), recria entitlements macOS (vão precisar de **network client/server** para falar com catracas TCP na LAN) e **substitui os `UnsupportedError`** de `firebase_options.dart` por configs reais.

### 2. Contornar o Firebase desktop parcial

- **Guardar messaging e orientação** em `main.dart`:
  ```dart
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await pushNotificationService.initialize();
    await SystemChrome.setPreferredOrientations([portraitUp, portraitDown]);
  }
  ```
  Tornar `pushNotificationService` um no-op em desktop. O PC de balcão não recebe push — ele faz **stream/poll do Firestore** para leituras de baixo risco.
- **Escritas autoritativas sempre via Cloud Function** (nunca `cloud_firestore-windows` em produção). No macOS, leitura nativa do Firestore é OK; no Windows, leitura só para painel após **soak test 24/7** de listeners long-lived.
- **Auth de "conta de dispositivo"** dedicada (login service-style email/senha via Identity Toolkit REST, suportado no desktop) em vez de auth interativo por usuário no kiosk.
- Isolar `image_cropper`/`mobile_scanner` atrás de abstração com fallback desktop (file-open dialog via `image_picker`; câmera via `camera_windows`/`camera_macos`) ou esconder essas telas no shell desktop. `in_app_update` já está guardado por `Platform.isAndroid` (`main.dart:69`).

### 3. Empacotamento, assinatura, instalação

- **Windows**: `flutter build windows --release` → empacotar com `msix` (Store ou sideload `.pfx`) ou Inno Setup; assinar com `signtool`.
- **macOS**: `flutter build macos --release` → `codesign` com Developer ID → notarizar com `notarytool` → `staple` → distribuir DMG/ZIP. **Hardened Runtime é obrigatório** para notarização.
- Automatizar multiplataforma com `flutter_distributor`. Adicionar alvos `windows`/`macos` ao `build.sh` (hoje só aab/apk/ipa).

### 4. Kiosk e auto-update (PC de balcão 24/7)

- **Kiosk/fullscreen**: `window_manager` — `setFullScreen(true)`, always-on-top, prevent-close, window event listeners. **Atenção**: nenhum pacote Flutter faz lockdown real de SO; bloquear Alt+Tab/tecla Windows exige **Windows Assigned Access** (política do SO), fora do escopo do app. O pacote `kiosk_mode` é Android/iOS only.
- **Auto-update**: `auto_updater` (Sparkle no Mac, WinSparkle no Windows) com `appcast.xml` assinado (DSA/EdDSA). Crítico para PC desatendido 24/7. Windows precisa de WinSparkle no PATH + Inno Setup 6.

---

## Integração com hardware

### Arquitetura recomendada

**Piloto = C (push-cloud); evolução = B (local-agent). O caminho de gravação é idêntico nos dois.**

```
[Catraca: match facial/digital EMBARCADO no device]
        │  HTTP POST (JSON / key=value) do evento de acesso
        ▼
   ── piloto (C): direto para ──►  Cloud Function HTTPS  ──►  Firestore (presença
   ── evolução (B): via Agent ──►   ingestAccessEvent          server-side, idempotente
       local headless 24/7           (Admin SDK Node)          por eventId do device)
        │
        ▼
   [Flutter desktop = console de gestão/cadastro + MODO KIOSK]
        └── lê o resultado via Firestore stream (nome+foto+faixa+check verde/X vermelho+som)
```

O PC **não está no caminho crítico de presença** em C: o evento vai catraca→nuvem. O Flutter desktop só configura, cadastra e exibe feedback (lendo o stream). Em B, um daemon headless (Windows Service / launchd) assume o POST com fila SQLite durável — necessário quando a rede da academia bloqueia push direto (NAT/firewall) ou para fabricantes DLL-only.

### Por que C ganhou (trade-offs das três)

| Critério | A (flutter-bridge) | B (local-agent) | C (push-cloud) |
|---|---|---|---|
| Viabilidade | 6 | 8 | 8 |
| Cross-platform | 4 | 6 | **9** |
| Confiabilidade 24/7 | 4 | **9** | **9** |
| Velocidade de dev | 5 | 5 | **8** |
| UX/feedback kiosk | **9** | 8 | 7 |
| **Total** | 28 (not-recommended) | 36 (recommended) | **41 (recommended)** |

- **A é descartada**: UI + drivers + gravação no **mesmo processo** → jank/crash/freeze da tela derruba a captação de eventos. A própria proposta admite que para 24/7 precisa mover drivers para Isolate — o que converge para B sem entregar a separação de processo de B. A só serve como a **camada de UI/kiosk por cima**, não como arquitetura de dados. Seu único trunfo (feedback in-process, latência mínima) não compensa o anti-padrão diante de "a catraca não pode parar".
- **C é o melhor piloto**: remove o componente mais propenso a falha (um PC de balcão) do caminho quente; menor volume de código (1 CF de ingestão + 1 de provisionamento + telas de gestão, **sem drivers no hot-path**); paridade Mac real para o caminho facial (tudo é REST/HTTP). Reusa infra provada do `arpjj-76350`.
- **B é a evolução de robustez**: daemon headless 24/7 com auto-restart, desacoplado da UI (fechar/travar/atualizar o app **não** interrompe a captação); fila SQLite durável drenando à mesma CF com idempotência ponta a ponta; isola código Windows-only (FFI/DLL) num único processo. Custo: **dois** binários para empacotar/assinar/notarizar/auto-atualizar + installer de service + possível fragmentação .NET para DLLs Henry/Topdata.

**Riscos honestos de C** (a endereçar antes de prod):
1. **Endpoint de ingestão é PÚBLICO** (a catraca não faz Firebase Auth). É a maior superfície de risco: um POST forjado = presença forjada. **Obrigatório**: HMAC/segredo por `deviceId` (`devices/{deviceId}.secret`), validação de assinatura no header, IP allowlist, rate-limit e idempotência estrita.
2. **`markPresent` exige `classId`/`className`** — um giro cru de catraca não carrega turma. A CF precisa resolver a turma ativa da academia no horário do evento, ou modelar um check-in sintético. Lógica de domínio não-trivial.
3. **NAT/firewall**: muitas catracas só postam na LAN ou exigem port-forward/IP público. O "Listener Local opcional" de C vira **provavelmente obrigatório** em redes restritas — e isso é, na prática, o Agent de B. Orçar como peça esperada, não opcional.
4. **Licença Pro/Enterprise** por catraca para modo Online/push (Control iD) — custo por device não cotado. Confirmar cedo.

### Protocolos e fabricantes (roadmap por esforço)

Padrão dominante no Brasil: **match embarcado no device + push/pull HTTP**, operação offline com base sincronizada.

1. **Control iD (piloto recomendado)** — iDBlock/iDAccess + iDFace. REST sobre TCP/IP, **push HTTP nativo em JSON** via "Monitor": configura-se `hostname:port:path` em `/set_configuration.fcgi` e o device POSTa `/api/notifications/dao` (logs), `/api/notifications/catra_event` (giro `EVENT_TURN_LEFT/RIGHT`), `/api/notifications/device_is_alive` (heartbeat). Liberação remota do giro via action `catra`. Match local (modo Pro: device decide, só envia `user_id`). **iDFace não usa template** — enroll é enviar a **foto** via API. Melhor documentado, JSON puro, platform-agnostic. (https://www.controlid.com.br/docs/access-api-pt/monitor/introducao-ao-monitor/)
2. **ZKTeco (ADMS/Push Protocol)** — terminais POSTam logs via HTTP/HTTPS, device inicia a conexão (dispensa IP público). Pegadinha: payload **key=value** (não JSON), exige parser específico. Segundo melhor por preço + push nativo. (https://github.com/adrobinoga/zk-protocol/blob/master/protocol.md)
3. **Intelbras** — REST documentada (Bio-T) + facial embarcado (CAP 3000, Duplo, SS 5531). Pegadinha: autorização online pode exigir o Controller via porta Wiegand + SDK, acoplando mais que o push direto da Control iD. (https://intelbras-caco-api.intelbras.com.br/)
4. **Henry (Primme) / Topdata (Inner)** — integração via **SDK/DLL Windows-only**, sem push HTTP aberto. Topdata: TCP porta 3570 por **pull**. Dominam academias e são baratos, mas **forçam um Agente Local Windows** (FFI/`P/Invoke`) — não funcionam no Mac e não devem ser o piloto. Entram na fase final, sob a arquitetura B.

**Push vs pull:** preferir push (Control iD/ZKTeco) — cross-platform, sem DLL, e o device empurra (resolve NAT). Pull/SDK (Henry/Topdata) amarra ao Windows.

**Biometria embarcada:** em todas as opções o facial/digital faz **match no próprio device** (liveness, 1:N de até 10–20k faces). O PC recebe só `user_id`, **nunca imagem/template bruto** — exceto enroll. Não precisamos de SDK de visão, câmera própria nem modelo de IA: delegamos ao hardware certificado. (https://www.controlid.com.br/docs/access-api-en/facial-recognition/facial-enroll/)

**Cadastro (enroll):**
- **Facial**: pela própria catraca (foto via API REST, sem template, sem hardware extra) — cross-platform, viabiliza Mac.
- **Digital de mesa USB** (Nitgen FingKey Hamster, DigitalPersona U.are.U 4500): SDK **DLL Windows-only** (frequentemente x86). Sem SDK Flutter/Dart. **Adiar** — só via Agente Local Windows se um cliente exigir. Em academias com Control iD/facial, dá para pular o leitor de mesa.

**Offline:** o equipamento opera offline com match embarcado e bufferiza eventos (Henry guarda ~8M eventos; Control iD bufferiza). **A porta nunca para.** Ao reconectar, drena o buffer. Cuidados: **idempotência por `eventId`** do device na CF (eventos reentregues não duplicam presença) e **preservar o timestamp original** do evento (não usar `now()` ao drenar). Provisionamento (enroll/exclusão device↔nuvem) precisa de fila/retry.

**LGPD (bloqueador de compliance):** biometria facial/digital é **dado pessoal sensível** (LGPD art.5 II / art.11). Obrigatório no produto desde o MVP:
1. **Consentimento específico e destacado** registrado no Firestore **antes** do enroll (não embutido em termo genérico, sob pena de nulidade), com finalidade/duração/revogação.
2. **Alternativa não-biométrica** sempre disponível (cartão/QR).
3. **Exclusão do template/face no device ao cancelar matrícula** (via CF de provisionamento, reaproveitando o fluxo de cancelamento existente), com relatório auditável.
4. Armazenar **referência/ID, não imagem bruta**; o template (irreversível) fica no edge. Trilha de auditoria de quem/quando enrolou/excluiu.
(https://confidata.com.br/blog/lgpd-dados-biometricos-reconhecimento-facial-digital)

---

## UI/UX responsiva impecável

Trunfo: navegação e gate já são *catalog-driven* (`kAdminNavCatalog`/`kPortalNavCatalog` + `resolveAdminCatalog`), e a sidebar e a sheet do menu já saem da **mesma fonte**. Trocar o **shell** adapta o app inteiro — as ~65 telas não mudam. O trabalho tela-a-tela vira incremental.

1. **Camada responsiva central** — novo `lib/core/responsive.dart`, fonte única que substitui o `width<768` solto. 4 breakpoints Material 3: `compact` (<600), `medium` (600–1024), `expanded` (1024–1440), `large` (>1440). Enum `Breakpoint` + extension em `BuildContext` (`context.isDesktop`, `context.bp`, helper `context.responsive<T>(compact:, medium:, expanded:, large:)` com fallback para a faixa menor). Funções puras, sem Riverpod. Primeiro consumidor: trocar os 3 usos de `768` no `admin_shell.dart` por `context.isDesktop`.

2. **`AdaptiveShell` catalog-driven** — unifica os dois shells e escolhe 3 modos por breakpoint, da **mesma** lista resolvida: `compact`→BottomNav + sheet "Mais"; `medium`→**NavigationRail só-ícones** (~72px, tooltips no hover) — o degrau que falta hoje; `expanded/large`→Sidebar expandida (a `AdminSidebar` de 250px atual, com opção de colapsar). Aplicar **também ao `PortalShell`** lendo `kPortalNavCatalog` — o portal do aluno ganha rail/sidebar no desktop de graça. **Um PR de baixo risco adapta a navegação do app inteiro.**

3. **`ContentBounded(maxWidth)`** — `Align(center)+ConstrainedBox` que é no-op no `compact` e a partir de `medium` centraliza/limita. Token único: **1200** para listas, **720** para forms/leitura (substitui os 480/512/1024/1080/1280 inconsistentes). Uma linha por tela, aplicar por ordem de uso do balcão: Alunos → Chamada → Financeiro → Relatórios → Turmas.

4. **Master-detail no desktop** só nas 3 telas core (Alunos, Chamada, Financeiro): widget `MasterDetail(master, detail, isWide: context.isExpanded)` — no `compact` mantém o push atual; no `expanded` renderiza lista (~360–420px) + detalhe lado a lado. Maior ganho de UX desktop (elimina coluna única no vazio).

5. **Grids fluidos e forms multi-coluna** — trocar `GridView.count` fixo por `SliverGridDelegateWithMaxCrossAxisExtent` (loja, galerias, KPIs de relatórios). **Preservar calendários de presença em 7 colunas** (semânticos = dias da semana). O `LayoutBuilder` de `form_section` (hoje empilha campos em <400px) ganha o caso oposto: 2 colunas em `expanded`.

6. **Dialogs/sheets adaptativos** — `showAdaptiveSheet(context, builder)`: `compact`→`showModalBottomSheet` (atual); `isDesktop`→`showDialog` centralizado com `maxWidth` consistente, ou side-panel à direita para fluxos longos. O `MoreMenuSheet` fica obsoleto no desktop (a sidebar mostra tudo) — só renderizar no `compact`.

7. **Ergonomia de balcão** — `visualDensity` adaptativo (comfortable no compact, compact no desktop); hover/cursor + realce em linhas clicáveis (Alunos, Cobrança); `Shortcuts`/`Actions` globais (Ctrl/Cmd+K buscar aluno, nova chamada, Ctrl+S salvar, Tab/setas); tooltips no rail colapsado. Manter `app.dart:201-204` com `textScaler.noScaling`.

8. **MODO KIOSK/CATRACA** — rota nova `/kiosk` montada **fora** dos shells (sem AppBar/Nav/banner de assinatura), fullscreen via `window_manager`. Máquina de estados visual legível a 2–3m (theme já tem `displayLarge` 32 + cores `success`/`error`):
   - **IDLE**: logo, relógio grande, "Aproxime-se da catraca".
   - **RECONHECIDO**: foto grande + nome + **faixa** (reusar widget de faixa/AnimatedBelt em variante display), check verde gigante, som de sucesso, "Bem-vindo <nome>" + contagem de presença.
   - **NEGADO**: X vermelho, motivo curto (mensalidade em atraso / não reconhecido), som distinto.
   - **auto-reset ~5s**. Banner "modo offline" sem internet; fila local idempotente por `eventId`, drenando ao reconectar.
   A UI consome um **stream de evento de acesso canônico** (`deviceId, externalUserId, timestamp, direção, método`) vindo de uma camada `HardwareDriver` abstrata — **a tela não conhece Control iD/serial/HTTP**, só reage. Inclui sub-modo enroll na recepção.

---

## Roadmap faseado

Cada fase entrega valor isolado e é mergeável sozinha (sem big-bang), porque navegação/gate já são centralizados no catálogo.

### F0 — Fundação desktop + camada responsiva (não quebra nada)
**Entregáveis:** `flutter create --platforms=windows,macos .` + `flutterfire configure`; guardas de plataforma em `main.dart` (messaging, orientação); isolar `image_cropper`/`mobile_scanner`; `lib/core/responsive.dart` (4 breakpoints + extension); trocar os 3 `width<768` do `AdminShell` por `context.isDesktop`; alvos `windows`/`macos` no `build.sh`; primeiro build Windows+Mac rodando uma janela com Firestore (leitura).
**Riscos:** auth no Windows (persistência de sessão na `firebase_auth ^5.4.1`) é frágil — **validar empiricamente login + leitura/escrita** num build Windows real antes de prometer paridade. Soak test de listeners long-lived no Windows.

### F1 — Navegação adaptativa + conteúdo limitado
**Entregáveis:** `AdaptiveShell` catalog-driven (BottomNav/Rail/Sidebar) aplicado a Admin **e** Portal; `ContentBounded` nas telas de maior volume; grids fluidos na loja/galerias. **Um PR adapta a navegação inteira.**
**Riscos:** aparência real do rail/master-detail só é validada em runtime (inferida do código até aqui). Auditar as ~65 telas com `MediaQuery` ad-hoc por larguras fixas.

### F2 — MODO KIOSK (UI) + contrato de evento canônico
**Entregáveis:** rota `/kiosk` fullscreen (`window_manager`), máquina de estados IDLE/RECONHECIDO/NEGADO + som + auto-reset, lendo um **mock** do stream de `AccessEvent` (sem hardware ainda); definir o contrato `HardwareDriver` + `AccessEvent` e a coleção `devices/{deviceId}` + `enrollments/{studentId}`.
**Riscos:** validar widget de faixa em tamanho display. Feedback do kiosk dependerá do round-trip cloud→stream (latência em Wi-Fi de academia — medir).

### F3 — Primeira catraca real (Control iD) via arquitetura C
**Entregáveis:** Cloud Function `ingestAccessEvent` (`onRequest`, clone dos padrões `server_functions.js:188`/webhook) com **HMAC por device + idempotência por `eventId` + IP allowlist + rate-limit**; resolução de turma ativa no horário do evento; gravação idempotente reusando `markPrivateLessonGiven`/`attendance_service`; piloto numa academia com iDBlock + iDFace (modo Pro, push direto à CF). Mapeamento `externalUserId→studentId`.
**Riscos:** **endpoint público** é a maior superfície (POST forjado = presença forjada) — hardening é não-negociável. NAT/firewall pode forçar o Listener Local já aqui. Confirmar licença Pro/Online da Control iD.

### F4 — Cadastro biométrico facial + LGPD
**Entregáveis:** enroll facial pela própria catraca (foto via API, sem template extra), disparado pelo console desktop; fluxo de **consentimento específico** registrado no Firestore antes do enroll; alternativa cartão/QR; **exclusão do template no device** ao cancelar matrícula (CF de provisionamento + retry); trilha de auditoria.
**Riscos:** compliance é bloqueador — consentimento e exclusão precisam estar provados antes de qualquer enroll em produção. Sync provisionamento device↔nuvem (consistência eventual).

### F5 — Local Agent (B) + demais fabricantes
**Entregáveis:** Bridge Agent headless (Dart standalone `dart compile exe`, ou .NET onde houver DLL) como Windows Service/launchd, com fila SQLite durável drenando à mesma CF; drivers ZKTeco (push key=value) → Intelbras → Henry/Topdata (FFI/`P/Invoke`, Windows-only) atrás da interface `HardwareDriver` com stub no-op para o Mac compilar; leitor USB de digital de mesa só aqui, isolado no Agent. Packaging do segundo binário (msix/DMG + auto_updater), recovery do service, heartbeat/alerta.
**Riscos:** dois binários = mais DevOps e suporte de campo (descoberta de IP, drift de api-key, service no boot). Mac vira suporte parcial para fabricantes DLL-only — comunicar isso ao dono (a promessa "Windows AND Mac" tem teto estrutural de hardware, não de arquitetura).

---

## MELHOR PRIMEIRO PASSO

**Executar F0 agora, e dentro dela o passo de maior alavancagem é: rodar `flutter create --platforms=windows,macos .` + `flutterfire configure`, aplicar as guardas de plataforma em `main.dart`, e provar um build Windows+Mac que abre uma janela com login (firebase_auth) e uma leitura Firestore funcionando.**

Por quê este passo, e não a UI ou o hardware:
- **É o pré-requisito literal de tudo.** Sem as pastas de plataforma e sem substituir os `UnsupportedError` de `firebase_options.dart`, nada roda no desktop — nem a camada responsiva, nem o kiosk, nem a integração de catraca. É a porta que destranca todas as fases seguintes.
- **De-risca o item mais incerto do projeto cedo e barato.** O maior "não sei" técnico é **se `firebase_auth`/Firestore realmente funcionam de forma confiável num build Windows real** (suporte FlutterFire é dev-only no Windows). Os gaps das três análises convergem nisso: ninguém verificou em runtime. Descobrir isso em dias (com um build real, não leitura de código) define se o Windows precisa rotear **toda** escrita por Cloud Function desde o dia 1 — decisão que molda F3–F5.
- **É reversível e não quebra mobile.** As guardas de plataforma (`if (Platform.isAndroid||isIOS)`) e a geração das pastas desktop não alteram o comportamento Android/iOS em produção; é aditivo e seguro de mergear no `firebase-production`.
- **Alimenta diretamente a primeira demo.** Com a janela desktop de pé, F1 (AdaptiveShell, um PR) entrega imediatamente o app inteiro responsivo no desktop — o "salto visível" que justifica o investimento antes de tocar em qualquer catraca.

Concretamente, criar primeiro: as pastas `windows/`/`macos/`, os blocos macOS/Windows em `firebase_options.dart` (via `flutterfire configure`), as 3 guardas em `main.dart` (messaging, orientação, e manter `in_app_update` já guardado), e um smoke test manual de login + uma query Firestore num build `--release` de cada plataforma. Só depois disso seguir para `lib/core/responsive.dart` e o `AdaptiveShell`.