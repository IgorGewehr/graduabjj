import 'package:flutter/material.dart';

import '../../../core/sports.dart';
import '../../../core/theme.dart';
import '../../../widgets/common/grade_display.dart';

/// Welcome header without belt (fallback / no student linked)
class WelcomeHeader extends StatelessWidget {
  final String userName;

  const WelcomeHeader({super.key, required this.userName});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia';
    if (hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$_greeting,',
          style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
        ),
        Text(
          userName.split(' ').first,
          style: AppTheme.displaySmall.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Welcome header with belt badge inline
class WelcomeHeaderWithBelt extends StatelessWidget {
  final String userName;
  final String belt;
  final int stripes;

  const WelcomeHeaderWithBelt({
    super.key,
    required this.userName,
    required this.belt,
    required this.stripes,
  });

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bom dia';
    if (hour < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$_greeting,',
          style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: Text(
                userName.split(' ').first,
                style: AppTheme.displaySmall.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            GradeDisplay(
              sportId: SportId.bjj,
              grade: belt,
              stripes: stripes,
              size: GradeDisplaySize.small,
            ),
          ],
        ),
      ],
    );
  }
}
