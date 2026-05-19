import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../services/services.dart';

/// Info tab content for student detail screen.
class StudentInfoTab extends StatelessWidget {
  final Student student;
  final List<Attendance> attendances;
  final List<Achievement> achievements;
  final bool autoGradEnabled;
  final EligibilityResult? eligibility;
  final VoidCallback onShowPromoteDialog;

  const StudentInfoTab({
    super.key,
    required this.student,
    required this.attendances,
    required this.achievements,
    required this.autoGradEnabled,
    required this.eligibility,
    required this.onShowPromoteDialog,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Auto-graduation banner (only when feature is enabled)
          if (autoGradEnabled && eligibility != null) ...[
            _EligibilityBanner(
              eligibility: eligibility!,
              onPromote: onShowPromoteDialog,
            ),
            const SizedBox(height: 16),
          ],

          // Quick stats
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Presenças',
                  value: student.totalAttendanceCount.toString(),
                  icon: Icons.check_circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Mês atual',
                  value: attendances
                      .where(
                        (a) =>
                            a.date.month == DateTime.now().month &&
                            a.date.year == DateTime.now().year,
                      )
                      .length
                      .toString(),
                  icon: Icons.calendar_today,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Conquistas',
                  value: achievements.length.toString(),
                  icon: Icons.emoji_events,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Personal info
          _buildSection('Informações Pessoais', [
            _InfoRow(label: 'Nome completo', value: student.fullName),
            if (student.nickname != null)
              _InfoRow(label: 'Apelido', value: student.nickname!),
            if (student.email != null)
              _InfoRow(label: 'E-mail', value: student.email!),
            if (student.phone != null)
              _InfoRow(label: 'Telefone', value: student.phone!),
            if (student.birthDate != null)
              _InfoRow(
                label: 'Nascimento',
                value: DateFormat('dd/MM/yyyy').format(student.birthDate!),
              ),
            _InfoRow(label: 'Categoria', value: student.category.label),
          ]),
          const SizedBox(height: 16),

          // Academy info
          _buildSection('Informações da Academia', [
            _InfoRow(
              label: 'Data de início',
              value: DateFormat('dd/MM/yyyy').format(student.startDate),
            ),
            if (student.planId != null)
              _InfoRow(label: 'Plano ID', value: student.planId!),
            _InfoRow(
              label: 'Mensalidade',
              value: 'R\$ ${student.tuitionValue.toStringAsFixed(2)}',
            ),
            _InfoRow(
              label: 'Dia de vencimento',
              value: student.tuitionDay.toString(),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private sub-widgets (eligibility banner, stat card, info row)
// ---------------------------------------------------------------------------

class _EligibilityBanner extends StatelessWidget {
  final EligibilityResult eligibility;
  final VoidCallback onPromote;

  const _EligibilityBanner({
    required this.eligibility,
    required this.onPromote,
  });

  @override
  Widget build(BuildContext context) {
    final e = eligibility;
    final eligible = e.eligible;
    final color = eligible ? AppTheme.warning : AppTheme.info;
    final lightColor = eligible ? AppTheme.warningLight : AppTheme.infoLight;
    final icon = eligible ? LucideIcons.zap : LucideIcons.target;
    final unit = e.weighted ? 'pts' : 'aulas';
    final progress = e.requiredClasses > 0
        ? (e.currentClasses / e.requiredClasses).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: lightColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  eligible ? 'Elegivel para graduar' : 'Proxima graduacao',
                  style: AppTheme.titleSmall.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (eligible)
                ElevatedButton.icon(
                  onPressed: onPromote,
                  icon: const Icon(LucideIcons.award, size: 14),
                  label: const Text('Graduar agora'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    textStyle: AppTheme.labelSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            eligible
                ? '${e.currentClasses}/${e.requiredClasses} $unit — pronto para a proxima graduacao.'
                : 'Faltam ${e.missingClasses} $unit (${e.currentClasses}/${e.requiredClasses})',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  Color _getIconColor() {
    if (icon == Icons.check_circle) return const Color(0xFF22C55E);
    if (icon == Icons.calendar_today) return const Color(0xFF3B82F6);
    if (icon == Icons.emoji_events) return const Color(0xFFF59E0B);
    return AppTheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _getIconColor();

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  IconData _getDefaultIcon() {
    if (label.contains('Nome')) return LucideIcons.user;
    if (label.contains('Apelido')) return LucideIcons.userCircle;
    if (label.contains('E-mail')) return LucideIcons.mail;
    if (label.contains('Telefone')) return LucideIcons.phone;
    if (label.contains('Nascimento')) return LucideIcons.cake;
    if (label.contains('Categoria')) return LucideIcons.tag;
    if (label.contains('Data de início')) return LucideIcons.calendar;
    if (label.contains('Plano')) return LucideIcons.creditCard;
    if (label.contains('Mensalidade')) return LucideIcons.dollarSign;
    if (label.contains('vencimento')) return LucideIcons.clock;
    return LucideIcons.info;
  }

  @override
  Widget build(BuildContext context) {
    final displayIcon = _getDefaultIcon();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.divider.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(displayIcon, size: 16, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
