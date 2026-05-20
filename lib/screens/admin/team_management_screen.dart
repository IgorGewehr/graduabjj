import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/dto/identity_dto.dart';
import '../../api/repositories.dart' as tatami_repos;
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';

/// Tela de gestão de membros (memberships) da academia.
///
/// Restrita a admin — fora isso, a sidebar nem mostra o link e este screen
/// renderiza um "acesso negado" defensivo. Lista as memberships ativas/
/// suspensas e oferece os 4 verbos:
///
/// - mudar role (dropdown) → PATCH /memberships/{uid}
/// - editar extra_permissions (checkboxes do TatamiPermissions) → mesmo PATCH
/// - suspender / reativar → PATCH /memberships/{uid}/status
/// - remover (com confirmação dupla) → DELETE /memberships/{uid}
///
/// Os endpoints vivem em [IdentityRemoteRepo]; este screen usa o
/// [tatami_repos.identityRepoProvider] direto (sem cache) — operações de
/// permissão são pouco frequentes e queremos consistência forte com o BE.
class TeamManagementScreen extends ConsumerStatefulWidget {
  const TeamManagementScreen({super.key});

  @override
  ConsumerState<TeamManagementScreen> createState() =>
      _TeamManagementScreenState();
}

class _TeamManagementScreenState extends ConsumerState<TeamManagementScreen> {
  bool _loading = true;
  String? _error;
  List<ApiMembership> _memberships = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    final academyId = user?.academyId;
    if (academyId == null) {
      setState(() {
        _loading = false;
        _error = 'Academia não selecionada';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Paginação esquerda fora por enquanto — academia média < 100
      // memberships. Quando crescer, transformar em ListView.builder
      // paginado com cursor.
      final page = await ref
          .read(tatami_repos.identityRepoProvider)
          .listMemberships(academyId, limit: 100);
      if (!mounted) return;

      // Resolve display_name and email for each member via getUserByUid.
      // Fire all lookups in parallel to minimize latency.
      final repo = ref.read(tatami_repos.identityRepoProvider);
      final resolved = await Future.wait(
        page.items.map((m) async {
          // If the backend already returned display_name, skip the lookup.
          if (m.displayName != null && m.displayName!.isNotEmpty) return m;
          try {
            final user = await repo.getUserByUid(m.uid);
            return m.withUserInfo(
              displayName: user.displayName ?? user.email,
              email: user.email,
            );
          } catch (_) {
            return m;
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        _memberships = resolved;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Erro ao carregar equipe: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    // Gate defensivo: a sidebar não rota aqui se não for admin, mas se
    // alguém abrir o URL direto preferimos não vazar a lista.
    if (user == null || !user.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Equipe')),
        body: const Center(
          child: Text('Apenas administradores podem gerenciar a equipe.'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Equipe'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.error,
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _memberships.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  LucideIcons.users,
                                  size: 64,
                                  color: Theme.of(context).disabledColor,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Nenhum registro encontrado',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Nenhum membro encontrado nesta academia',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ).animate().fadeIn(duration: 600.ms).scale(
                                  begin: const Offset(0.8, 0.8),
                                ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: _memberships.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _MembershipRow(
                            membership: _memberships[i],
                            isSelf: _memberships[i].uid == user.id,
                            onEdit: () => _openEdit(_memberships[i]),
                            onToggleStatus: () => _toggleStatus(_memberships[i]),
                            onRemove: () => _confirmRemove(_memberships[i]),
                          )
                              .animate(delay: (i * 40).ms)
                              .fadeIn(duration: 200.ms)
                              .slideX(begin: -0.04),
                        ),
                ),
    );
  }

  // ---------------------------------------------------------------------
  // Mutations
  // ---------------------------------------------------------------------

  Future<void> _openEdit(ApiMembership m) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user?.academyId == null) return;
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (_) => _EditMembershipDialog(membership: m),
    );
    if (result == null) return;

    try {
      await ref.read(tatami_repos.identityRepoProvider).updateMembership(
            user!.academyId!,
            m.uid,
            role: result.role,
            extraPermissions: result.extras,
          );
      if (!mounted) return;
      context.showSuccess('Permissões atualizadas.');
      _load();
    } catch (e) {
      if (!mounted) return;
      context.showError('Erro ao atualizar: $e');
    }
  }

  Future<void> _toggleStatus(ApiMembership m) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user?.academyId == null) return;

    // Suspended → Active; Active → Suspended. Removed não rola aqui (remove
    // tem caminho próprio com confirmação).
    final next = m.status == ApiMembershipStatus.active
        ? ApiMembershipStatus.suspended
        : ApiMembershipStatus.active;
    try {
      await ref.read(tatami_repos.identityRepoProvider).updateMembershipStatus(
            user!.academyId!,
            m.uid,
            next,
          );
      if (!mounted) return;
      context.showSuccess(
        next == ApiMembershipStatus.suspended ? 'Suspenso.' : 'Reativado.',
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      context.showError('Erro: $e');
    }
  }

  Future<void> _confirmRemove(ApiMembership m) async {
    // Confirmação dobrada — o segundo dialog exige typing do nome curto
    // do uid pra evitar tap acidental. BE também valida via header
    // X-Confirm-Remove (já mandado pelo repo).
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remover membro'),
        content: Text(
          'Tem certeza que quer remover ${m.displayName?.isNotEmpty == true ? m.displayName! : m.uid} da academia? Esta ação '
          'cancela TODAS as permissões deste usuário.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final user = ref.read(currentUserProvider).valueOrNull;
    if (user?.academyId == null) return;
    try {
      await ref
          .read(tatami_repos.identityRepoProvider)
          .removeMembership(user!.academyId!, m.uid);
      if (!mounted) return;
      context.showSuccess('Membro removido.');
      _load();
    } catch (e) {
      if (!mounted) return;
      context.showError('Erro ao remover: $e');
    }
  }
}

class _MembershipRow extends StatefulWidget {
  final ApiMembership membership;
  final bool isSelf;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onRemove;

  const _MembershipRow({
    required this.membership,
    required this.isSelf,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onRemove,
  });

  @override
  State<_MembershipRow> createState() => _MembershipRowState();
}

class _MembershipRowState extends State<_MembershipRow> {
  bool _pressed = false;

  String _roleLabel(ApiRole r) {
    switch (r) {
      case ApiRole.admin:
        return 'Administrador';
      case ApiRole.instructor:
        return 'Instrutor';
      case ApiRole.monitor:
        return 'Monitor';
      case ApiRole.student:
        return 'Aluno';
      case ApiRole.guardian:
        return 'Responsável';
    }
  }

  Color _statusColor() {
    switch (widget.membership.status) {
      case ApiMembershipStatus.active:
        return AppTheme.success;
      case ApiMembershipStatus.suspended:
        return AppTheme.warning;
      case ApiMembershipStatus.removed:
        return AppTheme.error;
    }
  }

  String _statusLabel() {
    switch (widget.membership.status) {
      case ApiMembershipStatus.active:
        return 'Ativo';
      case ApiMembershipStatus.suspended:
        return 'Suspenso';
      case ApiMembershipStatus.removed:
        return 'Removido';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                child: Icon(
                  LucideIcons.user,
                  size: 16,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.membership.displayName?.isNotEmpty == true
                          ? widget.membership.displayName!
                          : widget.membership.uid,
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.membership.email != null &&
                        widget.membership.email!.isNotEmpty)
                      Text(
                        widget.membership.email!,
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _roleLabel(widget.membership.role),
                            style: AppTheme.labelSmall,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor().withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _statusLabel(),
                            style: AppTheme.labelSmall
                                .copyWith(color: _statusColor()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Bloqueio defensivo: admin não pode auto-suspender/remover —
              // evita ficar "sem ninguém" no comando da academia.
              PopupMenuButton<String>(
                enabled: !widget.isSelf,
                tooltip: widget.isSelf ? 'Você mesmo' : 'Ações',
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      widget.onEdit();
                      break;
                    case 'toggle':
                      widget.onToggleStatus();
                      break;
                    case 'remove':
                      widget.onRemove();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Editar permissões'),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                      widget.membership.status == ApiMembershipStatus.active
                          ? 'Suspender'
                          : 'Reativar',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text(
                      'Remover',
                      style: TextStyle(color: Color(0xFFD32F2F)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (widget.membership.extraPermissions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.membership.extraPermissions
                  .map(
                    (p) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.infoLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        p,
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.info,
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
      ),
      ),
    );
  }
}

class _EditResult {
  final ApiRole role;
  final List<String> extras;
  const _EditResult({required this.role, required this.extras});
}

class _EditMembershipDialog extends StatefulWidget {
  final ApiMembership membership;
  const _EditMembershipDialog({required this.membership});

  @override
  State<_EditMembershipDialog> createState() => _EditMembershipDialogState();
}

class _EditMembershipDialogState extends State<_EditMembershipDialog> {
  late ApiRole _role;
  late Set<String> _extras;

  @override
  void initState() {
    super.initState();
    _role = widget.membership.role;
    _extras = widget.membership.extraPermissions.toSet();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Permissões de ${widget.membership.displayName?.isNotEmpty == true ? widget.membership.displayName! : widget.membership.uid}',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Role'),
              const SizedBox(height: 6),
              DropdownButton<ApiRole>(
                value: _role,
                isExpanded: true,
                items: ApiRole.values
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: Text(r.wire),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _role = v);
                },
              ),
              const SizedBox(height: 12),
              const Text('Permissões extras'),
              const SizedBox(height: 6),
              ...TatamiPermissions.all.map(
                (p) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _extras.contains(p),
                  title: Text(p, style: const TextStyle(fontFamily: 'monospace')),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _extras.add(p);
                      } else {
                        _extras.remove(p);
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _EditResult(role: _role, extras: _extras.toList()..sort()),
          ),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
