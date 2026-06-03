import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
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
        appBar: MediaQuery.of(context).size.width < 768
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
                  // Sidebar for larger screens
                  if (MediaQuery.of(context).size.width >= 768)
                    AdminSidebar(currentPath: location),
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
        bottomNavigationBar: MediaQuery.of(context).size.width < 768
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
    final isStoreEnabled = settings?.storeEnabled ?? false;
    final isGraduationEnabled = settings?.autoGraduationEnabled ?? false;
    final currentUser = ref.watch(currentUserProvider);
    final user = currentUser.valueOrNull;
    // Permission gates. Admins always pass; instructors need the explicit
    // extraPermissions entry granted at promotion time.
    final isAdminUser = user?.isAdmin == true;
    final canTakeAttendance =
        isAdminUser || user?.hasPermission('attendance:take') == true;
    final canSeeStudents =
        isAdminUser ||
        user?.hasPermission('students:create') == true ||
        user?.hasPermission('students:delete') == true;
    final canSeeFinancial = user?.hasPermission('financial:view') == true;
    final canSeeReports = user?.hasPermission('reports:view') == true;
    final canManageGraduation = user?.hasPermission('graduation:manage') == true;
    final canManageCompetitions =
        isAdminUser || user?.hasPermission('competitions:create') == true;

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

          // Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _NavItem(
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard,
                  label: 'Dashboard',
                  path: '/admin',
                  currentPath: currentPath,
                ),
                if (canSeeStudents)
                  _NavItem(
                    icon: Icons.people_outline,
                    activeIcon: Icons.people,
                    label: 'Alunos',
                    path: '/admin/alunos',
                    currentPath: currentPath,
                  ),
                // 'Chamada' abre a chamada normal. O FAB 'Chamada por QR'
                // dentro da propria tela leva pra projecao — sem precisar
                // de duas entradas na sidebar.
                if (canTakeAttendance)
                  _NavItem(
                    icon: Icons.check_circle_outline,
                    activeIcon: Icons.check_circle,
                    label: 'Chamada',
                    path: '/admin/chamada',
                    currentPath: currentPath,
                  ),
                _NavItem(
                  icon: Icons.calendar_month_outlined,
                  activeIcon: Icons.calendar_month,
                  label: 'Turmas',
                  path: '/admin/turmas',
                  currentPath: currentPath,
                ),
                if (isGraduationEnabled && canManageGraduation)
                  _NavItem(
                    icon: Icons.military_tech_outlined,
                    activeIcon: Icons.military_tech,
                    label: 'Graduação',
                    path: '/admin/graduacao',
                    currentPath: currentPath,
                  ),
                if (canManageCompetitions)
                  _NavItem(
                    icon: Icons.emoji_events_outlined,
                    activeIcon: Icons.emoji_events,
                    label: 'Campeonatos',
                    path: '/admin/campeonatos',
                    currentPath: currentPath,
                  ),
                if (canSeeFinancial)
                  _NavItem(
                    icon: Icons.attach_money_outlined,
                    activeIcon: Icons.attach_money,
                    label: 'Financeiro',
                    path: '/admin/financeiro',
                    currentPath: currentPath,
                  ),
                if (canSeeFinancial)
                  _NavItem(
                    icon: Icons.receipt_long_outlined,
                    activeIcon: Icons.receipt_long,
                    label: 'Cobranca',
                    path: '/admin/cobranca',
                    currentPath: currentPath,
                  ),
                if (canSeeReports)
                  _NavItem(
                    icon: Icons.bar_chart_outlined,
                    activeIcon: Icons.bar_chart,
                    label: 'Relatorios',
                    path: '/admin/relatorios',
                    currentPath: currentPath,
                  ),
                if (isStoreEnabled)
                  _NavItem(
                    icon: Icons.store_outlined,
                    activeIcon: Icons.store,
                    label: 'Loja',
                    path: '/admin/loja',
                    currentPath: currentPath,
                  ),
                // Configurações + código de equipe are admin-only — instructors
                // never touch academy-wide settings or generate invites.
                if (isAdminUser) ...[
                  const Divider(),
                  _NavItem(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings,
                    label: 'Configurações',
                    path: '/admin/configuracoes',
                    currentPath: currentPath,
                  ),
                  _NavItem(
                    icon: Icons.key_outlined,
                    activeIcon: Icons.key,
                    label: 'Código de equipe',
                    path: '/codigo-equipe',
                    currentPath: currentPath,
                  ),
                ],
              ],
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
}

/// Navigation Item Widget
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String path;
  final String currentPath;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.path,
    required this.currentPath,
  });

  bool get isActive => currentPath == path || currentPath.startsWith('$path/');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: Icon(
          isActive ? activeIcon : icon,
          color: isActive ? AppTheme.primary : AppTheme.textSecondary,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isActive ? AppTheme.primary : AppTheme.textPrimary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        selected: isActive,
        selectedTileColor: AppTheme.primary.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context); // Close drawer on mobile
          }
          context.go(path);
        },
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

  /// Catalog of everything that lives behind the "Menu" tile, tagged by
  /// section and tagged with the permission needed to see it. The shell
  /// applies the filter at render time so each role only sees what's
  /// actually theirs.
  static const List<_AdminMenuEntry> _menuCatalog = [
    // Gestão — primary academy operations
    _AdminMenuEntry(
      label: 'Turmas',
      icon: LucideIcons.calendar,
      path: '/admin/turmas',
      section: 'Gestão',
    ),
    _AdminMenuEntry(
      label: 'Graduação',
      icon: LucideIcons.award,
      path: '/admin/graduacao',
      section: 'Gestão',
      requiresGraduation: true,
      requiresPermission: 'graduation:manage',
    ),
    _AdminMenuEntry(
      label: 'Campeonatos',
      icon: LucideIcons.trophy,
      path: '/admin/campeonatos',
      section: 'Gestão',
      requiresPermission: 'competitions:create',
    ),
    _AdminMenuEntry(
      label: 'Musculação',
      icon: Icons.fitness_center,
      path: '/admin/musculacao',
      section: 'Gestão',
    ),
    _AdminMenuEntry(
      label: 'Jornal da Academia',
      icon: LucideIcons.newspaper,
      path: '/admin/jornal',
      section: 'Gestão',
      requiresPermission: 'events:manage',
    ),
    _AdminMenuEntry(
      label: 'Importar alunos',
      icon: Icons.upload_file,
      path: '/admin/importar-alunos',
      section: 'Gestão',
    ),
    // Financeiro
    _AdminMenuEntry(
      label: 'Cobrança',
      icon: LucideIcons.receipt,
      path: '/admin/cobranca',
      section: 'Financeiro',
      requiresPermission: 'financial:view',
    ),
    _AdminMenuEntry(
      label: 'Carteira',
      icon: LucideIcons.wallet,
      path: '/admin/carteira',
      section: 'Financeiro',
      requiresPermission: 'financial:view',
      requiresPayment: true,
    ),
    _AdminMenuEntry(
      label: 'Relatórios',
      icon: LucideIcons.barChart3,
      path: '/admin/relatorios',
      section: 'Financeiro',
      requiresPermission: 'reports:view',
    ),
    // Conteúdo
    _AdminMenuEntry(
      label: 'Treinos',
      icon: Icons.assignment_outlined,
      path: '/admin/treinos',
      section: 'Conteúdo',
    ),
    _AdminMenuEntry(
      label: 'Vídeos',
      icon: Icons.play_circle_outline,
      path: '/admin/videos',
      section: 'Conteúdo',
    ),
    _AdminMenuEntry(
      label: 'Loja',
      icon: LucideIcons.store,
      path: '/admin/loja',
      section: 'Conteúdo',
      requiresStore: true,
    ),
    // Conta — admin-only
    _AdminMenuEntry(
      label: 'Configurações',
      icon: LucideIcons.settings,
      path: '/admin/configuracoes',
      section: 'Conta',
      adminOnly: true,
    ),
    _AdminMenuEntry(
      label: 'Código de equipe',
      icon: LucideIcons.key,
      path: '/codigo-equipe',
      section: 'Conta',
      adminOnly: true,
    ),
  ];

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

    // Check if any menu entry is active
    for (final entry in _menuCatalog) {
      if (location == entry.path || location.startsWith('${entry.path}/')) {
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

  /// Resolves the menu catalog against the current user/settings and returns
  /// only the entries this role is allowed to see.
  List<_AdminMenuEntry> _visibleMenuEntries() {
    final settings = ref.read(academySettingsProvider).valueOrNull;
    final isStoreEnabled = settings?.storeEnabled ?? false;
    final isGraduationEnabled = settings?.autoGraduationEnabled ?? false;
    final isPaymentEnabled =
        (settings?.abacatePayEnabled ?? false) ||
        (settings?.asaasEnabled ?? false);
    final user = ref.read(currentUserProvider).valueOrNull;
    final isAdminUser = user?.isAdmin == true;

    return _menuCatalog.where((e) {
      if (e.adminOnly && !isAdminUser) return false;
      if (e.requiresStore && !isStoreEnabled) return false;
      if (e.requiresGraduation && !isGraduationEnabled) return false;
      if (e.requiresPayment && !isPaymentEnabled) return false;
      if (e.requiresPermission != null &&
          user?.hasPermission(e.requiresPermission!) != true) {
        return false;
      }
      return true;
    }).toList();
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
              (e) => MoreMenuItem(
                label: e.label,
                icon: e.icon,
                path: e.path,
                isActive: currentLocation == e.path,
                category: e.section,
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

/// One entry in the admin "Menu" sheet catalog. Each entry declares the
/// section it belongs to plus the gates required to surface it.
class _AdminMenuEntry {
  final String label;
  final IconData icon;
  final String path;
  final String section;
  final bool adminOnly;
  final bool requiresStore;
  final bool requiresGraduation;
  final bool requiresPayment;
  final String? requiresPermission;

  const _AdminMenuEntry({
    required this.label,
    required this.icon,
    required this.path,
    required this.section,
    this.adminOnly = false,
    this.requiresStore = false,
    this.requiresGraduation = false,
    this.requiresPayment = false,
    this.requiresPermission,
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
