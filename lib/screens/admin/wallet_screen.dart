import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../services/firebase_service.dart';
import '../../services/abacate_pay_service.dart';
import '../../providers/providers.dart';

/// Wallet Transaction model
class WalletTransaction {
  final String id;
  final String type; // 'payment', 'withdrawal', 'store_sale', 'refund'
  final String source; // 'mensalidade', 'loja', 'competicao', 'manual', 'saque'
  final double amount;
  final String status; // 'pending', 'completed', 'failed', 'cancelled'
  final String? description;
  final String? studentName;
  final String? productName;
  final DateTime createdAt;
  final DateTime? completedAt;

  final bool isAbacatePay;

  WalletTransaction({
    required this.id,
    required this.type,
    required this.source,
    required this.amount,
    required this.status,
    this.description,
    this.studentName,
    this.productName,
    required this.createdAt,
    this.completedAt,
    this.isAbacatePay = false,
  });

  factory WalletTransaction.fromPayment(Map<String, dynamic> map, String id) {
    final isAbacatePay = map['externalId'] != null;

    return WalletTransaction(
      id: id,
      type: 'payment',
      source: map['type'] ?? 'mensalidade',
      amount: (map['amount'] ?? map['value'] ?? 0).toDouble(),
      status: map['paymentDate'] != null
          ? 'completed'
          : (map['status'] ?? 'pending'),
      description: map['description'],
      studentName: map['studentName'],
      createdAt: map['createdAt']?.toDate() ?? DateTime.now(),
      completedAt: map['paymentDate']?.toDate() ?? map['paidAt']?.toDate(),
      isAbacatePay: isAbacatePay,
    );
  }

  factory WalletTransaction.fromStoreOrder(
      Map<String, dynamic> map, String id) {
    final isAbacatePay = map['externalPaymentId'] != null || map['abacatePayTransactionId'] != null;

    return WalletTransaction(
      id: id,
      type: 'store_sale',
      source: 'loja',
      amount: (map['total'] ?? map['totalAmount'] ?? 0).toDouble(),
      status: map['status'] == 'paid' || map['status'] == 'delivered' || map['status'] == 'completed'
          ? 'completed'
          : 'pending',
      description: 'Venda na loja',
      studentName: map['studentName'],
      productName: (map['items'] as List?)?.isNotEmpty == true
          ? '${(map['items'] as List).length} item(ns)'
          : null,
      createdAt: map['createdAt']?.toDate() ?? DateTime.now(),
      completedAt: map['deliveredAt']?.toDate(),
      isAbacatePay: isAbacatePay,
    );
  }

  bool get isCredit => type == 'payment' || type == 'store_sale';

  String get sourceLabel {
    switch (source) {
      case 'mensalidade':
        return 'Mensalidade';
      case 'loja':
        return 'Loja';
      case 'competicao':
        return 'Competicao';
      case 'manual':
        return 'Manual';
      case 'saque':
        return 'Saque';
      default:
        return source;
    }
  }

  IconData get sourceIcon {
    switch (source) {
      case 'mensalidade':
        return LucideIcons.creditCard;
      case 'loja':
        return LucideIcons.shoppingBag;
      case 'competicao':
        return LucideIcons.trophy;
      case 'saque':
        return LucideIcons.banknote;
      default:
        return LucideIcons.dollarSign;
    }
  }
}

/// Academy Wallet model
class AcademyWallet {
  final double availableBalance;
  final double pendingBalance;
  final double totalReceived;
  final double totalWithdrawn;
  final int transactionCount;

  AcademyWallet({
    required this.availableBalance,
    required this.pendingBalance,
    required this.totalReceived,
    required this.totalWithdrawn,
    required this.transactionCount,
  });

  factory AcademyWallet.empty() {
    return AcademyWallet(
      availableBalance: 0,
      pendingBalance: 0,
      totalReceived: 0,
      totalWithdrawn: 0,
      transactionCount: 0,
    );
  }
}

/// Admin Wallet Screen
class AdminWalletScreen extends ConsumerStatefulWidget {
  const AdminWalletScreen({super.key});

  @override
  ConsumerState<AdminWalletScreen> createState() => _AdminWalletScreenState();
}

class _AdminWalletScreenState extends ConsumerState<AdminWalletScreen> {
  AcademyWallet? _wallet;
  List<WalletTransaction> _transactions = [];
  bool _isLoading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadWalletData();
  }

  Future<void> _loadWalletData() async {
    final academyId = FirebaseService.academyId;
    if (academyId.isEmpty) return;

    try {
      final firestore = FirebaseService.firestore;
      final academyRef = firestore.collection('academies').doc(academyId);

      // Load payments (financials)
      final paymentsSnapshot = await academyRef.collection('financials').get();
      final payments = paymentsSnapshot.docs
          .map((doc) => WalletTransaction.fromPayment(doc.data(), doc.id))
          .toList();

      // Load store orders
      final ordersSnapshot = await academyRef.collection('storeOrders').get();
      final orders = ordersSnapshot.docs
          .map((doc) => WalletTransaction.fromStoreOrder(doc.data(), doc.id))
          .toList();

      // Combine and sort all transactions
      final allTransactions = [...payments, ...orders];

      // Filter for only AbacatePay transactions
      final abacatePayTransactions =
          allTransactions.where((tx) => tx.isAbacatePay).toList();

      abacatePayTransactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Calculate wallet balances based on filtered transactions
      double totalReceived = 0;
      double pendingBalance = 0;

      for (final tx in abacatePayTransactions) {
        if (tx.isCredit) {
          if (tx.status == 'completed') {
            totalReceived += tx.amount;
          } else if (tx.status == 'pending') {
            pendingBalance += tx.amount;
          }
        }
      }

      setState(() {
        _wallet = AcademyWallet(
          availableBalance: totalReceived,
          pendingBalance: pendingBalance,
          totalReceived: totalReceived,
          totalWithdrawn: 0,
          transactionCount: abacatePayTransactions.length,
        );
        _transactions = abacatePayTransactions;
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);
    await _loadWalletData();
  }

  void _showWithdrawalSheet() {
    final academyId = FirebaseService.academyId;
    if (academyId == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _WithdrawalBottomSheet(
        maxAmount: _wallet?.availableBalance ?? 0,
        onWithdraw: (amount, pixKey, pixKeyType) async {
          final service = AbacatePayService(academyId);
          final result = await service.requestWithdrawal(
            amountInCents: amount,
            pixKey: pixKey,
            pixKeyType: pixKeyType,
          );

          if (!mounted) return;
          Navigator.pop(context);

          if (result.success) {
            context.showSuccess('Saque solicitado com sucesso!');
          } else {
            context.showError(result.message ?? 'Erro ao solicitar saque');
          }
          _handleRefresh();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(academySettingsProvider).valueOrNull;
    final isAbacatePayEnabled = settings?.abacatePayEnabled ?? false;
    final currencyFormat =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    if (!isAbacatePayEnabled) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    LucideIcons.alertCircle,
                    size: 48,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Carteira Desativada',
                  style: AppTheme.headlineMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Ative os pagamentos pela plataforma nas configuracoes para acessar sua carteira.',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => context.go('/admin/configuracoes'),
                  icon: const Icon(LucideIcons.settings),
                  label: const Text('Ir para Configuracoes'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: CustomScrollView(
          slivers: [
            // Main Balance Card with Gradient
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                  child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF09090B),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Saldo Disponivel',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _isLoading
                          ? Container(
                              height: 48,
                              width: 180,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            )
                          : Text(
                              currencyFormat
                                  .format((_wallet?.availableBalance ?? 0) / 100),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 42,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.5,
                                height: 1.1,
                              ),
                            ),
                      if (!_isLoading && (_wallet?.pendingBalance ?? 0) > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'A receber: ${currencyFormat.format((_wallet?.pendingBalance ?? 0) / 100)}',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: (_wallet?.availableBalance ?? 0) >= 100
                              ? _showWithdrawalSheet
                              : null,
                          icon: const Icon(LucideIcons.arrowUpRight, size: 18),
                          label: const Text('Solicitar Saque'),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            disabledBackgroundColor: Colors.white.withOpacity(0.1),
                            disabledForegroundColor: Colors.white.withOpacity(0.3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),



            // Transactions Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Transacoes Recentes',
                      style: AppTheme.titleMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!_isLoading && _transactions.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_transactions.length}',
                          style: AppTheme.labelSmall.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Transactions List
            if (_isLoading)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    childCount: 5,
                  ),
                ),
              )
            else if (_transactions.isEmpty)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          LucideIcons.inbox,
                          size: 32,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhuma transacao ainda',
                        style: AppTheme.titleMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'As transacoes aparecerao aqui quando seus alunos fizerem pagamentos pela plataforma',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child:
                          _TransactionCard(transaction: _transactions[index]),
                    ),
                    childCount: _transactions.length,
                  ),
                ),
              ),

            // Bottom padding
            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stat Card Widget
class _StatCard extends StatelessWidget {
  final String title;
  final double? value;
  final String? valueText;
  final IconData icon;
  final Color color;
  final bool isLoading;

  const _StatCard({
    required this.title,
    this.value,
    this.valueText,
    required this.icon,
    required this.color,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          if (isLoading)
            Container(
              height: 24,
              width: 80,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            )
          else
            Text(
              valueText ?? currencyFormat.format((value ?? 0) / 100),
              style: AppTheme.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            title,
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Transaction Card Widget
class _TransactionCard extends StatelessWidget {
  final WalletTransaction transaction;

  const _TransactionCard({required this.transaction});

  Color _getStatusColor() {
    switch (transaction.status) {
      case 'completed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'failed':
      case 'cancelled':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }

  String _getStatusLabel() {
    switch (transaction.status) {
      case 'completed':
        return 'Concluido';
      case 'pending':
        return 'Pendente';
      case 'failed':
        return 'Falhou';
      case 'cancelled':
        return 'Cancelado';
      default:
        return transaction.status;
    }
  }

  Color _getSourceColor() {
    switch (transaction.source) {
      case 'mensalidade':
        return AppTheme.primary;
      case 'loja':
        return Colors.purple;
      case 'competicao':
        return Colors.orange;
      case 'saque':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM', 'pt_BR');
    final currencyFormat =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final statusColor = _getStatusColor();
    final sourceColor = _getSourceColor();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: sourceColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              transaction.sourceIcon,
              size: 20,
              color: sourceColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        transaction.studentName ??
                            transaction.description ??
                            transaction.sourceLabel,
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: sourceColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        transaction.sourceLabel,
                        style: AppTheme.labelSmall.copyWith(
                          color: sourceColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _getStatusLabel(),
                      style: AppTheme.labelSmall.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dateFormat.format(transaction.createdAt),
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${transaction.isCredit ? '+' : '-'} ${currencyFormat.format(transaction.amount / 100)}',
                style: AppTheme.titleSmall.copyWith(
                  fontWeight: FontWeight.w700,
                  color: transaction.isCredit
                      ? const Color(0xFF16A34A)
                      : AppTheme.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Withdrawal Bottom Sheet
class _WithdrawalBottomSheet extends StatefulWidget {
  final double maxAmount;
  final Future<void> Function(double amount, String pixKey, String pixKeyType)
      onWithdraw;

  const _WithdrawalBottomSheet({
    required this.maxAmount,
    required this.onWithdraw,
  });

  @override
  State<_WithdrawalBottomSheet> createState() => _WithdrawalBottomSheetState();
}

class _WithdrawalBottomSheetState extends State<_WithdrawalBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _pixKeyController = TextEditingController();
  String _pixKeyType = 'cpf';
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _amountController.dispose();
    _pixKeyController.dispose();
    super.dispose();
  }

  String _getPixKeyHint(String type) {
    switch (type) {
      case 'cpf':
        return '000.000.000-00';
      case 'cnpj':
        return '00.000.000/0000-00';
      case 'email':
        return 'email@exemplo.com';
      case 'phone':
        return '(00) 00000-0000';
      case 'random':
        return 'Chave aleatoria';
      default:
        return '';
    }
  }

  TextInputType _getPixKeyKeyboardType(String type) {
    switch (type) {
      case 'cpf':
      case 'cnpj':
      case 'phone':
        return TextInputType.number;
      case 'email':
        return TextInputType.emailAddress;
      default:
        return TextInputType.text;
    }
  }

  Future<void> _handleWithdraw() async {
    if (!_formKey.currentState!.validate()) return;

    final amountText = _amountController.text.replaceAll(RegExp(r'[^\d,]'), '');
    final amount = double.tryParse(amountText.replaceAll(',', '.')) ?? 0;
    final amountInCents = amount * 100;

    if (amountInCents < 100) {
      setState(() => _errorMessage = 'Valor minimo: R\$ 1,00');
      return;
    }

    if (amountInCents > widget.maxAmount) {
      setState(() => _errorMessage = 'Saldo insuficiente');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.onWithdraw(amountInCents, _pixKeyController.text, _pixKeyType);
    } catch (e) {
      setState(() => _errorMessage = 'Erro ao solicitar saque');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      LucideIcons.banknote,
                      color: AppTheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Solicitar Saque',
                          style: AppTheme.titleLarge.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Disponivel: ${currencyFormat.format(widget.maxAmount / 100)}',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Error Message
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.errorLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.alertCircle,
                          color: AppTheme.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Amount Field
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Valor do saque',
                  prefixText: 'R\$ ',
                  prefixIcon: Icon(LucideIcons.dollarSign),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Informe o valor';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // PIX Key Type
              DropdownButtonFormField<String>(
                value: _pixKeyType,
                decoration: const InputDecoration(
                  labelText: 'Tipo de chave PIX',
                  prefixIcon: Icon(LucideIcons.key),
                ),
                items: const [
                  DropdownMenuItem(value: 'cpf', child: Text('CPF')),
                  DropdownMenuItem(value: 'cnpj', child: Text('CNPJ')),
                  DropdownMenuItem(value: 'email', child: Text('E-mail')),
                  DropdownMenuItem(value: 'phone', child: Text('Telefone')),
                  DropdownMenuItem(value: 'random', child: Text('Chave aleatoria')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _pixKeyType = value);
                  }
                },
              ),
              const SizedBox(height: 16),

              // PIX Key Field
              TextFormField(
                controller: _pixKeyController,
                decoration: InputDecoration(
                  labelText: 'Chave PIX',
                  prefixIcon: const Icon(LucideIcons.key),
                  hintText: _getPixKeyHint(_pixKeyType),
                ),
                keyboardType: _getPixKeyKeyboardType(_pixKeyType),
                validator: (value) => Validators.pixKey(value, _pixKeyType),
              ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _handleWithdraw,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.banknote),
                  label: Text(_isLoading ? 'Processando...' : 'Solicitar Saque'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
