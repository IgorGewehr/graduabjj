import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/student.dart';
import 'student_detail_helpers.dart';

class StudentInfoTab extends StatelessWidget {
  const StudentInfoTab({
    super.key,
    required this.student,
    required this.attendanceCount,
    required this.progressionsCount,
  });

  final Student student;
  final int attendanceCount;
  final int progressionsCount;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          Row(
            children: [
              Expanded(
                child: StudentDetailStatCard(
                  label: 'Presencas',
                  value: '$attendanceCount',
                  icon: LucideIcons.clipboardCheck,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StudentDetailStatCard(
                  label: 'Graduacoes',
                  value: '$progressionsCount',
                  icon: LucideIcons.award,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Personal Info
          const StudentDetailSectionTitle('Informacoes Pessoais'),
          const SizedBox(height: 12),
          StudentDetailInfoCard(
            rows: [
              if (student.nickname != null)
                InfoRow(label: 'Apelido', value: student.nickname!),
              InfoRow(label: 'Categoria', value: student.category.label),
              if (student.birthDate != null)
                InfoRow(
                  label: 'Nascimento',
                  value: DateFormat('dd/MM/yyyy').format(student.birthDate!),
                ),
              if (student.email != null)
                InfoRow(label: 'Email', value: student.email!),
              if (student.phone != null)
                InfoRow(label: 'Telefone', value: student.phone!),
            ],
          ),

          // Guardian Info (for kids)
          if (student.category == StudentCategory.kids &&
              student.guardianName != null) ...[
            const SizedBox(height: 24),
            const StudentDetailSectionTitle('Responsavel'),
            const SizedBox(height: 12),
            StudentDetailInfoCard(
              rows: [
                InfoRow(label: 'Nome', value: student.guardianName!),
                if (student.guardianPhone != null)
                  InfoRow(label: 'Telefone', value: student.guardianPhone!),
                if (student.guardianEmail != null)
                  InfoRow(label: 'Email', value: student.guardianEmail!),
              ],
            ),
          ],

          // Medical Info
          if (student.medicalNotes != null &&
              student.medicalNotes!.isNotEmpty) ...[
            const SizedBox(height: 24),
            const StudentDetailSectionTitle('Observacoes Medicas'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Text(
                student.medicalNotes!,
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
