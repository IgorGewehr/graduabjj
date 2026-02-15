import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import 'firebase_service.dart';
import '../app.dart'; // Import for navigatorKey

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handle background message
  print('Handling background message: ${message.messageId}');
}

/// Push Notification Service
/// Handles Firebase Cloud Messaging for push notifications
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _fcmToken;
  bool _isAdmin = false;

  /// Pending notification data to process after router is ready
  Map<String, dynamic>? _pendingNotificationData;

  String? get fcmToken => _fcmToken;

  /// Set user role for correct notification routing
  void setUserRole({required bool isAdmin}) {
    _isAdmin = isAdmin;
    // Process any pending notification now that we know the role
    _processPendingNotification();
  }

  /// Initialize push notifications
  Future<void> initialize() async {
    if (_initialized) return;

    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize local notifications
    await _initializeLocalNotifications();

    // Request permissions
    await _requestPermission();

    // Get FCM token
    await _getToken();

    // Listen for token refresh
    _messaging.onTokenRefresh.listen(_onTokenRefresh);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Check if app was opened from a notification (terminated state)
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      // Store pending data - will navigate after router and auth are ready
      _pendingNotificationData = Map<String, dynamic>.from(initialMessage.data);
      print('Initial notification stored for deferred navigation: ${initialMessage.data}');
    }

    _initialized = true;
    print('Push Notification Service initialized');
  }

  /// Initialize local notifications plugin
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channel for Android
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'high_importance_channel',
        'Notificações Importantes',
        description: 'Canal para notificações importantes do GraduaBJJ',
        importance: Importance.high,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  /// Request notification permissions
  Future<bool> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    print('Notification permission: ${settings.authorizationStatus}');
    return granted;
  }

  /// Get FCM token
  Future<String?> _getToken() async {
    try {
      _fcmToken = await _messaging.getToken();
      print('FCM Token: $_fcmToken');

      // Save token to Firestore if user is logged in
      if (_fcmToken != null) {
        await _saveTokenToFirestore(_fcmToken!);
      }

      return _fcmToken;
    } catch (e) {
      print('Error getting FCM token: $e');
      return null;
    }
  }

  /// Handle token refresh
  Future<void> _onTokenRefresh(String token) async {
    print('FCM Token refreshed: $token');
    _fcmToken = token;
    await _saveTokenToFirestore(token);
  }

  /// Save FCM token to Firestore
  Future<void> _saveTokenToFirestore(String token) async {
    final userId = FirebaseService.currentUserId;
    if (userId == null) return;

    try {
      // Save token to global user document
      await RootCollections.user(userId).collection('fcmTokens').doc(token).set({
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('FCM token saved to Firestore');
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  /// Remove FCM token from Firestore (on logout)
  Future<void> removeToken() async {
    final userId = FirebaseService.currentUserId;
    if (userId == null || _fcmToken == null) return;

    try {
      await RootCollections.user(userId)
          .collection('fcmTokens')
          .doc(_fcmToken)
          .delete();
      print('FCM token removed from Firestore');
    } catch (e) {
      print('Error removing FCM token: $e');
    }
  }

  /// Handle foreground messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('Foreground message received: ${message.messageId}');

    final notification = message.notification;
    if (notification != null) {
      // Serialize data as JSON so it can be parsed back on tap
      final payloadJson = jsonEncode(message.data);
      await _showLocalNotification(
        title: notification.title ?? 'GraduaBJJ',
        body: notification.body ?? '',
        payload: payloadJson,
      );
    }
  }

  /// Show local notification
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'high_importance_channel',
      'Notificações Importantes',
      channelDescription: 'Canal para notificações importantes do GraduaBJJ',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Handle notification tap when app in background
  void _handleNotificationTap(RemoteMessage message) {
    print('Notification tapped: ${message.data}');
    _navigateFromNotification(message.data);
  }

  /// Handle local notification tap (foreground notifications)
  void _onNotificationTap(NotificationResponse response) {
    print('Local notification tapped: ${response.payload}');
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    try {
      final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      _navigateFromNotification(data);
    } catch (e) {
      print('Error parsing local notification payload: $e');
    }
  }

  /// Process any pending notification that was deferred during app startup
  void _processPendingNotification() {
    if (_pendingNotificationData == null) return;

    final data = _pendingNotificationData!;
    _pendingNotificationData = null;

    // Wait a short time for the router to stabilize after auth redirect
    Future.delayed(const Duration(milliseconds: 500), () {
      _navigateFromNotification(data);
    });
  }

  /// Navigate based on notification data
  void _navigateFromNotification(Map<String, dynamic> data) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      print('Navigator context not available, storing as pending');
      _pendingNotificationData = Map<String, dynamic>.from(data);
      return;
    }

    final type = data['type'] as String?;
    final id = data['id'] as String?;
    final academyId = data['academyId'] as String?;

    print('Navigating from notification - type: $type, id: $id, academyId: $academyId, isAdmin: $_isAdmin');

    final prefix = _isAdmin ? '/admin' : '/portal';

    try {
      switch (type) {
        case 'financial':
        case 'payment_received':
        case 'payment_pending':
        case 'payment_overdue':
        case 'payment_due_soon':
          context.go('$prefix/financeiro');
          break;

        case 'competition':
        case 'competition_reminder':
          context.go(_isAdmin ? '/admin/campeonatos' : '/portal/competicoes');
          break;

        case 'achievement':
        case 'graduation':
        case 'belt_promotion':
        case 'student_milestone':
          context.go(_isAdmin ? '/admin/graduacao' : '/portal/linha-do-tempo');
          break;

        case 'store_order':
        case 'order_paid':
          context.go(_isAdmin ? '/admin/loja/pedidos' : '/portal/loja/pedidos');
          break;

        case 'withdrawal_completed':
        case 'withdrawal_failed':
          context.go('/admin/carteira');
          break;

        case 'new_student_linked':
          if (_isAdmin && id != null) {
            context.go('/admin/alunos/$id');
          } else {
            context.go(prefix);
          }
          break;

        default:
          print('Unknown notification type: $type, navigating to home');
          context.go(prefix);
      }
    } catch (e) {
      print('Error navigating from notification: $e');
      try {
        context.go(prefix);
      } catch (e2) {
        print('Failed to navigate to fallback route: $e2');
      }
    }
  }

  /// Update token when user logs in
  Future<void> onUserLogin() async {
    if (_fcmToken != null) {
      await _saveTokenToFirestore(_fcmToken!);
    }
  }

  /// Clean up when user logs out
  Future<void> onUserLogout() async {
    await removeToken();
    _isAdmin = false;
    _pendingNotificationData = null;
  }

  /// Subscribe to topic (e.g., academy-wide notifications)
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      print('Subscribed to topic: $topic');
    } catch (e) {
      print('Error subscribing to topic: $e');
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      print('Unsubscribed from topic: $topic');
    } catch (e) {
      print('Error unsubscribing from topic: $e');
    }
  }
}

/// Global instance
final pushNotificationService = PushNotificationService();
