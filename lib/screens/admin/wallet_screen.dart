import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../services/firebase_service.dart';
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
    // Check for AbacatePay specific fields
    final isAbacatePay = map['externalId'] != null;
    
    return WalletTransaction(
      id: id,
      type: 'payment',
      source: map['type'] ?? 'mensalidade',
      amount: (map['amount'] ?? map['value'] ?? 0).toDouble(),
      status: map['paymentDate'] != null ? 'completed' : (map['status'] ?? 'pending'),
      description: map['description'],
      studentName: map['studentName'],
      createdAt: map['createdAt']?.toDate() ?? DateTime.now(),
      completedAt: map['paymentDate']?.toDate() ?? map['paidAt']?.toDate(),
      isAbacatePay: isAbacatePay,
    );
  }

  factory WalletTransaction.fromStoreOrder(Map<String, dynamic> map, String id) {
    // Check for AbacatePay specific fields for store orders
    final isAbacatePay = map['externalPaymentId'] != null;

    return WalletTransaction(
      id: id,
      type: 'store_sale',
      source: 'loja',
      amount: (map['total'] ?? 0).toDouble(),
      status: map['status'] == 'delivered' || map['status'] == 'completed' ? 'completed' : 'pending',
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

  // Carousel controller
  final PageController _carouselController = PageController(viewportFraction: 0.85);
  int _currentCardIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadWalletData();
  }

  @override
  void dispose() {
    _carouselController.dispose();
    super.dispose();
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
          .map((doc) => WalletTransaction.fromPayment(
              doc.data(), doc.id))
          .toList();

      // Load store orders
      final ordersSnapshot = await academyRef.collection('storeOrders').get();
      final orders = ordersSnapshot.docs
          .map((doc) => WalletTransaction.fromStoreOrder(
              doc.data(), doc.id))
          .toList();

      // Combine and sort all transactions
      final allTransactions = [...payments, ...orders];
      
      // Filter for only AbacatePay transactions
      // Only show transactions that have an external ID associated (AbacatePay)
      final abacatePayTransactions = allTransactions.where((tx) => tx.isAbacatePay).toList();
      
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
          availableBalance: totalReceived, // In a real scenario, subtract withdrawals
          pendingBalance: pendingBalance,
          totalReceived: totalReceived,
          totalWithdrawn: 0, // TODO: Load from withdrawals collection
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _WithdrawalBottomSheet(
        maxAmount: _wallet?.availableBalance ?? 0,
        onWithdraw: (amount, pixKey, pixKeyType) async {
          // TODO: Implement withdrawal
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saque solicitado com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
          _handleRefresh();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(academySettingsProvider).valueOrNull;
    final isAbacatePayEnabled = settings?.abacatePayEnabled ?? false;

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
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Carteira', style: AppTheme.headlineMedium),
                          Text(
                            'Gerencie seu saldo e transacoes',
                            style: AppTheme.bodyMedium.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _isRefreshing ? null : _handleRefresh,
                      icon: _isRefreshing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.refreshCw),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: (_wallet?.availableBalance ?? 0) >= 100
                          ? _showWithdrawalSheet
                          : null,
                      icon: const Icon(LucideIcons.banknote, size: 18),
                      label: const Text('Sacar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Balance Cards Carousel
            SliverToBoxAdapter(
              child: Column(
                children: [
                  SizedBox(
                    height: 100,
                    child: _isLoading
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          )
                        : PageView(
                            controller: _carouselController,
                            onPageChanged: (index) {
                              setState(() => _currentCardIndex = index);
                            },
                            children: [
                              _BalanceCarouselCard(
                                title: 'Disponivel',
                                value: _wallet?.availableBalance ?? 0,
                                icon: LucideIcons.wallet,
                                color: Colors.green,
                              ),
                              _BalanceCarouselCard(
                                title: 'Pendente',
                                value: _wallet?.pendingBalance ?? 0,
                                icon: LucideIcons.clock,
                                color: Colors.orange,
                              ),
                              _BalanceCarouselCard(
                                title: 'Total Recebido',
                                value: _wallet?.totalReceived ?? 0,
                                icon: LucideIcons.trendingUp,
                                color: AppTheme.primary,
                              ),
                              _BalanceCarouselCard(
                                title: 'Total Sacado',
                                value: _wallet?.totalWithdrawn ?? 0,
                                icon: LucideIcons.arrowUpRight,
                                color: Colors.purple,
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),
                  // Dot indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentCardIndex == index ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentCardIndex == index
                              ? AppTheme.textPrimary
                              : AppTheme.divider,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),

            // Transactions Header
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
                        '${_transactions.length} transacoes',
                        style: AppTheme.labelSmall,
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
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceVariant,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.dollarSign,
                            size: 40,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhuma transacao ainda',
                          style: AppTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'As transacoes aparecerao aqui quando seus alunos fizerem pagamentos',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
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
                      child: _TransactionCard(transaction: _transactions[index]),
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

/// Balance Carousel Card Widget
class _BalanceCarouselCard extends StatelessWidget {
  final String title;
  final double value;
  final IconData icon;
  final Color color;

  const _BalanceCarouselCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  currencyFormat.format(value / 100),
                  style: AppTheme.headlineSmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  title,
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
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
    final dateFormat = DateFormat('dd MMM yyyy HH:mm', 'pt_BR');
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
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
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: sourceColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
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
                        transaction.description ?? transaction.sourceLabel,
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getStatusLabel(),
                        style: AppTheme.labelSmall.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    Expanded(
                      child: Text(
                        [
                          if (transaction.studentName != null) transaction.studentName,
                          if (transaction.productName != null) transaction.productName,
                          dateFormat.format(transaction.createdAt),
                        ].join(' • '),
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${transaction.isCredit ? '+' : '-'} ${currencyFormat.format(transaction.amount / 100)}',
            style: AppTheme.titleSmall.copyWith(
              fontWeight: FontWeight.w700,
              color: transaction.isCredit ? Colors.green : AppTheme.error,
            ),
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
                decoration: const InputDecoration(
                  labelText: 'Chave PIX',
                  prefixIcon: Icon(LucideIcons.key),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Informe a chave PIX';
                  }
                  return null;
                },
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
