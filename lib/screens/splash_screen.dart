import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/brand_tokens.dart';

/// Splash Screen - Initial loading screen
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.bone,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Desenho vetorial direto, sem escala intermediária, para manter
            // as bordas do tatame nítidas durante toda a abertura.
            const CustomPaint(
              size: Size.square(168),
              painter: _MyDojoMarkPainter(),
            ),

            const SizedBox(height: 48),

            // Loading indicator
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Brand.blood),
              ),
            ).animate().fadeIn(delay: 400.ms, duration: 400.ms),
          ],
        ),
      ),
    );
  }
}

class _MyDojoMarkPainter extends CustomPainter {
  const _MyDojoMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const sourceWidth = 320.0;
    const sourceHeight = 352.0;
    final scale = (size.width / sourceWidth).clamp(
      0.0,
      size.height / sourceHeight,
    );
    final offsetX = (size.width - sourceWidth * scale) / 2;
    final offsetY = (size.height - sourceHeight * scale) / 2;

    canvas
      ..translate(offsetX, offsetY)
      ..scale(scale);

    final ink = Paint()
      ..color = Brand.ink
      ..isAntiAlias = false;
    final blood = Paint()
      ..color = Brand.blood
      ..isAntiAlias = false;

    canvas
      ..drawRect(const Rect.fromLTWH(29, 28, 92, 168), ink)
      ..drawRect(const Rect.fromLTWH(131, 28, 168, 92), ink)
      ..drawRect(const Rect.fromLTWH(207, 130, 92, 168), ink)
      ..drawRect(const Rect.fromLTWH(29, 206, 168, 92), ink)
      ..drawRect(const Rect.fromLTWH(122, 312, 76, 10), blood);
  }

  @override
  bool shouldRepaint(_MyDojoMarkPainter oldDelegate) => false;
}
