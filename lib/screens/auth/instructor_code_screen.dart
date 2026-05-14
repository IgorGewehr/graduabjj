import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/instructor_link_code_service.dart';

/// Screen for an authenticated user to redeem an instructor invite code.
///
/// Flow:
///   1. User pastes the 8-char code.
///   2. `validateInstructorCodeGlobally` finds it across all academies via
///      collectionGroup (anonymous-readable rule).
///   3. User sees what permissions they'll get and confirms.
///   4. `redeemInstructorCode` links the user to that academy as `instructor`
///      and stamps the snapshot of `extraPermissions` into the mapping.
class InstructorCodeScreen extends ConsumerStatefulWidget {
  const InstructorCodeScreen({super.key});

  @override
  ConsumerState<InstructorCodeScreen> createState() =>
      _InstructorCodeScreenState();
}

class _InstructorCodeScreenState extends ConsumerState<InstructorCodeScreen> {
  final _codeController = TextEditingController();
  bool _validating = false;
  bool _redeeming = false;
  String? _error;
  ({InstructorLinkCode code, String academyId})? _resolved;
  bool _done = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _validate() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.length < 6) {
      setState(() => _error = 'Digite o codigo de 8 caracteres.');
      return;
    }
    setState(() {
      _error = null;
      _validating = true;
    });
    try {
      final found = await validateInstructorCodeGlobally(code);
      if (!mounted) return;
      if (found == null) {
        setState(() {
          _error = 'Codigo invalido, expirado ou ja usado.';
          _validating = false;
        });
        return;
      }
      setState(() {
        _resolved = found;
        _validating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao validar o codigo. Tente novamente.';
        _validating = false;
      });
    }
  }

  Future<void> _redeem() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (_resolved == null || user == null) return;
    setState(() {
      _error = null;
      _redeeming = true;
    });
    try {
      await redeemInstructorCode(
        code: _resolved!.code,
        academyId: _resolved!.academyId,
        userId: user.id,
        userEmail: user.email,
        userDisplayName: user.displayName,
      );
      // Refresh user-academy mapping so the new academy shows up
      ref.invalidate(userAcademyMappingProvider);
      ref.invalidate(currentUserProvider);
      if (!mounted) return;
      setState(() {
        _done = true;
        _redeeming = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Erro ao vincular como instrutor. Tente novamente.';
        _redeeming = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Codigo de equipe')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _done
              ? _buildSuccess()
              : _resolved != null
                  ? _buildConfirm()
                  : _buildInput(),
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(LucideIcons.users, size: 20),
            const SizedBox(width: 8),
            Text('Codigo de equipe', style: AppTheme.headlineSmall),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Digite o codigo de 8 caracteres que o dono da academia te enviou.',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _codeController,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 8,
          enabled: !_validating,
          style: const TextStyle(
            letterSpacing: 4,
            fontFamily: 'monospace',
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            labelText: 'Codigo',
            counterText: '',
            errorText: _error,
            prefixIcon: const Icon(LucideIcons.keyRound, size: 18),
          ),
          onSubmitted: (_) => _validate(),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _validating ? null : _validate,
          child: _validating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Validar codigo'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => context.pop(),
          child: const Text('Voltar'),
        ),
      ],
    );
  }

  Widget _buildConfirm() {
    final res = _resolved!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Voce esta prestes a se vincular como', style: AppTheme.bodyMedium),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.infoLight,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.userCog, size: 14, color: AppTheme.info),
              const SizedBox(width: 6),
              Text(
                'Instrutor',
                style: AppTheme.labelMedium.copyWith(
                  color: AppTheme.info,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border.all(color: AppTheme.divider),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Convidado por',
                  style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary)),
              const SizedBox(height: 4),
              Text(res.code.createdByName,
                  style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'PERMISSOES',
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _PermChip(label: 'Chamada, turmas, alunos (base)'),
            ...res.code.extraPermissions.map((p) {
              final def = kGrantableExtraPermissions
                  .where((g) => g.permission == p)
                  .firstOrNull;
              return _PermChip(label: def?.label ?? p);
            }),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              style: AppTheme.labelSmall.copyWith(color: AppTheme.error)),
        ],
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _redeeming ? null : _redeem,
          child: _redeeming
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Confirmar e vincular'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _redeeming ? null : () => setState(() => _resolved = null),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 48),
          Icon(LucideIcons.checkCircle, size: 64, color: AppTheme.success),
          const SizedBox(height: 16),
          Text('Vinculado com sucesso!', style: AppTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Voce agora e instrutor nessa academia.',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.go('/admin'),
            child: const Text('Ir para o painel'),
          ),
        ],
      ),
    );
  }
}

class _PermChip extends StatelessWidget {
  final String label;
  const _PermChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.shieldCheck, size: 12, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(label,
              style: AppTheme.labelSmall.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}
