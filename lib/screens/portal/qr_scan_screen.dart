import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../api/dto/attendance_dto.dart' as api_att;
import '../../api/repositories.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/student_provider.dart';
import '../../services/qr_attendance_service.dart' show QrAttendanceException, QrAttendanceResult;

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
  String? _errorMessage;
  bool _showErrorOverlay = false;
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
      _errorMessage = null;
      _showErrorOverlay = false;
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

      QrAttendanceResult? result;
      final classId = _extractClassIdFromTatamiToken(raw);
      if (classId == null) {
        throw const QrAttendanceException(
          'QR inválido. Peça ao professor para gerar um novo.',
        );
      }
      final att = await ref.read(attendanceRepoProvider).selfCheckin(
            academyId,
            api_att.SelfCheckinRequest(
              classId: classId,
              qrToken: raw,
            ),
          );
      result = QrAttendanceResult(
        classId: att.classId,
        className: '',
        studentId: att.studentId,
        studentName: student?.fullName ?? user!.displayName,
        markedAt: att.createdAt ?? DateTime.now(),
      );

      await _controller.stop();
      if (!mounted) return;

      HapticFeedback.heavyImpact();

      setState(() {
        _success = result;
        _isProcessing = false;
      });

      Future.delayed(2500.ms, () {
        if (!mounted) return;
        Navigator.of(context).pop();
      });
    } on QrAttendanceException catch (e) {
      if (!mounted) return;
      HapticFeedback.vibrate();
      setState(() {
        _errorMessage = e.message;
        _showErrorOverlay = true;
        _isProcessing = false;
      });
      _scheduleErrorDismiss();
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.vibrate();
      setState(() {
        _errorMessage = 'Falha inesperada. Tente de novo.';
        _showErrorOverlay = true;
        _isProcessing = false;
      });
      _scheduleErrorDismiss();
    }
  }

  String? _extractClassIdFromTatamiToken(String token) {
    try {
      final dot = token.indexOf('.');
      if (dot <= 0) return null;
      final payloadB64 = token.substring(0, dot);
      final padded = payloadB64.padRight(
        (payloadB64.length + 3) ~/ 4 * 4,
        '=',
      );
      final bytes = base64Url.decode(padded);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map && decoded['c'] is String) {
        return decoded['c'] as String;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void _scheduleErrorDismiss() {
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || _success != null) return;
      setState(() {
        _showErrorOverlay = false;
        _errorMessage = null;
      });
    });
  }

  void _dismissError() {
    setState(() {
      _showErrorOverlay = false;
      _errorMessage = null;
    });
  }

  void _retry() {
    setState(() {
      _success = null;
      _errorMessage = null;
      _showErrorOverlay = false;
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
      body: Stack(
        children: [
          if (success == null) ...[
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
          if (success != null)
            _SuccessOverlay(result: success, onScanAnother: _retry),
          if (_showErrorOverlay && _errorMessage != null)
            _ErrorOverlay(
              message: _errorMessage!,
              onRetry: _dismissError,
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
        child: SizedBox(
          width: 240,
          height: 240,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.8),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              Positioned(
                left: 2,
                right: 2,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        AppTheme.success.withValues(alpha: 0.9),
                        Colors.transparent,
                      ],
                    ),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .moveY(
                      begin: 0,
                      end: 236,
                      duration: 1500.ms,
                      curve: Curves.easeInOut,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessOverlay extends StatelessWidget {
  final QrAttendanceResult result;
  final VoidCallback onScanAnother;

  const _SuccessOverlay({required this.result, required this.onScanAnother});

  @override
  Widget build(BuildContext context) {
    final className = result.className.isEmpty ? null : result.className;
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppTheme.success,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.check,
                size: 52,
                color: Colors.white,
              )
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 200.ms),
            )
                .animate()
                .scale(
                  begin: const Offset(0, 0),
                  end: const Offset(1, 1),
                  duration: 600.ms,
                  curve: Curves.elasticOut,
                ),
            const SizedBox(height: 24),
            const Text(
              'Check-in confirmado!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                fontFamily: AppTheme.fontFamily,
              ),
              textAlign: TextAlign.center,
            )
                .animate()
                .fadeIn(delay: 300.ms, duration: 300.ms)
                .slideY(begin: 0.2, end: 0, delay: 300.ms, duration: 300.ms),
            if (className != null) ...[
              const SizedBox(height: 8),
              Text(
                'Turma: $className',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  fontFamily: AppTheme.fontFamily,
                ),
                textAlign: TextAlign.center,
              )
                  .animate()
                  .fadeIn(delay: 400.ms, duration: 300.ms),
            ],
            const SizedBox(height: 6),
            Text(
              DateFormat('HH:mm').format(result.markedAt),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
                fontFamily: AppTheme.fontFamily,
              ),
            )
                .animate()
                .fadeIn(delay: 450.ms, duration: 300.ms),
            const SizedBox(height: 36),
            TextButton(
              onPressed: onScanAnother,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.7),
              ),
              child: const Text('Escanear outra turma'),
            )
                .animate()
                .fadeIn(delay: 600.ms, duration: 300.ms),
          ],
        ),
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorOverlay({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppTheme.error,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.x,
                size: 52,
                color: Colors.white,
              )
                  .animate()
                  .fadeIn(delay: 150.ms, duration: 200.ms),
            )
                .animate()
                .scale(
                  begin: const Offset(0, 0),
                  end: const Offset(1, 1),
                  duration: 500.ms,
                  curve: Curves.elasticOut,
                ),
            const SizedBox(height: 24),
            Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                fontFamily: AppTheme.fontFamily,
              ),
              textAlign: TextAlign.center,
            )
                .animate()
                .fadeIn(delay: 250.ms, duration: 300.ms)
                .slideY(begin: 0.2, end: 0, delay: 250.ms, duration: 300.ms),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.error,
              ),
              child: const Text('Tentar novamente'),
            )
                .animate()
                .fadeIn(delay: 400.ms, duration: 300.ms),
          ],
        ),
      ),
    );
  }
}
