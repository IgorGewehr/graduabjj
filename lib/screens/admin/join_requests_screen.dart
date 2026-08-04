import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/join_request.dart';
import '../../models/student.dart';
import '../../providers/join_request_providers.dart';
import '../../services/firebase_service.dart';
import '../../services/student_service.dart';
import '../../services/team_service.dart';
import '../../widgets/polish/polish.dart';

/// Solicitações de entrada (self-onboarding). O professor vê os alunos que se
/// cadastraram com o código da academia e aprova (linkando a uma ficha existente
/// OU criando uma nova) ou nega. Também exibe/gera o código único da academia.
class AdminJoinRequestsScreen extends ConsumerStatefulWidget {
  const AdminJoinRequestsScreen({super.key});

  @override
  ConsumerState<AdminJoinRequestsScreen> createState() =>
      _AdminJoinRequestsScreenState();
}

class _AdminJoinRequestsScreenState
    extends ConsumerState<AdminJoinRequestsScreen> {
  final _busy = <String>{}; // uids em processamento
  bool _rotating = false;

  String get _academyId => FirebaseService.academyId;

  // ── Normalização p/ sugestão de match (nome sem acento/caixa) ──────────────
  static const _accents = {
    'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
    'é': 'e', 'ê': 'e', 'è': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
    'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c', 'ñ': 'n',
  };
  String _norm(String? s) {
    var out = (s ?? '').toLowerCase().trim();
    _accents.forEach((k, v) => out = out.replaceAll(k, v));
    return out.replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _generateOrRotateCode({required bool rotate}) async {
    if (rotate) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Gerar novo código?'),
          content: const Text(
            'O código atual deixa de funcionar. Alunos que ainda não se '
            'cadastraram vão precisar do código novo.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Gerar novo')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _rotating = true);
    try {
      await teamService.rotateAcademyJoinCode(_academyId);
      // O stream de academyJoinCodeProvider atualiza sozinho.
    } catch (e) {
      if (mounted) context.showError('Não foi possível gerar o código.');
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  Future<void> _deny(JoinRequest req) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Negar solicitação?'),
        content: Text('${req.fullName} não será adicionado à academia. '
            'Ele pode solicitar de novo depois.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Negar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _decide(req, action: 'deny');
  }

  Future<void> _decide(JoinRequest req,
      {required String action, String? linkStudentId}) async {
    setState(() => _busy.add(req.uid));
    try {
      await teamService.decideJoinRequest(
        academyId: _academyId,
        requestUid: req.uid,
        action: action,
        linkStudentId: linkStudentId,
      );
      if (mounted) {
        context.showSuccess(action == 'approve'
            ? '${req.fullName} aprovado!'
            : 'Solicitação de ${req.fullName} negada.');
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('já está vinculada')
            ? 'Essa ficha já está vinculada a outra conta.'
            : 'Não foi possível concluir. Tente de novo.';
        context.showError(msg);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(req.uid));
    }
  }

  Future<void> _approve(JoinRequest req) async {
    // Carrega fichas ÓRFÃS (sem conta vinculada) para oferecer vínculo + sugestão.
    List<Student> orphans = const [];
    try {
      final all = await StudentService(_academyId).getAll();
      orphans = all
          .where((s) => (s.linkedUserId == null || s.linkedUserId!.isEmpty))
          .toList();
    } catch (_) {/* segue sem lista — ainda dá pra criar nova */}

    // Sugestão: CPF igual (forte) senão nome normalizado igual.
    Student? suggestion;
    String? suggestionReason;
    final reqCpf = (req.cpf ?? '').replaceAll(RegExp(r'\D'), '');
    if (reqCpf.isNotEmpty) {
      for (final s in orphans) {
        if ((s.cpf ?? '').replaceAll(RegExp(r'\D'), '') == reqCpf) {
          suggestion = s;
          suggestionReason = 'mesmo CPF';
          break;
        }
      }
    }
    if (suggestion == null) {
      final reqName = _norm(req.fullName);
      for (final s in orphans) {
        if (_norm(s.fullName) == reqName && reqName.isNotEmpty) {
          suggestion = s;
          suggestionReason = 'mesmo nome';
          break;
        }
      }
    }

    if (!mounted) return;
    final choice = await showModalBottomSheet<_ApproveChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ApproveSheet(
        request: req,
        orphans: orphans,
        suggestion: suggestion,
        suggestionReason: suggestionReason,
        norm: _norm,
      ),
    );
    if (choice == null) return;
    await _decide(req,
        action: 'approve', linkStudentId: choice.linkStudentId);
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(academyJoinRequestsProvider);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Solicitações'),
      ),
      body: Column(
        children: [
          _buildCodeCard(),
          Expanded(
            child: requestsAsync.when(
              loading: () => Padding(
                padding: const EdgeInsets.all(20),
                child: PolishSkeleton.list(count: 4, itemHeight: 120),
              ),
              error: (e, _) => const PolishedEmptyState(
                icon: LucideIcons.alertTriangle,
                title: 'Erro ao carregar',
                subtitle: 'Verifique sua conexão e tente novamente.',
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const PolishedEmptyState(
                    icon: LucideIcons.inbox,
                    title: 'Nenhuma solicitação',
                    subtitle:
                        'Quando um aluno se cadastrar com o código da academia, '
                        'a solicitação aparece aqui para você aprovar.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final req = list[i];
                    return _RequestCard(
                      request: req,
                      busy: _busy.contains(req.uid),
                      onApprove: () => _approve(req),
                      onDeny: () => _deny(req),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeCard() {
    final codeAsync = ref.watch(academyJoinCodeProvider);
    final code = codeAsync.valueOrNull;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(LucideIcons.ticket, color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Código da academia',
                    style: AppTheme.labelSmall
                        .copyWith(color: AppTheme.textSecondary)),
                const SizedBox(height: 2),
                if (code == null || code.isEmpty)
                  Text('Ainda não gerado',
                      style: AppTheme.bodyMedium
                          .copyWith(fontWeight: FontWeight.w600))
                else
                  Text(
                    code,
                    style: AppTheme.headlineSmall.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 4,
                    ),
                  ),
              ],
            ),
          ),
          if (_rotating)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (code == null || code.isEmpty)
            FilledButton(
              onPressed: () => _generateOrRotateCode(rotate: false),
              child: const Text('Gerar'),
            )
          else ...[
            IconButton(
              tooltip: 'Copiar',
              icon: const Icon(LucideIcons.copy, size: 20),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                context.showSuccess('Código copiado!');
              },
            ),
            IconButton(
              tooltip: 'Gerar novo',
              icon: const Icon(LucideIcons.refreshCw, size: 20),
              onPressed: () => _generateOrRotateCode(rotate: true),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApproveChoice {
  /// null = criar ficha nova; caso contrário linka a esta ficha existente.
  final String? linkStudentId;
  const _ApproveChoice(this.linkStudentId);
}

class _RequestCard extends StatelessWidget {
  final JoinRequest request;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  const _RequestCard({
    required this.request,
    required this.busy,
    required this.onApprove,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final initial =
        request.fullName.isNotEmpty ? request.fullName[0].toUpperCase() : '?';
    final when = request.createdAt != null
        ? DateFormat("d/MM 'às' HH:mm").format(request.createdAt!)
        : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                child: Text(initial,
                    style: TextStyle(
                        color: AppTheme.primary, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request.fullName,
                        style: AppTheme.titleSmall
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      children: [
                        if ((request.phone ?? '').isNotEmpty)
                          _meta(LucideIcons.phone, request.phone!),
                        if ((request.cpf ?? '').isNotEmpty)
                          _meta(LucideIcons.fileText, request.cpf!),
                        if ((request.email ?? '').isNotEmpty)
                          _meta(LucideIcons.mail, request.email!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (when != null) ...[
            const SizedBox(height: 8),
            Text('Solicitado em $when',
                style: AppTheme.labelSmall
                    .copyWith(color: AppTheme.textSecondary)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onDeny,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: BorderSide(
                        color: AppTheme.error.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Negar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: busy ? null : onApprove,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(LucideIcons.check, size: 18),
                  label: const Text('Aprovar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(text,
              style: AppTheme.labelSmall
                  .copyWith(color: AppTheme.textSecondary)),
        ],
      );
}

/// Bottom sheet de aprovação: sugestão de match + criar nova + buscar existente.
class _ApproveSheet extends StatefulWidget {
  final JoinRequest request;
  final List<Student> orphans;
  final Student? suggestion;
  final String? suggestionReason;
  final String Function(String?) norm;

  const _ApproveSheet({
    required this.request,
    required this.orphans,
    required this.suggestion,
    required this.suggestionReason,
    required this.norm,
  });

  @override
  State<_ApproveSheet> createState() => _ApproveSheetState();
}

class _ApproveSheetState extends State<_ApproveSheet> {
  final _searchController = TextEditingController();
  bool _showSearch = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _beltLabel(Student s) {
    final g = s.getGrade(SportId.bjj);
    if (g == null) return '';
    return getGradeLabel(SportId.bjj, g.currentGrade);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.orphans
        : widget.orphans
            .where((s) => widget.norm(s.fullName).contains(widget.norm(_query)))
            .toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Aprovar ${widget.request.fullName}',
              style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Ligue este cadastro a uma ficha que já existe ou crie uma nova. '
            'Cada ficha só pode ter uma conta.',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),

          // Sugestão de match
          if (widget.suggestion != null && !_showSearch) ...[
            _SuggestionTile(
              student: widget.suggestion!,
              reason: widget.suggestionReason ?? '',
              beltLabel: _beltLabel(widget.suggestion!),
              onTap: () => Navigator.pop(
                  context, _ApproveChoice(widget.suggestion!.id)),
            ),
            const SizedBox(height: 12),
          ],

          // Criar ficha nova
          if (!_showSearch)
            _ActionTile(
              icon: LucideIcons.userPlus,
              iconColor: AppTheme.success,
              title: 'Criar ficha nova',
              subtitle: 'Usa os dados que o aluno preencheu no cadastro.',
              onTap: () => Navigator.pop(context, const _ApproveChoice(null)),
            ),

          // Vincular a aluno existente (busca)
          if (!_showSearch) ...[
            const SizedBox(height: 12),
            _ActionTile(
              icon: LucideIcons.link,
              iconColor: AppTheme.primary,
              title: 'Vincular a um aluno existente',
              subtitle: widget.orphans.isEmpty
                  ? 'Nenhuma ficha sem conta disponível.'
                  : '${widget.orphans.length} ficha(s) sem conta.',
              onTap: widget.orphans.isEmpty
                  ? null
                  : () => setState(() => _showSearch = true),
            ),
          ],

          // Modo busca
          if (_showSearch) ...[
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Buscar aluno pelo nome...',
                prefixIcon: const Icon(LucideIcons.search, size: 20),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4),
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Nenhum aluno encontrado.',
                          style: AppTheme.bodySmall
                              .copyWith(color: AppTheme.textSecondary)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final s = filtered[i];
                        final belt = _beltLabel(s);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor:
                                AppTheme.primary.withValues(alpha: 0.1),
                            child: Text(
                              s.fullName.isNotEmpty
                                  ? s.fullName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(color: AppTheme.primary),
                            ),
                          ),
                          title: Text(s.fullName),
                          subtitle: belt.isEmpty ? null : Text(belt),
                          trailing: const Icon(LucideIcons.chevronRight,
                              size: 18),
                          onTap: () =>
                              Navigator.pop(context, _ApproveChoice(s.id)),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => setState(() {
                _showSearch = false;
                _query = '';
                _searchController.clear();
              }),
              icon: const Icon(LucideIcons.arrowLeft, size: 16),
              label: const Text('Voltar'),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final Student student;
  final String reason;
  final String beltLabel;
  final VoidCallback onTap;

  const _SuggestionTile({
    required this.student,
    required this.reason,
    required this.beltLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.sparkles, color: AppTheme.warning, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Provável match • $reason',
                      style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.warning,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    beltLabel.isEmpty
                        ? student.fullName
                        : '${student.fullName} • $beltLabel',
                    style: AppTheme.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppTheme.bodyMedium
                            .copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: AppTheme.labelSmall
                            .copyWith(color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              if (!disabled) const Icon(LucideIcons.chevronRight, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
