import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../api/domain_providers.dart' as tatami;
import '../../api/dto/financial_dto.dart' as api_fin;
import '../../api/repositories.dart';
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/services.dart';
import '../../widgets/common/academy_page_header.dart';
import 'financial/financial_reports_tab.dart';
import 'financial/financial_widgets.dart';
import 'financial/generate_tuitions_sheet.dart';
import 'financial/payments_tab.dart';
import 'financial/plans_tab.dart';
import 'financial_reports_screen.dart';
import 'paying_students_screen.dart';

/// Admin Financial Screen — coordinates tabs, loads data, owns top-level state.
class AdminFinancialScreen extends ConsumerStatefulWidget {
  const AdminFinancialScreen({super.key});

  @override
  ConsumerState<AdminFinancialScreen> createState() =>
      _AdminFinancialScreenState();
}

class _AdminFinancialScreenState extends ConsumerState<AdminFinancialScreen>
    with SingleTickerProviderStateMixin {
  // Data
  List<Payment> _allPayments = [];
  List<Plan> _plans = [];
  List<Student> _students = [];
  Map<String, dynamic>? _monthlySummary;
  bool _isLoading = true;

  // State
  DateTime _selectedMonth = DateTime.now();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentMonthKey =>
      DateFormat('yyyy-MM').format(_selectedMonth);

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final academyId = FirebaseService.academyId;

      Future<List<Payment>> paymentsFuture() async {
        final first =
            DateTime(_selectedMonth.year, _selectedMonth.month, 1);
        final last =
            DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
        final q = tatami.FinancialsQuery(
          academyId: academyId,
          filter: api_fin.FinancialFilter(
            dueFrom: first,
            dueTo: last,
            limit: 500,
          ),
        );
        ref.invalidate(tatami.tatamiPaymentsLegacyProvider(q));
        return ref.read(tatami.tatamiPaymentsLegacyProvider(q).future);
      }

      Future<List<Student>> studentsFuture() async {
        final q = tatami.StudentsQuery(academyId: academyId);
        ref.invalidate(tatami.tatamiStudentsLegacyProvider(q));
        final all =
            await ref.read(tatami.tatamiStudentsLegacyProvider(q).future);
        return all
            .where((s) =>
                s.status == StudentStatus.active ||
                s.status == StudentStatus.injured)
            .toList();
      }

      Future<Map<String, dynamic>> monthlyFuture() async {
        final key = tatami.AcademyMonth(
          academyId: academyId,
          month: _currentMonthKey,
        );
        ref.invalidate(tatami.tatamiMonthlyReportLegacyProvider(key));
        return ref
            .read(tatami.tatamiMonthlyReportLegacyProvider(key).future);
      }

      final results = await Future.wait([
        paymentsFuture(),
        PlanService(academyId).list(),
        studentsFuture(),
        monthlyFuture(),
      ]);

      setState(() {
        _allPayments = results[0] as List<Payment>;
        _plans = results[1] as List<Plan>;
        _students = results[2] as List<Student>;
        _monthlySummary = results[3] as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth =
          DateTime(_selectedMonth.year, _selectedMonth.month + delta);
    });
    _loadData();
  }

  String _formatCurrency(double value) {
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
        .format(value);
  }

  // ---- Computed lists ----

  List<Payment> get _pendingPayments => _allPayments
      .where((p) => p.status == PaymentStatus.pending && !p.isOverdue)
      .toList();

  List<Payment> get _overduePayments => _allPayments
      .where((p) => p.isOverdue || p.status == PaymentStatus.overdue)
      .toList();

  double get _expectedRevenue {
    double total = 0;
    for (final plan in _plans.where((p) => p.isActive)) {
      total += plan.studentIds
          .fold(0.0, (sum, sid) => sum + plan.getStudentValue(sid));
    }
    return total;
  }

  // ---- Payment actions (passed as callbacks to PaymentsTab) ----

  Future<void> _sendReminder(Payment payment) async {
    try {
      final studentService = StudentService(FirebaseService.academyId);
      final student = await studentService.getById(payment.studentId);
      if (student?.phone == null) {
        if (mounted) {
          context.showWarning('Aluno nao possui telefone cadastrado');
        }
        return;
      }

      final whatsappLink = _buildWhatsAppReminderLink(
        phone: student!.phone!,
        studentName: payment.studentName,
        amount: payment.value,
        dueDate: payment.dueDate,
      );

      if (mounted) context.showInfo('Abrir WhatsApp: $whatsappLink');
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    }
  }

  /// Constrói o link de lembrete WhatsApp. Inlined de PaymentService para
  /// remover dependência do Firestore-backed service.
  String _buildWhatsAppReminderLink({
    required String phone,
    required String studentName,
    required double amount,
    required DateTime dueDate,
  }) {
    final formattedPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    final phoneWithCountry =
        formattedPhone.startsWith('55') ? formattedPhone : '55$formattedPhone';
    final formattedDate =
        '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}/${dueDate.year}';
    final formattedAmount = 'R\$ ${amount.toStringAsFixed(2)}';
    final message = Uri.encodeComponent(
      'Olá! Este é um lembrete sobre a mensalidade de $studentName.\n\n'
      'Valor: $formattedAmount\n'
      'Vencimento: $formattedDate\n\n'
      'Por favor, entre em contato caso tenha alguma dúvida.',
    );
    return 'https://wa.me/$phoneWithCountry?text=$message';
  }

  Future<void> _cancelPayment(Payment payment) async {
    try {
      final academyId = FirebaseService.academyId;
      await ref.read(financialRepoProvider).updateStatus(
            academyId,
            payment.id,
            const api_fin.UpdateFinancialStatusRequest(
              status: api_fin.ApiFinancialStatus.cancelled,
            ),
          );
      if (mounted) {
        context.showSuccess('Pagamento cancelado');
        _loadData();
      }
    } catch (e) {
      if (mounted) context.showError('Erro ao cancelar: $e');
    }
  }

  Future<void> _reactivatePayment(Payment payment) async {
    try {
      final academyId = FirebaseService.academyId;
      // Determina o status baseado na data de vencimento (igual à lógica legacy)
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final dueDate = DateTime(
          payment.dueDate.year, payment.dueDate.month, payment.dueDate.day);
      final newStatus = dueDate.isBefore(todayStart)
          ? api_fin.ApiFinancialStatus.overdue
          : api_fin.ApiFinancialStatus.pending;

      await ref.read(financialRepoProvider).updateStatus(
            academyId,
            payment.id,
            api_fin.UpdateFinancialStatusRequest(status: newStatus),
          );
      if (mounted) {
        context.showSuccess('Pagamento reativado');
        _loadData();
      }
    } catch (e) {
      if (mounted) context.showError('Erro ao reativar: $e');
    }
  }

  // ---- Generate tuitions ----

  void _showGenerateTuitionsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => GenerateTuitionsSheet(
        month: _selectedMonth,
        monthKey: _currentMonthKey,
        plans: _plans,
        students: _students,
        payments: _allPayments,
        onGenerate: (planId) async {
          // Nota: o endpoint Tatami generate-monthly é academy-wide + idempotente.
          // O filtro `planId` era exclusivo do path Firestore; no Tatami o BE
          // garante idempotência por (student, plan, month) server-side.
          try {
            final academyId = FirebaseService.academyId;
            final result = await ref.read(financialRepoProvider).generateMonthly(
                  academyId,
                  _currentMonthKey,
                );
            if (!mounted) return;
            // ignore: use_build_context_synchronously
            Navigator.pop(sheetContext);
            final count = result.generatedCount;
            context.showSuccess(
                '$count mensalidade${count != 1 ? 's' : ''} gerada${count != 1 ? 's' : ''}!');
            _loadData();
          } catch (e) {
            if (mounted) context.showError('Erro: $e');
          }
        },
      ),
    );
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final canWrite =
        user?.hasPermission(TatamiPermissions.financialWrite) ?? false;

    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: _buildFAB(canWrite),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  SliverToBoxAdapter(child: _buildHeader()),
                  SliverToBoxAdapter(
                    child: FinancialMonthSelector(
                      selectedMonth: _selectedMonth,
                      onPrev: () => _changeMonth(-1),
                      onNext: () => _changeMonth(1),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: FinancialStatsGrid(
                      monthlySummary: _monthlySummary,
                      formatCurrency: _formatCurrency,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: FinancialTabBar(
                      tabController: _tabController,
                      pendingTotal: _pendingPayments.length +
                          _overduePayments.length,
                    ),
                  ),
                  SliverFillRemaining(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        PlansTab(
                          plans: _plans,
                          students: _students,
                          formatCurrency: _formatCurrency,
                          expectedRevenue: _expectedRevenue,
                          onRefresh: _loadData,
                        ),
                        PaymentsTab(
                          allPayments: _allPayments,
                          pendingPayments: _pendingPayments,
                          overduePayments: _overduePayments,
                          formatCurrency: _formatCurrency,
                          canWrite: canWrite,
                          onMarkPaid: (_) async => _loadData(),
                          onSendReminder: _sendReminder,
                          onCancel: _cancelPayment,
                          onReactivate: _reactivatePayment,
                        ),
                        FinancialReportsTab(
                          monthlySummary: _monthlySummary,
                          selectedMonth: _selectedMonth,
                          plans: _plans,
                          students: _students,
                          formatCurrency: _formatCurrency,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFAB(bool canWrite) {
    if (!canWrite) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, _) {
        if (_tabController.index == 1) {
          return FloatingActionButton.extended(
            onPressed: _showGenerateTuitionsDialog,
            backgroundColor: AppTheme.primary,
            icon: const Icon(LucideIcons.receipt, size: 20),
            label: const Text('Gerar'),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildHeader() {
    return AcademyPageHeader(
      icon: LucideIcons.dollarSign,
      title: 'Financeiro',
      description: 'Mensalidades e pagamentos',
      actions: [
        IconButton(
          onPressed: _loadData,
          icon: const Icon(LucideIcons.refreshCw, size: 20),
          tooltip: 'Atualizar',
        ),
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PayingStudentsScreen(
                students: _students,
                plans: _plans,
              ),
            ),
          ),
          icon: const Icon(LucideIcons.users, size: 20),
          tooltip: 'Alunos Pagantes',
        ),
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminFinancialReportsScreen(),
            ),
          ),
          icon: const Icon(LucideIcons.barChart2, size: 20),
          tooltip: 'Relatórios',
        ),
      ],
    );
  }
}
