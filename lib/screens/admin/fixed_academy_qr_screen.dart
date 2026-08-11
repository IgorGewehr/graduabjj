import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import '../../services/fixed_academy_qr_service.dart';
import '../../widgets/polish/polish.dart';

/// Owner-only screen for the academy-wide permanent attendance QR.
/// Generation is idempotent: reopening this page always returns the same code.
class FixedAcademyQrScreen extends StatefulWidget {
  final String academyId;

  const FixedAcademyQrScreen({super.key, required this.academyId});

  @override
  State<FixedAcademyQrScreen> createState() => _FixedAcademyQrScreenState();
}

class _FixedAcademyQrScreenState extends State<FixedAcademyQrScreen> {
  final _service = FixedAcademyQrService();
  FixedAcademyQrData? _data;
  String? _error;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await _service.getOrCreate(widget.academyId);
      if (!mounted) return;
      setState(() => _data = data);
    } on FixedAcademyQrException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  Future<void> _print() async {
    final data = _data;
    if (data == null || _printing) return;
    setState(() => _printing = true);
    try {
      await Printing.layoutPdf(
        name: 'qr-checkin-${data.academyId}.pdf',
        onLayout: (format) => _buildPdf(data, format),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nao foi possivel abrir a impressao.')),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<Uint8List> _buildPdf(
    FixedAcademyQrData data,
    PdfPageFormat format,
  ) async {
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(48),
        build: (_) => pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                data.academyName,
                style: pw.TextStyle(
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'CHECK-IN DE PRESENCA',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              pw.SizedBox(height: 28),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: data.payload.encode(),
                width: 300,
                height: 300,
              ),
              pw.SizedBox(height: 28),
              pw.Text(
                'Abra o app, escaneie este codigo e selecione sua turma.',
                style: const pw.TextStyle(fontSize: 15),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'O codigo e permanente e funciona para turmas atuais e futuras.',
                style: const pw.TextStyle(
                  fontSize: 11,
                  color: PdfColors.grey700,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
    return document.save();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('QR fixo da academia')),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.alertTriangle,
                      color: AppTheme.error,
                      size: 42,
                    ),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          : data == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          children: [
                            Text(
                              data.academyName,
                              style: AppTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Check-in de presenca',
                              style: AppTheme.labelLarge.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 22),
                            QrImageView(
                              data: data.payload.encode(),
                              version: QrVersions.auto,
                              size: 300,
                              backgroundColor: Colors.white,
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'O aluno escaneia e escolhe uma das turmas disponiveis naquele horario.',
                              style: AppTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ).entrance(),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.infoLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(LucideIcons.lock, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Este QR nao expira e nao muda quando novas turmas forem criadas. Turma, matricula, horario e duplicidade sao validados pelo servidor.',
                                style: AppTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _printing ? null : _print,
                          icon: _printing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(LucideIcons.printer, size: 18),
                          label: const Text('Imprimir ou salvar em PDF'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
