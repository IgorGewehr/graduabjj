import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:share_plus/share_plus.dart';

import '../core/fighter_theme.dart';
import '../widgets/polish/polish.dart';

/// "Motor de Cards" (v1, jul/2026) — captura um card compartilhável (ex.:
/// `FighterShareCard`) como PNG e dispara o share sheet nativo. Ponto ÚNICO
/// de contato com `share_plus` + captura offscreen; nenhum outro arquivo
/// deve chamar `RenderRepaintBoundary.toImage` ou `Share.shareXFiles` direto.
///
/// ## Por que bottom sheet de preview (e não capturar direto)
/// A armadilha clássica de screenshot programático no Flutter é chamar
/// `toImage()` antes do 1º frame do widget ter sido pintado — o
/// RenderRepaintBoundary ainda "sujo" gera um PNG em branco ou cortado. Aqui
/// o card é primeiro exibido DE VERDADE num bottom sheet; só quando o
/// usuário toca em "Compartilhar" — ou seja, depois de pelo menos um frame
/// renderizado — é que capturamos o boundary. Bônus: o usuário vê exatamente
/// o que vai sair no WhatsApp antes de mandar.
///
/// ## Gate de plataforma
/// `share_plus` não tem sheet nativo fora de Android/iOS (o app também
/// compila pra Windows desktop — `lib/core/platform_support.dart`). Mesmo
/// padrão do resto do app: no-op com aviso amigável fora de mobile.
///
/// `path_provider` NÃO é dependência direta deste pubspec (só transitiva) —
/// por isso o arquivo temporário usa `Directory.systemTemp` (dart:io puro)
/// em vez do diretório "certo" de cache do plugin.
class ShareCardService {
  ShareCardService._();

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Abre o bottom sheet de PREVIEW com [card] — desenhado no seu tamanho
  /// NATIVO [width]×[height] (o preview só o exibe em escala menor pra
  /// caber na tela; a captura sempre lê o boundary na resolução real) — e
  /// compartilha o PNG resultante ao toque em "Compartilhar".
  ///
  /// [onShared] roda só depois do share efetivar (ex.: log de analytics).
  /// Best-effort: nunca bloqueia nem propaga erro pro caller.
  static Future<void> presentAndShare({
    required BuildContext context,
    required Widget card,
    required double width,
    required double height,
    String? shareText,
    Future<void> Function()? onShared,
  }) async {
    if (!isSupported) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Compartilhar só está disponível no app do celular.'),
          ),
        );
      }
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FighterTheme.ink,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _SharePreviewSheet(
        card: card,
        width: width,
        height: height,
        shareText: shareText,
        onShared: onShared,
      ),
    );
  }
}

class _SharePreviewSheet extends StatefulWidget {
  const _SharePreviewSheet({
    required this.card,
    required this.width,
    required this.height,
    required this.shareText,
    required this.onShared,
  });

  final Widget card;
  final double width;
  final double height;
  final String? shareText;
  final Future<void> Function()? onShared;

  @override
  State<_SharePreviewSheet> createState() => _SharePreviewSheetState();
}

class _SharePreviewSheetState extends State<_SharePreviewSheet> {
  final _boundaryKey = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('share card boundary não montado');
      }
      // 3.0 sobre o canvas 360×450 do FighterShareCard = 1080×1350 exatos
      // (4:5, o formato nativo de feed/story).
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('encode PNG falhou');
      final bytes = byteData.buffer.asUint8List();

      final file = await File(
        '${Directory.systemTemp.path}/bjjeasy_card_'
        '${DateTime.now().millisecondsSinceEpoch}.png',
      ).writeAsBytes(bytes, flush: true);
      if (!mounted) return;

      // sharePositionOrigin evita crash conhecido do share_plus em iPad
      // (o popover precisa de uma âncora); barato de calcular e inofensivo
      // em iPhone/Android, que ignoram o parâmetro.
      final box = context.findRenderObject() as RenderBox?;
      final origin =
          box != null ? (box.localToGlobal(Offset.zero) & box.size) : null;

      await Share.shareXFiles(
        [XFile(file.path)],
        text: widget.shareText,
        sharePositionOrigin: origin,
      );
      await widget.onShared?.call();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('[share_card_service] falhou: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não rolou de compartilhar agora. Tenta de novo.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final previewWidth = math.min(screenWidth - 64, 320.0);
    final previewHeight = previewWidth * widget.height / widget.width;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // O RepaintBoundary por dentro continua no tamanho NATIVO
            // (widget.width×widget.height) — o FittedBox só re-escala o
            // DESENHO pra caber no preview; toImage() sempre lê a
            // resolução real do boundary, não a escala visual.
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: previewWidth,
                height: previewHeight,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: widget.width,
                    height: widget.height,
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: widget.card,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: Pressable(
                onTap: _busy ? null : _share,
                child: Container(
                  decoration: BoxDecoration(
                    color: FighterTheme.blood,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: FighterTheme.boneText,
                            strokeWidth: 2.4,
                          ),
                        )
                      : const Text(
                          'COMPARTILHAR',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.6,
                            color: FighterTheme.boneText,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
