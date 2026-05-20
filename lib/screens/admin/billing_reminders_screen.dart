import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../api/dto/financial_dto.dart' as api_fin;
import '../../api/dto/student_dto.dart' show StudentFilter;
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../providers/api_provider.dart';
import '../../providers/selected_academy_provider.dart';
import '../../services/billing_reminder_service.dart';
import '../../services/firebase_service.dart';
import '../../services/payment_service.dart';
import 'billing_reminders/billing_stages_builder.dart';
import 'billing_reminders/billing_tab_bar.dart';
import 'billing_reminders/bulk_actions_bar.dart';
import 'billing_reminders/bulk_result_dialog.dart';
import 'billing_reminders/bulk_send_dialog.dart';
import 'billing_reminders/bulk_send_executor.dart';
import 'billing_reminders/contact_dialog.dart';
import 'billing_reminders/individual_send_executor.dart';
import 'billing_reminders/send_dialog.dart';
import 'billing_reminders/settings_dialog.dart';
import 'billing_reminders/stage_list.dart';
import 'billing_reminders/stats_header.dart';

/// Admin Billing Reminders Screen
/// Displays overdue payments organized by collection stages (D+1, D+3, D+7, D+15, D+30+)
/// with WhatsApp and Email billing capabilities.
class AdminBillingRemindersScreen extends ConsumerStatefulWidget {
  const AdminBillingRemindersScreen({super.key});

  @override
  ConsumerState<AdminBillingRemindersScreen> createState() =>
      _AdminBillingRemindersScreenState();
}

class _AdminBillingRemindersScreenState
    extends ConsumerState<AdminBillingRemindersScreen>
    with SingleTickerProviderStateMixin {
  Map<BillingStage, List<Map<String, dynamic>>> _overdueStages = {
    BillingStage.d0: [],
    BillingStage.d1: [],
    BillingStage.d3: [],
    BillingStage.d7: [],
    BillingStage.d15: [],
    BillingStage.d30: [],
  };
  CollectionStats? _stats;
  Map<String, StudentContact> _studentContacts = {};
  BillingNotificationSettings? _notificationSettings;
  bool _isLoading = true;
  bool _isSending = false;

  late TabController _tabController;
  late BillingReminderService _billingService;
  BillingNotificationService? _notificationService;

  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: BillingStage.values.length,
      vsync: this,
    );
    _billingService = BillingReminderService(ref.read(safeAcademyIdProvider) ?? '');
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final academyId = ref.read(safeAcademyIdProvider) ?? '';
      _billingService = BillingReminderService(academyId);

      // Load all data from Tatami — no Firestore reads.
      // 1. Students (for contact info) via Tatami
      final studentsPage = await ref.read(
        tatami.tatamiStudentsProvider(tatami.StudentsQuery(
          academyId: academyId,
          filter: const StudentFilter(limit: 500),
        )).future,
      );
      final contacts = <String, StudentContact>{};
      for (final s in studentsPage.items) {
        contacts[s.id] = StudentContact(
          studentId: s.id,
          studentName: s.fullName,
          phone: s.phone,
          email: s.email,
          guardianPhone: s.guardian?.phone,
          guardianEmail: s.guardian?.email,
          category: s.category?.name ?? 'adult',
          photoUrl: s.photoUrl,
        );
      }

      // 2. Notification settings via Tatami
      final notifSettings = await _billingService.getNotificationSettings();

      // 3. Financials (overdue + pending) via Tatami
      final overdueQ = tatami.FinancialsQuery(
        academyId: academyId,
        filter: const api_fin.FinancialFilter(
          status: api_fin.ApiFinancialStatus.overdue,
          limit: 500,
        ),
      );
      final pendingQ = tatami.FinancialsQuery(
        academyId: academyId,
        filter: const api_fin.FinancialFilter(
          status: api_fin.ApiFinancialStatus.pending,
          limit: 500,
        ),
      );
      ref.invalidate(tatami.tatamiPaymentsLegacyProvider(overdueQ));
      ref.invalidate(tatami.tatamiPaymentsLegacyProvider(pendingQ));
      final paymentLists = await Future.wait([
        ref.read(tatami.tatamiPaymentsLegacyProvider(overdueQ).future),
        ref.read(tatami.tatamiPaymentsLegacyProvider(pendingQ).future),
      ]);
      final allPayments = <Payment>[...paymentLists[0], ...paymentLists[1]];
      final stages = buildStagesFromPayments(allPayments, contacts);

      // 4. Compute stats from the loaded payments (no extra Firestore call)
      final computedStats = _computeStatsFromPayments(allPayments, stages);

      // Academy name from cache (avoids extra Firestore round-trip).
      String academyName = ref.read(currentAcademyInfoProvider)?.name ?? '';
      if (academyName.isEmpty) {
        final info = await ref
            .read(selectedAcademyProvider.notifier)
            .getAcademyInfo(academyId);
        academyName = info?.name ?? 'Academia';
      }

      setState(() {
        _overdueStages = stages;
        _stats = computedStats;
        _studentContacts = contacts;
        _notificationSettings = notifSettings;
        _notificationService = BillingNotificationService(
          academyId: academyId,
          academyName: academyName,
          customTemplates: notifSettings.messageTemplates,
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) FeedbackUtils.showError(context, 'Erro ao carregar dados: $e');
    }
  }

  int _stageCount(BillingStage stage) => _overdueStages[stage]?.length ?? 0;

  /// Compute collection stats from already-loaded payments (no Firestore).
  CollectionStats _computeStatsFromPayments(
    List<Payment> payments,
    Map<BillingStage, List<Map<String, dynamic>>> stages,
  ) {
    int totalOverdue = 0;
    double totalAmount = 0;
    int totalDays = 0;
    final uniqueStudents = <String>{};

    final stageCounts = <BillingStage, int>{};
    final stageAmounts = <BillingStage, double>{};
    for (final stage in BillingStage.values) {
      final items = stages[stage] ?? [];
      stageCounts[stage] = items.length;
      double amt = 0;
      for (final item in items) {
        amt += (item['amount'] as num?)?.toDouble() ?? 0;
        uniqueStudents.add(item['studentId'] as String? ?? '');
        totalDays += (item['daysOverdue'] as int?) ?? 0;
      }
      stageAmounts[stage] = amt;
      totalOverdue += items.length;
      totalAmount += amt;
    }

    final byStage = <BillingStage, CollectionStageData>{};
    for (final stage in BillingStage.values) {
      byStage[stage] = CollectionStageData(
        count: stageCounts[stage] ?? 0,
        amount: stageAmounts[stage] ?? 0,
      );
    }

    return CollectionStats(
      totalOverdue: totalOverdue,
      totalOverdueAmount: totalAmount,
      totalStudentsOverdue: uniqueStudents.length,
      recoveryRate: 0,
      averageDaysOverdue:
          totalOverdue > 0 ? (totalDays / totalOverdue).round() : 0,
      byStage: byStage,
    );
  }

  BillingStage get _currentStage => BillingStage.values[_tabController.index];

  // ============================================
  // Individual send
  // ============================================
  void _showSendDialog({
    required String mode,
    required Map<String, dynamic> financialItem,
    required BillingStage stage,
    required StudentContact contact,
  }) {
    final studentName = financialItem['studentName'] as String? ?? '';
    final amount = (financialItem['amount'] as num?)?.toDouble() ?? 0;
    final dueDate = financialItem['dueDate'] as DateTime;
    final daysOverdue = financialItem['daysOverdue'] as int? ?? 0;

    final String message;
    String subject = '';
    if (mode == 'whatsapp') {
      message = _notificationService!.generateWhatsAppMessage(
        stage: stage,
        studentName: studentName,
        amount: amount,
        dueDate: dueDate,
        daysOverdue: daysOverdue,
      );
    } else {
      final content = _notificationService!.generateEmailContent(
        stage: stage,
        studentName: studentName,
        amount: amount,
        dueDate: dueDate,
        daysOverdue: daysOverdue,
      );
      subject = content.subject;
      message = content.message;
    }

    showBillingSendDialog(
      context: context,
      mode: mode,
      studentName: studentName,
      contact: contact,
      message: message,
      subject: subject,
      onConfirm: ({required String message, String? subject}) async {
        setState(() => _isSending = true);
        final result = await executeIndividualSend(
          mode: mode,
          financialItem: financialItem,
          stage: stage,
          contact: contact,
          message: message,
          subject: subject,
          notificationService: _notificationService!,
          billingService: _billingService,
          tatamiClient: ref.read(tatamiClientProvider),
          academyId: ref.read(safeAcademyIdProvider) ?? '',
        );
        setState(() => _isSending = false);
        if (!mounted) return;
        if (result.success) {
          FeedbackUtils.showSuccess(
            context,
            '${mode == 'whatsapp' ? 'WhatsApp' : 'Email'} enviado para $studentName!',
          );
        } else {
          FeedbackUtils.showError(context, 'Erro: ${result.error}');
        }
      },
    );
  }

  // ============================================
  // Bulk send
  // ============================================
  void _showBulkSendDialog(BillingStage stage) {
    final items = _overdueStages[stage] ?? [];
    if (items.isEmpty || _notificationService == null) return;

    final recipients = _notificationService!.collectRecipientsForStage(
      financials: items,
      contacts: _studentContacts,
    );

    showBillingBulkSendDialog(
      context: context,
      stage: stage,
      items: items,
      recipients: recipients,
      initialMessage: _notificationService!.generateGenericStageMessage(stage),
      initialSubject: _notificationService!.generateGenericEmailSubject(stage),
      onConfirm: ({
        required String message,
        required String subject,
        required List<String> phones,
        required List<String> emails,
        String? scheduledTime,
      }) async {
        if (!(_notificationSettings?.whatsappEnabled ?? false) &&
            !(_notificationSettings?.emailEnabled ?? false)) {
          if (mounted) {
            FeedbackUtils.showError(
              context,
              'Nenhum canal de notificacao esta habilitado.',
            );
          }
          return;
        }
        setState(() => _isSending = true);
        final execResult = await executeBulkSend(
          stage: stage,
          messageTemplate: message,
          subjectTemplate: subject,
          items: _overdueStages[stage] ?? [],
          studentContacts: _studentContacts,
          notificationSettings: _notificationSettings!,
          notificationService: _notificationService!,
          billingService: _billingService,
          tatamiClient: ref.read(tatamiClientProvider),
          academyId: ref.read(safeAcademyIdProvider) ?? '',
        );
        setState(() => _isSending = false);
        if (!mounted) return;
        if (execResult.hasError) {
          FeedbackUtils.showError(
            context,
            'Erro no envio em massa: ${execResult.error}',
          );
        } else {
          showBulkResultDialog(
            context: context,
            result: execResult.serverResult!,
          );
        }
      },
    );
  }

  // ============================================
  // Build
  // ============================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Regua de Cobranca'),
        actions: [
          IconButton(
            onPressed: () => showBillingSettingsDialog(
              context: context,
              currentSettings: _notificationSettings,
              onSaved: (newSettings) async {
                await _billingService.saveNotificationSettings(newSettings);
                if (!mounted) return;
                setState(() {
                  _notificationSettings = newSettings;
                  _notificationService?.customTemplates =
                      newSettings.messageTemplates;
                });
                FeedbackUtils.showSuccess(this.context, 'Configuracoes salvas!');
              },
            ),
            icon: const Icon(LucideIcons.settings, size: 20),
            tooltip: 'Configuracoes',
          ),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: Column(
                    children: [
                      if (_stats != null)
                        BillingStatsHeader(
                          stats: _stats!,
                          currencyFormat: _currencyFormat,
                        ),
                      const SizedBox(height: 8),
                      if (_notificationSettings != null &&
                          !_notificationSettings!.hasWhatsAppApi &&
                          !_notificationSettings!.hasEmailApi)
                        _ApiWarningBanner(settings: _notificationSettings!),
                      const SizedBox(height: 8),
                      BillingTabBar(
                        tabController: _tabController,
                        stageCount: _stageCount,
                        onTap: () => setState(() {}),
                      ),
                      BulkActionsBar(
                        currentStage: _currentStage,
                        stageItems: _overdueStages[_currentStage] ?? [],
                        isSending: _isSending,
                        hasWhatsApp:
                            _notificationSettings?.hasWhatsAppApi ?? false,
                        hasEmail: _notificationSettings?.hasEmailApi ?? false,
                        onSendTap: () => _showBulkSendDialog(_currentStage),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: BillingStage.values.map((stage) {
                            return BillingStageList(
                              stage: stage,
                              items: _overdueStages[stage] ?? [],
                              studentContacts: _studentContacts,
                              notificationSettings: _notificationSettings,
                              currencyFormat: _currencyFormat,
                              dateFormat: _dateFormat,
                              onSendWhatsApp: ({
                                required Map<String, dynamic> financialItem,
                                required StudentContact contact,
                              }) => _showSendDialog(
                                mode: 'whatsapp',
                                financialItem: financialItem,
                                stage: stage,
                                contact: contact,
                              ),
                              onSendEmail: ({
                                required Map<String, dynamic> financialItem,
                                required StudentContact contact,
                              }) => _showSendDialog(
                                mode: 'email',
                                financialItem: financialItem,
                                stage: stage,
                                contact: contact,
                              ),
                              onContactLog: ({
                                required String financialId,
                                required String studentId,
                                required String studentName,
                                required int daysOverdue,
                              }) => showBillingContactDialog(
                                context: context,
                                financialId: financialId,
                                studentId: studentId,
                                studentName: studentName,
                                stage: stage,
                                daysOverdue: daysOverdue,
                                billingService: _billingService,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
          if (_isSending)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Enviando cobrancas...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small private widget kept inline — avoids a trivial one-use file
// ---------------------------------------------------------------------------
class _ApiWarningBanner extends StatelessWidget {
  const _ApiWarningBanner({required this.settings});

  final BillingNotificationSettings settings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.alertTriangle, size: 16, color: AppTheme.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Habilite os canais de cobranca (WhatsApp e/ou Email) nas configuracoes para enviar cobrancas automaticas.',
                style: AppTheme.bodySmall.copyWith(color: AppTheme.warning),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
