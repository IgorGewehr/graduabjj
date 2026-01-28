import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_service.dart';

/// Notification Type
enum NotificationType {
  system,
  financial,
  graduation,
  competition,
  achievement,
  attendance,
  announcement,
}

extension NotificationTypeExtension on NotificationType {
  String get value {
    switch (this) {
      case NotificationType.system:
        return 'system';
      case NotificationType.financial:
        return 'financial';
      case NotificationType.graduation:
        return 'graduation';
      case NotificationType.competition:
        return 'competition';
      case NotificationType.achievement:
        return 'achievement';
      case NotificationType.attendance:
        return 'attendance';
      case NotificationType.announcement:
        return 'announcement';
    }
  }

  static NotificationType fromString(String value) {
    switch (value) {
      case 'financial':
        return NotificationType.financial;
      case 'graduation':
        return NotificationType.graduation;
      case 'competition':
        return NotificationType.competition;
      case 'achievement':
        return NotificationType.achievement;
      case 'attendance':
        return NotificationType.attendance;
      case 'announcement':
        return NotificationType.announcement;
      default:
        return NotificationType.system;
    }
  }
}

/// Notification Priority
enum NotificationPriority { low, normal, high, urgent }

extension NotificationPriorityExtension on NotificationPriority {
  String get value {
    switch (this) {
      case NotificationPriority.low:
        return 'low';
      case NotificationPriority.normal:
        return 'normal';
      case NotificationPriority.high:
        return 'high';
      case NotificationPriority.urgent:
        return 'urgent';
    }
  }

  static NotificationPriority fromString(String value) {
    switch (value) {
      case 'low':
        return NotificationPriority.low;
      case 'high':
        return NotificationPriority.high;
      case 'urgent':
        return NotificationPriority.urgent;
      default:
        return NotificationPriority.normal;
    }
  }
}

/// Notification Model
class AppNotification {
  final String id;
  final String userId;
  final NotificationType type;
  final NotificationPriority priority;
  final String title;
  final String message;
  final String? imageUrl;
  final String? actionUrl;
  final String? actionLabel;
  final String? studentId;
  final String? financialId;
  final String? competitionId;
  final bool read;
  final DateTime? readAt;
  final List<String> channels;
  final DateTime createdAt;
  final DateTime? expiresAt;

  AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    this.priority = NotificationPriority.normal,
    required this.title,
    required this.message,
    this.imageUrl,
    this.actionUrl,
    this.actionLabel,
    this.studentId,
    this.financialId,
    this.competitionId,
    this.read = false,
    this.readAt,
    this.channels = const ['in_app'],
    required this.createdAt,
    this.expiresAt,
  });

  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppNotification(
      id: doc.id,
      userId: data['userId'] ?? '',
      type: NotificationTypeExtension.fromString(data['type'] ?? 'system'),
      priority: NotificationPriorityExtension.fromString(data['priority'] ?? 'normal'),
      title: data['title'] ?? '',
      message: data['message'] ?? '',
      imageUrl: data['imageUrl'],
      actionUrl: data['actionUrl'],
      actionLabel: data['actionLabel'],
      studentId: data['studentId'],
      financialId: data['financialId'],
      competitionId: data['competitionId'],
      read: data['read'] ?? false,
      readAt: data['readAt'] != null
          ? (data['readAt'] as Timestamp).toDate()
          : null,
      channels: data['channels'] != null
          ? List<String>.from(data['channels'])
          : ['in_app'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: data['expiresAt'] != null
          ? (data['expiresAt'] as Timestamp).toDate()
          : null,
    );
  }

  // Computed properties
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isUnread => !read && !isExpired;
}

/// Notification Service - Multi-tenant notification management
class NotificationService {
  final String academyId;
  late final Collections _collections;

  NotificationService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _notificationsRef => _collections.notifications;

  // ============================================
  // Get User Notifications (One-time fetch)
  // ============================================
  Future<List<AppNotification>> getByUser(String userId, {int limit = 50}) async {
    final query = await _notificationsRef
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return query.docs
        .map((doc) => AppNotification.fromFirestore(doc))
        .where((n) => !n.isExpired)
        .toList();
  }

  // ============================================
  // Stream User Notifications (Real-time updates)
  // ============================================
  Stream<List<AppNotification>> streamByUser(String userId, {int limit = 50}) {
    return _notificationsRef
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => AppNotification.fromFirestore(doc))
          .where((n) => !n.isExpired)
          .toList();
    });
  }

  // ============================================
  // Get Unread Count (One-time fetch)
  // ============================================
  Future<int> getUnreadCount(String userId) async {
    final query = await _notificationsRef
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();

    return query.docs
        .map((doc) => AppNotification.fromFirestore(doc))
        .where((n) => !n.isExpired)
        .length;
  }

  // ============================================
  // Stream Unread Count (Real-time updates)
  // ============================================
  Stream<int> streamUnreadCount(String userId) {
    return _notificationsRef
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => AppNotification.fromFirestore(doc))
          .where((n) => !n.isExpired)
          .length;
    });
  }

  // ============================================
  // Mark as Read
  // ============================================
  Future<void> markAsRead(String notificationId) async {
    await _notificationsRef.doc(notificationId).update({
      'read': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================
  // Mark All as Read
  // ============================================
  Future<void> markAllAsRead(String userId) async {
    final query = await _notificationsRef
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();

    for (final doc in query.docs) {
      await doc.reference.update({
        'read': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ============================================
  // Delete Notification
  // ============================================
  Future<void> delete(String notificationId) async {
    await _notificationsRef.doc(notificationId).delete();
  }

  // ============================================
  // Get Recent Notifications
  // ============================================
  Future<List<AppNotification>> getRecent(String userId, {int limit = 5}) async {
    return getByUser(userId, limit: limit);
  }

  // ============================================
  // Create Notification
  // ============================================
  Future<AppNotification> create({
    required String userId,
    required NotificationType type,
    required String title,
    required String message,
    NotificationPriority priority = NotificationPriority.normal,
    String? actionUrl,
    String? actionLabel,
    String? studentId,
    String? financialId,
    String? competitionId,
    int? expiresInDays,
  }) async {
    final expiresAt = expiresInDays != null
        ? DateTime.now().add(Duration(days: expiresInDays))
        : null;

    final data = <String, dynamic>{
      'academyId': academyId,
      'userId': userId,
      'type': type.value,
      'priority': priority.value,
      'title': title,
      'message': message,
      'read': false,
      'channels': ['in_app'],
      'sentVia': ['in_app'],
      'createdAt': FieldValue.serverTimestamp(),
    };

    // Only add optional fields if they have values
    if (actionUrl != null) data['actionUrl'] = actionUrl;
    if (actionLabel != null) data['actionLabel'] = actionLabel;
    if (studentId != null) data['studentId'] = studentId;
    if (financialId != null) data['financialId'] = financialId;
    if (competitionId != null) data['competitionId'] = competitionId;
    if (expiresAt != null) data['expiresAt'] = Timestamp.fromDate(expiresAt);

    final docRef = await _notificationsRef.add(data);
    final doc = await docRef.get();

    return AppNotification.fromFirestore(doc);
  }
}

// ============================================
// Factory Function
// ============================================
NotificationService createNotificationService(String academyId) {
  return NotificationService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
NotificationService get notificationService =>
    NotificationService(FirebaseService.academyId);
