import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/fighter_theme.dart';
import '../../models/join_request.dart';
import '../../providers/join_request_providers.dart';
import '../../providers/providers.dart';
import '../../services/settings_service.dart';
import '../../services/team_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/polish/polish.dart';

/// **ACADEMIA** — the single tab that carries academy context.
///
/// Everything portable (passaporte, jornada, faixa, cena/ranking) lives in the
/// Lutador/Cena domains; this hub is the *only* place the academy selector and
/// the academy-contextual shortcuts appear. It is the "Groups/Club" container
/// of the Strava "You" model: contextual to the selected academy, gated by that
/// academy's feature flags, and it cleanly degrades to a "join an academy"
/// prompt for the free (no-academy) fighter.
///
/// Visual language: [FighterTheme] (anti-"AI-slop" — bone canvas, one blood
/// accent, decided hairlines, tabular figures, ALL-CAPS heroes). Belt colors
/// are never used here — this surface has no belt to represent.
class AcademiaHubScreen extends ConsumerWidget {
  const AcademiaHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Escuta em tempo real para transicionar a tela no exato segundo em que o mestre aprova
    ref.listen<AsyncValue<PendingJoinRequest?>>(pendingJoinRequestProvider, (previous, next) {
      if (previous?.valueOrNull != null && next.valueOrNull == null) {
        ref.invalidate(userAcademyMappingProvider);
        ref.invalidate(currentUserProvider);
        ref.invalidate(currentStudentProvider);
        ref.invalidate(academySettingsProvider);
        ref.read(selectedAcademyProvider.notifier).refreshAcademyCache();
      }
    });

    ref.listen<AsyncValue<UserAcademyMapping?>>(userAcademyMappingProvider, (previous, next) {
      final prevIds = previous?.valueOrNull?.academyIds ?? [];
      final nextIds = next.valueOrNull?.academyIds ?? [];
      if (nextIds.length > prevIds.length) {
        ref.invalidate(currentUserProvider);
        ref.invalidate(currentStudentProvider);
        ref.invalidate(academySettingsProvider);
        ref.read(selectedAcademyProvider.notifier).refreshAcademyCache();
      }
    });

    final settingsAsync = ref.watch(academySettingsProvider);
    // Sem academia: ou o aluno tem uma SOLICITAÇÃO pendente (aguardando o
    // professor aprovar) → tela de espera; ou não tem nada → prompt de entrar.
    final pending = ref.watch(pendingJoinRequestProvider).valueOrNull;
    Widget noAcademy() => pending != null
        ? _PendingApprovalState(pending: pending)
        : const _NoAcademyState();

    return Scaffold(
      backgroundColor: FighterTheme.bone,
      body: SafeArea(
        bottom: false,
        child: settingsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: FighterTheme.blood,
            ),
          ),
          // A null settings document means the fighter has no selected academy
          // (the provider returns null when `academyId == null`) — i.e. a free,
          // academy-less user. Surface the pending-approval or "join" prompt.
          error: (_, _) => noAcademy(),
          data: (settings) {
            if (settings == null) return noAcademy();
            return _AcademyHubBody(settings: settings);
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending approval — solicitação enviada, aguardando o professor
// ─────────────────────────────────────────────────────────────────────────────

class _PendingApprovalState extends ConsumerStatefulWidget {
  final PendingJoinRequest pending;
  const _PendingApprovalState({required this.pending});

  @override
  ConsumerState<_PendingApprovalState> createState() =>
      _PendingApprovalStateState();
}

class _PendingApprovalStateState
    extends ConsumerState<_PendingApprovalState> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: FighterTheme.paper,
        title: const Text('Cancelar solicitação?'),
        content: Text(
          'Você vai sair da fila de aprovação da ${widget.pending.academyName}. '
          'Dá pra enviar de novo depois com o mesmo código.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Voltar'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: FighterTheme.blood),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Cancelar solicitação'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await teamService.cancelJoinRequest(widget.pending.academyId);
      // O stream de pendingJoinRequestProvider limpa sozinho → volta ao prompt.
      if (mounted) context.showSuccess('Solicitação cancelada.');
    } catch (e) {
      if (mounted) {
        setState(() => _cancelling = false);
        context.showError('Não foi possível cancelar. Tente de novo.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: FighterTheme.blood.withValues(alpha: 0.08),
                shape: BoxShape.circle,
                border: Border.all(
                    color: FighterTheme.blood.withValues(alpha: 0.35)),
              ),
              child: const Icon(LucideIcons.hourglass,
                  color: FighterTheme.blood, size: 36),
            ),
            const SizedBox(height: 24),
            Text(
              'AGUARDANDO APROVAÇÃO DO MESTRE',
              textAlign: TextAlign.center,
              style: FighterTheme.heroLabel.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: FighterTheme.ink,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.building2, size: 14, color: FighterTheme.bone),
                  const SizedBox(width: 6),
                  Text(
                    widget.pending.academyName.toUpperCase(),
                    style: FighterTheme.heroLabelOnInk.copyWith(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Sua solicitação de entrada foi enviada para o professor da academia.\n\nAssim que o mestre aprovar seu cadastro, o acesso completo às turmas, horários e presenças da ${widget.pending.academyName} será liberado automaticamente aqui!\n\nEnquanto isso, você já pode registrar seus treinos pessoais e acompanhar sua evolução.',
              textAlign: TextAlign.center,
              style: FighterTheme.bodyVoice.copyWith(
                color: FighterTheme.ink.withValues(alpha: 0.75),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ref.invalidate(pendingJoinRequestProvider);
                  ref.invalidate(currentUserProvider);
                  ref.invalidate(currentStudentProvider);
                  context.showSuccess('Verificando aprovação...');
                },
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('VERIFICAR APROVAÇÃO'),
                style: FilledButton.styleFrom(
                  backgroundColor: FighterTheme.ink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _cancelling
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: FighterTheme.blood),
                  )
                : TextButton(
                    onPressed: _cancel,
                    style: TextButton.styleFrom(
                        foregroundColor: FighterTheme.ash),
                    child: const Text('Cancelar solicitação'),
                  ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Body — fighter has an academy
// ─────────────────────────────────────────────────────────────────────────────

class _AcademyHubBody extends ConsumerWidget {
  const _AcademyHubBody({required this.settings});

  final AcademySettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final academyInfo = ref.watch(currentAcademyInfoProvider);
    final hasMultiple = ref.watch(hasMultipleAcademiesProvider);

    final name = settings.name.isNotEmpty
        ? settings.name
        : (academyInfo?.name ?? 'Academia');
    final logoUrl = settings.logoUrl ?? academyInfo?.logoUrl;
    final subtitle = (settings.portalSlogan != null &&
            settings.portalSlogan!.trim().isNotEmpty)
        ? settings.portalSlogan!
        : null;

    final shortcuts = _shortcutsFor(settings);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _AcademyHeader(
          name: name,
          logoUrl: logoUrl,
          subtitle: subtitle,
          hasMultiple: hasMultiple,
          onSwitch: () => context.push('/portal/academias'),
          onAddAcademy: () => context.push('/portal/academias/adicionar'),
        ).fadeInQuick(),
        const SizedBox(height: 28),
        Text(
          'NO TATAME'.toUpperCase(),
          style: FighterTheme.heroLabel.copyWith(color: FighterTheme.ash),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < shortcuts.length; i++) ...[
          _ShortcutTile(
            shortcut: shortcuts[i],
            onTap: () => context.push(shortcuts[i].route),
          ).entrance(index: i),
          if (i != shortcuts.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  /// Builds the visible shortcut list, honoring this academy's feature flags —
  /// off features are never shown (no locked teasers in the contextual hub).
  List<_Shortcut> _shortcutsFor(AcademySettings s) {
    return [
      // Core contextual screens — always available while in an academy.
      const _Shortcut(
        label: 'Horários',
        icon: LucideIcons.calendar,
        route: '/portal/horarios',
      ),
      const _Shortcut(
        label: 'Presenças',
        icon: LucideIcons.clipboardCheck,
        route: '/portal/presencas',
      ),
      const _Shortcut(
        label: 'Competições',
        icon: LucideIcons.trophy,
        route: '/portal/competicoes',
      ),
      if (s.bookingEnabled)
        const _Shortcut(
          label: 'Reservar aula',
          icon: LucideIcons.calendarPlus,
          route: '/portal/reservas',
        ),
      const _Shortcut(
        label: 'Financeiro',
        icon: LucideIcons.dollarSign,
        route: '/portal/financeiro',
      ),
      if (s.storeEnabled && s.storePublished)
        const _Shortcut(
          label: 'Loja',
          icon: LucideIcons.store,
          route: '/portal/loja',
        ),
      if (s.journalVisibleToStudents)
        const _Shortcut(
          label: 'Jornal',
          icon: LucideIcons.newspaper,
          route: '/portal/jornal',
        ),
      if (s.workoutPlansEnabled)
        const _Shortcut(
          label: 'Treinos',
          icon: LucideIcons.dumbbell,
          route: '/portal/treinos',
        ),
      if (s.trainingVideosEnabled)
        const _Shortcut(
          label: 'Vídeos',
          icon: LucideIcons.video,
          route: '/portal/videos',
        ),
      if (s.strikingEnabled)
        const _Shortcut(
          label: 'Trocação',
          icon: LucideIcons.swords,
          route: '/portal/trocacao',
        ),
    ];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header — current academy + (multi-academy) switch chip
// ─────────────────────────────────────────────────────────────────────────────

class _AcademyHeader extends StatelessWidget {
  const _AcademyHeader({
    required this.name,
    required this.logoUrl,
    required this.subtitle,
    required this.hasMultiple,
    required this.onSwitch,
    required this.onAddAcademy,
  });

  final String name;
  final String? logoUrl;
  final String? subtitle;
  final bool hasMultiple;
  final VoidCallback onSwitch;
  final VoidCallback onAddAcademy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: FighterTheme.lightCard(borderColor: FighterTheme.hairline),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Logo(name: name, logoUrl: logoUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ACADEMIA'.toUpperCase(),
                      style: FighterTheme.heroLabel.copyWith(
                        fontSize: 11,
                        color: FighterTheme.blood,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name.toUpperCase(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        letterSpacing: 0.2,
                        color: FighterTheme.ink,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FighterTheme.bodyVoice.copyWith(fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (hasMultiple) ...[
            const SizedBox(height: 14),
            _SwitchChip(onTap: onSwitch),
          ],
          // SEMPRE presente, sutil: entrar numa nova academia.
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Divider(
              height: 1,
              thickness: 1,
              color: FighterTheme.hairline.withValues(alpha: 0.08),
            ),
          ),
          const SizedBox(height: 10),
          Pressable(
            onTap: onAddAcademy,
            child: Row(
              children: [
                const Icon(LucideIcons.plus,
                    size: 15, color: FighterTheme.ash),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ENTRAR EM OUTRA ACADEMIA',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FighterTheme.heroLabel.copyWith(
                      fontSize: 11,
                      color: FighterTheme.ash,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const Icon(
                  LucideIcons.chevronRight,
                  size: 14,
                  color: FighterTheme.ash,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchChip extends StatelessWidget {
  const _SwitchChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: FighterTheme.ink,
          borderRadius: FighterTheme.chipBorderRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.school,
              size: 15,
              color: FighterTheme.boneText,
            ),
            const SizedBox(width: 8),
            Text(
              'TROCAR DE ACADEMIA',
              style: FighterTheme.heroLabelOnInk.copyWith(
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              LucideIcons.chevronRight,
              size: 15,
              color: FighterTheme.boneText,
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.name, required this.logoUrl});

  final String name;
  final String? logoUrl;

  static const double _size = 52;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _size,
      height: _size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: FighterTheme.cardRadius,
        border: Border.all(color: FighterTheme.hairline, width: 1),
      ),
      child: logoUrl != null && logoUrl!.isNotEmpty
          ? AppCachedImage(
              imageUrl: logoUrl,
              width: _size,
              height: _size,
              fit: BoxFit.cover,
              errorIcon: _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() {
    return Container(
      width: _size,
      height: _size,
      color: FighterTheme.ink,
      alignment: Alignment.center,
      child: Text(
        _initials(),
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: FighterTheme.boneText,
        ),
      ),
    );
  }

  /// Up to 2 initials from the academy name (first letters of first two words).
  String _initials() {
    if (name.isEmpty) return 'A';
    final words = name.trim().split(RegExp(r'\s+'));
    final letters = words
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();
    return letters.isNotEmpty ? letters : 'A';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shortcut tile
// ─────────────────────────────────────────────────────────────────────────────

class _Shortcut {
  const _Shortcut({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;
  final String route;
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({required this.shortcut, required this.onTap});

  final _Shortcut shortcut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: FighterTheme.lightCard(),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: FighterTheme.bone,
                borderRadius: FighterTheme.chipBorderRadius,
              ),
              child: Icon(shortcut.icon, size: 20, color: FighterTheme.ink),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                shortcut.label.toUpperCase(),
                style: FighterTheme.heroLabel.copyWith(fontSize: 14),
              ),
            ),
            const Icon(
              LucideIcons.chevronRight,
              size: 18,
              color: FighterTheme.ash,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state — free fighter, no academy
// ─────────────────────────────────────────────────────────────────────────────

class _NoAcademyState extends StatelessWidget {
  const _NoAcademyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: PolishedEmptyState(
        icon: LucideIcons.school,
        title: 'Você ainda não está numa academia',
        subtitle:
            'Entre com o código da sua equipe pra puxar horários, presenças e '
            'o resto do tatame pra cá. Sua jornada de lutador segue com você '
            'mesmo sem academia.',
        actionLabel: 'Entrar por código',
        onAction: () => context.push('/portal/academias/adicionar'),
        accent: FighterTheme.blood,
      ),
    );
  }
}
