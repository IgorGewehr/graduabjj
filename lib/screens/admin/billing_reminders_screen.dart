import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../api/dto/financial_dto.dart' as api_fin;
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../providers/selected_academy_provider.dart';
import '../../services/billing_reminder_service.dart';
import '../../services/firebase_service.dart';
import '../../services/payment_service.dart';
import '../../widgets/cached_image.dart';

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
  // Data
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
    _billingService = BillingReminderService(FirebaseService.academyId);
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
      final academyId = FirebaseService.academyId;
      _billingService = BillingReminderService(academyId);

      // Stages reconstruídas no widget a partir do Tatami (overdue + pending
      // paginados em paralelo, classificados por daysOverdue local). Fallback
      // Firestore removido na Fase 1; `_billingService` ainda existe para
      // getStudentContacts/getCollectionStats/getNotificationSettings (gap
      // BE — collection stats/settings ainda Firestore-backed).
      Future<Map<BillingStage, List<Map<String, dynamic>>>> stagesFuture(
        Map<String, StudentContact> contacts,
      ) async {
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
        final futures = await Future.wait([
          ref.read(tatami.tatamiPaymentsLegacyProvider(overdueQ).future),
          ref.read(tatami.tatamiPaymentsLegacyProvider(pendingQ).future),
        ]);
        final all = <Payment>[...futures[0], ...futures[1]];
        return _buildStagesFromPayments(all, contacts);
      }

      // Carrega contatos primeiro para poder denormalizar studentName quando
      // os stages vierem do Tatami (DTO Financial não traz studentName).
      // Stats/settings em paralelo com isso. Sequenciamento mínimo para
      // não perder o fan-out.
      final contactsAndExtras = await Future.wait([
        _billingService.getStudentContacts(),
        _billingService.getCollectionStats(),
        _billingService.getNotificationSettings(),
      ]);
      final contacts = contactsAndExtras[0] as Map<String, StudentContact>;
      final stages = await stagesFuture(contacts);
      final results = [
        stages,
        contactsAndExtras[1],
        contacts,
        contactsAndExtras[2],
      ];

      // Academy name for notification service templates ({academia}). Vem do
      // cache populado por `selectedAcademyProvider` no boot — evita uma
      // round-trip Firestore por load (era o único uso direto de
      // FirebaseFirestore.instance nesta tela). Quando a academia ainda não
      // estiver no cache (caso de borda em deep-link), faz fallback para
      // o `getAcademyInfo(academyId)` async do notifier.
      String academyName =
          ref.read(currentAcademyInfoProvider)?.name ?? '';
      if (academyName.isEmpty) {
        final info = await ref
            .read(selectedAcademyProvider.notifier)
            .getAcademyInfo(academyId);
        academyName = info?.name ?? 'Academia';
      }

      final notifSettings = results[3] as BillingNotificationSettings;

      setState(() {
        _overdueStages =
            results[0] as Map<BillingStage, List<Map<String, dynamic>>>;
        _stats = results[1] as CollectionStats;
        _studentContacts = results[2] as Map<String, StudentContact>;
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
      if (mounted) {
        FeedbackUtils.showError(context, 'Erro ao carregar dados: $e');
      }
    }
  }

  int _stageCount(BillingStage stage) {
    return _overdueStages[stage]?.length ?? 0;
  }

  /// Pure: agrupa pagamentos overdue/pending em billing stages D+1..D+30+.
  /// Replica `BillingReminderService._classifyStage` no widget — sem chamar
  /// nada de IO. studentName vem denormalizado a partir de [contacts].
  Map<BillingStage, List<Map<String, dynamic>>> _buildStagesFromPayments(
    List<Payment> payments,
    Map<String, StudentContact> contacts,
  ) {
    final out = <BillingStage, List<Map<String, dynamic>>>{
      BillingStage.d0: [],
      BillingStage.d1: [],
      BillingStage.d3: [],
      BillingStage.d7: [],
      BillingStage.d15: [],
      BillingStage.d30: [],
    };
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    for (final p in payments) {
      if (p.status != PaymentStatus.overdue &&
          p.status != PaymentStatus.pending) {
        continue;
      }
      final dueStart =
          DateTime(p.dueDate.year, p.dueDate.month, p.dueDate.day);
      final daysOverdue = todayStart.difference(dueStart).inDays;
      if (daysOverdue < 1) continue;

      BillingStage? stage;
      if (daysOverdue >= 30) {
        stage = BillingStage.d30;
      } else if (daysOverdue >= 15) {
        stage = BillingStage.d15;
      } else if (daysOverdue >= 7) {
        stage = BillingStage.d7;
      } else if (daysOverdue >= 3) {
        stage = BillingStage.d3;
      } else if (daysOverdue >= 1) {
        stage = BillingStage.d1;
      }
      if (stage == null) continue;

      final contact = contacts[p.studentId];
      out[stage]!.add({
        'id': p.id,
        'studentId': p.studentId,
        'studentName': p.studentName.isNotEmpty
            ? p.studentName
            : (contact?.studentName ?? ''),
        'amount': p.value,
        'dueDate': p.dueDate,
        'status': p.status == PaymentStatus.overdue ? 'overdue' : 'pending',
        'referenceMonth': p.referenceMonth,
        'planId': p.planId,
        'description': p.description,
        'daysOverdue': daysOverdue,
        'stage': stage.value,
      });
    }

    for (final st in BillingStage.values) {
      out[st]!.sort((a, b) {
        final aD = a['daysOverdue'] as int;
        final bD = b['daysOverdue'] as int;
        return bD.compareTo(aD);
      });
    }
    return out;
  }

  BillingStage get _currentStage => BillingStage.values[_tabController.index];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Regua de Cobranca'),
        actions: [
          IconButton(
            onPressed: () => _showSettingsDialog(),
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
                      // Stats Header
                      _buildStatsHeader(),
                      const SizedBox(height: 8),

                      // API Warning
                      if (_notificationSettings != null &&
                          !_notificationSettings!.hasWhatsAppApi &&
                          !_notificationSettings!.hasEmailApi)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.warning.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.alertTriangle,
                                  size: 16,
                                  color: AppTheme.warning,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Habilite os canais de cobranca (WhatsApp e/ou Email) nas configuracoes para enviar cobrancas automaticas.',
                                    style: AppTheme.bodySmall.copyWith(
                                      color: AppTheme.warning,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 8),

                      // Tab Bar
                      _buildTabBar(),

                      // Bulk action buttons
                      _buildBulkActions(),

                      // Tab Content
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: BillingStage.values
                              .map((stage) => _buildStageList(stage))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),
          // Loading overlay during bulk send
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

  // ============================================
  // Stats Header
  // ============================================
  Widget _buildStatsHeader() {
    if (_stats == null) return const SizedBox.shrink();

    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildStatCard(
            icon: LucideIcons.alertCircle,
            label: 'Total Vencido',
            value: _currencyFormat.format(_stats!.totalOverdueAmount),
            color: AppTheme.error,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            icon: LucideIcons.users,
            label: 'Inadimplentes',
            value: '${_stats!.totalStudentsOverdue}',
            color: AppTheme.warning,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            icon: LucideIcons.trendingUp,
            label: 'Taxa Recuperacao',
            value: '${_stats!.recoveryRate.toStringAsFixed(1)}%',
            color: AppTheme.success,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            icon: LucideIcons.clock,
            label: 'Media Dias Atraso',
            value: '${_stats!.averageDaysOverdue} dias',
            color: AppTheme.info,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: AppTheme.labelSmall.copyWith(color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTheme.titleLarge.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ============================================
  // Tab Bar
  // ============================================
  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.divider, width: 1)),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: AppTheme.textPrimary,
        unselectedLabelColor: AppTheme.textSecondary,
        indicatorColor: AppTheme.primary,
        labelStyle: AppTheme.titleSmall,
        unselectedLabelStyle: AppTheme.bodySmall,
        onTap: (_) => setState(() {}),
        tabs: BillingStage.values.map((stage) {
          final count = _stageCount(stage);
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(stage.label),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _stageColor(stage),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: AppTheme.labelSmall.copyWith(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _stageColor(BillingStage stage) {
    switch (stage) {
      case BillingStage.d0:
        return AppTheme.primary;
      case BillingStage.d1:
        return AppTheme.warning;
      case BillingStage.d3:
        return Colors.orange;
      case BillingStage.d7:
        return Colors.deepOrange;
      case BillingStage.d15:
        return AppTheme.error;
      case BillingStage.d30:
        return Colors.red.shade900;
    }
  }

  // ============================================
  // Bulk Action Buttons (Unified)
  // ============================================
  Widget _buildBulkActions() {
    final currentStage = _currentStage;
    final stageItems = _overdueStages[currentStage] ?? [];
    if (stageItems.isEmpty) return const SizedBox.shrink();

    final hasWhatsApp = _notificationSettings?.hasWhatsAppApi ?? false;
    final hasEmail = _notificationSettings?.hasEmailApi ?? false;

    if (!hasWhatsApp && !hasEmail) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: _isSending
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : ElevatedButton.icon(
                onPressed: () => _showBulkSendDialog(currentStage),
                icon: const Icon(LucideIcons.send, size: 16),
                label: Text(
                  'Cobrar todos (${stageItems.length})',
                  style: const TextStyle(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
      ),
    );
  }

  // ============================================
  // Stage List
  // ============================================
  Widget _buildStageList(BillingStage stage) {
    final items = _overdueStages[stage] ?? [];

    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.checkCircle,
              size: 48,
              color: AppTheme.success.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum pagamento neste estagio',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildPaymentItem(item, stage);
      },
    );
  }

  Widget _buildPaymentItem(Map<String, dynamic> item, BillingStage stage) {
    final studentName = item['studentName'] as String? ?? '';
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final dueDate = item['dueDate'] as DateTime;
    final daysOverdue = item['daysOverdue'] as int? ?? 0;
    final financialId = item['id'] as String? ?? '';
    final studentId = item['studentId'] as String? ?? '';
    final contact = _studentContacts[studentId];
    final phone = contact?.effectivePhone;
    final email = contact?.effectiveEmail;
    final hasWhatsApp = _notificationSettings?.hasWhatsAppApi ?? false;
    final hasEmail = _notificationSettings?.hasEmailApi ?? false;
    final photoUrl = contact?.photoUrl;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                AppCachedAvatar(
                  imageUrl: photoUrl,
                  radius: 18,
                  backgroundColor: _stageColor(stage).withValues(alpha: 0.1),
                  child: (photoUrl == null || photoUrl.isEmpty)
                      ? Text(
                          studentName.isNotEmpty
                              ? studentName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: _stageColor(stage),
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(studentName, style: AppTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${_currencyFormat.format(amount)} - Venc: ${_dateFormat.format(dueDate)}',
                        style: AppTheme.bodySmall,
                      ),
                      Text(
                        '$daysOverdue dias em atraso',
                        style: AppTheme.bodySmall.copyWith(
                          color: _stageColor(stage),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Contact info chips
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (phone != null && phone.isNotEmpty)
                  Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      LucideIcons.phone,
                      size: 12,
                      color: AppTheme.success,
                    ),
                    label: Text(phone, style: const TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                  ),
                if (email != null && email.isNotEmpty)
                  Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      LucideIcons.mail,
                      size: 12,
                      color: AppTheme.info,
                    ),
                    label: Text(email, style: const TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                  ),
                if ((phone == null || phone.isEmpty) &&
                    (email == null || email.isEmpty))
                  Chip(
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      LucideIcons.alertTriangle,
                      size: 12,
                      color: Colors.orange,
                    ),
                    label: Text(
                      contact?.category == 'kids'
                          ? 'Sem contato do responsavel'
                          : 'Sem contato',
                      style: TextStyle(fontSize: 11, color: Colors.orange),
                    ),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Send WhatsApp
                if (hasWhatsApp && phone != null && phone.isNotEmpty)
                  IconButton(
                    onPressed: () => _showSendDialog(
                      mode: 'whatsapp',
                      financialItem: item,
                      stage: stage,
                      contact: contact!,
                    ),
                    icon: const Icon(LucideIcons.messageCircle, size: 20),
                    color: AppTheme.success,
                    tooltip: 'Enviar WhatsApp',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                // Send Email
                if (hasEmail && email != null && email.isNotEmpty)
                  IconButton(
                    onPressed: () => _showSendDialog(
                      mode: 'email',
                      financialItem: item,
                      stage: stage,
                      contact: contact!,
                    ),
                    icon: const Icon(LucideIcons.mail, size: 20),
                    color: AppTheme.info,
                    tooltip: 'Enviar Email',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                // Phone
                if (phone != null && phone.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      FeedbackUtils.showInfo(
                        context,
                        'Ligar para $studentName: $phone',
                      );
                    },
                    icon: const Icon(LucideIcons.phone, size: 20),
                    color: AppTheme.textSecondary,
                    tooltip: 'Telefone',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                // Manual contact log
                IconButton(
                  onPressed: () => _showContactDialog(
                    financialId: financialId,
                    studentId: studentId,
                    studentName: studentName,
                    stage: stage,
                    daysOverdue: daysOverdue,
                  ),
                  icon: const Icon(LucideIcons.clipboardList, size: 20),
                  color: AppTheme.textSecondary,
                  tooltip: 'Registrar Contato',
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // Send Dialog (individual)
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
    final financialId = financialItem['id'] as String? ?? '';
    final studentId = financialItem['studentId'] as String? ?? '';

    String message;
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

    final messageController = TextEditingController(text: message);
    final subjectController = TextEditingController(text: subject);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                mode == 'whatsapp'
                    ? LucideIcons.messageCircle
                    : LucideIcons.mail,
                color: mode == 'whatsapp' ? AppTheme.success : AppTheme.info,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                mode == 'whatsapp' ? 'Enviar WhatsApp' : 'Enviar Email',
                style: AppTheme.titleLarge.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Para: $studentName',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (mode == 'whatsapp')
                  Text(
                    'Tel: ${contact.effectivePhone}',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                if (mode == 'email')
                  Text(
                    'Email: ${contact.effectiveEmail}',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                const SizedBox(height: 16),
                if (mode == 'email') ...[
                  Text('Assunto', style: AppTheme.labelMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: subjectController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text('Mensagem', style: AppTheme.labelMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: messageController,
                  maxLines: 8,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Cancelar',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _executeSend(
                  mode: mode,
                  financialItem: financialItem,
                  stage: stage,
                  contact: contact,
                  message: messageController.text,
                  subject: mode == 'email' ? subjectController.text : null,
                );
              },
              icon: Icon(LucideIcons.send, size: 16),
              label: Text(
                mode == 'whatsapp' ? 'Enviar WhatsApp' : 'Enviar Email',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: mode == 'whatsapp'
                    ? AppTheme.success
                    : AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================
  // Execute Individual Send
  // ============================================
  Future<void> _executeSend({
    required String mode,
    required Map<String, dynamic> financialItem,
    required BillingStage stage,
    required StudentContact contact,
    required String message,
    String? subject,
  }) async {
    if (_notificationService == null) return;

    setState(() => _isSending = true);

    try {
      final studentName = financialItem['studentName'] as String? ?? '';
      final amount = (financialItem['amount'] as num?)?.toDouble() ?? 0;
      final dueDate = financialItem['dueDate'] as DateTime;
      final daysOverdue = financialItem['daysOverdue'] as int? ?? 0;
      final financialId = financialItem['id'] as String? ?? '';
      final studentId = financialItem['studentId'] as String? ?? '';

      NotificationResult result;

      if (mode == 'whatsapp') {
        result = await _notificationService!.sendWhatsApp(
          phone: contact.effectivePhone!,
          studentName: studentName,
          studentId: studentId,
          financialId: financialId,
          amount: amount,
          dueDate: dueDate,
          daysOverdue: daysOverdue,
          stage: stage,
          message: message,
        );
      } else {
        result = await _notificationService!.sendEmail(
          email: contact.effectiveEmail!,
          studentName: studentName,
          studentId: studentId,
          financialId: financialId,
          amount: amount,
          dueDate: dueDate,
          daysOverdue: daysOverdue,
          stage: stage,
          subject: subject ?? 'Cobranca - $studentName',
          message: message,
        );
      }

      if (result.success) {
        // Auto-log contact
        await _billingService.logContactAttempt(
          financialId: financialId,
          studentId: studentId,
          studentName: studentName,
          type: mode == 'whatsapp' ? ContactType.whatsapp : ContactType.email,
          notes:
              'Cobranca enviada via ${mode == 'whatsapp' ? 'WhatsApp' : 'Email'}',
          stage: stage.value,
          daysOverdue: daysOverdue,
          contactedBy: FirebaseService.currentUserId ?? '',
          contactedByName: 'Admin',
        );

        if (mounted) {
          FeedbackUtils.showSuccess(
            context,
            '${mode == 'whatsapp' ? 'WhatsApp' : 'Email'} enviado para $studentName!',
          );
        }
      } else {
        if (mounted) {
          FeedbackUtils.showError(
            context,
            'Erro: ${result.error ?? 'Falha no envio'}',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        FeedbackUtils.showError(context, 'Erro ao enviar: $e');
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  // ============================================
  // Unified Bulk Send Dialog
  // ============================================
  void _showBulkSendDialog(BillingStage stage) {
    final items = _overdueStages[stage] ?? [];
    if (items.isEmpty || _notificationService == null) return;

    final recipients = _notificationService!.collectRecipientsForStage(
      financials: items,
      contacts: _studentContacts,
    );

    final messageController = TextEditingController(
      text: _notificationService!.generateGenericStageMessage(stage),
    );
    final subjectController = TextEditingController(
      text: _notificationService!.generateGenericEmailSubject(stage),
    );
    bool scheduleEnabled = false;
    DateTime? scheduledDateTime;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(LucideIcons.send, color: AppTheme.success, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    'Cobrar todos (${items.length})',
                    style: AppTheme.titleLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Recipients info card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.info.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.info.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  LucideIcons.messageCircle,
                                  size: 14,
                                  color: AppTheme.success,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${recipients.phones.length} telefone(s)',
                                  style: AppTheme.bodySmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  LucideIcons.mail,
                                  size: 14,
                                  color: AppTheme.info,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${recipients.emails.length} email(s)',
                                  style: AppTheme.bodySmall,
                                ),
                              ],
                            ),
                            if (recipients.skipped > 0) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    LucideIcons.alertTriangle,
                                    size: 14,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${recipients.skipped} sem contato',
                                    style: AppTheme.bodySmall.copyWith(
                                      color: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Email subject
                      if (recipients.emails.isNotEmpty) ...[
                        Text('Assunto do Email', style: AppTheme.labelMedium),
                        const SizedBox(height: 6),
                        TextField(
                          controller: subjectController,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Message
                      Text('Mensagem', style: AppTheme.labelMedium),
                      const SizedBox(height: 6),
                      TextField(
                        controller: messageController,
                        maxLines: 6,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          helperText:
                              'Variaveis: {nome}, {valor}, {vencimento}, {dias} — personalizadas por aluno',
                          helperMaxLines: 2,
                        ),
                      ),

                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),

                      // Schedule toggle
                      SwitchListTile(
                        title: Row(
                          children: [
                            Icon(
                              LucideIcons.clock,
                              size: 18,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text('Agendar envio'),
                          ],
                        ),
                        value: scheduleEnabled,
                        activeColor: AppTheme.primary,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setDialogState(() => scheduleEnabled = value);
                        },
                      ),

                      // Date/time picker
                      if (scheduleEnabled) ...[
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            LucideIcons.calendar,
                            color: AppTheme.primary,
                          ),
                          title: Text(
                            scheduledDateTime != null
                                ? DateFormat(
                                    'dd/MM/yyyy HH:mm',
                                  ).format(scheduledDateTime!)
                                : 'Selecionar data e hora',
                            style: AppTheme.bodyMedium.copyWith(
                              color: scheduledDateTime != null
                                  ? AppTheme.textPrimary
                                  : AppTheme.textSecondary,
                            ),
                          ),
                          subtitle: const Text('Horario de Brasilia'),
                          trailing: Icon(
                            LucideIcons.chevronRight,
                            size: 18,
                            color: AppTheme.textSecondary,
                          ),
                          onTap: () async {
                            final now = DateTime.now();
                            final date = await showDatePicker(
                              context: context,
                              initialDate: scheduledDateTime ?? now,
                              firstDate: now,
                              lastDate: now.add(const Duration(days: 90)),
                            );
                            if (date == null) return;

                            final time = await showTimePicker(
                              context: context,
                              initialTime: scheduledDateTime != null
                                  ? TimeOfDay.fromDateTime(scheduledDateTime!)
                                  : TimeOfDay.fromDateTime(
                                      now.add(const Duration(hours: 1)),
                                    ),
                            );
                            if (time == null) return;

                            setDialogState(() {
                              scheduledDateTime = DateTime(
                                date.year,
                                date.month,
                                date.day,
                                time.hour,
                                time.minute,
                              );
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: (scheduleEnabled && scheduledDateTime == null)
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                          _executeBulkSendNew(
                            stage: stage,
                            message: messageController.text,
                            subject: subjectController.text,
                            phones: recipients.phones,
                            emails: recipients.emails,
                            scheduledTime:
                                scheduleEnabled && scheduledDateTime != null
                                ? DateFormat(
                                    'yyyy-MM-dd HH:mm',
                                  ).format(scheduledDateTime!)
                                : null,
                          );
                        },
                  icon: Icon(
                    scheduleEnabled ? LucideIcons.clock : LucideIcons.send,
                    size: 16,
                  ),
                  label: Text(
                    scheduleEnabled ? 'Agendar Envio' : 'Enviar Agora',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheduleEnabled
                        ? AppTheme.primary
                        : AppTheme.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================
  // Execute Bulk Send (personalized per student)
  // ============================================
  Future<void> _executeBulkSendNew({
    required BillingStage stage,
    required String message,
    required String subject,
    required List<String> phones,
    required List<String> emails,
    String? scheduledTime,
  }) async {
    if (_notificationService == null) return;
    if (!(_notificationSettings?.whatsappEnabled ?? false) &&
        !(_notificationSettings?.emailEnabled ?? false)) {
      FeedbackUtils.showError(
        context,
        'Nenhum canal de notificacao esta habilitado. Habilite WhatsApp ou Email nas configuracoes.',
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final items = _overdueStages[stage] ?? [];
      final messageTemplate = message;
      final subjectTemplate = subject;
      int waSent = 0, waFailed = 0, waTotal = 0;
      int emSent = 0, emFailed = 0, emTotal = 0;
      final failures = <BulkFailure>[];

      for (final item in items) {
        final studentId = item['studentId'] as String? ?? '';
        final contact = _studentContacts[studentId];
        if (contact == null) continue;

        final studentName = item['studentName'] as String? ?? '';
        final amount = (item['amount'] as num?)?.toDouble() ?? 0;
        final dueDate = item['dueDate'] as DateTime;
        final daysOverdue = item['daysOverdue'] as int? ?? 0;
        final financialId = item['id'] as String? ?? '';

        final personalizedMessage = _notificationService!.applyMessageTemplate(
          messageTemplate,
          studentName,
          amount,
          dueDate,
          daysOverdue,
        );
        final personalizedSubject = _notificationService!.applyMessageTemplate(
          subjectTemplate,
          studentName,
          amount,
          dueDate,
          daysOverdue,
        );

        // Send WhatsApp (only if enabled in settings)
        final phone = contact.effectivePhone;
        if ((_notificationSettings?.whatsappEnabled ?? false) &&
            phone != null &&
            phone.isNotEmpty) {
          waTotal++;
          final result = await _notificationService!.sendWhatsApp(
            phone: phone,
            studentName: studentName,
            studentId: studentId,
            financialId: financialId,
            amount: amount,
            dueDate: dueDate,
            daysOverdue: daysOverdue,
            stage: stage,
            message: personalizedMessage,
          );
          if (result.success) {
            waSent++;
          } else {
            waFailed++;
            failures.add(
              BulkFailure(
                type: 'whatsapp',
                recipient: phone,
                error: result.error ?? '',
              ),
            );
          }
        }

        // Send Email (only if enabled in settings)
        final email = contact.effectiveEmail;
        if ((_notificationSettings?.emailEnabled ?? false) &&
            email != null &&
            email.isNotEmpty) {
          emTotal++;
          final result = await _notificationService!.sendEmail(
            email: email,
            studentName: studentName,
            studentId: studentId,
            financialId: financialId,
            amount: amount,
            dueDate: dueDate,
            daysOverdue: daysOverdue,
            stage: stage,
            subject: personalizedSubject,
            message: personalizedMessage,
          );
          if (result.success) {
            emSent++;
          } else {
            emFailed++;
            failures.add(
              BulkFailure(
                type: 'email',
                recipient: email,
                error: result.error ?? '',
              ),
            );
          }
        }

        // Auto-log contact
        final sentWhatsApp =
            (_notificationSettings?.whatsappEnabled ?? false) &&
            phone != null &&
            phone.isNotEmpty;
        final sentEmail =
            (_notificationSettings?.emailEnabled ?? false) &&
            email != null &&
            email.isNotEmpty;
        if (sentWhatsApp || sentEmail) {
          await _billingService.logContactAttempt(
            financialId: financialId,
            studentId: studentId,
            studentName: studentName,
            type: sentWhatsApp ? ContactType.whatsapp : ContactType.email,
            notes: 'Cobranca em massa (personalizada)',
            stage: stage.value,
            daysOverdue: daysOverdue,
            contactedBy: FirebaseService.currentUserId ?? '',
            contactedByName: 'Admin',
          );
        }
      }

      if (mounted) {
        _showBulkServerResultDialog(
          BulkServerResult(
            success: true,
            scheduled: false,
            whatsapp: BulkChannelSummary(
              total: waTotal,
              sent: waSent,
              failed: waFailed,
            ),
            email: BulkChannelSummary(
              total: emTotal,
              sent: emSent,
              failed: emFailed,
            ),
            failures: failures,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        FeedbackUtils.showError(context, 'Erro no envio em massa: $e');
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  // ============================================
  // Bulk Server Result Dialog
  // ============================================
  void _showBulkServerResultDialog(BulkServerResult result) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                result.scheduled ? LucideIcons.clock : LucideIcons.checkCircle,
                color: result.scheduled ? AppTheme.info : AppTheme.success,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.scheduled ? 'Envio Agendado' : 'Resultado do Envio',
                  style: AppTheme.titleMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (result.scheduled) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.calendar,
                          size: 18,
                          color: AppTheme.info,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Agendado para ${result.scheduledTime ?? ""}',
                            style: AppTheme.bodyMedium.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Channel summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Column(
                        children: [
                          Icon(
                            LucideIcons.messageCircle,
                            size: 18,
                            color: AppTheme.success,
                          ),
                          const SizedBox(height: 4),
                          Text('WhatsApp', style: AppTheme.labelSmall),
                          Text(
                            '${result.whatsapp.sent ?? result.whatsapp.total}/${result.whatsapp.total}',
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Icon(
                            LucideIcons.mail,
                            size: 18,
                            color: AppTheme.info,
                          ),
                          const SizedBox(height: 4),
                          Text('Email', style: AppTheme.labelSmall),
                          Text(
                            '${result.email.sent ?? result.email.total}/${result.email.total}',
                            style: AppTheme.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Failures
                if (result.failures.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Falhas no envio:',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...result.failures.map(
                    (f) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.xCircle,
                            size: 14,
                            color: AppTheme.error,
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.divider,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              f.type == 'whatsapp' ? 'WA' : 'Email',
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              f.recipient,
                              style: AppTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            f.error,
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Fechar',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================
  // Settings Dialog
  // ============================================
  void _showSettingsDialog() {
    bool whatsappEnabled = _notificationSettings?.whatsappEnabled ?? false;
    bool emailEnabled = _notificationSettings?.emailEnabled ?? false;
    // Clone current templates or start empty
    final waTemplates = Map<String, String>.from(
      _notificationSettings?.messageTemplates?.whatsapp ?? {},
    );
    final emailSubjectTemplates = Map<String, String>.from(
      _notificationSettings?.messageTemplates?.emailSubject ?? {},
    );
    final emailBodyTemplates = Map<String, String>.from(
      _notificationSettings?.messageTemplates?.emailBody ?? {},
    );
    bool showTemplates = false;
    int selectedStageIdx = 0;
    final stages = ['D+1', 'D+3', 'D+7', 'D+15', 'D+30'];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final stageKey = stages[selectedStageIdx];

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      LucideIcons.settings,
                      color: AppTheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Configuracoes',
                    style: AppTheme.titleLarge.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Canais de Cobranca', style: AppTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Habilite os canais que deseja utilizar para enviar cobrancas aos alunos.',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Cobranca via WhatsApp'),
                        secondary: Icon(
                          LucideIcons.phone,
                          color: whatsappEnabled
                              ? AppTheme.success
                              : AppTheme.textSecondary,
                        ),
                        value: whatsappEnabled,
                        activeColor: AppTheme.success,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setDialogState(() => whatsappEnabled = value);
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Cobranca via Email'),
                        secondary: Icon(
                          LucideIcons.mail,
                          color: emailEnabled
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                        ),
                        value: emailEnabled,
                        activeColor: AppTheme.primary,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setDialogState(() => emailEnabled = value);
                        },
                      ),

                      const Divider(height: 24),

                      // Template Editor Toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Templates de Mensagem',
                            style: AppTheme.titleSmall,
                          ),
                          TextButton(
                            onPressed: () {
                              setDialogState(
                                () => showTemplates = !showTemplates,
                              );
                            },
                            child: Text(showTemplates ? 'Ocultar' : 'Editar'),
                          ),
                        ],
                      ),
                      Text(
                        'Variaveis: {nome}, {valor}, {vencimento}, {dias}, {academia}',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),

                      if (showTemplates) ...[
                        const SizedBox(height: 12),

                        // Stage selector chips
                        Wrap(
                          spacing: 6,
                          children: List.generate(stages.length, (i) {
                            return ChoiceChip(
                              label: Text(
                                stages[i],
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: selectedStageIdx == i,
                              onSelected: (_) {
                                setDialogState(() => selectedStageIdx = i);
                              },
                              selectedColor: AppTheme.primary.withValues(
                                alpha: 0.2,
                              ),
                              visualDensity: VisualDensity.compact,
                            );
                          }),
                        ),
                        const SizedBox(height: 12),

                        // WhatsApp template
                        Text(
                          'WhatsApp - $stageKey',
                          style: AppTheme.labelMedium,
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          initialValue:
                              waTemplates[stageKey] ??
                              BillingNotificationService
                                  .defaultWhatsAppTemplates[stageKey] ??
                              '',
                          maxLines: 3,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.all(10),
                          ),
                          onChanged: (v) {
                            waTemplates[stageKey] = v;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Email subject
                        Text(
                          'Assunto Email - $stageKey',
                          style: AppTheme.labelMedium,
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          initialValue:
                              emailSubjectTemplates[stageKey] ??
                              BillingNotificationService
                                  .defaultEmailSubjectTemplates[stageKey] ??
                              '',
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                          onChanged: (v) {
                            emailSubjectTemplates[stageKey] = v;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Email body
                        Text(
                          'Corpo Email - $stageKey',
                          style: AppTheme.labelMedium,
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          initialValue:
                              emailBodyTemplates[stageKey] ??
                              BillingNotificationService
                                  .defaultEmailBodyTemplates[stageKey] ??
                              '',
                          maxLines: 4,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.all(10),
                          ),
                          onChanged: (v) {
                            emailBodyTemplates[stageKey] = v;
                          },
                        ),

                        // Reset to default
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () {
                              setDialogState(() {
                                waTemplates.remove(stageKey);
                                emailSubjectTemplates.remove(stageKey);
                                emailBodyTemplates.remove(stageKey);
                              });
                            },
                            child: Text(
                              'Restaurar padrao para $stageKey',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.warning,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      final templates = BillingMessageTemplates(
                        whatsapp: waTemplates,
                        emailSubject: emailSubjectTemplates,
                        emailBody: emailBodyTemplates,
                      );

                      final newSettings = BillingNotificationSettings(
                        whatsappEnabled: whatsappEnabled,
                        emailEnabled: emailEnabled,
                        messageTemplates: templates,
                      );

                      await _billingService.saveNotificationSettings(
                        newSettings,
                      );

                      setState(() {
                        _notificationSettings = newSettings;
                        // Update notification service with new templates
                        _notificationService?.customTemplates = templates;
                      });

                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      if (mounted) {
                        FeedbackUtils.showSuccess(
                          context,
                          'Configuracoes salvas!',
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        FeedbackUtils.showError(context, 'Erro ao salvar: $e');
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================
  // Contact Dialog (manual log)
  // ============================================
  void _showContactDialog({
    required String financialId,
    required String studentId,
    required String studentName,
    required BillingStage stage,
    required int daysOverdue,
  }) {
    ContactType selectedType = ContactType.whatsapp;
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      LucideIcons.clipboardList,
                      color: AppTheme.info,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Registrar Contato',
                      style: AppTheme.titleLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aluno: $studentName',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Tipo de Contato', style: AppTheme.labelMedium),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<ContactType>(
                      value: selectedType,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: ContactType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text(type.label),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => selectedType = value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Text('Observacoes', style: AppTheme.labelMedium),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Detalhes do contato...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await _billingService.logContactAttempt(
                        financialId: financialId,
                        studentId: studentId,
                        studentName: studentName,
                        type: selectedType,
                        notes: notesController.text,
                        stage: stage.value,
                        daysOverdue: daysOverdue,
                        contactedBy: FirebaseService.currentUserId ?? '',
                        contactedByName: 'Admin',
                      );

                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      if (mounted) {
                        FeedbackUtils.showSuccess(
                          context,
                          'Contato registrado com sucesso!',
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        FeedbackUtils.showError(
                          context,
                          'Erro ao registrar contato: $e',
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
