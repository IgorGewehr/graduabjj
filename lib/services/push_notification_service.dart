import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/navigator_key.dart';

/// Background message handler. MUST be a top-level / static function annotated
/// with `@pragma('vm:entry-point')`. We don't need to do work here — when the
/// app is backgrounded/terminated the OS shows the notification from the
/// `notification` payload automatically; the tap is handled on resume.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Real FCM push (A2/F2). The Cloud Functions already send to
/// `users/{uid}/fcmTokens/*` (doc id == token); this registers/cleans those
/// tokens and routes taps to `data.actionUrl`. Same public interface as the
/// previous stub, so the existing call sites (main.dart, auth_provider) work.
class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _fcmToken;
  bool _initialized = false;

  String? get fcmToken => _fcmToken;

  /// One-time setup (called from main, before auth). Safe to call without a
  /// logged-in user; token persistence happens on [onUserLogin].
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      await _messaging.requestPermission(
          alert: true, badge: true, sound: true);

      // iOS: also surface notifications while the app is in the foreground.
      await _messaging.setForegroundNotificationPresentationOptions(
          alert: true, badge: true, sound: true);

      // Tap handling (warm start + cold start).
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTapNavigation);
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _handleTapNavigation(initial);

      // Keep the stored token fresh.
      _messaging.onTokenRefresh.listen((t) {
        _fcmToken = t;
        _saveToken(t);
      });
    } catch (e) {
      debugPrint('[push] initialize error: $e');
    }
  }

  /// Fetch the device token and persist it under the signed-in user.
  Future<void> onUserLogin() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        _fcmToken = token;
        await _saveToken(token);
      }
    } catch (e) {
      debugPrint('[push] onUserLogin error: $e');
    }
  }

  /// Remove this device's token so a logged-out device stops receiving push.
  Future<void> onUserLogout() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final token = _fcmToken ?? await _messaging.getToken();
      if (uid != null && token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('fcmTokens')
            .doc(token)
            .delete();
      }
    } catch (e) {
      debugPrint('[push] onUserLogout error: $e');
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
    } catch (e) {
      debugPrint('[push] subscribeToTopic error: $e');
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
    } catch (e) {
      debugPrint('[push] unsubscribeFromTopic error: $e');
    }
  }

  /// Kept for interface compatibility (no role-based topics for now).
  void setUserRole({required bool isAdmin}) {}

  Future<void> _saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(token) // doc id == token (matches the server's cleanup path)
        .set({
      'token': token,
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Routes a tapped notification to its `data.actionUrl` (e.g. '/portal/...').
  void _handleTapNavigation(RemoteMessage message) {
    final url = message.data['actionUrl'];
    if (url is! String || url.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      try {
        GoRouter.of(ctx).go(url);
      } catch (e) {
        debugPrint('[push] navigation error: $e');
      }
    });
  }
}

/// Global instance.
final pushNotificationService = PushNotificationService();
