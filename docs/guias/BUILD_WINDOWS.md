# Build Windows (.exe) — GraduaBJJ Desktop

App de balcão para Windows (Flutter desktop), pensado para rodar no PC da
recepção de uma academia, lado a lado com o [gateway de catracas](CATRACA_GATEWAY.md)
(projeto irmão `catraca-gateway`, Dart puro, sem Flutter). Este guia documenta
o pipeline real de build — `.github/workflows/windows.yml` — e a camada de
compatibilidade que faz o mesmo código Flutter rodar em mobile e desktop.

## 1. O workflow (`.github/workflows/windows.yml`)

**Trigger:** `workflow_dispatch` manual (Actions → "Build Windows (.exe)" →
"Run workflow") **e** push automático na branch `b2c` quando o diff toca
`lib/**`, `windows/**`, `pubspec.yaml`, `pubspec.lock` ou o próprio arquivo do
workflow.

**Runner:** `windows-latest` — não existe cross-compile de Linux/macOS para
`.exe` no Flutter (assim como no `catraca-gateway`), então o binário nasce
sempre no CI, num Windows de verdade.

### O fix `CMAKE_POLICY_VERSION_MINIMUM: '3.5'`

```yaml
env:
  CMAKE_POLICY_VERSION_MINIMUM: '3.5'
```

**Por quê:** o Firebase C++ SDK (baixado automaticamente durante o build para
dar suporte a `cloud_firestore`/`firebase_auth` no Windows) declara internamente
`cmake_minimum_required(VERSION < 3.5)` em alguns dos seus `CMakeLists.txt`
vendorizados. O runner `windows-latest` já vem com **CMake 4.x**, que **removeu**
o suporte a políticas de compatibilidade tão antigas — o configure quebra com
`Compatibility with CMake < 3.5 has been removed`. A env var acima é o
equivalente de linha de comando a `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`: instrui
o CMake a **tratar** essas políticas antigas como se fossem 3.5, sem precisar
mexer no código vendorizado do SDK do Firebase. Sem isso o `flutter build
windows --release` falha antes mesmo de compilar uma linha de Dart.

### Passos

1. `actions/checkout@v4`.
2. `subosito/flutter-action@v2` — Flutter **pinado em `3.41.5`, channel
   `stable`**, com cache habilitado. Bump manual quando a máquina de dev
   local também subir de versão (evita builds locais vs. CI divergentes).
3. `flutter config --enable-windows-desktop`.
4. `flutter pub get`.
5. `flutter analyze --no-fatal-infos --no-fatal-warnings` com
   `continue-on-error: true` — **não bloqueia o build**. É um sinal, não um
   gate; o objetivo do workflow é sempre produzir um `.exe` testável.
6. `flutter build windows --release`.
7. Empacotamento via PowerShell: comprime `build/windows/x64/runner/Release/*`
   (com fallback para o layout antigo `build/windows/runner/Release`, sem a
   subpasta `x64`, para robustez entre versões do Flutter) num único
   `graduabjj-windows.zip` via `Compress-Archive`.
8. `actions/upload-artifact@v4` — nome `graduabjj-windows`, retenção de
   **30 dias**, `if-no-files-found: error` (o build falha alto e claro se o
   zip não existir, em vez de publicar um artefato vazio silenciosamente).

## 2. Camada de compatibilidade desktop

O código Flutter é **um só** para mobile e desktop — não há fork de app. Duas
peças pequenas absorvem as diferenças de plataforma sem espalhar `if
(Platform.isWindows)` pelas ~65 telas.

### `lib/services/fns.dart` — Cloud Functions callable no desktop

O plugin `cloud_functions` **não tem implementação nativa para
Windows/Linux**. `Fns` é a camada única de chamada de callables com fallback:

- **Mobile/iOS/Android/Web:** passthrough exato para
  `FirebaseFunctions.instance.httpsCallable(name).call(data)` — comportamento
  e exceções (`FirebaseFunctionsException`) **idênticos** ao que já existia.
  Os apps de celular não mudam em nada.
- **Desktop (`Platform.isWindows || Platform.isLinux`, fora da Web):** fala
  HTTP direto com o endpoint do callable
  (`https://us-central1-<projectId>.cloudfunctions.net/<name>`), replicando o
  protocolo dos callables (`{"data": ...}` no corpo, `{"result": ...}` na
  resposta), com o ID token do Firebase Auth no header `Authorization: Bearer`.
  Erros viram `FnsException(code, message, details)` — espelha o formato de
  `FirebaseFunctionsException` para quem consome o erro não precisar
  distinguir plataforma.

`Fns.functions` é um `CallableClient` **drop-in**: os serviços trocam a
origem de `FirebaseFunctions.instance` → `Fns.functions` e o resto do call
site (`.httpsCallable(name).call(data).data`, `try/catch`) não muda **uma
linha**. Isso é o que torna a extensão para desktop aditiva — nenhum service
existente foi reescrito, só a fonte do cliente callable.

### `lib/core/platform_support.dart` — o que degrada no desktop

```dart
class PlatformSupport {
  static bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  static bool get canCropImage => kIsWeb || Platform.isAndroid || Platform.isIOS;
  static bool get canScanCamera => kIsWeb || Platform.isAndroid || Platform.isIOS;
}
```

| Capacidade | Mobile/Web | Desktop | Degradação |
|---|---|---|---|
| `image_cropper` | OK | sem suporte | pula o recorte, usa a imagem original sem editar |
| `mobile_scanner` (câmera/QR) | OK | sem suporte | oferece digitação manual do código em vez de câmera |
| `firebase_messaging` (FCM) | OK (guardado por `isMobile` em `main.dart`) | **ausente em todo desktop** | o PC de balcão não recebe push; lê o Firestore por stream em vez disso |
| Orientação travada (`setPreferredOrientations`) | portrait mobile | não aplicado (`isMobile` guard em `main.dart:124`) | janela livre no desktop |

`main.dart` já guarda os três pontos historicamente frágeis (confirmados no
código, não hipotéticos):
`final isMobile = Platform.isAndroid || Platform.isIOS;` guarda tanto o init
do FCM (`if (isMobile && !Platform.isIOS) await pushNotificationService.initialize();`)
quanto `setPreferredOrientations`. `firebase_options.dart` (em
`lib/core/firebase_options.dart`) já tem blocos reais para `TargetPlatform.macOS`
e `TargetPlatform.windows` (gerados via `flutterfire configure`) — só
`TargetPlatform.linux` ainda lança `UnsupportedError`.

### Cautela: Firestore no Windows é dev-only segundo o FlutterFire

O suporte oficial do plugin `cloud_firestore` para Windows é documentado como
**"not intended for production use cases, only local development workflows"**.
Na prática: **leituras diretas do Firestore no Windows são aceitáveis** para
telas de baixo risco (painel/streams), mas **qualquer escrita autoritativa
deve ir por Cloud Function** (via `Fns`, nunca `FirebaseFirestore.instance` de
dentro de um build Windows de produção) — é o mesmo padrão que o
[`catraca-gateway`](CATRACA_GATEWAY.md) e a [ingestão de catracas](CATRACAS.md)
já seguem (Admin SDK server-side, nunca o cliente Firestore do device). `macOS`
é tratado como produção-OK pelo FlutterFire; `Windows` exige mais cautela —
ainda não passou por um soak test de listeners long-lived em produção.

## 3. Como baixar o artefato e rodar

1. Aba **Actions** do repositório → workflow **"Build Windows (.exe)"**.
2. Botão **"Run workflow"** (branch `b2c`) → aguarde ~10–20 min.
3. Baixe o artefato **`graduabjj-windows`** (zip) na página do run concluído.
4. Extraia o zip **inteiro** numa pasta e rode `graduabjj.exe`.

> **Importante:** mantenha `graduabjj.exe` **junto** das DLLs e da pasta
> `data/` que vêm no mesmo zip — não mova só o `.exe` para outro lugar. O
> Flutter Windows runner depende desses arquivos ao lado do executável
> (`flutter_windows.dll`, plugins nativos compilados, os assets em `data/`).
> Rodar o `.exe` isolado falha silenciosamente ou trava no boot.

## 4. O que AINDA FALTA para distribuição real (status honesto)

Hoje o pipeline produz **só um zip cru** anexado ao run do Actions. Não existe
nenhuma das peças abaixo — nenhuma delas está mesmo parcialmente feita:

| Peça | Status | Observação |
|---|---|---|
| Instalador (Inno Setup ou MSIX) | ❌ não existe | hoje é "extrair zip e rodar", sem atalho de Menu Iniciar, sem desinstalador |
| Assinatura de código / SmartScreen | ❌ não existe | o `.exe` não é assinado — Windows SmartScreen vai alertar "editor desconhecido" no primeiro clique; precisa de um certificado de assinatura de código (custo recorrente) + `signtool` no workflow |
| Publicação em GitHub Release | ❌ não existe | o artefato só vive nos 30 dias de retenção do Actions; não há passo de `gh release create` automatizado |
| Auto-update | ❌ não existe | nenhum mecanismo tipo `auto_updater`/WinSparkle + `appcast.xml`; cada atualização hoje é manual (baixar zip novo do Actions e substituir a pasta) |
| Instalação como serviço/tarefa 24/7 | ❌ não existe **para o app Flutter** | o `catraca-gateway` (projeto irmão) **já tem** isso via `scripts/install-task.ps1` — ver [CATRACA_GATEWAY.md](CATRACA_GATEWAY.md); o app Flutter em si ainda não |

Este é o estado real documentado no plano `docs/PLANO_DESKTOP_HARDWARE_2026-06.md`
(fase F0/F1 concluídas: plataformas habilitadas, guardas de plataforma,
camada responsiva; empacotamento/assinatura/auto-update são fases
posteriores, ainda não iniciadas).

## 5. Troubleshooting

- **`Compatibility with CMake < 3.5 has been removed`** — a env
  `CMAKE_POLICY_VERSION_MINIMUM` não foi aplicada (ex.: rodando localmente
  sem setá-la). No CI já está fixada no `windows.yml`; localmente, exporte a
  mesma variável antes de `flutter build windows`.
- **App não abre / fecha sozinho ao rodar `graduabjj.exe`** — quase sempre é
  o `.exe` foi movido sem as DLLs/`data/` ao lado (ver seção 3). Extraia o
  zip de novo, inteiro, numa pasta nova.
- **`flutter analyze` "falhou" no log do Actions mas o build continuou** —
  esperado. O passo de analyze é `continue-on-error: true` de propósito; olhe
  o passo "Build Windows (release)" para saber se o `.exe` de fato foi gerado.
- **Login/Firestore instável no Windows** — suporte do FlutterFire para
  Windows é dev-only (ver seção 2); se aparecer um problema de sessão/auth
  persistindo entre execuções, é uma lacuna conhecida, não uma regressão —
  documentado como risco aberto em `docs/PLANO_DESKTOP_HARDWARE_2026-06.md`
  (fase F0), ainda sem soak test de produção.
- **Push/notificação nunca chega no PC de balcão** — esperado, por design:
  FCM não existe em nenhum desktop. O padrão adotado é o PC ler o Firestore
  por stream, não receber push.
- **Câmera/scanner de QR não abre no Windows** — esperado
  (`PlatformSupport.canScanCamera == false` em desktop); a tela correspondente
  deve oferecer entrada manual do código como alternativa.
- **Workflow não dispara em push** — confira se o push foi na branch `b2c` e
  se o diff tocou algum dos paths filtrados (`lib/**`, `windows/**`,
  `pubspec.yaml`, `pubspec.lock`, o próprio workflow). Push em outra branch
  não dispara automaticamente — use `workflow_dispatch` manual.
