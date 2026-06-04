import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../services/instructor_link_code_service.dart';
import '../../services/student_service.dart';
import '../../services/team_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/polish/polish.dart';

/// Team management tab for academy admins.
///
/// Lists active invite codes and lets the owner generate a new one with
/// hand-picked extra permissions. Mirrors the marcusjj TeamTab — keeps the
/// invite codes as the surface (ongoing instructor management is a v2).
class TeamTabContent extends ConsumerStatefulWidget {
  const TeamTabContent({super.key});

  @override
  ConsumerState<TeamTabContent> createState() => _TeamTabContentState();
}

class _TeamTabContentState extends ConsumerState<TeamTabContent> {
  bool _loading = true;
  List<InstructorLinkCode> _codes = const [];
  AcademyMembers _members =
      const AcademyMembers(admins: [], instructors: [], students: []);
  InstructorLinkCodeService? _service;
  String? _academyId;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      if (user?.academyId == null) {
        setState(() {
          _codes = const [];
          _members = const AcademyMembers(
            admins: [],
            instructors: [],
            students: [],
          );
          _loading = false;
        });
        return;
      }
      _academyId = user!.academyId!;
      _service = InstructorLinkCodeService(_academyId!);
      // Codes + members loaded in parallel — both routinely take >100ms each
      // and they're independent.
      final results = await Future.wait([
        _service!.listActive(),
        teamService.listMembers(_academyId!),
      ]);
      setState(() {
        _codes = results[0] as List<InstructorLinkCode>;
        _members = results[1] as AcademyMembers;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _demoteMember(AcademyMember m) async {
    if (_academyId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rebaixar para aluno?'),
        content: Text(
          '${m.displayName} voltará a ser aluno e perderá o acesso administrativo. '
          'A vinculação à academia é mantida.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.warning),
            child: const Text('Rebaixar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await teamService.demoteToStudent(
        userId: m.userId,
        academyId: _academyId!,
      );
      if (!mounted) return;
      context.showSuccess('${m.displayName} agora é aluno.');
      _refresh();
    } catch (e) {
      if (!mounted) return;
      context.showError('Não foi possível rebaixar: $e');
    }
  }

  Future<void> _revokeMember(AcademyMember m) async {
    if (_academyId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover da academia?'),
        content: Text(
          '${m.displayName} será removido da academia e perderá todo o acesso. '
          'Esta ação não apaga o histórico, apenas o vínculo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await teamService.revokeMember(
        userId: m.userId,
        academyId: _academyId!,
      );
      if (!mounted) return;
      context.showSuccess('${m.displayName} foi removido.');
      _refresh();
    } catch (e) {
      if (!mounted) return;
      context.showError('Não foi possível remover: $e');
    }
  }

  Future<void> _openInviteDialog() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null || _service == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _InviteDialog(
        service: _service!,
        createdBy: user.id,
        createdByName: user.displayName,
        onCreated: (_) => _refresh(),
      ),
    );
  }

  Future<void> _openPromoteDialog() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user?.academyId == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _PromoteDialog(academyId: user!.academyId!),
    );
    _refresh();
  }

  Future<void> _openEditPermissionsDialog(AcademyMember m) async {
    final academyId = _academyId;
    if (academyId == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _EditPermissionsDialog(
        member: m,
        academyId: academyId,
      ),
    );
    _refresh();
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    context.showSuccess('Código $code copiado.');
  }

  Future<void> _delete(InstructorLinkCode c) async {
    if (_service == null) return;
    try {
      await _service!.delete(c.id);
      if (!mounted) return;
      context.showInfo('Convite removido.');
      _refresh();
    } catch (_) {
      if (!mounted) return;
      context.showError('Erro ao remover convite.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.infoLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.info.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.info, size: 18, color: AppTheme.info),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Gere um código de 8 caracteres valido por 30 minutos. O professor digita esse codigo na tela inicial do app/web e vira instrutor automaticamente com as permissoes que voce marcar.',
                      style: AppTheme.bodySmall.copyWith(color: AppTheme.info),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _service == null ? null : _openPromoteDialog,
                    icon: const Icon(LucideIcons.arrowUpCircle, size: 16),
                    label: const Text('Promover aluno'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _service == null ? null : _openInviteDialog,
                    icon: const Icon(LucideIcons.userPlus, size: 16),
                    label: const Text('Convidar professor'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'EQUIPE ATUAL',
              style: AppTheme.labelSmall.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            _TeamMembersSection(
              loading: _loading,
              admins: _members.admins,
              instructors: _members.instructors,
              onDemote: _demoteMember,
              onRevoke: _revokeMember,
              onEditPermissions: _openEditPermissionsDialog,
              currentUserId: ref.read(currentUserProvider).valueOrNull?.id,
            ),
            const SizedBox(height: 24),
            Text(
              'CONVITES ATIVOS',
              style: AppTheme.labelSmall.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              PolishSkeleton.list(count: 2, itemHeight: 90)
            else if (_codes.isEmpty)
              const PolishedEmptyState(
                icon: LucideIcons.ticket,
                title: 'Nenhum convite ativo',
                subtitle: 'Gere um codigo para convidar um professor.',
              )
            else
              ..._codes.asMap().entries.map(
                (e) => _CodeRow(
                  code: e.value,
                  onCopy: () => _copyCode(e.value.code),
                  onDelete: () => _delete(e.value),
                ).entrance(index: e.key),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  final InstructorLinkCode code;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  const _CodeRow({
    required this.code,
    required this.onCopy,
    required this.onDelete,
  });

  String _remainingLabel() {
    final remaining = code.expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return 'expirado';
    final min = remaining.inMinutes;
    return 'expira em ${min}min';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
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
              Expanded(
                child: Text(
                  code.code,
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  LucideIcons.copy,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
                onPressed: onCopy,
                tooltip: 'Copiar codigo',
              ),
              IconButton(
                icon: Icon(LucideIcons.trash2, size: 16, color: AppTheme.error),
                onPressed: onDelete,
                tooltip: 'Remover',
              ),
            ],
          ),
          Row(
            children: [
              Icon(LucideIcons.clock, size: 12, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
              Text(
                _remainingLabel(),
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          if (code.extraPermissions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: code.extraPermissions.map((p) {
                final def = kGrantableExtraPermissions
                    .where((g) => g.permission == p)
                    .firstOrNull;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    def?.label ?? p,
                    style: AppTheme.labelSmall.copyWith(fontSize: 10),
                  ),
                );
              }).toList(),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Apenas permissoes padrao do instrutor',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InviteDialog extends StatefulWidget {
  final InstructorLinkCodeService service;
  final String createdBy;
  final String createdByName;
  final ValueChanged<InstructorLinkCode> onCreated;

  const _InviteDialog({
    required this.service,
    required this.createdBy,
    required this.createdByName,
    required this.onCreated,
  });

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final Set<String> _selected = {};
  bool _generating = false;
  InstructorLinkCode? _created;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final code = await widget.service.generate(
        createdBy: widget.createdBy,
        createdByName: widget.createdByName,
        extraPermissions: _selected.toList(),
      );
      widget.onCreated(code);
      if (!mounted) return;
      setState(() {
        _created = code;
        _generating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = 'Erro ao gerar codigo. Tente novamente.';
      });
    }
  }

  Future<void> _copy() async {
    if (_created == null) return;
    await Clipboard.setData(ClipboardData(text: _created!.code));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_created != null ? 'Codigo gerado' : 'Convidar professor'),
      content: _created != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Envie este codigo ao professor — valido por 30 minutos',
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _created!.code,
                  style: AppTheme.displaySmall.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _copy,
                  icon: const Icon(LucideIcons.copy, size: 14),
                  label: const Text('Copiar codigo'),
                ),
              ],
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selecione as permissoes extras. As permissoes base do instrutor (chamada, turmas, alunos) sao incluidas automaticamente.',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...kGrantableExtraPermissions.map(
                    (def) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _selected.contains(def.permission),
                      onChanged: _generating
                          ? null
                          : (v) {
                              setState(() {
                                if (v == true) {
                                  _selected.add(def.permission);
                                } else {
                                  _selected.remove(def.permission);
                                }
                              });
                            },
                      title: Text(
                        def.label,
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        def.description,
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
      actions: _created != null
          ? [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fechar'),
              ),
            ]
          : [
              TextButton(
                onPressed: _generating
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: _generating ? null : _generate,
                child: _generating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text('Gerar codigo'),
              ),
            ],
    );
  }
}

/// Promote an existing linked student to instructor with optional extra
/// permissions. Mirrors the web PromoteDialog.
class _PromoteDialog extends ConsumerStatefulWidget {
  final String academyId;
  const _PromoteDialog({required this.academyId});

  @override
  ConsumerState<_PromoteDialog> createState() => _PromoteDialogState();
}

class _PromoteDialogState extends ConsumerState<_PromoteDialog> {
  final _searchController = TextEditingController();
  final Set<String> _extras = {};
  List<Student> _candidates = const [];
  Student? _selected;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    try {
      final svc = StudentService(widget.academyId);
      final all = await svc.listAll();
      if (!mounted) return;
      setState(() {
        _candidates = all
            .where((s) => (s.linkedUserId ?? '').isNotEmpty)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<Student> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _candidates;
    return _candidates.where((s) {
      return s.fullName.toLowerCase().contains(q) ||
          (s.nickname?.toLowerCase().contains(q) ?? false) ||
          (s.email?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _submit() async {
    if (_selected == null || (_selected!.linkedUserId ?? '').isEmpty) return;
    setState(() => _submitting = true);
    try {
      await promoteUserToInstructor(
        userId: _selected!.linkedUserId!,
        academyId: widget.academyId,
        extraPermissions: _extras.toList(),
        email: _selected!.email,
        displayName: _selected!.fullName,
      );
      if (!mounted) return;
      context.showSuccess('${_selected!.fullName} promovido a instrutor.');
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      context.showError('Erro ao promover aluno.');
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _selected == null
            ? 'Promover aluno a instrutor'
            : 'Promover ${_selected!.fullName}',
      ),
      content: SizedBox(
        width: 500,
        child: _selected != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'O aluno mantem o acesso ao portal de aluno, mas passa a ver os recursos de instrutor com as permissoes selecionadas.',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: kGrantableExtraPermissions
                            .map(
                              (def) => CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: _extras.contains(def.permission),
                                onChanged: _submitting
                                    ? null
                                    : (v) {
                                        setState(() {
                                          if (v == true) {
                                            _extras.add(def.permission);
                                          } else {
                                            _extras.remove(def.permission);
                                          }
                                        });
                                      },
                                title: Text(
                                  def.label,
                                  style: AppTheme.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  def.description,
                                  style: AppTheme.labelSmall.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Apenas alunos com conta criada aparecem na lista.',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nome ou email...',
                      prefixIcon: Icon(LucideIcons.search, size: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _loading
                        ? PolishSkeleton.list(
                            count: 5,
                            itemHeight: 56,
                            scrollable: false,
                            padding: EdgeInsets.zero,
                          )
                        : _filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Nenhum aluno encontrado.',
                              style: AppTheme.bodyMedium.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final s = _filtered[i];
                              return ListTile(
                                leading: AppCachedAvatar(
                                  imageUrl: s.photoUrl,
                                  radius: 16,
                                  child: (s.photoUrl ?? '').isEmpty
                                      ? Text(
                                          s.fullName
                                              .substring(0, 1)
                                              .toUpperCase(),
                                        )
                                      : null,
                                ),
                                title: Text(s.fullName),
                                subtitle: Text(s.email ?? '—'),
                                onTap: () => setState(() {
                                  _selected = s;
                                }),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: _selected != null
          ? [
              TextButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() => _selected = null),
                child: const Text('Voltar'),
              ),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text('Promover a instrutor'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
            ],
    );
  }
}

class _TeamMembersSection extends StatelessWidget {
  final bool loading;
  final List<AcademyMember> admins;
  final List<AcademyMember> instructors;
  final ValueChanged<AcademyMember> onDemote;
  final ValueChanged<AcademyMember> onRevoke;
  final ValueChanged<AcademyMember> onEditPermissions;
  final String? currentUserId;

  const _TeamMembersSection({
    required this.loading,
    required this.admins,
    required this.instructors,
    required this.onDemote,
    required this.onRevoke,
    required this.onEditPermissions,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return PolishSkeleton.list(count: 2, itemHeight: 72);
    }
    if (admins.isEmpty && instructors.isEmpty) {
      return const PolishedEmptyState(
        icon: LucideIcons.users,
        title: 'Ainda nao ha equipe cadastrada',
        subtitle: 'Convide professores ou promova alunos.',
      );
    }
    var memberIndex = -1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in admins)
          _MemberRow(
            member: m,
            badgeLabel: 'Admin',
            badgeColor: AppTheme.primary,
            // Admins cannot be demoted or revoked from this screen — explicit
            // safety so the academy doesn't accidentally orphan itself.
            actions: const [],
          ).entrance(index: ++memberIndex),
        for (final m in instructors)
          _MemberRow(
            member: m,
            badgeLabel: 'Instrutor',
            badgeColor: AppTheme.info,
            actions: m.userId == currentUserId
                ? const []
                : [
                    _MemberAction(
                      icon: LucideIcons.settings,
                      label: 'Editar permissões',
                      color: AppTheme.info,
                      onTap: () => onEditPermissions(m),
                    ),
                    _MemberAction(
                      icon: LucideIcons.userMinus,
                      label: 'Rebaixar',
                      color: AppTheme.warning,
                      onTap: () => onDemote(m),
                    ),
                    _MemberAction(
                      icon: LucideIcons.userX,
                      label: 'Remover',
                      color: AppTheme.error,
                      onTap: () => onRevoke(m),
                    ),
                  ],
          ).entrance(index: ++memberIndex),
      ],
    );
  }
}

class _MemberAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MemberAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

/// Edit the extra permissions of an existing instructor (re-promotes idempotently).
class _EditPermissionsDialog extends ConsumerStatefulWidget {
  final AcademyMember member;
  final String academyId;
  const _EditPermissionsDialog({required this.member, required this.academyId});

  @override
  ConsumerState<_EditPermissionsDialog> createState() =>
      _EditPermissionsDialogState();
}

class _EditPermissionsDialogState
    extends ConsumerState<_EditPermissionsDialog> {
  late Set<String> _selected;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.member.extraPermissions);
  }

  Future<void> _save() async {
    setState(() => _submitting = true);
    try {
      await teamService.promoteToInstructor(
        userId: widget.member.userId,
        academyId: widget.academyId,
        extraPermissions: _selected.toList(),
      );
      if (!mounted) return;
      context.showSuccess('Permissões de ${widget.member.displayName} atualizadas.');
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      context.showError('Erro ao atualizar permissões.');
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Permissões de ${widget.member.displayName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selecione as permissões extras deste instrutor.',
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            ...kGrantableExtraPermissions.map(
              (def) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _selected.contains(def.permission),
                onChanged: _submitting
                    ? null
                    : (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(def.permission);
                          } else {
                            _selected.remove(def.permission);
                          }
                        });
                      },
                title: Text(
                  def.label,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  def.description,
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _submitting ? null : _save,
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Salvar'),
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  final AcademyMember member;
  final String badgeLabel;
  final Color badgeColor;
  final List<_MemberAction> actions;

  const _MemberRow({
    required this.member,
    required this.badgeLabel,
    required this.badgeColor,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final permissionsLabel = member.extraPermissions.isEmpty
        ? null
        : member.extraPermissions.length == 1
            ? '1 permissão extra'
            : '${member.extraPermissions.length} permissões extras';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.displayName.isEmpty
                            ? member.email
                            : member.displayName,
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeLabel,
                        style: AppTheme.labelSmall.copyWith(
                          color: badgeColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (member.email.isNotEmpty &&
                    member.email != member.displayName) ...[
                  const SizedBox(height: 2),
                  Text(
                    member.email,
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (permissionsLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    permissionsLabel,
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final a in actions) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: a.label,
              icon: Icon(a.icon, size: 18, color: a.color),
              onPressed: a.onTap,
            ),
          ],
        ],
      ),
    );
  }
}
