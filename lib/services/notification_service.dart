import '../api/dto/notification_dto.dart' as api;
import '../api/notification_repo.dart';

/// Notification Type - matches types stored by webhook/Cloud Functions
enum NotificationType {
  system,
  paymentReceived,
  paymentPending,
  paymentOverdue,
  paymentDueSoon,
  orderPaid,
  withdrawalCompleted,
  withdrawalFailed,
  graduationEligible,
  graduationNear,
  newStudentLinked,
  studentMilestone,
  competitionReminder,
}

extension NotificationTypeExtension on NotificationType {
  String get value {
    switch (this) {
      case NotificationType.system:
        return 'system';
      case NotificationType.paymentReceived:
        return 'payment_received';
      case NotificationType.paymentPending:
        return 'payment_pending';
      case NotificationType.paymentOverdue:
        return 'payment_overdue';
      case NotificationType.paymentDueSoon:
        return 'payment_due_soon';
      case NotificationType.orderPaid:
        return 'order_paid';
      case NotificationType.withdrawalCompleted:
        return 'withdrawal_completed';
      case NotificationType.withdrawalFailed:
        return 'withdrawal_failed';
      case NotificationType.graduationEligible:
        return 'graduation_eligible';
      case NotificationType.graduationNear:
        return 'graduation_near';
      case NotificationType.newStudentLinked:
        return 'new_student_linked';
      case NotificationType.studentMilestone:
        return 'student_milestone';
      case NotificationType.competitionReminder:
        return 'competition_reminder';
    }
  }

  static NotificationType fromString(String value) {
    switch (value) {
      case 'payment_received':
        return NotificationType.paymentReceived;
      case 'payment_pending':
        return NotificationType.paymentPending;
      case 'payment_overdue':
        return NotificationType.paymentOverdue;
      case 'payment_due_soon':
        return NotificationType.paymentDueSoon;
      case 'order_paid':
        return NotificationType.orderPaid;
      case 'withdrawal_completed':
        return NotificationType.withdrawalCompleted;
      case 'withdrawal_failed':
        return NotificationType.withdrawalFailed;
      case 'graduation_eligible':
        return NotificationType.graduationEligible;
      case 'graduation_near':
        return NotificationType.graduationNear;
      case 'new_student_linked':
        return NotificationType.newStudentLinked;
      case 'student_milestone':
        return NotificationType.studentMilestone;
      case 'competition_reminder':
        return NotificationType.competitionReminder;
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

  /// Sprint 6 wiring — adapter `ApiNotification` → `AppNotification` legacy.
  ///
  /// Mapeamento de tipos (Tatami catálogo vs legacy):
  /// - payment_due       → paymentPending  (Tatami unifica 3 estados em 1)
  /// - payment_paid      → paymentReceived
  /// - payment_overdue   → paymentOverdue
  /// - graduation_eligible → graduationEligible
  /// - graduation_promoted → studentMilestone
  /// - competition_announcement → competitionReminder
  /// - competition_enrollment → competitionReminder
  /// - store_order_update → orderPaid
  /// - generic           → system
  ///
  /// Priority não vem do Tatami (não foi modelada) — sempre `normal`.
  /// Channels: Tatami expõe inbox/push/whatsapp/email; legacy só sabe
  /// `in_app` e `push` — projetamos via `.name`.
  factory AppNotification.fromApi(api.ApiNotification n) {
    return AppNotification(
      id: n.id,
      userId: n.recipientUid,
      type: _typeFromApi(n.type),
      priority: NotificationPriority.normal,
      title: n.title,
      message: n.body ?? '',
      actionUrl: n.actionUrl,
      studentId: n.metadata?['student_id'] as String?,
      financialId: n.metadata?['financial_id'] as String?,
      competitionId: n.metadata?['competition_id'] as String?,
      read: n.isRead,
      readAt: n.readAt,
      channels: n.channels.map((c) => c.name).toList(),
      createdAt: n.createdAt,
    );
  }

  static NotificationType _typeFromApi(api.ApiNotificationType t) {
    switch (t) {
      case api.ApiNotificationType.payment_due:
        return NotificationType.paymentPending;
      case api.ApiNotificationType.payment_paid:
        return NotificationType.paymentReceived;
      case api.ApiNotificationType.payment_overdue:
        return NotificationType.paymentOverdue;
      case api.ApiNotificationType.graduation_eligible:
        return NotificationType.graduationEligible;
      case api.ApiNotificationType.graduation_promoted:
        return NotificationType.studentMilestone;
      case api.ApiNotificationType.competition_announcement:
      case api.ApiNotificationType.competition_enrollment:
        return NotificationType.competitionReminder;
      case api.ApiNotificationType.store_order_update:
        return NotificationType.orderPaid;
      case api.ApiNotificationType.generic:
        return NotificationType.system;
    }
  }

  // Computed properties
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isUnread => !read && !isExpired;
}

/// Notification Service - wraps NotificationRemoteRepo for legacy callers.
///
/// All Firestore operations have been replaced with HTTP calls via
/// [NotificationRemoteRepo]. The [academyId] is forwarded as a filter
/// on endpoints that support it.
class NotificationService {
  final String academyId;
  final NotificationRemoteRepo _repo;

  NotificationService(this.academyId, this._repo);

  // ============================================
  // Get User Notifications (One-time fetch)
  // ============================================
  Future<List<AppNotification>> getByUser(String userId, {int limit = 50}) async {
    final page = await _repo.list(
      filter: api.NotificationsFilter(
        academyId: academyId,
        limit: limit,
      ),
    );
    return page.items
        .map(AppNotification.fromApi)
        .where((n) => !n.isExpired)
        .toList();
  }

  // ============================================
  // Stream User Notifications (Real-time updates)
  //
  // Tatami expõe SSE via NotificationRemoteRepo.streamNotifications().
  // Aqui convertemos o stream SSE (List<ApiNotification>) em
  // Stream<List<AppNotification>> para consumo legado.
  // ============================================
  Stream<List<AppNotification>> streamByUser(String userId, {int limit = 50}) {
    return _repo.streamNotifications().map(
          (batch) => batch
              .map(AppNotification.fromApi)
              .where((n) => !n.isExpired)
              .toList(),
        );
  }

  // ============================================
  // Get Unread Count (One-time fetch)
  // ============================================
  Future<int> getUnreadCount(String userId) async {
    return _repo.getUnreadCount(academyId: academyId);
  }

  // ============================================
  // Stream Unread Count (Real-time updates via polling)
  //
  // O Tatami não expõe um stream de contagem dedicado. Fazemos polling
  // a cada 30s como substituto leve; SSE poderia ser usada em sprint
  // posterior para reduzir latência.
  // ============================================
  Stream<int> streamUnreadCount(String userId) {
    return Stream.periodic(const Duration(seconds: 30)).asyncMap(
      (_) => _repo.getUnreadCount(academyId: academyId),
    );
  }

  // ============================================
  // Mark as Read
  // ============================================
  Future<void> markAsRead(String notificationId) async {
    await _repo.markRead(notificationId, read: true);
  }

  // ============================================
  // Mark All as Read
  // ============================================
  Future<void> markAllAsRead(String userId) async {
    await _repo.markAllRead(academyId: academyId);
  }

  // ============================================
  // Delete Notification
  // ============================================
  Future<void> delete(String notificationId) async {
    await _repo.delete(notificationId);
  }

  // ============================================
  // Get Recent Notifications
  // ============================================
  Future<List<AppNotification>> getRecent(String userId, {int limit = 5}) async {
    return getByUser(userId, limit: limit);
  }

  // ============================================
  // Create Notification
  //
  // Notificações individuais são criadas pelo backend como efeito colateral
  // de eventos de domínio. Para criar de forma programática (ex.: admin),
  // use NotificationRemoteRepo.broadcast() com um filtro de recipient_uid.
  //
  // Esta implementação faz broadcast para um único usuário via
  // POST /v1/academies/{id}/notifications/broadcast.
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
    // Map legacy type to nearest Tatami type.
    final apiType = _legacyTypeToApi(type);

    final meta = <String, dynamic>{};
    if (studentId != null) meta['student_id'] = studentId;
    if (financialId != null) meta['financial_id'] = financialId;
    if (competitionId != null) meta['competition_id'] = competitionId;

    final req = api.BroadcastRequest(
      type: apiType,
      title: title,
      body: message,
      actionUrl: actionUrl,
      metadata: meta.isEmpty ? null : meta,
      recipients: api.BroadcastRecipientsFilter(includeUids: [userId]),
    );

    await _repo.broadcast(academyId, req);

    // The broadcast endpoint returns a BroadcastResponse (id + count), not
    // the created notification itself. We synthesize a local AppNotification
    // so that callers that use the return value keep working.
    return AppNotification(
      id: '',
      userId: userId,
      type: type,
      priority: priority,
      title: title,
      message: message,
      actionUrl: actionUrl,
      actionLabel: actionLabel,
      studentId: studentId,
      financialId: financialId,
      competitionId: competitionId,
      read: false,
      channels: const ['in_app'],
      createdAt: DateTime.now(),
      expiresAt: expiresInDays != null
          ? DateTime.now().add(Duration(days: expiresInDays))
          : null,
    );
  }

  static api.ApiNotificationType _legacyTypeToApi(NotificationType t) {
    switch (t) {
      case NotificationType.paymentPending:
      case NotificationType.paymentDueSoon:
        return api.ApiNotificationType.payment_due;
      case NotificationType.paymentReceived:
        return api.ApiNotificationType.payment_paid;
      case NotificationType.paymentOverdue:
        return api.ApiNotificationType.payment_overdue;
      case NotificationType.graduationEligible:
      case NotificationType.graduationNear:
        return api.ApiNotificationType.graduation_eligible;
      case NotificationType.studentMilestone:
        return api.ApiNotificationType.graduation_promoted;
      case NotificationType.competitionReminder:
        return api.ApiNotificationType.competition_announcement;
      case NotificationType.orderPaid:
        return api.ApiNotificationType.store_order_update;
      case NotificationType.newStudentLinked:
      case NotificationType.withdrawalCompleted:
      case NotificationType.withdrawalFailed:
      case NotificationType.system:
        return api.ApiNotificationType.generic;
    }
  }
}

// ============================================
// Factory Function
// ============================================
NotificationService createNotificationService(
  String academyId,
  NotificationRemoteRepo repo,
) {
  return NotificationService(academyId, repo);
}

// ============================================
// Default Instance (uses current academy)
//
// NOTE: requires a NotificationRemoteRepo — callers that previously used
// `notificationService` as a top-level getter should instead obtain
// NotificationService via a Riverpod provider or pass the repo explicitly.
// This factory is kept for legacy call-sites during incremental migration.
// ============================================
NotificationService buildNotificationService(
  String academyId,
  NotificationRemoteRepo repo,
) =>
    NotificationService(academyId, repo);
