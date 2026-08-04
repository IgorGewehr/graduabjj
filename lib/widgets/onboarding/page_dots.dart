import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A row of animated pagination dots for a [PageView]-style carousel.
///
/// The active dot stretches into a short pill (width 20) and fills with
/// [AppTheme.textPrimary]; inactive dots stay 8×8 and use [AppTheme.divider].
/// Transitions run over 200ms so swiping feels fluid without drawing focus.
///
/// Usage: `PageDots(count: slides.length, currentPage: _page)`
class PageDots extends StatelessWidget {
  final int count;
  final int currentPage;

  const PageDots({
    super.key,
    required this.count,
    required this.currentPage,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 20 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? AppTheme.textPrimary : AppTheme.divider,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}
