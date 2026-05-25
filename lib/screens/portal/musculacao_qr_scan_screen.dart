import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme.dart';
import '../../services/musculacao_checkin_service.dart';

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
    extends ConsumerState<MusculacaoQrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _processing = false;
  bool _success = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
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
      await _controller.stop();
      if (!mounted) return;
      setState(() {
        _success = true;
        _processing = false;
      });
    } on MusculacaoCheckinException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _processing = false;
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && !_success) setState(() => _error = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
        MobileScanner(controller: _controller, onDetect: _handle),
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(16),
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
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 96),
          const SizedBox(height: 16),
          const Text(
            'Presenca registrada!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Concluir'),
          ),
        ],
      ),
    );
  }
}
