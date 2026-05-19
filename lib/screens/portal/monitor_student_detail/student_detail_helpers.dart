import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';

// ── Belt helpers ─────────────────────────────────────────────────────────────

String studentBeltDisplayName(String belt) {
  const names = {
    'white': 'Branca',
    'blue': 'Azul',
    'purple': 'Roxa',
    'brown': 'Marrom',
    'black': 'Preta',
    'grey': 'Cinza',
    'yellow': 'Amarela',
    'orange': 'Laranja',
    'green': 'Verde',
  };
  return names[belt] ?? belt;
}

Color studentBeltColor(String belt) {
  const colors = {
    'white': Color(0xFFF5F5F5),
    'blue': Color(0xFF2563EB),
    'purple': Color(0xFF7C3AED),
    'brown': Color(0xFF92400E),
    'black': Color(0xFF171717),
    'grey': Color(0xFF6B7280),
    'yellow': Color(0xFFF59E0B),
    'orange': Color(0xFFF97316),
    'green': Color(0xFF22C55E),
  };
  final baseBelt = belt.split('-').first;
  return colors[baseBelt] ?? Colors.grey;
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class StudentDetailSectionTitle extends StatelessWidget {
  const StudentDetailSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTheme.titleSmall.copyWith(
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
    );
  }
}

class StudentDetailStatCard extends StatelessWidget {
  const StudentDetailStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.primary, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class StudentDetailInfoCard extends StatelessWidget {
  const StudentDetailInfoCard({super.key, required this.rows});

  final List<InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: rows.map((row) {
          final isLast = rows.last == row;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(bottom: BorderSide(color: AppTheme.divider)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  row.label,
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                Text(
                  row.value,
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class InfoRow {
  final String label;
  final String value;

  const InfoRow({required this.label, required this.value});
}

class AcademyBadge extends StatelessWidget {
  const AcademyBadge(this.academyName, {super.key});

  final String academyName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.building2, size: 10, color: Color(0xFF6366F1)),
          const SizedBox(width: 4),
          Text(
            academyName,
            style: AppTheme.labelSmall.copyWith(
              color: const Color(0xFF6366F1),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class MedalCard extends StatelessWidget {
  const MedalCard({
    super.key,
    required this.emoji,
    required this.count,
    required this.label,
    required this.color,
  });

  final String emoji;
  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: AppTheme.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── History item model ────────────────────────────────────────────────────────

class HistoryItem {
  final DateTime date;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;

  const HistoryItem({
    required this.date,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
  });
}

// ── Belt badge + status badge (used in SliverAppBar) ─────────────────────────

class BeltBadge extends StatelessWidget {
  const BeltBadge({super.key, required this.student});

  final Student student;

  @override
  Widget build(BuildContext context) {
    final beltNames = {
      'white': 'Branca',
      'blue': 'Azul',
      'purple': 'Roxa',
      'brown': 'Marrom',
      'black': 'Preta',
      'grey': 'Cinza',
      'yellow': 'Amarela',
      'orange': 'Laranja',
      'green': 'Verde',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            beltNames[student.currentBelt] ?? student.currentBelt,
            style: TextStyle(
              color: student.currentBelt == 'white' ? Colors.black : Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (student.currentStripes > 0) ...[
            const SizedBox(width: 4),
            Text(
              '${student.currentStripes} grau(s)',
              style: TextStyle(
                color: student.currentBelt == 'white'
                    ? Colors.black54
                    : Colors.white70,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class StudentStatusBadge extends StatelessWidget {
  const StudentStatusBadge({super.key, required this.student});

  final Student student;

  @override
  Widget build(BuildContext context) {
    final statusColors = {
      StudentStatus.active: AppTheme.success,
      StudentStatus.inactive: AppTheme.textSecondary,
      StudentStatus.suspended: AppTheme.warning,
      StudentStatus.injured: AppTheme.info,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColors[student.status]?.withValues(alpha: 0.3) ??
            Colors.grey.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        student.status.label,
        style: TextStyle(
          color: student.currentBelt == 'white' ? Colors.black : Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
