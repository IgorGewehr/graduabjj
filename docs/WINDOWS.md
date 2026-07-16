# GraduaBJJ no Windows (app de balcão / desktop)

O app roda em Windows 10/11 (x64) como executável nativo — pensado para o **PC
de recepção da academia** (balcão), integração com **catraca/leitor** e uso
administrativo. Os apps mobile (Android/iOS) **não mudam**: toda a
compatibilização desktop é aditiva e guardada por plataforma.

## O que muda no Windows (e por quê)

| Recurso | Mobile | Windows | Como |
|---|---|---|---|
| Cloud Functions | plugin `cloud_functions` | HTTP direto (ID token) | `lib/services/fns.dart` — `cloud_functions` não tem Windows; no desktop chamamos o endpoint HTTPS da função com o mesmo protocolo callable. Mobile segue passthrough (intocado). |
| Push (FCM) | ligado | desligado | `firebase_messaging` não tem desktop; balcão lê o Firestore por stream. Guardado em `main.dart`. |
| Leitura de QR (câmera) | `mobile_scanner` | indisponível | Sem câmera no desktop → tela mostra fallback ("use a catraca/leitor"). Guardado por `PlatformSupport.canScanCamera`. |
| Recorte de imagem | `image_cropper` | usa a imagem original | `image_cropper` não tem Windows → no desktop pula o recorte. Guardado por `PlatformSupport.canCropImage`. |
| In-app update | Play Store | n/a | Só Android. |

Firestore, Auth e Storage funcionam no Windows normalmente (FlutterFire tem
suporte desktop). A config fica em `lib/core/firebase_options.dart` (`windows`).

## Opção A — Baixar o .exe pronto (GitHub Actions, sem instalar nada)

1. No repositório → aba **Actions** → workflow **"Build Windows (.exe)"**.
2. **Run workflow** (branch `b2c`) e aguarde ~10–20 min.
3. Baixe o artefato **`graduabjj-windows`** (zip).
4. Extraia e rode **`graduabjj.exe`**.
   > Mantenha o `.exe` **junto** das DLLs e da pasta `data/`. Não mova só o
   > executável — ele precisa dos arquivos ao lado.

O workflow também roda sozinho a cada push na `b2c` que toque em código/pubspec.

## Opção B — Compilar localmente no PC Windows

Pré-requisitos: Windows 10/11 x64, **Flutter 3.41.5 (stable)**, **Visual Studio
2022** com o workload *"Desktop development with C++"*.

```powershell
git clone https://github.com/IgorGewehr/graduabjj.git
cd graduabjj
git checkout b2c
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release
# saída: build\windows\x64\runner\Release\graduabjj.exe
```

Para desenvolver/rodar direto: `flutter run -d windows`.

## Catraca / controle de acesso (Control iD Face)

A presença por catraca espelha o check-in por QR: o aluno é reconhecido pela
face na catraca → a Cloud Function `ingestAccessEvent` marca presença na turma
ativa e libera o giro. Detalhes de configuração do device em
`functions/access_control/README.md`. Não exige o app Windows — a catraca fala
direto com a função na nuvem — mas o balcão Windows é onde a academia
gerencia/monitora tudo.
