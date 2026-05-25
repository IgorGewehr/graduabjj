import 'package:intl/intl.dart';

import 'notification_service.dart';
import 'firebase_service.dart';

/// Notification Dispatcher
/// Handles creating notifications and optionally sending push notifications
class NotificationDispatcher {
  final String academyId;
  late final NotificationService _notificationService;

  NotificationDispatcher(this.academyId) {
    _notificationService = NotificationService(academyId);
  }

  /// Format currency for Brazilian Real
  String _formatCurrency(int valueInCents) {
    final value = valueInCents / 100;
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  /// Format date in Brazilian format
  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  // ============================================
  // NOTIFICATIONS FOR STUDENTS
  // ============================================

  /// Notify student about new tuition created
  Future<AppNotification> notifyNewTuition({
    required String userId,
    required String studentName,
    required int amount,
    required DateTime dueDate,
    String? financialId,
  }) async {
    return _notificationService.create(
      userId: userId,
      type: NotificationType.paymentPending,
      priority: NotificationPriority.normal,
      title: 'Nova Mensalidade',
      message: 'Sua mensalidade de ${_formatCurrency(amount)} vence em ${_formatDate(dueDate)}.',
      actionUrl: '/portal/financeiro',
      actionLabel: 'Ver detalhes',
      financialId: financialId,
      expiresInDays: 30,
    );
  }

  /// Notify student about overdue tuition
  Future<AppNotification> notifyOverdueTuition({
    required String userId,
    required String studentName,
    required int amount,
    required int daysOverdue,
    String? financialId,
  }) async {
    return _notificationService.create(
      userId: userId,
      type: NotificationType.paymentOverdue,
      priority: NotificationPriority.high,
      title: 'Pagamento Atrasado',
      message: 'Sua mensalidade de ${_formatCurrency(amount)} está atrasada há $daysOverdue dias.',
      actionUrl: '/portal/financeiro',
      actionLabel: 'Regularizar',
      financialId: financialId,
      expiresInDays: 30,
    );
  }

  /// Notify student about new achievement
  Future<AppNotification> notifyNewAchievement({
    required String userId,
    required String studentName,
    required String achievementTitle,
    String? studentId,
  }) async {
    return _notificationService.create(
      userId: userId,
      type: NotificationType.studentMilestone,
      priority: NotificationPriority.normal,
      title: 'Conquista Desbloqueada!',
      message: 'Parabéns! Você conquistou: $achievementTitle',
      actionUrl: '/portal/linha-do-tempo',
      actionLabel: 'Ver conquistas',
      studentId: studentId,
      expiresInDays: 30,
    );
  }

  /// Notify student about checkin availability
  Future<AppNotification> notifyCheckinAvailable({
    required String userId,
    required String className,
    required DateTime startTime,
  }) async {
    final timeFormat = DateFormat('HH:mm').format(startTime);
    return _notificationService.create(
      userId: userId,
      type: NotificationType.system,
      priority: NotificationPriority.normal,
      title: 'Aula Disponível',
      message: 'O check-in para $className está aberto! Aula às $timeFormat.',
      actionUrl: '/portal/presenca',
      actionLabel: 'Fazer check-in',
      expiresInDays: 1,
    );
  }

  /// Notify student about graduation eligibility
  Future<AppNotification> notifyGraduationEligible({
    required String userId,
    required String studentName,
    required int attendanceCount,
    String? studentId,
  }) async {
    return _notificationService.create(
      userId: userId,
      type: NotificationType.graduationEligible,
      priority: NotificationPriority.high,
      title: 'Pronto para Graduação!',
      message: 'Você atingiu $attendanceCount presenças e está elegível para graduação!',
      actionUrl: '/portal/presenca',
      actionLabel: 'Ver progresso',
      studentId: studentId,
      expiresInDays: 30,
    );
  }

  // ============================================
  // NOTIFICATIONS FOR ADMINS
  // ============================================

  /// Notify admin about new store order
  Future<AppNotification> notifyStoreOrder({
    required String adminUserId,
    required String studentName,
    required int total,
    required String orderId,
  }) async {
    return _notificationService.create(
      userId: adminUserId,
      type: NotificationType.orderPaid,
      priority: NotificationPriority.normal,
      title: 'Novo Pedido',
      message: '$studentName fez um pedido de ${_formatCurrency(total)} na loja.',
      actionUrl: '/loja/pedidos/$orderId',
      actionLabel: 'Ver pedido',
      expiresInDays: 7,
    );
  }

  /// Notify admin about payment received
  Future<AppNotification> notifyPaymentReceived({
    required String adminUserId,
    required String studentName,
    required int amount,
    String? studentId,
    String? financialId,
  }) async {
    return _notificationService.create(
      userId: adminUserId,
      type: NotificationType.paymentReceived,
      priority: NotificationPriority.normal,
      title: 'Pagamento Recebido',
      message: '$studentName pagou ${_formatCurrency(amount)}.',
      actionUrl: studentId != null ? '/financeiro?studentId=$studentId' : '/financeiro',
      actionLabel: 'Ver detalhes',
      studentId: studentId,
      financialId: financialId,
      expiresInDays: 30,
    );
  }

  /// Notify admin about new student account linked
  Future<AppNotification> notifyNewStudentLinked({
    required String adminUserId,
    required String studentName,
    required String userEmail,
    String? studentId,
  }) async {
    return _notificationService.create(
      userId: adminUserId,
      type: NotificationType.newStudentLinked,
      priority: NotificationPriority.normal,
      title: 'Nova Conta Vinculada',
      message: '$userEmail vinculou sua conta ao aluno $studentName.',
      actionUrl: studentId != null ? '/alunos/$studentId' : '/alunos',
      actionLabel: 'Ver aluno',
      studentId: studentId,
      expiresInDays: 7,
    );
  }

  // ============================================
  // BULK NOTIFICATIONS
  // ============================================

  /// Notify a student that new training content (workout plan or video) was
  /// shared with them. Used when content is assigned to specific students.
  Future<AppNotification> notifyNewContent({
    required String userId,
    required String title,
    required bool isVideo,
    String? actionUrl,
  }) async {
    return _notificationService.create(
      userId: userId,
      type: NotificationType.system,
      priority: NotificationPriority.normal,
      title: isVideo ? 'Novo vídeo disponível' : 'Novo treino disponível',
      message: isVideo
          ? 'Seu professor compartilhou um vídeo: $title'
          : 'Seu professor enviou um treino: $title',
      actionUrl: actionUrl,
      actionLabel: 'Abrir',
      expiresInDays: 30,
    );
  }
}

// ============================================
// Factory Function
// ============================================
NotificationDispatcher createNotificationDispatcher(String academyId) {
  return NotificationDispatcher(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
NotificationDispatcher get notificationDispatcher =>
    NotificationDispatcher(FirebaseService.academyId);
