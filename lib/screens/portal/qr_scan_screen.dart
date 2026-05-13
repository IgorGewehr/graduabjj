import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/student_provider.dart';
import '../../services/qr_attendance_service.dart';

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
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _isProcessing = false;
  String? _statusMessage;
  bool _statusIsError = false;
  QrAttendanceResult? _success;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_isProcessing || _success != null) return;
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
      final user = ref.read(currentUserProvider).valueOrNull;
      final student = ref.read(currentStudentProvider).valueOrNull;
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

      await _controller.stop();
      if (!mounted) return;
      setState(() {
        _success = result;
        _isProcessing = false;
      });
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
      _statusMessage = null;
      _statusIsError = false;
    });
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final success = _success;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Check-in por QR'),
        actions: [
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
          : Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _handleDetection,
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
                            color: Colors.black.withOpacity(0.55),
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
                                    : 'Aponte para o QR exibido pelo professor',
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

class _ReticleOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withOpacity(0.8), width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  final QrAttendanceResult result;
  final VoidCallback onScanAnother;

  const _SuccessView({required this.result, required this.onScanAnother});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppTheme.successLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.checkCircle,
                size: 48,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Presenca registrada!',
              style: AppTheme.headlineLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              result.className,
              style: AppTheme.titleMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(result.markedAt),
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(LucideIcons.qrCode, size: 16),
              label: const Text('Escanear outra turma'),
              onPressed: onScanAnother,
            ),
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
