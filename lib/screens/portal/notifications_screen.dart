import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../services/notification_service.dart';
import '../../widgets/polish/polish.dart';

String _formatTimeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inMinutes < 60) return 'ha ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'ha ${diff.inHours}h';
  if (diff.inDays < 7) return 'ha ${diff.inDays}d';
  if (diff.inDays < 30) return 'ha ${(diff.inDays / 7).floor()} sem';
  return 'ha ${(diff.inDays / 30).floor()} mes(es)';
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  IconData _getIconForType(NotificationType type) {
    switch (type) {
      case NotificationType.paymentReceived:
      case NotificationType.paymentPending:
      case NotificationType.paymentOverdue:
      case NotificationType.paymentDueSoon:
        return LucideIcons.dollarSign;
      case NotificationType.orderPaid:
        return LucideIcons.shoppingBag;
      case NotificationType.withdrawalCompleted:
      case NotificationType.withdrawalFailed:
        return LucideIcons.wallet;
      case NotificationType.graduationEligible:
      case NotificationType.graduationNear:
        return LucideIcons.award;
      case NotificationType.competitionReminder:
        return LucideIcons.trophy;
      case NotificationType.newStudentLinked:
        return LucideIcons.userPlus;
      case NotificationType.studentMilestone:
        return LucideIcons.star;
      case NotificationType.system:
        return LucideIcons.bell;
    }
  }

  Color _getColorForPriority(NotificationPriority priority) {
    switch (priority) {
      case NotificationPriority.urgent:
        return Colors.red;
      case NotificationPriority.high:
        return Colors.orange;
      case NotificationPriority.normal:
        return AppTheme.textPrimary;
      case NotificationPriority.low:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(userNotificationsProvider);
    final notificationService = ref.watch(notificationServiceProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Notificacoes',
          style: AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (notificationsAsync.valueOrNull?.any((n) => !n.read) == true)
            TextButton(
              onPressed: () async {
                HapticFeedback.selectionClick();
                final currentUser = ref.read(currentUserProvider).valueOrNull;
                if (currentUser != null && notificationService != null) {
                  await notificationService.markAllAsRead(currentUser.id);
                }
              },
              child: Text(
                'Marcar todas lidas',
                style: AppTheme.labelSmall.copyWith(color: AppTheme.primary),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.divider),
        ),
      ),
      body: notificationsAsync.when(
        loading: () => PolishSkeleton.list(count: 6),
        error: (error, _) => PolishedEmptyState(
          icon: LucideIcons.alertCircle,
          title: 'Erro ao carregar notificacoes',
          subtitle: 'Verifique sua conexao e tente novamente.',
          accent: AppTheme.error,
          actionLabel: 'Tentar novamente',
          onAction: () {
            HapticFeedback.lightImpact();
            ref.invalidate(userNotificationsProvider);
          },
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return const PolishedEmptyState(
              icon: LucideIcons.bellOff,
              title: 'Nenhuma notificacao',
              subtitle: 'Voce sera notificado sobre pagamentos e novidades',
            );
          }

          // Wrap the whole list in an AnimatedSwitcher keyed by the unread
          // count so a "marcar todas lidas" change cross-fades the row
          // styles instead of repainting them in place.
          return RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: () async {
              HapticFeedback.mediumImpact();
              ref.invalidate(userNotificationsProvider);
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _NotificationListBody(
                key: ValueKey(
                  'notifications-${notifications.length}-${notifications.where((n) => !n.read).length}',
                ),
                notifications: notifications,
                notificationService: notificationService,
                getIconForType: _getIconForType,
                getColorForPriority: _getColorForPriority,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Extracted notification list body so the AnimatedSwitcher above can swap it
/// when the read/unread count changes. Keeps the animation cheap (one widget
/// fade) instead of re-running through every item's transition machinery.
class _NotificationListBody extends StatelessWidget {
  final List<AppNotification> notifications;
  final NotificationService? notificationService;
  final IconData Function(NotificationType type) getIconForType;
  final Color Function(NotificationPriority priority) getColorForPriority;

  const _NotificationListBody({
    super.key,
    required this.notifications,
    required this.notificationService,
    required this.getIconForType,
    required this.getColorForPriority,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: notifications.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
      itemBuilder: (context, index) {
        final notification = notifications[index];
        final icon = getIconForType(notification.type);
        final color = getColorForPriority(notification.priority);

        return Dismissible(
          key: Key(notification.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.red.withValues(alpha: 0.1),
            child: const Icon(LucideIcons.trash2, color: Colors.red, size: 20),
          ),
          onDismissed: (_) {
            // Sprint 6 — light haptic confirms the swipe-to-delete.
            HapticFeedback.lightImpact();
            notificationService?.delete(notification.id);
          },
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: notification.read
                    ? AppTheme.divider
                    : color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: notification.read ? AppTheme.textSecondary : color,
              ),
            ),
            title: Text(
              notification.title,
              style: AppTheme.bodyMedium.copyWith(
                fontWeight: notification.read
                    ? FontWeight.w400
                    : FontWeight.w600,
                color: notification.read
                    ? AppTheme.textSecondary
                    : AppTheme.textPrimary,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  notification.message,
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTimeAgo(notification.createdAt),
                  style: AppTheme.labelSmall.copyWith(
                    fontSize: 10,
                    color: AppTheme.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            trailing: !notification.read
                ? Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
            onTap: () async {
              if (!notification.read) {
                await notificationService?.markAsRead(notification.id);
              }
              if (notification.actionUrl != null && context.mounted) {
                context.push(notification.actionUrl!);
              }
            },
          ),
        ).entrance(index: index);
      },
    );
  }
}
