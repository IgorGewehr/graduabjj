import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import 'shared_widgets.dart';

/// Kids belts order
const List<String> kidsBeltOrder = [
  'grey',
  'grey_white',
  'yellow',
  'yellow_white',
  'orange',
  'orange_white',
  'green',
  'green_white',
];

/// Adult belts order
const List<String> adultBeltOrder = [
  'white',
  'blue',
  'purple',
  'brown',
  'black',
];

class StudentsTab extends StatelessWidget {
  final int totalStudents;
  final int activeStudents;
  final int inactiveStudents;
  final int injuredStudents;
  final int kidsCount;
  final int adultsCount;
  final Map<String, int> kidsBeltDistribution;
  final Map<String, int> adultBeltDistribution;

  const StudentsTab({
    super.key,
    required this.totalStudents,
    required this.activeStudents,
    required this.inactiveStudents,
    required this.injuredStudents,
    required this.kidsCount,
    required this.adultsCount,
    required this.kidsBeltDistribution,
    required this.adultBeltDistribution,
  });

  String _getBeltLabel(String belt, bool isKids) {
    if (isKids) {
      const labels = {
        'grey': 'Cinza',
        'grey_white': 'Cinza/Br',
        'yellow': 'Amarela',
        'yellow_white': 'Amar/Br',
        'orange': 'Laranja',
        'orange_white': 'Larj/Br',
        'green': 'Verde',
        'green_white': 'Verde/Br',
        'white': 'Branca',
      };
      return labels[belt] ?? belt;
    } else {
      const labels = {
        'white': 'Branca',
        'blue': 'Azul',
        'purple': 'Roxa',
        'brown': 'Marrom',
        'black': 'Preta',
      };
      return labels[belt] ?? belt;
    }
  }

  Color _getBeltColor(String belt, bool isKids) {
    if (isKids) {
      const colors = {
        'grey': Color(0xFF9E9E9E),
        'grey_white': Color(0xFFE0E0E0),
        'yellow': Color(0xFFFFEB3B),
        'yellow_white': Color(0xFFFFF9C4),
        'orange': Color(0xFFFF9800),
        'orange_white': Color(0xFFFFE0B2),
        'green': Color(0xFF4CAF50),
        'green_white': Color(0xFFC8E6C9),
        'white': Color(0xFFF5F5F5),
      };
      return colors[belt] ?? Colors.grey;
    } else {
      const colors = {
        'white': Color(0xFFF5F5F5),
        'blue': Color(0xFF2563EB),
        'purple': Color(0xFF7C3AED),
        'brown': Color(0xFF92400E),
        'black': Color(0xFF171717),
      };
      return colors[belt] ?? Colors.grey;
    }
  }

  List<Color> _getGradientColors(String belt) {
    if (belt.contains('_white')) {
      final baseBelt = belt.replaceAll('_white', '');
      return [_getBeltColor(baseBelt, true), const Color(0xFFF5F5F5)];
    }
    return [Colors.grey, Colors.grey];
  }

  Color _getBeltDisplayColor(String belt, bool isKids) {
    if (isKids) {
      const colors = {
        'grey': Color(0xFF757575),
        'grey_white': Color(0xFF9E9E9E),
        'yellow': Color(0xFFFBC02D),
        'yellow_white': Color(0xFFFFD54F),
        'orange': Color(0xFFF57C00),
        'orange_white': Color(0xFFFFB74D),
        'green': Color(0xFF388E3C),
        'green_white': Color(0xFF66BB6A),
        'white': Color(0xFF9E9E9E),
      };
      return colors[belt] ?? Colors.grey;
    } else {
      const colors = {
        'white': Color(0xFF9E9E9E),
        'blue': Color(0xFF2563EB),
        'purple': Color(0xFF7C3AED),
        'brown': Color(0xFF92400E),
        'black': Color(0xFF171717),
      };
      return colors[belt] ?? Colors.grey;
    }
  }

  Widget _buildBeltChart(
    Map<String, int> distribution,
    List<String> order,
    bool isKids,
  ) {
    final total = distribution.values.fold(0, (a, b) => a + b);
    if (total == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Nenhum aluno nesta categoria'),
        ),
      );
    }

    final activeBelts = order
        .where((belt) => (distribution[belt] ?? 0) > 0)
        .toList();

    return Column(
      children: activeBelts.map((belt) {
        final count = distribution[belt] ?? 0;
        final percentage = total > 0 ? count / total : 0.0;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              // Belt color indicator
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _getBeltColor(belt, isKids),
                  borderRadius: BorderRadius.circular(6),
                  border: belt == 'white' || belt.contains('white')
                      ? Border.all(color: AppTheme.divider, width: 1)
                      : null,
                  gradient: belt.contains('_')
                      ? LinearGradient(
                          colors: _getGradientColors(belt),
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 70,
                child: Text(
                  _getBeltLabel(belt, isKids),
                  style: AppTheme.bodySmall.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceVariant,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: percentage,
                      child: Container(
                        height: 24,
                        decoration: BoxDecoration(
                          color: _getBeltDisplayColor(belt, isKids),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 50,
                child: Text(
                  '$count (${(percentage * 100).toStringAsFixed(0)}%)',
                  style: AppTheme.labelSmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main stat card
          MainStatCard(
            title: 'Total de Alunos',
            value: totalStudents.toString(),
            subtitle: '$activeStudents ativos',
            icon: LucideIcons.users,
            color: AppTheme.primary,
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              Expanded(
                child: MiniStatCard(
                  icon: LucideIcons.userCheck,
                  label: 'Ativos',
                  value: activeStudents.toString(),
                  color: AppTheme.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MiniStatCard(
                  icon: LucideIcons.userX,
                  label: 'Inativos',
                  value: inactiveStudents.toString(),
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MiniStatCard(
                  icon: LucideIcons.cross,
                  label: 'Lesionados',
                  value: injuredStudents.toString(),
                  color: AppTheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Category breakdown
          Row(
            children: [
              Expanded(
                child: MiniStatCard(
                  icon: LucideIcons.baby,
                  label: 'Infantil',
                  value: kidsCount.toString(),
                  color: AppTheme.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: MiniStatCard(
                  icon: LucideIcons.user,
                  label: 'Adulto',
                  value: adultsCount.toString(),
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Kids belt distribution
          if (kidsCount > 0) ...[
            ReportCard(
              title: 'Faixas Infantil',
              icon: LucideIcons.award,
              badge: '$kidsCount alunos',
              child: _buildBeltChart(
                kidsBeltDistribution,
                kidsBeltOrder,
                true,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Adults belt distribution
          if (adultsCount > 0)
            ReportCard(
              title: 'Faixas Adulto',
              icon: LucideIcons.award,
              badge: '$adultsCount alunos',
              child: _buildBeltChart(
                adultBeltDistribution,
                adultBeltOrder,
                false,
              ),
            ),
        ],
      ),
    );
  }
}
