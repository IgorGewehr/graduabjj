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
import 'services/push_notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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

  // Initialize Push Notifications
  await pushNotificationService.initialize();

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

  // Bootstrap Tatami feature flags from Remote Config BEFORE the app mounts.
  //
  // Pattern: build a standalone [ProviderContainer], hidrate
  // [tatamiFlagsProvider] from Remote Config, then hand the same container
  // to [UncontrolledProviderScope] so the running app inherits the resolved
  // flags on the very first frame (no "flag flip" mid-session).
  //
  // Any failure (offline, timeout, malformed values) is swallowed — the
  // container keeps the all-off default. Tatami paths stay dark, the app
  // boots on the legacy Firestore path. Operacional can re-flip when the
  // user is back online via the pull-to-refresh pattern documented in
  // docs/USING_TATAMI_REPOS.md §1.
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

/// Reads the eight Tatami flags from Firebase Remote Config and applies them
/// to [tatamiFlagsProvider] inside [container]. Defaults to all-off on any
/// error so an offline boot stays on the legacy path.
Future<void> _hydrateTatamiFlags(ProviderContainer container) async {
  try {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        // 1h is the recommended minimum for production — shorter intervals
        // are throttled by Firebase server-side. Operacional can force-fetch
        // via the Remote Config console for canary tests.
        minimumFetchInterval: const Duration(hours: 1),
      ),
    );
    await rc.setDefaults(const <String, dynamic>{
      'useTatamiIdentity': false,
      'useTatamiReads': false,
      'useTatamiWrites': false,
      'useTatamiFinancials': false,
      'useTatamiAttendance': false,
      'useTatamiNotifications': false,
      'useTatamiStore': false,
      'useTatamiCompetitions': false,
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
    // Silently fall through with TatamiFlags.allOff — the app must boot
    // even when Remote Config is unreachable (offline / first launch on
    // a flaky network / Firebase outage). Operacional sees the legacy
    // path; flags will hidrate on the next successful boot.
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
