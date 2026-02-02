import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../providers/providers.dart';
import '../../services/notification_service.dart';

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
      case NotificationType.financial:
        return LucideIcons.dollarSign;
      case NotificationType.graduation:
        return LucideIcons.award;
      case NotificationType.competition:
        return LucideIcons.trophy;
      case NotificationType.achievement:
        return LucideIcons.star;
      case NotificationType.attendance:
        return LucideIcons.clipboardCheck;
      case NotificationType.announcement:
        return LucideIcons.megaphone;
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.alertCircle, size: 48, color: AppTheme.textSecondary),
              const SizedBox(height: 12),
              Text('Erro ao carregar notificacoes', style: AppTheme.bodyMedium),
            ],
          ),
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.bellOff, size: 48, color: AppTheme.textSecondary),
                  const SizedBox(height: 12),
                  Text(
                    'Nenhuma notificacao',
                    style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Voce sera notificado sobre pagamentos e novidades',
                    style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
            itemBuilder: (context, index) {
              final notification = notifications[index];
              final icon = _getIconForType(notification.type);
              final color = _getColorForPriority(notification.priority);

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
                  notificationService?.delete(notification.id);
                },
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                      fontWeight: notification.read ? FontWeight.w400 : FontWeight.w600,
                      color: notification.read ? AppTheme.textSecondary : AppTheme.textPrimary,
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
              );
            },
          );
        },
      ),
    );
  }
}
