import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'api/feature_flags.dart';
import 'core/firebase_options.dart';
import 'core/theme.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Firestore offline persistence — mantido apenas enquanto chamadas
  // residuais ao Firestore sobrevivem (auth fallback global_user, models
  // como Timestamp helpers, retention/billing services). Pós-Fase 3 +
  // wiring completo dos services Firestore restantes, este bloco e o
  // import de cloud_firestore podem sair de main.dart.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

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

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Pós-Fase 1: Tatami é o único path e o `tatamiFlagsProvider` é um shim
  // @Deprecated (tudo já default `true`). Mantemos o bootstrap via Remote
  // Config para o caso de operacional querer DESLIGAR explicitamente um
  // grupo em produção (ex.: rollback emergencial após bug regressão).
  // Qualquer falha continua silenciosamente — defaults são allOn agora.
  final container = ProviderContainer();
  await _hydrateTatamiFlags(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GraduaBJJApp(),
    ),
  );

  // Check for mandatory app update (Android only)
  _checkForImmediateUpdate();
}

/// Lê os 8 bits de Remote Config e aplica em [tatamiFlagsProvider].
///
/// **Pós-Fase 1**: defaults agora são `true` (Tatami é o único path). Este
/// hidrate sobrescreve só os bits que estiverem `false` no Remote Config —
/// caminho usado em emergência para forçar rollback de um contexto
/// específico sem deploy. Qualquer falha (offline, timeout) é silenciosa;
/// a app boota com tudo ligado como padrão.
Future<void> _hydrateTatamiFlags(ProviderContainer container) async {
  // ignore: deprecated_member_use_from_same_package
  try {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 1),
      ),
    );
    // Defaults pós-migração: tudo ligado. Operacional só baixa um bit para
    // `false` no Remote Config em caso de rollback emergencial.
    await rc.setDefaults(const <String, dynamic>{
      'useTatamiIdentity': true,
      'useTatamiReads': true,
      'useTatamiWrites': true,
      'useTatamiFinancials': true,
      'useTatamiAttendance': true,
      'useTatamiNotifications': true,
      'useTatamiStore': true,
      'useTatamiCompetitions': true,
    });
    await rc.fetchAndActivate();

    container.read(tatamiFlagsProvider.notifier).state = TatamiFlags(
      useTatamiIdentity: rc.getBool('useTatamiIdentity'),
      useTatamiReads: rc.getBool('useTatamiReads'),
      useTatamiWrites: rc.getBool('useTatamiWrites'),
      useTatamiFinancials: rc.getBool('useTatamiFinancials'),
      useTatamiAttendance: rc.getBool('useTatamiAttendance'),
      useTatamiNotifications: rc.getBool('useTatamiNotifications'),
      useTatamiStore: rc.getBool('useTatamiStore'),
      useTatamiCompetitions: rc.getBool('useTatamiCompetitions'),
    );
  } catch (_) {
    // Silently fall through with TatamiFlags.allOn — Tatami é o único path
    // mesmo quando Remote Config está inacessível.
  }
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
