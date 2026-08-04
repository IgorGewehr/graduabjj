import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/platform_support.dart';
import '../../core/theme.dart';
import '../../services/analytics_service.dart';
import '../../services/musculacao_checkin_service.dart';
import '../../widgets/polish/polish.dart';

/// Fullscreen scanner for the fixed musculação QR ('qr' mode). Reads the static
/// code printed at the reception desk and records attendance through the
/// `selfCheckin` Cloud Function. All validation — academy, mode, operating
/// hours, active status and one-per-day dedup — happens server-side, so the
/// client only needs the academyId encoded in the QR.
class MusculacaoQrScanScreen extends ConsumerStatefulWidget {
  const MusculacaoQrScanScreen({super.key});

  @override
  ConsumerState<MusculacaoQrScanScreen> createState() =>
      _MusculacaoQrScanScreenState();
}

class _MusculacaoQrScanScreenState
    extends ConsumerState<MusculacaoQrScanScreen>
    with SingleTickerProviderStateMixin {
  // Sem câmera no desktop (mobile_scanner): controller nulo → build mostra
  // fallback.
  final MobileScannerController? _controller = PlatformSupport.canScanCamera
      ? MobileScannerController(
          detectionSpeed: DetectionSpeed.normal,
          facing: CameraFacing.back,
        )
      : null;

  late final AnimationController _scanLineController;

  bool _processing = false;
  bool _success = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _handle(BarcodeCapture capture) async {
    if (_processing || _success) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .firstOrNull;
    if (raw == null) return;

    final academyId = parseMusculacaoQrAcademy(raw);
    if (academyId == null) {
      // Not a musculação QR (e.g. a class QR or garbage) — ignore so the user
      // can reposition without an error flash.
      return;
    }

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      await MusculacaoCheckinService().checkIn(academyId: academyId);
      await _controller?.stop();
      if (!mounted) return;
      setState(() {
        _success = true;
        _processing = false;
      });
      // Genuine win: musculação check-in confirmed.
      Celebration.confetti(context);
      // Analytics (jul/2026): check-in do QR fixo da musculação confirmado.
      AnalyticsService.logCheckinScanned(kind: 'musculacao');
    } on MusculacaoCheckinException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _processing = false;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_success) setState(() => _error = null);
      });
    } catch (_) {
      // A TimeoutException, network drop or platform-channel error would
      // otherwise escape uncaught, leaving the scanner frozen on a spinner with
      // no way to retry. Surface a fallback message and re-arm the scanner.
      if (!mounted) return;
      setState(() {
        _error = 'Falha inesperada. Tente de novo.';
        _processing = false;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_success) setState(() => _error = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Check-in')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'A leitura de QR usa a câmera do celular. No computador, use a '
              'catraca/leitor da academia.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Check-in da Musculacao'),
      ),
      body: _success ? _buildSuccess() : _buildScanner(),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          controller: _controller!,
          onDetect: _handle,
          errorBuilder: (context, error, child) => _CameraErrorView(
            error: error,
            onRetry: () {
              _controller?.start();
            },
          ),
        ),
        IgnorePointer(
          child: Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _scanLineController,
                    builder: (context, _) {
                      final dy = _scanLineController.value * (240 - 4);
                      return Positioned(
                        top: dy,
                        left: 10,
                        right: 10,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: LinearGradient(
                              colors: [
                                AppTheme.primary.withValues(alpha: 0),
                                AppTheme.primary,
                                AppTheme.primary.withValues(alpha: 0),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.6),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 60,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_processing)
                const CircularProgressIndicator(color: Colors.white)
              else
                Text(
                  _error ?? 'Aponte a camera para o QR da recepcao',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _error != null ? AppTheme.error : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SuccessCheck(size: 96, color: Colors.greenAccent),
          const SizedBox(height: 16),
          const Text(
            'Presenca registrada!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ).fadeInQuick(),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Concluir'),
          ).entrance(index: 1),
        ],
      ),
    );
  }
}

/// Styled fallback shown when the camera cannot start (permission denied, no
/// camera, or a controller failure). Replaces mobile_scanner's bare unstyled
/// default error with a dark panel, a PT-BR message and recovery affordances.
class _CameraErrorView extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onRetry;

  const _CameraErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final code = error.errorCode;
    final isPermission = code == MobileScannerErrorCode.permissionDenied;
    final isUnsupported = code == MobileScannerErrorCode.unsupported;

    final String title;
    final String detail;
    if (isPermission) {
      title = 'Acesso a camera negado';
      detail =
          'Para escanear o QR, permita o acesso a camera nas configuracoes do '
          'aparelho e tente novamente.';
    } else if (isUnsupported) {
      title = 'Camera indisponivel';
      detail = 'Este aparelho nao oferece uma camera para leitura do QR.';
    } else {
      title = 'Camera indisponivel';
      detail = 'Nao foi possivel iniciar a camera. Tente novamente.';
    }

    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPermission ? LucideIcons.cameraOff : LucideIcons.alertTriangle,
              color: Colors.white,
              size: 56,
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: AppTheme.headlineSmall.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: AppTheme.bodyMedium.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            if (!isUnsupported)
              FilledButton.icon(
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('Tentar novamente'),
                onPressed: onRetry,
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}
