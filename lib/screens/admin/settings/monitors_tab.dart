import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import 'settings_shared_widgets.dart';

/// Content for the "Monitores" settings tab.
class MonitorsTab extends StatelessWidget {
  final List<String> monitorIds;
  final List<Map<String, dynamic>> linkedStudents;
  final bool isLoadingMonitors;
  final void Function(String studentId) onAddMonitor;
  final void Function(String studentId) onRemoveMonitor;

  const MonitorsTab({
    super.key,
    required this.monitorIds,
    required this.linkedStudents,
    required this.isLoadingMonitors,
    required this.onAddMonitor,
    required this.onRemoveMonitor,
  });

  @override
  Widget build(BuildContext context) {
    final currentMonitors = linkedStudents
        .where((s) => monitorIds.contains(s['id']))
        .toList();

    final availableStudents = linkedStudents
        .where((s) => !monitorIds.contains(s['id']))
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        key: const ValueKey('monitors'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Add Monitor Section
          SettingsCard(
            title: 'Adicionar Monitor',
            icon: LucideIcons.userPlus,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selecione um aluno com conta vinculada para adiciona-lo como monitor.',
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                if (availableStudents.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.info,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            linkedStudents.isEmpty
                                ? 'Nenhum aluno possui conta vinculada.'
                                : 'Todos os alunos vinculados ja sao monitores.',
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: null,
                      hint: Text(
                        'Selecionar aluno',
                        style: AppTheme.bodyMedium.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      items: availableStudents.map((student) {
                        final name = student['nickname'] ?? student['fullName'];
                        return DropdownMenuItem(
                          value: student['id'] as String,
                          child: Text(name),
                        );
                      }).toList(),
                      onChanged: isLoadingMonitors
                          ? null
                          : (value) {
                              if (value != null) {
                                onAddMonitor(value);
                              }
                            },
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      dropdownColor: AppTheme.surface,
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Current Monitors List
          SettingsCard(
            title: 'Monitores Atuais (${currentMonitors.length})',
            icon: LucideIcons.shield,
            child: currentMonitors.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          LucideIcons.shield,
                          color: AppTheme.textDisabled,
                          size: 48,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Nenhum monitor cadastrado',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: currentMonitors.map((monitor) {
                      final name = monitor['nickname'] ?? monitor['fullName'];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  (name as String).substring(0, 1).toUpperCase(),
                                  style: AppTheme.titleMedium.copyWith(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: AppTheme.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (monitor['nickname'] != null)
                                    Text(
                                      monitor['fullName'],
                                      style: AppTheme.labelSmall.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: isLoadingMonitors
                                  ? null
                                  : () => onRemoveMonitor(
                                      monitor['id'] as String),
                              icon: Icon(
                                LucideIcons.x,
                                color: AppTheme.error,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),

          const SizedBox(height: 16),

          // Info about permissions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.info, color: Colors.blue, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Permissoes do Monitor',
                      style: AppTheme.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• Fazer chamada de presenca\n• Visualizar, cadastrar e editar alunos',
                  style: AppTheme.bodySmall.copyWith(
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Monitores NAO tem acesso a: Financeiro, Relatorios, Configuracoes.',
                  style: AppTheme.labelSmall.copyWith(
                    color: Colors.blue.shade600,
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
