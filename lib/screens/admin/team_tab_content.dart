import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/instructor_link_code_service.dart';

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
  InstructorLinkCodeService? _service;

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
          _loading = false;
        });
        return;
      }
      _service = InstructorLinkCodeService(user!.academyId!);
      final list = await _service!.listActive();
      setState(() {
        _codes = list;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
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
                border: Border.all(color: AppTheme.info.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.info, size: 18, color: AppTheme.info),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Gere um código de 8 caracteres valido por 30 minutos. O professor digita esse codigo na tela inicial do app/web e vira instrutor automaticamente com as permissoes que voce marcar.',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.info,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _service == null ? null : _openInviteDialog,
                icon: const Icon(LucideIcons.userPlus, size: 16),
                label: const Text('Convidar professor'),
              ),
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_codes.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Nenhum convite ativo.',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              )
            else
              ..._codes.map(
                (c) => _CodeRow(
                  code: c,
                  onCopy: () => _copyCode(c.code),
                  onDelete: () => _delete(c),
                ),
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
                icon: Icon(LucideIcons.copy, size: 16, color: AppTheme.textSecondary),
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
                style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                    Text(_error!,
                        style: AppTheme.labelSmall.copyWith(color: AppTheme.error)),
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
                onPressed: _generating ? null : () => Navigator.of(context).pop(),
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
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Gerar codigo'),
              ),
            ],
    );
  }
}
