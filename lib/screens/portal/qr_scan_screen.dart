import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/platform_support.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/student_provider.dart';
import '../../services/analytics_service.dart';
import '../../services/fixed_academy_qr_service.dart';
import '../../services/qr_attendance_service.dart';
import '../../widgets/polish/polish.dart';
import 'widgets/fixed_qr_class_selection.dart';

/// QR Scan Screen (Student Portal)
///
/// Reads the QR shown by the professor (or printed) and immediately marks
/// attendance through [QrAttendanceService]. The check-in window and class
/// enrollment are validated server-side by the service.
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  // Desktop (Windows/Linux) não tem câmera via mobile_scanner: controller fica
  // nulo e o build mostra um fallback (o check-in por QR é do celular; no
  // desktop a presença vem da catraca).
  final MobileScannerController? _controller = PlatformSupport.canScanCamera
      ? MobileScannerController(
          detectionSpeed: DetectionSpeed.normal,
          facing: CameraFacing.back,
        )
      : null;

  bool _isProcessing = false;
  String? _statusMessage;
  bool _statusIsError = false;
  QrAttendanceResult? _success;
  FixedAcademyQrPayload? _fixedPayload;
  FixedAcademyQrSession? _fixedSession;
  String? _selectedFixedClassId;
  String? _fixedError;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_isProcessing || _success != null || _fixedSession != null) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .firstOrNull;
    if (raw == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = null;
      _statusIsError = false;
    });

    try {
      final fixedPayload = FixedAcademyQrPayload.tryParse(raw);
      if (fixedPayload != null) {
        final session = await FixedAcademyQrService().resolve(fixedPayload);
        await _controller?.stop();
        if (!mounted) return;
        setState(() {
          _fixedPayload = fixedPayload;
          _fixedSession = session;
          _isProcessing = false;
        });
        return;
      }

      final user = await ref.read(currentUserProvider.future);
      final student = await ref.read(currentStudentProvider.future);
      final academyId = user?.academyId;
      final studentId = student?.id ?? user?.studentId;

      if (academyId == null || studentId == null) {
        throw const QrAttendanceException(
          'Aluno nao encontrado. Faca login novamente.',
        );
      }

      final service = QrAttendanceService(academyId);
      final result = await service.processScan(
        rawPayload: raw,
        studentId: studentId,
        studentNameOverride: student?.fullName ?? user!.displayName,
        verifiedBy: user!.id,
        verifiedByName: user.displayName,
      );

      await _controller?.stop();
      if (!mounted) return;
      setState(() {
        _success = result;
        _isProcessing = false;
      });
    } on FixedAcademyQrException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.message;
        _statusIsError = true;
        _isProcessing = false;
      });
      _scheduleStatusReset();
    } on QrAttendanceException catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.message;
        _statusIsError = true;
        _isProcessing = false;
      });
      _scheduleStatusReset();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Falha inesperada. Tente de novo.';
        _statusIsError = true;
        _isProcessing = false;
      });
      _scheduleStatusReset();
    }
  }

  void _scheduleStatusReset() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || _success != null) return;
      setState(() {
        _statusMessage = null;
        _statusIsError = false;
      });
    });
  }

  void _retry() {
    setState(() {
      _success = null;
      _fixedPayload = null;
      _fixedSession = null;
      _selectedFixedClassId = null;
      _fixedError = null;
      _statusMessage = null;
      _statusIsError = false;
    });
    _controller?.start();
  }

  Future<void> _checkInFixedClass(FixedAcademyQrClass cls) async {
    final payload = _fixedPayload;
    if (payload == null || _isProcessing) return;
    setState(() {
      _isProcessing = true;
      _selectedFixedClassId = cls.id;
      _fixedError = null;
    });
    try {
      final result = await FixedAcademyQrService().checkIn(
        payload: payload,
        classId: cls.id,
      );
      if (!mounted) return;
      setState(() {
        _success = result;
        _fixedSession = null;
        _isProcessing = false;
      });
    } on FixedAcademyQrException catch (error) {
      if (!mounted) return;
      setState(() {
        _fixedError = error.message;
        _selectedFixedClassId = null;
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Desktop: sem câmera. Mostra orientação em vez de crashar.
    if (_controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Check-in por QR')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'A leitura de QR usa a câmera do celular. No computador, a '
              'presença é registrada pela catraca/leitor da academia.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final success = _success;
    final fixedSession = _fixedSession;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Check-in por QR'),
        actions: [
          if (success == null && fixedSession == null)
            IconButton(
              icon: ValueListenableBuilder<MobileScannerState>(
                valueListenable: _controller,
                builder: (context, state, _) {
                  final on = state.torchState == TorchState.on;
                  return Icon(on ? LucideIcons.zapOff : LucideIcons.zap);
                },
              ),
              tooltip: 'Lanterna',
              onPressed: () => _controller.toggleTorch(),
            ),
        ],
      ),
      body: success != null
          ? _SuccessView(result: success, onScanAnother: _retry)
          : fixedSession != null
          ? FixedQrClassSelection(
              session: fixedSession,
              selectedClassId: _selectedFixedClassId,
              errorMessage: _fixedError,
              isSubmitting: _isProcessing,
              onSelected: _checkInFixedClass,
              onScanAgain: _retry,
            )
          : Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _handleDetection,
                  errorBuilder: (context, error) => _CameraErrorView(
                    error: error,
                    onRetry: () {
                      _controller.start();
                    },
                  ),
                ),
                _ReticleOverlay(),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    minimum: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_statusMessage != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _statusIsError
                                  ? AppTheme.error
                                  : AppTheme.success,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _statusIsError
                                      ? LucideIcons.alertTriangle
                                      : LucideIcons.checkCircle,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    _statusMessage!,
                                    style: AppTheme.labelMedium.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isProcessing) ...[
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ] else
                                const Icon(
                                  LucideIcons.qrCode,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              const SizedBox(width: 4),
                              Text(
                                _isProcessing
                                    ? 'Validando...'
                                    : 'Aponte para o QR da academia ou da turma',
                                style: AppTheme.labelMedium.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Styled fallback shown when the camera cannot start (permission denied, no
/// camera, or a controller failure). Replaces the bare unstyled default error
/// from mobile_scanner with a dark panel, a clear PT-BR message, and recovery
/// affordances (retry + back).
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

class _ReticleOverlay extends StatefulWidget {
  @override
  State<_ReticleOverlay> createState() => _ReticleOverlayState();
}

class _ReticleOverlayState extends State<_ReticleOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double box = 240;
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: box,
          height: box,
          child: Stack(
            children: [
              // Reticle frame
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              // Sweeping scan line
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final dy = _controller.value * (box - 4);
                  return Positioned(
                    top: dy,
                    left: 8,
                    right: 8,
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
    );
  }
}

class _SuccessView extends StatefulWidget {
  final QrAttendanceResult result;
  final VoidCallback onScanAnother;

  const _SuccessView({required this.result, required this.onScanAnother});

  @override
  State<_SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends State<_SuccessView> {
  @override
  void initState() {
    super.initState();
    // Genuine win: attendance confirmed — celebrate once on appearance.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Celebration.confetti(context);
    });
    // Analytics (jul/2026): check-in por QR de turma confirmado. Aqui (não no
    // handler de scan) porque _SuccessView só constrói quando o resultado já
    // voltou com sucesso — 1x por check-in, sem contar tentativas com erro.
    AnalyticsService.logCheckinScanned(kind: 'qr');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SuccessCheck(size: 96),
            const SizedBox(height: 20),
            Text(
              'Presenca registrada!',
              style: AppTheme.headlineLarge,
              textAlign: TextAlign.center,
            ).fadeInQuick(),
            const SizedBox(height: 8),
            Text(
              widget.result.className,
              style: AppTheme.titleMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ).entrance(index: 1),
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(widget.result.markedAt),
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ).entrance(index: 2),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(LucideIcons.qrCode, size: 16),
              label: const Text('Escanear outra turma'),
              onPressed: widget.onScanAnother,
            ).entrance(index: 3),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar'),
            ),
          ],
        ),
      ),
    );
  }
}
