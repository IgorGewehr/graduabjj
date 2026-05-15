import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/selected_academy_provider.dart';
import '../cached_image.dart';

/// Standard page header used on admin screens that scope their data to the
/// current academy (Alunos, Financeiro, Equipe, etc).
///
/// For users with 2+ academies it shows a tappable chip with the current
/// academy name and an arrow — tapping opens a bottom sheet to switch.
/// Single-academy users see the name as a subtle static chip so the page
/// still has consistent context.
class AcademyPageHeader extends ConsumerWidget {
  final IconData? icon;
  final String title;
  final String? description;
  final List<Widget> actions;

  const AcademyPageHeader({
    super.key,
    required this.title,
    this.icon,
    this.description,
    this.actions = const [],
  });

  void _openSwitcher(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AcademySwitcherSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only watch the small derived bits we actually render — `.select` keeps
    // this header (used on most pages) inert when other fields of the
    // mapping/info change.
    final academyIds = ref.watch(
      userAcademyMappingProvider.select(
        (m) => m.valueOrNull?.academyIds ?? const <String>[],
      ),
    );
    final hasMultiple = academyIds.length > 1;
    final academyName = ref.watch(
      currentAcademyInfoProvider.select((info) => info?.name),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTheme.headlineSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (description != null)
                      Text(
                        description!,
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
          if (academyIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: hasMultiple ? () => _openSwitcher(context, ref) : null,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.building2,
                      size: 12,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      academyName ?? 'Academia',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasMultiple) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        LucideIcons.chevronDown,
                        size: 12,
                        color: AppTheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet listing every academy the user belongs to. Tapping one
/// triggers the selected_academy_provider switch which already invalidates
/// per-academy data caches.
class _AcademySwitcherSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapping = ref.watch(userAcademyMappingProvider).valueOrNull;
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final academiesAsync = ref.watch(userAcademiesInfoProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trocar academia',
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            academiesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Erro ao carregar academias.',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              data: (infos) => Column(
                children: infos.map((info) {
                  final detail = mapping?.academyDetails?[info.id];
                  final isCurrent = currentUser?.academyId == info.id;
                  final isPrimary = mapping?.primaryAcademyId == info.id;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: AppCachedAvatar(
                      imageUrl: info.logoUrl,
                      backgroundColor: AppTheme.primary.withValues(
                        alpha: isCurrent ? 0.2 : 0.08,
                      ),
                      child: (info.logoUrl ?? '').isEmpty
                          ? Icon(
                              LucideIcons.building2,
                              size: 18,
                              color: AppTheme.primary,
                            )
                          : null,
                    ),
                    title: Text(
                      info.name,
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: isCurrent
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      '${detail != null ? detail.role.value : 'aluno'}${isPrimary ? ' • Principal' : ''}',
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    trailing: isCurrent
                        ? Icon(
                            LucideIcons.check,
                            size: 18,
                            color: AppTheme.primary,
                          )
                        : null,
                    onTap: isCurrent
                        ? null
                        : () async {
                            Navigator.of(context).pop();
                            await ref
                                .read(selectedAcademyProvider.notifier)
                                .selectAcademy(info.id);
                          },
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
