import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../services/musculacao_checkin_service.dart';

/// Card de check-in de musculacao do portal do aluno.
///
/// Logica server-authoritative preservada: o check-in real e feito pela Cloud
/// Function `selfCheckin` via [MusculacaoCheckinService.checkIn]; no modo QR a
/// presenca so e marcada apos o scanner retornar `true`. O estado [_doneToday]
/// e apenas visual/efemero (nao persiste, nao gateia nada).
///
/// Publico para permitir reuso pelo hero da home.
class MusculacaoCheckinCard extends ConsumerStatefulWidget {
  /// When true the academy uses the fixed-QR mode: tapping opens the scanner
  /// instead of calling the function directly.
  final bool qrMode;

  const MusculacaoCheckinCard({super.key, required this.qrMode});

  @override
  ConsumerState<MusculacaoCheckinCard> createState() =>
      _MusculacaoCheckinCardState();
}

class _MusculacaoCheckinCardState
    extends ConsumerState<MusculacaoCheckinCard> {
  bool _loading = false;
  bool _doneToday = false;

  Future<void> _checkin() async {
    if (widget.qrMode) {
      final result = await context.push<bool>('/portal/musculacao-checkin');
      if (result == true && mounted) setState(() => _doneToday = true);
      return;
    }
    setState(() => _loading = true);
    try {
      await MusculacaoCheckinService().checkIn();
      if (!mounted) return;
      setState(() => _doneToday = true);
      context.showSuccess('Presenca registrada!');
    } on MusculacaoCheckinException catch (e) {
      if (!mounted) return;
      if (e.message.toLowerCase().contains('registrou presen')) {
        setState(() => _doneToday = true);
      }
      context.showError(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = _doneToday;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: done
              ? [AppTheme.success, AppTheme.success.withValues(alpha: 0.85)]
              : [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.check_circle : Icons.fitness_center,
                color: Colors.white,
                size: 22,
              )
                  .animate(target: done ? 1 : 0)
                  .scaleXY(
                    begin: 0.6,
                    end: 1,
                    duration: 320.ms,
                    curve: Curves.easeOutBack,
                  ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  done
                      ? 'Presenca de hoje registrada'
                      : 'Treino de musculacao',
                  style: AppTheme.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: 240.ms,
            switchInCurve: Curves.easeOut,
            child: Text(
              done
                  ? 'Bom treino! Volte amanha para registrar de novo.'
                  : widget.qrMode
                      ? 'Escaneie o QR da recepcao para registrar presenca.'
                      : 'Chegou na academia? Registre sua presenca.',
              key: ValueKey<bool>(done),
              style: AppTheme.bodyMedium.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_loading || done) ? null : _checkin,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: done ? AppTheme.success : AppTheme.primary,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.7),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      done
                          ? Icons.check
                          : widget.qrMode
                              ? Icons.qr_code_scanner
                              : Icons.location_on,
                      size: 18,
                    ),
              label: Text(
                done
                    ? 'Check-in feito'
                    : widget.qrMode
                        ? 'Escanear QR'
                        : 'Cheguei',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 280.ms)
        .slideY(begin: 0.06, end: 0, duration: 320.ms, curve: Curves.easeOut);
  }
}
