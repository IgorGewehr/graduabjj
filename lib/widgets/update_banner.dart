import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme.dart';
import '../providers/app_update_provider.dart';
import '../providers/subscription_provider.dart';
import '../services/app_update_service.dart';

/// Banner suave de "atualização disponível", no topo dos shells (admin e
/// portal). Só aparece quando a loja tem versão mais nova; é dispensável na
/// sessão (volta no próximo cold start, como os banners de assinatura) e
/// **nunca bloqueia** o app. Tocar conduz a atualização (in_app_update no
/// Android, App Store no iOS). Reusa `dismissedBannersProvider` com a chave
/// 'update'.
///
/// Visual neutro de propósito: nos shells ele fica **abaixo** dos banners de
/// cobrança (trial/vencimento), que têm prioridade — assim não compete com um
/// aviso de pagamento.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(appUpdateProvider).valueOrNull;
    final dismissed = ref.watch(dismissedBannersProvider).contains('update');
    if (status == null || !status.available || dismissed) {
      return const SizedBox.shrink();
    }

    return Material(
      color: AppTheme.surfaceVariant,
      child: InkWell(
        onTap: () => AppUpdateService.startUpdate(status),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.system_update,
                  size: 16, color: AppTheme.textPrimary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Atualização disponível',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Text(
                'Atualizar',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Icon(LucideIcons.chevronRight,
                  size: 16, color: AppTheme.textPrimary),
              const SizedBox(width: 2),
              // Dispensa o aviso só nesta sessão (volta ao reabrir o app).
              InkResponse(
                onTap: () => ref
                    .read(dismissedBannersProvider.notifier)
                    .update((s) => {...s, 'update'}),
                radius: 18,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(LucideIcons.x,
                      size: 16, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
