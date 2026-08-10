import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/firebase_options.dart';
import 'core/theme.dart';
import 'services/push_notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Safety-net (hotfix tela-branca): qualquer exceção não capturada num build de
  // widget vira uma tela de erro AMIGÁVEL em vez do retângulo cinza/branco padrão
  // do Flutter em release. Evita que uma falha numa tela deixe o usuário olhando
  // para o nada após o login.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // Observabilidade: registra o erro (console + onError/Crashlytics) ANTES de
    // mostrar o card — senão crashes determinísticos de build ficam invisíveis.
    FlutterError.presentError(details);
    return Material(
      color: const Color(0xFFF7F7F7),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.error_outline, size: 48, color: Color(0xFF991B1B)),
              SizedBox(height: 16),
              Text(
                'Algo deu errado ao carregar esta tela.\n'
                'Feche e abra o app novamente.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Color(0xFF333333)),
              ),
            ],
          ),
        ),
      ),
    );
  };

  // Plataformas mobile (Android/iOS) vs desktop (Windows/macOS). Vários serviços
  // são mobile-only e ficam guardados por isto: FCM/firebase_messaging (sem
  // suporte em desktop), orientação travada e in-app update.
  final isMobile = Platform.isAndroid || Platform.isIOS;

  // Initialize Firebase.
  // No ANDROID o FirebaseInitProvider (via google-services.json) AUTO-inicializa
  // o app [DEFAULT] ANTES do main() → chamar initializeApp de novo lançava
  // [core/duplicate-app] e CRASHAVA no boot (só no Android; iOS não tem auto-
  // init). Nesse instante o Firebase.apps do lado Dart ainda está VAZIO (não
  // enxerga o app criado nativamente), então um guard por isEmpty não basta —
  // por isso engolimos especificamente o duplicate-app (o app nativo já existe
  // e é válido). Qualquer outro erro de init continua propagando.
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }

  // Enable Firestore offline persistence (Sprint 5).
  //
  // Once enabled, every Firestore read is served first from the local SQLite
  // cache and then refreshed from the network in the background. This makes
  // navigation between screens feel instantaneous after the first session,
  // and keeps the app usable without connectivity.
  //
  // CACHE_SIZE_UNLIMITED is safe on mobile because Firestore garbage-collects
  // least-recently-used entries when the device is under storage pressure.
  // If a user reports "stale data", they can force a refresh via the existing
  // pull-to-refresh affordance which calls `ref.invalidate(...)` and bypasses
  // cache via `Source.server`. Reinstalling the app also wipes the cache.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Initialize Push Notifications — FCM só existe em mobile (firebase_messaging
  // não tem desktop). No desktop o PC de balcão lê o Firestore por stream.
  //
  // ANDROID: init síncrono aqui mesmo, ANTES do runApp — comportamento
  // INALTERADO desde sempre (é o caminho estável; a mudança de timing feita
  // pro iOS abaixo não pode atrasar nem arriscar este bloco).
  //
  // iOS (TAREFA 2, jul/2026 — religando após o hotfix do commit 1ddf1e7): o
  // firebase_messaging crasha NATIVAMENTE no init em iOS 26 — crash nativo,
  // então o try/catch Dart de initialize() NÃO pega, e por isso o commit
  // 1ddf1e7 desligou o FCM inteiramente no iOS pra estancar o crash 100% no
  // boot. Em vez de manter desligado pra sempre, o init agora roda DEFERIDO
  // pra depois do 1º frame (bloco após runApp, mais abaixo), atrás de um
  // kill-switch remoto cacheado (appConfig/flags.fcmIosEnabled — ver
  // push_notification_service.dart) que permite desligar de novo, em
  // produção e sem nova build, se o crash reaparecer em campo.
  if (isMobile && !Platform.isIOS) {
    await pushNotificationService.initialize();
  }

  // Initialize date formatting for pt_BR
  await initializeDateFormatting('pt_BR', null);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Set preferred orientations (mobile-only; no desktop a janela é livre)
  if (isMobile) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  runApp(coanst ProviderScope(child: GraduaBJJApp()));

  // TAREFA 2 (iOS): init do FCM deferido pra depois do 1º frame — se o
  // crash nativo do plugin (ver comentário acima) voltar a acontecer, o
  // usuário já viu a UI renderizada (splash/portal) em vez de tela branca
  // instantânea no boot. A leitura que decide o boot ATUAL é só o cache
  // local (SharedPreferences, síncrono-rápido) — NUNCA o Firestore, que só
  // entra depois, em background, pra preparar o PRÓXIMO boot (ver a
  // máquina de estados documentada em iosKillSwitchCachedValue()).
  if (isMobile && Platform.isIOS) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final enabled = await pushNotificationService.iosKillSwitchCachedValue();
      if (enabled) {
        await pushNotificationService.initialize();
        // TAREFA 1 (token em toda abertura autenticada): a sessão pode já
        // estar autenticada por restore/silent-login do FirebaseAuth — reusa
        // o MESMO caminho idempotente do login (auth_provider.dart) em vez
        // de depender só do listener genérico do router (app.dart), que
        // pode ter rodado ANTES do FCM terminar de inicializar aqui (no iOS
        // o init só começa depois do 1º frame, então há uma corrida real).
        if (FirebaseAuth.instance.currentUser != null) {
          await pushNotificationService.onUserLogin();
        }
      }
      // Nunca aguardado pelo boot atual: só prepara o cache pro PRÓXIMO
      // processo (ver syncIosKillSwitchInBackground).
      unawaited(pushNotificationService.syncIosKillSwitchInBackground());
    });
  }

  // Check for mandatory app update (Android only)
  _checkForImmediateUpdate();
}

Future<void> _checkForImmediateUpdate() async {
  if (!Platform.isAndroid) return;
  try {
    final info = await InAppUpdate.checkForUpdate();
    if (info.updateAvailability == UpdateAvailability.updateAvailable &&
        info.immediateUpdateAllowed) {
      await InAppUpdate.performImmediateUpdate();
    }
  } catch (_) {
    // Silently ignore - debug build, sideloaded, or no Play Store
  }
}
