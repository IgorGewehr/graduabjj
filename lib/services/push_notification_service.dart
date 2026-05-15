/// Push Notification Service - disabled
/// Push notifications are not active in this build.
class PushNotificationService {
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  String? get fcmToken => null;

  Future<void> initialize() async {}
  void setUserRole({required bool isAdmin}) {}
  Future<void> onUserLogin() async {}
  Future<void> onUserLogout() async {}
  Future<void> subscribeToTopic(String topic) async {}
  Future<void> unsubscribeFromTopic(String topic) async {}
}

/// Global instance
final pushNotificationService = PushNotificationService();
