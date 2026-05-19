import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/dto/student_dto.dart';
import '../../api/repositories.dart';
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../widgets/skeletons/skeletons.dart';
import 'profile/profile_academies_section.dart';
import 'profile/profile_account_section.dart';
import 'profile/profile_edit_sheets.dart';
import 'profile/profile_helpers.dart';
import 'profile/profile_hero_header.dart';
import 'profile/profile_info_widgets.dart';
import 'profile/profile_quick_actions.dart';
import 'profile/profile_stat_card.dart';

/// Profile Screen - Redesigned with hero header, stats, and collapsed sections
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) {
          return _buildEmptyState();
        }

        final attendanceCountAsync = ref.watch(
          studentAttendanceCountProvider(student.id),
        );
        final plansAsync = ref.watch(studentPlansProvider(student.id));
        final startDate = student.jiujitsuStartDate ?? student.startDate;
        final trainingTime = ProfileHelpers.formatTrainingTime(startDate);

        return RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            ref.invalidate(currentStudentProvider);
            ref.invalidate(studentAttendanceCountProvider(student.id));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Hero Header
                ProfileHeroHeader(student: student),

                const SizedBox(height: 20),

                // Stats Row
                Row(
                  children: [
                    ProfileStatCard(
                      icon: LucideIcons.clipboardCheck,
                      value: '${attendanceCountAsync.valueOrNull ?? 0}',
                      label: 'presencas',
                    ),
                    const SizedBox(width: 12),
                    ProfileStatCard(
                      icon: LucideIcons.calendar,
                      value: trainingTime,
                      label: 'de treino',
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Quick Actions
                ProfileQuickActions(
                  onTimeline: () => context.go('/portal/linha-do-tempo'),
                  onEdit: () =>
                      _showEditPersonalDataSheet(context, ref, student),
                ),

                const SizedBox(height: 24),

                // Academy-managed section
                Align(
                  alignment: Alignment.centerLeft,
                  child: ProfileSectionHeader(title: 'GERENCIADO PELA ACADEMIA'),
                ),
                const SizedBox(height: 8),
                ProfileInfoCard(
                  children: [
                    ProfileInfoRow(
                      label: 'Inicio',
                      value: DateFormat('dd/MM/yyyy').format(student.startDate),
                    ),
                    ProfileInfoRow(
                      label: 'Status',
                      value: student.status.label,
                      valueColor: AppTheme.getStatusColor(student.status.value),
                    ),
                    if ((plansAsync.valueOrNull ?? []).isNotEmpty)
                      ProfileInfoRow(
                        label:
                            'Plano${(plansAsync.valueOrNull ?? []).length > 1 ? 's' : ''}',
                        value: (plansAsync.valueOrNull ?? [])
                            .map((p) => p.name)
                            .join(', '),
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                // My Data section
                Align(
                  alignment: Alignment.centerLeft,
                  child: ProfileSectionHeader(title: 'MEUS DADOS'),
                ),
                const SizedBox(height: 8),
                ProfileInfoCard(
                  children: [
                    ProfileDataTile(
                      icon: LucideIcons.user,
                      title: 'Dados Pessoais',
                      subtitle: ProfileHelpers.getPersonalDataSummary(student),
                      isSubtitleEmpty: ProfileHelpers.isPersonalDataEmpty(student),
                      onTap: () =>
                          _showEditPersonalDataSheet(context, ref, student),
                    ),
                    ProfileDataTile(
                      icon: LucideIcons.mapPin,
                      title: 'Endereco',
                      subtitle: ProfileHelpers.getAddressSummary(student),
                      isSubtitleEmpty:
                          student.address == null ||
                          !ProfileHelpers.hasAddress(student.address!),
                      onTap: () =>
                          _showEditAddressSheet(context, ref, student),
                    ),
                    ProfileDataTile(
                      icon: LucideIcons.heartPulse,
                      title: 'Saude e Emergencia',
                      subtitle: ProfileHelpers.getHealthEmergencySummary(student),
                      isSubtitleEmpty:
                          ProfileHelpers.isHealthDataEmpty(student) &&
                          student.emergencyContact == null,
                      onTap: () => _showEditHealthAndEmergencySheet(
                        context,
                        ref,
                        student,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Preferences
                Align(
                  alignment: Alignment.centerLeft,
                  child: ProfileSectionHeader(title: 'PREFERENCIAS'),
                ),
                const SizedBox(height: 8),
                ProfilePrivacyToggle(
                  value: student.isProfilePublic,
                  onChanged: (value) =>
                      _updatePrivacy(context, ref, student, value),
                ),

                const SizedBox(height: 24),

                // Academies
                const ProfileAcademiesSection(),

                const SizedBox(height: 24),

                // Account
                const ProfileAccountSection(),

                const SizedBox(height: 80),
              ],
            ),
          ),
        );
      },
      loading: () => _buildLoadingState(),
      error: (_, __) => _buildEmptyState(),
    );
  }

  // ============================================
  // ACTIONS
  // ============================================

  Future<void> _updatePrivacy(
    BuildContext context,
    WidgetRef ref,
    Student student,
    bool value,
  ) async {
    try {
      final currentUser = ref.read(currentUserProvider).valueOrNull;
      final academyId = currentUser?.academyId;
      if (academyId == null) return;

      await ref.read(studentRepoProvider).update(
            academyId,
            student.id,
            UpdateStudentRequest(isProfilePublic: value),
          );
      ref.invalidate(currentStudentProvider);

      if (context.mounted) {
        context.showSuccess(
          value ? 'Perfil agora e publico' : 'Perfil agora e privado',
        );
      }
    } catch (e) {
      if (context.mounted) {
        context.showError('Erro ao atualizar: $e');
      }
    }
  }

  void _showEditPersonalDataSheet(
    BuildContext context,
    WidgetRef ref,
    Student student,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditPersonalDataSheet(
        student: student,
        onSave: (data) async {
          final currentUser = ref.read(currentUserProvider).valueOrNull;
          final academyId = currentUser?.academyId;
          if (academyId == null) return;
          final weight = data['weight'] as double?;
          await ref.read(studentRepoProvider).update(
                academyId,
                student.id,
                UpdateStudentRequest(
                  nickname: data['nickname'] as String?,
                  phone: data['phone'] as String?,
                  email: data['email'] as String?,
                  cpf: data['cpf'] as String?,
                  rg: data['rg'] as String?,
                  weightKg: weight,
                  birthDate: data['birthDate'] as DateTime?,
                ),
              );
          ref.invalidate(currentStudentProvider);
        },
      ),
    );
  }

  void _showEditAddressSheet(
    BuildContext context,
    WidgetRef ref,
    Student student,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditAddressSheet(
        student: student,
        onSave: (data) async {
          final currentUser = ref.read(currentUserProvider).valueOrNull;
          final academyId = currentUser?.academyId;
          if (academyId == null) return;
          ApiAddress? apiAddress;
          final addressMap = data['address'] as Map<String, dynamic>?;
          if (addressMap != null) {
            apiAddress = ApiAddress(
              street: addressMap['street'] as String?,
              city: addressMap['city'] as String?,
              state: addressMap['state'] as String?,
              zipCode: addressMap['zipCode'] as String?,
            );
          }
          await ref.read(studentRepoProvider).update(
                academyId,
                student.id,
                UpdateStudentRequest(address: apiAddress),
              );
          ref.invalidate(currentStudentProvider);
        },
      ),
    );
  }

  void _showEditHealthAndEmergencySheet(
    BuildContext context,
    WidgetRef ref,
    Student student,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditHealthAndEmergencySheet(
        student: student,
        onSave: (data) async {
          final currentUser = ref.read(currentUserProvider).valueOrNull;
          final academyId = currentUser?.academyId;
          if (academyId == null) return;
          // allergies comes as List<String>? — join to single string for API
          final allergiesList = data['allergies'] as List?;
          final allergiesStr = allergiesList != null
              ? allergiesList.join(', ')
              : null;
          // emergencyContact comes as Map with name/phone/relationship
          final ecMap = data['emergencyContact'] as Map<String, dynamic>?;
          String? emergencyContactStr;
          if (ecMap != null) {
            final name = ecMap['name'] as String? ?? '';
            final phone = ecMap['phone'] as String? ?? '';
            final rel = ecMap['relationship'] as String? ?? '';
            emergencyContactStr =
                '$name${phone.isNotEmpty ? ' ($phone)' : ''}${rel.isNotEmpty ? ' - $rel' : ''}';
          }
          await ref.read(studentRepoProvider).update(
                academyId,
                student.id,
                UpdateStudentRequest(
                  bloodType: data['bloodType'] as String?,
                  allergies: allergiesStr,
                  healthNotes: data['healthNotes'] as String?,
                  emergencyContact: emergencyContactStr,
                ),
              );
          ref.invalidate(currentStudentProvider);
        },
      ),
    );
  }

  // ============================================
  // LOADING & EMPTY STATES
  // ============================================

  Widget _buildLoadingState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: const [
          SizedBox(height: 16),
          // Avatar shimmer
          SkeletonAvatar(size: 88),
          SizedBox(height: 20),
          // Stats shimmer
          SkeletonStats(count: 2, height: 80),
          SizedBox(height: 24),
          // Card shimmer
          SkeletonCard(
            height: 150,
            showAvatar: false,
            padding: EdgeInsets.all(16),
          ),
          SizedBox(height: 12),
          SkeletonCard(height: 80, showAvatar: true),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 80),
          Icon(LucideIcons.userX, size: 48, color: AppTheme.textDisabled),
          const SizedBox(height: 16),
          Text(
            'Perfil nao encontrado',
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Sua conta nao esta vinculada a um aluno',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          // Account section always visible for account deletion
          const ProfileAccountSection(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
