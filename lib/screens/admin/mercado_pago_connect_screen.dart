import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../services/mercado_pago_service.dart';
import '../../services/settings_service.dart';

enum _ConnState { intro, waiting, success, error }

/// Dedicated full-screen flow to connect the academy's Mercado Pago account.
///
/// Opens the MP OAuth page in the browser, then resolves the result via three
/// coordinated paths: a deep-link return (graduabjj://mp-oauth-callback), an
/// app-resume re-check, and exponential-backoff polling as the safety net.
/// Pops `true` once connected.
class MercadoPagoConnectScreen extends StatefulWidget {
  final String academyId;
  const MercadoPagoConnectScreen({super.key, required this.academyId});

  @override
  State<MercadoPagoConnectScreen> createState() =>
      _MercadoPagoConnectScreenState();
}

class _MercadoPagoConnectScreenState extends State<MercadoPagoConnectScreen>
    with WidgetsBindingObserver {
  late final MercadoPagoService _service;
  late final ConfettiController _confetti;
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  _ConnState _state = _ConnState.intro;
  String? _error;
  DateTime? _startedAt;
  bool _polling = false;

  static const _timeout = Duration(minutes: 15);

  @override
  void initState() {
    super.initState();
    _service = MercadoPagoService(widget.academyId);
    _confetti = ConfettiController(duration: const Duration(seconds: 3));
    WidgetsBinding.instance.addObserver(this);
    // Fast-path: deep-link back from the browser.
    _linkSub = _appLinks.uriLinkStream.listen((uri) {
      if (uri.host == 'mp-oauth-callback' ||
          uri.toString().contains('mp-oauth-callback')) {
        _checkOnce();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    _confetti.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Re-check when the user comes back from the browser.
    if (s == AppLifecycleState.resumed && _state == _ConnState.waiting) {
      _checkOnce();
    }
  }

  Future<void> _start() async {
    setState(() {
      _state = _ConnState.waiting;
      _error = null;
      _startedAt = DateTime.now();
    });
    try {
      final url = await _service.startConnect();
      if (url == null || url.isEmpty) {
        _fail('Não foi possível iniciar a conexão.');
        return;
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      _poll();
    } catch (e) {
      _fail('Erro ao iniciar: $e');
    }
  }

  /// Exponential-backoff poll: 3s (0-60s) → 6s (60-120s) → 12s, until timeout.
  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    while (mounted && _state == _ConnState.waiting) {
      final elapsed = DateTime.now().difference(_startedAt!);
      if (elapsed > _timeout) {
        _fail('Tempo esgotado. Toque em "Já autorizei" ou tente de novo.');
        break;
      }
      final wait = elapsed.inSeconds < 60
          ? 3
          : elapsed.inSeconds < 120
              ? 6
              : 12;
      await Future.delayed(Duration(seconds: wait));
      if (!mounted || _state != _ConnState.waiting) break;
      if (await _isConnected()) {
        _succeed();
        break;
      }
    }
    _polling = false;
  }

  Future<bool> _isConnected() async {
    try {
      final s = await SettingsService(widget.academyId).getAcademySettings();
      return s?.mpConnected ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkOnce() async {
    if (_state != _ConnState.waiting) return;
    if (await _isConnected()) _succeed();
  }

  void _succeed() {
    if (!mounted || _state == _ConnState.success) return;
    setState(() => _state = _ConnState.success);
    _confetti.play();
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _state = _ConnState.error;
      _error = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conectar Mercado Pago'),
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.pop(context, _state == _ConnState.success),
        ),
      ),
      body: Stack(
        alignment: Alignment.topCenter,
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: _buildBody(),
            ),
          ),
          ConfettiWidget(
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            numberOfParticles: 28,
            gravity: 0.15,
            colors: const [
              AppTheme.primary,
              AppTheme.success,
              AppTheme.warning,
              Color(0xFF7C3AED),
              Color(0xFFEC4899),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _ConnState.intro:
        return _stateColumn(
          color: const Color(0xFF009EE3),
          icon: LucideIcons.creditCard,
          title: 'Receba via Mercado Pago',
          message:
              'Conecte sua conta do Mercado Pago para receber as mensalidades e '
              'pedidos da loja via PIX e cartão, direto na sua conta — sem taxa '
              'da plataforma.',
          primary: ('Conectar agora', _start),
        );
      case _ConnState.waiting:
        return _stateColumn(
          color: const Color(0xFF009EE3),
          icon: LucideIcons.externalLink,
          title: 'Aguardando autorização',
          message:
              'Conclua a autorização no navegador. Assim que terminar, volte '
              'para cá — vamos detectar automaticamente.',
          spinner: true,
          primary: ('Abrir navegador novamente', _start),
          secondary: ('Já autorizei', _checkOnce),
        );
      case _ConnState.success:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _circleIcon(AppTheme.success, LucideIcons.checkCircle)
                .animate()
                .scaleXY(begin: 0.5, duration: 500.ms, curve: Curves.elasticOut),
            const SizedBox(height: 24),
            Text('Conectado!',
                style: AppTheme.headlineSmall
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _pixReminderBox(),
            const SizedBox(height: 28),
            _primaryButton(
                'Concluir', () => Navigator.pop(context, true)),
          ],
        );
      case _ConnState.error:
        return _stateColumn(
          color: AppTheme.error,
          icon: LucideIcons.alertCircle,
          title: 'Não foi possível conectar',
          message: _error ?? 'Tente novamente.',
          primary: ('Tentar novamente', _start),
          secondary: ('Voltar', () => Navigator.pop(context, false)),
        );
    }
  }

  Widget _stateColumn({
    required Color color,
    required IconData icon,
    required String title,
    required String message,
    bool spinner = false,
    (String, VoidCallback)? primary,
    (String, VoidCallback)? secondary,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _circleIcon(color, icon),
        if (spinner) ...[
          const SizedBox(height: 20),
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ],
        const SizedBox(height: 24),
        Text(title,
            style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Text(message,
            style:
                AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center),
        const SizedBox(height: 28),
        if (primary != null) _primaryButton(primary.$1, primary.$2),
        if (secondary != null) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: secondary.$2, child: Text(secondary.$1)),
        ],
      ],
    ).animate().fadeIn(duration: 250.ms);
  }

  Widget _circleIcon(Color color, IconData icon) => Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 42, color: color),
      );

  Widget _primaryButton(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      );

  Widget _pixReminderBox() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.info.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(LucideIcons.info, size: 18, color: AppTheme.info),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Para receber via PIX, garanta que sua conta Mercado Pago tem '
                'uma chave PIX cadastrada.',
                style:
                    AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      );
}
