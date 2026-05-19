import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../providers/providers.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/skeletons/skeletons.dart';

/// Academies Management Screen
/// Shows list of linked academies with options to add, set primary, or unlink
class AcademiesScreen extends ConsumerWidget {
  const AcademiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final academiesAsync = ref.watch(userAcademiesInfoProvider);
    final mapping = ref.watch(userAcademyMappingProvider).valueOrNull;
    final selectedId = ref.watch(selectedAcademyIdProvider);
    final primaryId = mapping?.primaryAcademyId;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
        ),
        title: Text('Minhas Academias', style: AppTheme.headlineSmall),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.divider),
        ),
      ),
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: () async {
          HapticFeedback.mediumImpact();
          ref.invalidate(userAcademiesInfoProvider);
          ref.invalidate(userAcademyMappingProvider);
          await ref
              .read(selectedAcademyProvider.notifier)
              .refreshAcademyCache();
        },
        child: academiesAsync.when(
          data: (academies) {
            if (academies.isEmpty) {
              return _buildEmptyState(context);
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Info card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.infoLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.info,
                        size: 18,
                        color: AppTheme.info,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Voce pode treinar em multiplas academias. A academia principal e usada como padrao.',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.info,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Academy cards
                ...academies.map(
                  (academy) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AcademyCard(
                      academy: academy,
                      isSelected: academy.id == selectedId,
                      isPrimary: academy.id == primaryId,
                      onTap: () => _showAcademyOptions(
                        context,
                        ref,
                        academy,
                        isPrimary: academy.id == primaryId,
                        canUnlink: academies.length > 1,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Add academy button
                OutlinedButton.icon(
                  onPressed: () => context.push('/portal/academias/adicionar'),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: const Text('Adicionar Academia'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ],
            );
          },
          loading: () => const SkeletonList(
            itemCount: 4,
            itemHeight: 96,
            padding: EdgeInsets.all(16),
          ),
          error: (error, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  LucideIcons.alertCircle,
                  size: 48,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Erro ao carregar academias',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    ref.invalidate(userAcademiesInfoProvider);
                  },
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(40),
              ),
              child: const Icon(
                LucideIcons.building2,
                size: 40,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            Text('Nenhuma Academia', style: AppTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Voce ainda nao esta vinculado a nenhuma academia.',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push('/portal/academias/adicionar'),
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('Adicionar Academia'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAcademyOptions(
    BuildContext context,
    WidgetRef ref,
    AcademyInfo academy, {
    required bool isPrimary,
    required bool canUnlink,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _buildLogo(academy),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            academy.name,
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(academy.role.label, style: AppTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Options
              if (!isPrimary)
                ListTile(
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _setPrimaryAcademy(context, ref, academy);
                  },
                  leading: const Icon(LucideIcons.star, size: 20),
                  title: const Text('Definir como Principal'),
                  subtitle: const Text('Usar esta academia como padrao'),
                ),

              ListTile(
                onTap: () {
                  Navigator.pop(sheetContext);
                  ref
                      .read(selectedAcademyProvider.notifier)
                      .selectAcademy(academy.id);
                  context.go('/portal');
                },
                leading: const Icon(LucideIcons.arrowRightLeft, size: 20),
                title: const Text('Trocar para esta Academia'),
                subtitle: const Text('Ver dados desta academia'),
              ),

              if (canUnlink)
                ListTile(
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _confirmUnlink(context, ref, academy, isPrimary);
                  },
                  leading: Icon(
                    LucideIcons.unlink,
                    size: 20,
                    color: AppTheme.error,
                  ),
                  title: Text(
                    'Desvincular',
                    style: TextStyle(color: AppTheme.error),
                  ),
                  subtitle: const Text('Remover vinculo com esta academia'),
                ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setPrimaryAcademy(
    BuildContext context,
    WidgetRef ref,
    AcademyInfo academy,
  ) async {
    try {
      final authService = ref.read(authServiceProvider);
      await authService.switchPrimaryAcademy(academy.id);

      // Switch active academy in Riverpod — propagates to all reactive providers.
      await ref.read(selectedAcademyProvider.notifier).selectAcademy(academy.id);

      // Refresh data
      ref.invalidate(userAcademyMappingProvider);

      if (context.mounted) {
        FeedbackUtils.showSuccess(
          context,
          '${academy.name} definida como academia principal',
        );
      }
    } catch (e) {
      if (context.mounted) {
        FeedbackUtils.showError(context, 'Erro ao definir academia principal');
      }
    }
  }

  void _confirmUnlink(
    BuildContext context,
    WidgetRef ref,
    AcademyInfo academy,
    bool isPrimary,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desvincular Academia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tem certeza que deseja desvincular de "${academy.name}"?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.warningLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.alertTriangle,
                    size: 18,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Voce perdera acesso aos dados desta academia.',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _unlinkAcademy(context, ref, academy);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );
  }

  Future<void> _unlinkAcademy(
    BuildContext context,
    WidgetRef ref,
    AcademyInfo academy,
  ) async {
    try {
      final authService = ref.read(authServiceProvider);
      await authService.unlinkFromAcademy(academy.id);

      // Refresh data
      ref.invalidate(userAcademiesInfoProvider);
      ref.invalidate(userAcademyMappingProvider);
      await ref.read(selectedAcademyProvider.notifier).refreshAcademyCache();

      if (context.mounted) {
        FeedbackUtils.showSuccess(context, 'Desvinculado de ${academy.name}');
      }
    } catch (e) {
      if (context.mounted) {
        FeedbackUtils.showError(context, 'Erro ao desvincular academia');
      }
    }
  }

  Widget _buildLogo(AcademyInfo academy) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: academy.logoUrl == null ? AppTheme.primary : null,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: academy.logoUrl != null
          ? AppCachedImage(
              imageUrl: academy.logoUrl,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorIcon: _buildDefaultLogo(academy.name),
            )
          : _buildDefaultLogo(academy.name),
    );
  }

  Widget _buildDefaultLogo(String name) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'A',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Academy Card Widget
class _AcademyCard extends StatelessWidget {
  final AcademyInfo academy;
  final bool isSelected;
  final bool isPrimary;
  final VoidCallback onTap;

  const _AcademyCard({
    required this.academy,
    required this.isSelected,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.divider,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Logo
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: academy.logoUrl == null ? AppTheme.primary : null,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: academy.logoUrl != null
                  ? AppCachedImage(
                      imageUrl: academy.logoUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorIcon: _buildDefaultLogo(),
                    )
                  : _buildDefaultLogo(),
            ),
            const SizedBox(width: 16),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          academy.name,
                          style: AppTheme.titleMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isPrimary) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Principal',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(academy.role.label, style: AppTheme.bodySmall),
                  if (isSelected) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppTheme.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Ativa',
                          style: AppTheme.labelSmall.copyWith(
                            color: AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Chevron
            const Icon(
              LucideIcons.chevronRight,
              size: 20,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultLogo() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Text(
          academy.name.isNotEmpty ? academy.name[0].toUpperCase() : 'A',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
