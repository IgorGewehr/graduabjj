import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../providers/providers.dart';
import '../../../widgets/common/delete_account_helper.dart';

/// Account section with delete account option
class ProfileAccountSection extends ConsumerWidget {
  const ProfileAccountSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CONTA',
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            children: [
              // Change password
              _AccountTile(
                icon: LucideIcons.lock,
                title: 'Trocar senha',
                onTap: () => _showChangePasswordDialog(context, ref),
              ),
              const Divider(height: 1),
              // Redeem instructor code
              _AccountTile(
                icon: LucideIcons.key,
                title: 'Resgatar código de equipe',
                onTap: () => context.push('/codigo-equipe'),
              ),
              const Divider(height: 1),
              // Legal links
              _AccountTile(
                icon: LucideIcons.fileText,
                title: 'Termos de Uso',
                onTap: () => _openUrl(AppConstants.termsOfServiceUrl),
              ),
              const Divider(height: 1),
              _AccountTile(
                icon: LucideIcons.shield,
                title: 'Politica de Privacidade',
                onTap: () => _openUrl(AppConstants.privacyPolicyUrl),
              ),
              const Divider(height: 1),
              // Delete account
              _AccountTile(
                icon: LucideIcons.trash2,
                title: 'Excluir minha conta',
                isDestructive: true,
                onTap: () => DeleteAccountHelper.showConfirmation(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        onSubmit: (current, next) async {
          final authService = ref.read(authServiceProvider);
          await authService.updatePassword(
            currentPassword: current,
            newPassword: next,
          );
        },
      ),
    );
  }
}

/// Dialog that asks for current password + new password + confirmation, then
/// triggers reauth + update. Validates new password length and confirmation
/// match client-side; Firebase errors (`wrong-password`,
/// `requires-recent-login`, etc.) are surfaced inline.
class _ChangePasswordDialog extends StatefulWidget {
  final Future<void> Function(String currentPassword, String newPassword)
  onSubmit;

  const _ChangePasswordDialog({required this.onSubmit});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _showCurrent = false;
  bool _showNew = false;
  bool _saving = false;
  bool _success = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cur = _currentController.text;
    final next = _newController.text;
    final conf = _confirmController.text;

    if (cur.isEmpty) {
      setState(() => _error = 'Informe sua senha atual.');
      return;
    }
    if (next.length < 6) {
      setState(
        () => _error = 'A nova senha precisa ter pelo menos 6 caracteres.',
      );
      return;
    }
    if (next != conf) {
      setState(() => _error = 'A confirmacao nao bate com a nova senha.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(cur, next);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _success = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _mapError(e);
      });
    }
  }

  String _mapError(Object e) {
    final s = e.toString();
    if (s.contains('wrong-password') || s.contains('invalid-credential')) {
      return 'Senha atual incorreta.';
    }
    if (s.contains('requires-recent-login')) {
      return 'Por seguranca, saia e entre novamente antes de trocar a senha.';
    }
    if (s.contains('weak-password')) {
      return 'Senha muito fraca. Use ao menos 6 caracteres.';
    }
    return 'Erro ao trocar a senha. Tente novamente.';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_success ? 'Senha atualizada' : 'Trocar senha'),
      content: _success
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.checkCircle,
                  color: AppTheme.success,
                  size: 36,
                ),
                const SizedBox(height: 12),
                Text(
                  'Sua senha foi alterada com sucesso.',
                  style: AppTheme.bodyMedium,
                ),
              ],
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _currentController,
                    obscureText: !_showCurrent,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      labelText: 'Senha atual',
                      prefixIcon: const Icon(LucideIcons.lock, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showCurrent ? LucideIcons.eyeOff : LucideIcons.eye,
                          size: 18,
                        ),
                        onPressed: () =>
                            setState(() => _showCurrent = !_showCurrent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newController,
                    obscureText: !_showNew,
                    enabled: !_saving,
                    decoration: InputDecoration(
                      labelText: 'Nova senha',
                      prefixIcon: const Icon(LucideIcons.key, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showNew ? LucideIcons.eyeOff : LucideIcons.eye,
                          size: 18,
                        ),
                        onPressed: () => setState(() => _showNew = !_showNew),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmController,
                    obscureText: !_showNew,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Confirmar nova senha',
                      prefixIcon: Icon(LucideIcons.key, size: 18),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
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
      actions: _success
          ? [
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ]
          : [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
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
                    : const Text('Salvar'),
              ),
            ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isDestructive;

  const _AccountTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppTheme.error : AppTheme.textPrimary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: AppTheme.bodyMedium.copyWith(color: color),
              ),
            ),
            Icon(
              LucideIcons.chevronRight,
              size: 16,
              color: isDestructive
                  ? AppTheme.error.withValues(alpha: 0.5)
                  : AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
