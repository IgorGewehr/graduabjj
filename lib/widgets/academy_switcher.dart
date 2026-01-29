import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../core/theme.dart';
import '../providers/providers.dart';

/// Academy Switcher Widget for AppBar
/// Shows current academy with dropdown to switch when user has multiple academies
class AcademySwitcher extends ConsumerWidget {
  const AcademySwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMultiple = ref.watch(hasMultipleAcademiesProvider);
    final selectedState = ref.watch(selectedAcademyProvider);
    final settingsAsync = ref.watch(academySettingsProvider);

    return settingsAsync.when(
      data: (settings) {
        final name = settings?.name ?? 'GraduaBJJ';
        final slogan = settings?.portalSlogan;
        final logoUrl = settings?.logoUrl;

        if (!hasMultiple) {
          // Single academy - just show name
          return _buildSingleAcademyDisplay(
            context: context,
            name: name,
            slogan: slogan,
            logoUrl: logoUrl,
          );
        }

        // Multiple academies - show dropdown trigger
        return _buildMultiAcademyDropdown(
          context: context,
          ref: ref,
          name: name,
          slogan: slogan,
          logoUrl: logoUrl,
          isLoading: selectedState.isLoading,
        );
      },
      loading: () => _buildLoadingState(),
      error: (_, __) => _buildSingleAcademyDisplay(
        context: context,
        name: 'GraduaBJJ',
        slogan: null,
        logoUrl: null,
      ),
    );
  }

  Widget _buildSingleAcademyDisplay({
    required BuildContext context,
    required String name,
    String? slogan,
    String? logoUrl,
  }) {
    return Row(
      children: [
        _buildLogo(name: name, logoUrl: logoUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: AppTheme.titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (slogan != null && slogan.isNotEmpty)
                Text(
                  slogan,
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMultiAcademyDropdown({
    required BuildContext context,
    required WidgetRef ref,
    required String name,
    String? slogan,
    String? logoUrl,
    required bool isLoading,
  }) {
    return GestureDetector(
      onTap: isLoading ? null : () => _showAcademySelector(context, ref),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          _buildLogo(name: name, logoUrl: logoUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: AppTheme.titleMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    if (isLoading)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.textSecondary,
                        ),
                      )
                    else
                      const Icon(
                        LucideIcons.chevronDown,
                        size: 16,
                        color: AppTheme.textSecondary,
                      ),
                  ],
                ),
                if (slogan != null && slogan.isNotEmpty)
                  Text(
                    slogan,
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo({required String name, String? logoUrl}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: logoUrl == null ? AppTheme.primary : null,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: logoUrl != null
          ? Image.network(
              logoUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildDefaultLogo(name),
            )
          : _buildDefaultLogo(name),
    );
  }

  Widget _buildDefaultLogo(String name) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'G',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 100,
          height: 16,
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  void _showAcademySelector(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _AcademySelectorSheet(
        onSelect: (academyId) {
          Navigator.pop(sheetContext);
          ref.read(selectedAcademyProvider.notifier).selectAcademy(academyId);
        },
      ),
    );
  }
}

/// Bottom sheet for selecting an academy
class _AcademySelectorSheet extends ConsumerWidget {
  final void Function(String academyId) onSelect;

  const _AcademySelectorSheet({required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final academiesAsync = ref.watch(userAcademiesInfoProvider);
    final selectedId = ref.watch(selectedAcademyIdProvider);
    final mapping = ref.watch(userAcademyMappingProvider).valueOrNull;
    final primaryId = mapping?.primaryAcademyId;

    return Container(
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
            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'Minhas Academias',
                    style: AppTheme.headlineSmall,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x, size: 20),
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Academy list
            academiesAsync.when(
              data: (academies) {
                if (academies.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nenhuma academia vinculada',
                      style: AppTheme.bodyMedium,
                    ),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: academies.length,
                  itemBuilder: (context, index) {
                    final academy = academies[index];
                    final isSelected = academy.id == selectedId;
                    final isPrimary = academy.id == primaryId;

                    return _buildAcademyTile(
                      context: context,
                      academy: academy,
                      isSelected: isSelected,
                      isPrimary: isPrimary,
                      onTap: () => onSelect(academy.id),
                    );
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
              error: (_, __) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Erro ao carregar academias',
                  style: AppTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Manage academies button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  // Navigate to academies management screen
                  Navigator.pushNamed(context, '/portal/academias');
                },
                icon: const Icon(LucideIcons.settings, size: 18),
                label: const Text('Gerenciar Academias'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcademyTile({
    required BuildContext context,
    required AcademyInfo academy,
    required bool isSelected,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: academy.logoUrl == null ? AppTheme.primary : null,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: academy.logoUrl != null
            ? Image.network(
                academy.logoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildDefaultLogo(academy.name),
              )
            : _buildDefaultLogo(academy.name),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              academy.name,
              style: AppTheme.titleMedium.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isPrimary) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Principal',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                  fontSize: 9,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        academy.role.label,
        style: AppTheme.bodySmall,
      ),
      trailing: isSelected
          ? const Icon(
              LucideIcons.check,
              color: AppTheme.success,
              size: 20,
            )
          : null,
      selected: isSelected,
      selectedTileColor: AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildDefaultLogo(String name) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'A',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
