import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
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

  runApp(const ProviderScope(child: GraduaBJJApp()));

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
