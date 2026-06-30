import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/navigation/nav_catalog.dart';
import '../../core/navigation/nav_resolver.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../models/academy.dart';
import '../../providers/auth_provider.dart';
import '../../providers/portal_providers.dart';
import '../../providers/subscription_provider.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/common/more_menu_sheet.dart';
import '../../widgets/common/back_button_handler.dart';
import '../../widgets/update_banner.dart';
import '../../widgets/polish/polish.dart';
import '../paywall_screen.dart';

/// Admin Navigation Shell - Main navigation for admin screens
class AdminShell extends ConsumerWidget {
  final Widget child;

  const AdminShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    ref.watch(currentUserProvider);
    final sub = ref.watch(subscriptionProvider).valueOrNull;

    // Subscription gate: when the academy has no active access (trial expired
    // and unpaid), staff see the paywall instead of the admin area. Students
    // are unaffected — they live in the portal shell. Defaults to allowing
    // access while the subscription is still loading (no paywall flash).
    if (!ref.watch(hasSubscriptionAccessProvider)) {
      // Renovação recorrente que falhou (pastDue) → mensagem de "atualize seu
      // pagamento" em vez do paywall genérico.
      return PaywallScreen(
        pastDue: sub?.status == SubscriptionStatus.pastDue,
      );
    }

    // Avisos de trial / vencimento da assinatura — só aparecem depois do gate
    // acima liberar o acesso. Tocar abre o paywall; o X dispensa o aviso apenas
    // nesta sessão (volta ao reabrir o app — ver dismissedBannersProvider).
    final dismissed = ref.watch(dismissedBannersProvider);
    final showTrialBanner =
        (sub?.isTrialing ?? false) && !dismissed.contains('trial');
    final showExpiryBanner =
        (sub?.isPaidExpiringSoon ?? false) && !dismissed.contains('expiry');
    final trialDaysLeft = sub?.trialDaysLeft ?? 0;
    final paidDaysLeft = sub?.paidDaysLeft ?? 0;

    final settingsAsync = ref.watch(academySettingsProvider);
    final settings = settingsAsync.valueOrNull;

    // Check if this is the root route (/admin)
    final isRootRoute = location == '/admin';

    return BackButtonHandler(
      isRootRoute: isRootRoute,
      currentLocation: location,
      exitMessage: 'Pressione voltar novamente para sair',
      child: Scaffold(
        backgroundColor: AppTheme.background,
        // AppBar mobile só no compact (<600); em medium/expanded o logo + sino
        // vivem na Rail/Sidebar lateral.
        appBar: context.isCompact
            ? AppBar(
                backgroundColor: AppTheme.surface,
                elevation: 0,
                scrolledUnderElevation: 0,
                title: Row(
                  children: [
                    // Logo
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: (settings?.logoUrl ?? '').isEmpty
                            ? AppTheme.textPrimary
                            : null,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: (settings?.logoUrl ?? '').isEmpty
                          ? Center(
                              child: Text(
                                settings?.name.isNotEmpty == true
                                    ? settings!.name[0].toUpperCase()
                                    : 'A',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            )
                          : AppCachedImage(
                              imageUrl: settings!.logoUrl,
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                            ),
                    ),
                    const SizedBox(width: 10),
                    // Academy name and slogan
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            settings?.name ?? 'Minha Academia',
                            style: AppTheme.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (settings?.portalSlogan != null &&
                              settings!.portalSlogan!.isNotEmpty)
                            Text(
                              settings.portalSlogan!,
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
                actions: [_AdminNotificationBell(), const SizedBox(width: 8)],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: Container(height: 1, color: AppTheme.divider),
                ),
              )
            : null,
        body: Column(
          children: [
            if (showTrialBanner)
              _SubscriptionBanner(
                kind: _BannerKind.trial,
                daysLeft: trialDaysLeft,
                onTap: () => context.push('/paywall'),
                onClose: () => ref
                    .read(dismissedBannersProvider.notifier)
                    .update((s) => {...s, 'trial'}),
              ),
            if (showExpiryBanner)
              _SubscriptionBanner(
                kind: _BannerKind.expiry,
                daysLeft: paidDaysLeft,
                onTap: () => context.push('/paywall'),
                onClose: () => ref
                    .read(dismissedBannersProvider.notifier)
                    .update((s) => {...s, 'expiry'}),
              ),
            // Aviso de atualização — menor prioridade, fica abaixo dos avisos
            // de cobrança acima (some sozinho se não houver versão nova).
            const UpdateBanner(),
            Expanded(
              child: Row(
                children: [
                  // Navegação lateral adaptativa: Sidebar expandida (250px) no
                  // expanded/large (>=1024); NavigationRail só-ícones (72px) no
                  // medium (600-1024); nada no compact (usa o BottomNav abaixo).
                  if (context.isWide)
                    AdminSidebar(currentPath: location)
                  else if (context.isMedium)
                    AdminRail(currentPath: location),
                  // Main content — gentle cross-fade on route change.
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: PolishMotion.normal,
                      switchInCurve: PolishMotion.transition,
                      switchOutCurve: PolishMotion.transition,
                      child: KeyedSubtree(
                        key: ValueKey(location),
                        child: child,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: context.isCompact
            ? AdminBottomNav(currentPath: location)
            : null,
      ),
    );
  }
}

/// Tipo de aviso exibido no topo da área admin.
enum _BannerKind { trial, expiry }

/// Slim banner no topo da área admin: contagem do trial OU aviso de assinatura
/// prestes a vencer. Fica vermelho (urgente) nos últimos 3 dias. Tocar abre o
/// paywall; o X dispensa o aviso só na sessão atual (volta ao reabrir o app).
class _SubscriptionBanner extends StatelessWidget {
  final _BannerKind kind;
  final int daysLeft;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _SubscriptionBanner({
    required this.kind,
    required this.daysLeft,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final urgent = daysLeft <= 3;
    final color = urgent ? AppTheme.error : AppTheme.warning;
    final isTrial = kind == _BannerKind.trial;
    final String label;
    if (isTrial) {
      label = daysLeft <= 0
          ? 'Seu trial termina hoje'
          : daysLeft == 1
              ? 'Falta 1 dia de trial'
              : 'Faltam $daysLeft dias de trial';
    } else {
      label = daysLeft <= 0
          ? 'Sua assinatura vence hoje'
          : daysLeft == 1
              ? 'Sua assinatura vence em 1 dia'
              : 'Sua assinatura vence em $daysLeft dias';
    }
    final cta = isTrial ? 'Assinar' : 'Renovar';

    return Material(
      color: color.withValues(alpha: 0.12),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(LucideIcons.clock, size: 16, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.labelMedium.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                cta,
                style: AppTheme.labelMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 16, color: color),
              const SizedBox(width: 2),
              // Dispensa o aviso só nesta sessão (volta ao reabrir o app).
              InkResponse(
                onTap: onClose,
                radius: 18,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    LucideIcons.x,
                    size: 16,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Admin Sidebar Navigation
class AdminSidebar extends ConsumerWidget {
  final String currentPath;

  const AdminSidebar({super.key, required this.currentPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(academySettingsProvider);
    final settings = settingsAsync.valueOrNull;
    final currentUser = ref.watch(currentUserProvider);
    final user = currentUser.valueOrNull;

    // Single source of truth: resolve the admin catalog and render every
    // non-hidden entry grouped by section. `locked` entries surface in the
    // discovery state and deep-link to settings on tap.
    final resolved = resolveAdminCatalog(
      catalog: kAdminNavCatalog,
      settings: settings,
      user: user,
    ).where((r) => !r.isHidden).toList();

    return Container(
      width: 250,
      color: AppTheme.surface,
      child: Column(
        children: [
          // Header/Logo
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (settings?.logoUrl ?? '').isEmpty
                        ? AppTheme.primary
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (settings?.logoUrl ?? '').isEmpty
                      ? Center(
                          child: Text(
                            settings?.name.isNotEmpty == true
                                ? settings!.name[0].toUpperCase()
                                : 'A',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        )
                      : AppCachedImage(
                          imageUrl: settings!.logoUrl,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    settings?.name ?? 'Minha Academia',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ).fadeInQuick(),
          const Divider(height: 1),

          // Navigation Items — rendered from the resolved catalog, grouped by
          // section with uppercase headers. Same set as the mobile menu.
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: _buildSidebarChildren(context, resolved),
            ),
          ),

          // User section
          const Divider(height: 1),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: AppTheme.primary,
              child: Text(
                user?.displayName.isNotEmpty == true
                    ? user!.displayName[0].toUpperCase()
                    : 'U',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            title: Text(
              user?.displayName ?? 'Admin',
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              user?.isAdmin == true ? 'Administrador' : 'Instrutor',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                final confirmed = await FeedbackUtils.showConfirmDialog(
                  context,
                  title: 'Sair da conta',
                  message: 'Tem certeza que deseja sair?',
                  confirmText: 'Sair',
                  icon: Icons.logout,
                );
                if (!confirmed) return;
                final authService = ref.read(authServiceProvider);
                await authService.signOut();
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Builds the sidebar body from the resolved catalog: a section header
  /// (uppercase) before each new section, then the entries. `Conta` is
  /// preceded by a divider to preserve the old account-area separation.
  List<Widget> _buildSidebarChildren(
    BuildContext context,
    List<ResolvedNavEntry> resolved,
  ) {
    final children = <Widget>[];
    NavSection? lastSection;
    for (final r in resolved) {
      final entry = r.entry;
      if (entry.section != lastSection) {
        if (entry.section == NavSection.conta) {
          children.add(const Divider());
        }
        children.add(_SidebarSectionHeader(label: entry.section.label));
        lastSection = entry.section;
      }
      children.add(
        _NavItem(
          icon: entry.icon,
          activeIcon: entry.activeIcon ?? entry.icon,
          label: entry.label,
          path: entry.route,
          currentPath: currentPath,
          locked: r.isLocked,
          feature: entry.feature,
        ),
      );
    }
    return children;
  }
}

/// Uppercase section label rendered above each group in the sidebar.
class _SidebarSectionHeader extends StatelessWidget {
  final String label;

  const _SidebarSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: AppTheme.labelSmall.copyWith(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Navigation Item Widget
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String path;
  final String currentPath;

  /// When true the item renders dimmed with a padlock/"Ative" badge and a tap
  /// deep-links to settings for [feature] instead of navigating to [path].
  final bool locked;
  final FeatureId? feature;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.path,
    required this.currentPath,
    this.locked = false,
    this.feature,
  });

  bool get isActive => currentPath == path || currentPath.startsWith('$path/');

  @override
  Widget build(BuildContext context) {
    final Color iconColor = locked
        ? AppTheme.textDisabled
        : isActive
            ? AppTheme.primary
            : AppTheme.textSecondary;
    final Color labelColor = locked
        ? AppTheme.textDisabled
        : isActive
            ? AppTheme.primary
            : AppTheme.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: Icon(
          locked ? icon : (isActive ? activeIcon : icon),
          color: iconColor,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        trailing: locked ? const _SidebarLockBadge() : null,
        selected: isActive && !locked,
        selectedTileColor: AppTheme.primary.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context); // Close drawer on mobile
          }
          if (locked && feature != null) {
            context.go(settingsDeepLinkFor(feature!));
          } else {
            context.go(path);
          }
        },
      ),
    );
  }
}

/// "Ative" pill with padlock, shown on the trailing edge of a locked sidebar
/// item (discovery state for an OFF feature).
class _SidebarLockBadge extends StatelessWidget {
  const _SidebarLockBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.lock, size: 11, color: AppTheme.warning),
          const SizedBox(width: 4),
          Text(
            'Ative',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.warning,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Admin NavigationRail — só-ícones (72px) para o degrau `medium` (600–1024).
/// Mesma fonte do catálogo resolvido da Sidebar; cada entrada vira um ícone com
/// tooltip. Logo no topo, sino + logout embaixo (paridade com o AppBar mobile).
class AdminRail extends ConsumerWidget {
  final String currentPath;

  const AdminRail({super.key, required this.currentPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(academySettingsProvider).valueOrNull;
    final user = ref.watch(currentUserProvider).valueOrNull;
    final resolved = resolveAdminCatalog(
      catalog: kAdminNavCatalog,
      settings: settings,
      user: user,
    ).where((r) => !r.isHidden).toList();

    return Container(
      width: 72,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(right: BorderSide(color: AppTheme.divider, width: 1)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (settings?.logoUrl ?? '').isEmpty ? AppTheme.primary : null,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: (settings?.logoUrl ?? '').isEmpty
                ? Center(
                    child: Text(
                      settings?.name.isNotEmpty == true
                          ? settings!.name[0].toUpperCase()
                          : 'A',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  )
                : AppCachedImage(
                    imageUrl: settings!.logoUrl,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                  ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final r in resolved)
                  _RailItem(
                    entry: r.entry,
                    currentPath: currentPath,
                    locked: r.isLocked,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          _AdminNotificationBell(),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () async {
              final confirmed = await FeedbackUtils.showConfirmDialog(
                context,
                title: 'Sair da conta',
                message: 'Tem certeza que deseja sair?',
                confirmText: 'Sair',
                icon: Icons.logout,
              );
              if (!confirmed) return;
              await ref.read(authServiceProvider).signOut();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Item icon-only da Rail: tooltip com o label, realce ativo em pílula, e um
/// cadeado pequeno quando a feature está bloqueada (discovery).
class _RailItem extends StatelessWidget {
  final NavEntry entry;
  final String currentPath;
  final bool locked;

  const _RailItem({
    required this.entry,
    required this.currentPath,
    required this.locked,
  });

  bool get isActive =>
      currentPath == entry.route || currentPath.startsWith('${entry.route}/');

  @override
  Widget build(BuildContext context) {
    final active = isActive && !locked;
    final color = locked
        ? AppTheme.textDisabled
        : active
            ? AppTheme.primary
            : AppTheme.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Tooltip(
        message:
            locked ? '${entry.label} — ative nas configurações' : entry.label,
        preferBelow: false,
        child: Material(
          color: active
              ? AppTheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              if (locked && entry.feature != null) {
                context.go(settingsDeepLinkFor(entry.feature!));
              } else {
                context.go(entry.route);
              }
            },
            child: SizedBox(
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    active ? (entry.activeIcon ?? entry.icon) : entry.icon,
                    color: color,
                    size: 22,
                  ),
                  if (locked)
                    const Positioned(
                      right: 8,
                      top: 8,
                      child: Icon(
                        LucideIcons.lock,
                        size: 10,
                        color: AppTheme.warning,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Admin Bottom Navigation (for mobile) - Fintech style matching webapp
class AdminBottomNav extends ConsumerStatefulWidget {
  final String currentPath;

  const AdminBottomNav({super.key, required this.currentPath});

  @override
  ConsumerState<AdminBottomNav> createState() => _AdminBottomNavState();
}

class _AdminBottomNavState extends ConsumerState<AdminBottomNav> {
  static const _AdminNavItem _financialBottomNavItem = _AdminNavItem(
    label: 'Financeiro',
    icon: LucideIcons.dollarSign,
    path: '/admin/financeiro',
  );
  static const _AdminNavItem _turmasBottomNavItem = _AdminNavItem(
    label: 'Turmas',
    icon: LucideIcons.calendar,
    path: '/admin/turmas',
  );
  static const _AdminNavItem _menuBottomNavItem = _AdminNavItem(
    label: 'Menu',
    icon: LucideIcons.layoutGrid,
    path: '', // Special case for bottom sheet
  );

  /// Returns the current bottom nav list, gated by permissions on the user.
  List<_AdminNavItem> _bottomNavItemsFor(WidgetRef ref) {
    final user = ref.read(currentUserProvider).valueOrNull;
    final isAdminUser = user?.isAdmin == true;
    final canSeeFinancial = user?.hasPermission('financial:view') == true;
    final canTakeAttendance =
        isAdminUser || user?.hasPermission('attendance:take') == true;
    final canSeeStudents =
        isAdminUser ||
        user?.hasPermission('students:create') == true ||
        user?.hasPermission('students:edit') == true ||
        user?.hasPermission('students:manage') == true ||
        user?.hasPermission('students:delete') == true;

    final items = <_AdminNavItem>[
      const _AdminNavItem(
        label: 'Dashboard',
        icon: LucideIcons.layoutDashboard,
        path: '/admin',
      ),
      if (canTakeAttendance)
        const _AdminNavItem(
          label: 'Chamada',
          icon: LucideIcons.clipboardCheck,
          path: '/admin/chamada',
        ),
      if (canSeeStudents)
        const _AdminNavItem(
          label: 'Alunos',
          icon: LucideIcons.users,
          path: '/admin/alunos',
        ),
      canSeeFinancial ? _financialBottomNavItem : _turmasBottomNavItem,
      _menuBottomNavItem,
    ];
    return items;
  }

  int _getSelectedIndex(List<_AdminNavItem> items) {
    final location = widget.currentPath;

    // Check bottom nav items (except "Mais")
    for (int i = 0; i < items.length - 1; i++) {
      final path = items[i].path;
      // Exact match for /admin, prefix match for others
      if (path == '/admin') {
        if (location == path) return i;
      } else if (location == path || location.startsWith('$path/')) {
        return i;
      }
    }

    // Check if any catalog entry is active (it lives behind the "Menu" tile).
    for (final entry in kAdminNavCatalog) {
      if (location == entry.route || location.startsWith('${entry.route}/')) {
        return items.length - 1; // "Menu" index
      }
    }

    return 0;
  }

  void _onItemTapped(int index, List<_AdminNavItem> items) {
    if (index == items.length - 1) {
      _showMoreMenu();
    } else {
      context.go(items[index].path);
    }
  }

  /// Resolves the admin catalog against the current user/settings and returns
  /// the entries this role can see (visible + locked); hidden ones are dropped.
  List<ResolvedNavEntry> _visibleMenuEntries() {
    final settings = ref.read(academySettingsProvider).valueOrNull;
    final user = ref.read(currentUserProvider).valueOrNull;
    return resolveAdminCatalog(
      catalog: kAdminNavCatalog,
      settings: settings,
      user: user,
    ).where((r) => !r.isHidden).toList();
  }

  void _showMoreMenu() {
    final currentLocation = widget.currentPath;
    final navigator = GoRouter.of(context);
    final entries = _visibleMenuEntries();
    final settings = ref.read(academySettingsProvider).valueOrNull;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => MoreMenuSheet(
        headerTitle: 'Menu',
        headerSubtitle: settings?.name ?? 'Administração',
        items: entries
            .map(
              (r) => MoreMenuItem(
                label: r.entry.label,
                icon: r.entry.icon,
                path: r.entry.route,
                isActive: currentLocation == r.entry.route && !r.isLocked,
                category: r.entry.section.label,
                locked: r.isLocked,
                feature: r.entry.feature,
              ),
            )
            .toList(),
        onLogout: () async {
          final confirmed = await FeedbackUtils.showConfirmDialog(
            sheetContext,
            title: 'Sair da conta',
            message: 'Tem certeza que deseja sair?',
            confirmText: 'Sair',
            icon: Icons.logout,
          );
          if (!confirmed) return;
          if (sheetContext.mounted) Navigator.pop(sheetContext);
          final authService = ref.read(authServiceProvider);
          await authService.signOut();
        },
        onNavigate: (path) {
          Navigator.pop(sheetContext);
          navigator.go(path);
        },
        onLockedTap: (feature) {
          Navigator.pop(sheetContext);
          navigator.go(settingsDeepLinkFor(feature));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _bottomNavItemsFor(ref);
    final selectedIndex = _getSelectedIndex(items);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.95),
        border: const Border(
          top: BorderSide(color: AppTheme.divider, width: 1),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: List.generate(
              items.length,
              (index) => _AdminBottomNavItem(
                item: items[index],
                isSelected: selectedIndex == index,
                onTap: () => _onItemTapped(index, items),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Navigation item data
class _AdminNavItem {
  final String label;
  final IconData icon;
  final String path;

  const _AdminNavItem({
    required this.label,
    required this.icon,
    required this.path,
  });
}

/// Bottom nav item widget - Fintech style with pill indicator
class _AdminBottomNavItem extends StatelessWidget {
  final _AdminNavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _AdminBottomNavItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Pressable(
        onTap: onTap,
        scale: 0.92,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon with pill background when selected
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.textPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  item.icon,
                  size: 20,
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 3),
              // Label
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Admin notification bell with unread badge
class _AdminNotificationBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount =
        ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    return IconButton(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(LucideIcons.bell, size: 20),
          if (unreadCount > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      onPressed: () => context.push('/admin/notificacoes'),
    );
  }
}
