import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';

import 'package:flutter/services.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../core/validators.dart';
import '../../services/firebase_service.dart';
import '../../services/abacate_pay_service.dart';
import '../../services/totp_service.dart';
import '../../providers/providers.dart';
import '../../widgets/polish/polish.dart';

/// Wallet Transaction model
class WalletTransaction {
  final String id;
  final String type; // 'payment', 'withdrawal', 'store_sale', 'refund'
  final String source; // 'mensalidade', 'loja', 'competicao', 'manual', 'saque'
  final double amount;
  final double? fee; // Fee charged (in reais)
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
    this.fee,
    required this.status,
    this.description,
    this.studentName,
    this.productName,
    required this.createdAt,
    this.completedAt,
    this.isAbacatePay = false,
  });

  factory WalletTransaction.fromPayment(Map<String, dynamic> map, String id) {
    final isAbacatePay = map['externalId'] != null || map['asaasPaymentId'] != null;

    return WalletTransaction(
      id: id,
      type: 'payment',
      source: map['type'] ?? 'mensalidade',
      amount: (map['amount'] ?? map['value'] ?? 0).toDouble(),
      fee: map['fee'] != null ? (map['fee'] as num).toDouble() / 100 : null,
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
    final isAbacatePay = map['externalPaymentId'] != null || map['abacatePayTransactionId'] != null || map['asaasPaymentId'] != null;

    return WalletTransaction(
      id: id,
      type: 'store_sale',
      source: 'loja',
      amount: (map['total'] ?? map['totalAmount'] ?? 0).toDouble(),
      fee: map['fee'] != null ? (map['fee'] as num).toDouble() / 100 : null,
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
  bool _isTotpEnabled = false;
  String _transactionFilter = 'all'; // 'all', 'mensalidade', 'saque', 'loja'

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

      // Load wallet balance document (maintained by webhook with fee deduction)
      final walletSnap = await academyRef.collection('wallet').doc('balance').get();

      // Load wallet transactions (the authoritative source)
      final txSnapshot = await academyRef
          .collection('walletTransactions')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      final transactions = txSnapshot.docs.map((doc) {
        final data = doc.data();
        final type = data['type'] as String? ?? 'payment';
        final source = type == 'withdrawal' ? 'saque' :
            (data['financialId']?.toString().startsWith('order_') == true ? 'loja' : 'mensalidade');

        return WalletTransaction(
          id: doc.id,
          type: type,
          source: source,
          amount: (data['amount'] ?? 0).toDouble(),
          status: data['status'] ?? 'pending',
          description: data['description'],
          studentName: data['studentName'],
          createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
          completedAt: data['completedAt']?.toDate(),
          isAbacatePay: true,
        );
      })
      // Hide pending student payments/orders, but keep withdrawals (any status)
      .where((t) => t.status != 'pending' || t.type == 'withdrawal')
      .toList();

      // Use wallet/balance document for balances (correctly includes fee deductions)
      double availableBalance = 0;
      double pendingBalance = 0;
      double totalReceived = 0;
      double totalWithdrawn = 0;
      int transactionCount = transactions.length;

      if (walletSnap.exists) {
        final walletData = walletSnap.data()!;
        availableBalance = (walletData['availableBalance'] ?? 0).toDouble();
        pendingBalance = (walletData['pendingBalance'] ?? 0).toDouble();
        totalReceived = (walletData['totalReceived'] ?? 0).toDouble();
        totalWithdrawn = (walletData['totalWithdrawn'] ?? 0).toDouble();
        transactionCount = (walletData['transactionCount'] ?? transactions.length);
      }

      // Load TOTP status
      bool totpEnabled = false;
      try {
        totpEnabled = await TotpService().isTotpEnabled();
      } catch (_) {}

      setState(() {
        _wallet = AcademyWallet(
          availableBalance: availableBalance,
          pendingBalance: pendingBalance,
          totalReceived: totalReceived,
          totalWithdrawn: totalWithdrawn,
          transactionCount: transactionCount,
        );
        _transactions = transactions;
        _isTotpEnabled = totpEnabled;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRefresh() async {
    await _loadWalletData();
  }

  void _showWithdrawalSheet() {
    final academyId = FirebaseService.academyId;

    // If TOTP is enabled, require validation before showing withdrawal sheet
    if (_isTotpEnabled) {
      _showTotpCodeBottomSheet(
        title: 'Autenticacao 2FA',
        subtitle: 'Digite o codigo do seu autenticador para continuar',
        onValidated: () => _openWithdrawalSheet(academyId),
      );
      return;
    }

    _openWithdrawalSheet(academyId);
  }

  void _openWithdrawalSheet(String academyId) {
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
            Celebration.confetti(context);
            context.showSuccess('Saque solicitado com sucesso!');
          } else {
            context.showError(result.message ?? 'Erro ao solicitar saque');
          }
          _handleRefresh();
        },
      ),
    );
  }

  void _showTotpCodeBottomSheet({
    required String title,
    required String subtitle,
    required VoidCallback onValidated,
    bool isDisable = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _TotpCodeBottomSheet(
        title: title,
        subtitle: subtitle,
        onSubmit: (code) async {
          final service = TotpService();

          if (isDisable) {
            final result = await service.disableTotp(code);
            if (!mounted) return result.success;
            Navigator.pop(sheetContext);
            if (result.success) {
              context.showSuccess('2FA desativado com sucesso');
              _handleRefresh();
            } else {
              context.showError(result.message ?? 'Codigo invalido');
            }
            return result.success;
          } else {
            final result = await service.validateCode(code);
            if (!mounted) return result.success;
            if (result.success) {
              Navigator.pop(sheetContext);
              onValidated();
            }
            return result.success;
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(academySettingsProvider).valueOrNull;
    final mpConnected = settings?.mpConnected ?? false;
    // The platform wallet (saldo/saques) only exists for the AbacatePay flow.
    // When Mercado Pago is connected, money lands straight in the academy's own
    // MP account, so there's no platform balance to show — but it's not a
    // disabled dead-end either. Show an MP-appropriate informational view.
    final isPaymentEnabled = settings?.abacatePayEnabled ?? false; // Apenas AbacatePay
    final currencyFormat =
        NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    if (!isPaymentEnabled) {
      if (mpConnected) {
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: PolishedEmptyState(
            icon: LucideIcons.wallet,
            accent: const Color(0xFF009EE3),
            title: 'Pagamentos via Mercado Pago',
            subtitle:
                'Sua conta esta conectada ao Mercado Pago. Os pagamentos caem '
                'direto na sua conta Mercado Pago — sem saldo nem saques pela '
                'plataforma. Acompanhe o dinheiro pelo app do Mercado Pago.',
            actionLabel: 'Ir para Configuracoes',
            onAction: () => context.go('/admin/configuracoes'),
          ),
        );
      }
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: PolishedEmptyState(
          icon: LucideIcons.alertCircle,
          accent: Colors.orange,
          title: 'Carteira Desativada',
          subtitle:
              'Ative os pagamentos pela plataforma nas configuracoes para acessar sua carteira.',
          actionLabel: 'Ir para Configuracoes',
          onAction: () => context.go('/admin/configuracoes'),
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
                          : AnimatedCountUp(
                              value: (_wallet?.availableBalance ?? 0) / 100,
                              decimals: 2,
                              prefix: 'R\$ ',
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

            // Fee Information Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Card(
                  color: Colors.blue.shade50,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.blue.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Taxa de R\$ 0,80 por transação (pagamentos e saques), deduzida automaticamente.',
                            style: TextStyle(fontSize: 13, color: Colors.blue.shade800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Transactions Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                              '${_transactions.where((t) {
                                if (_transactionFilter == 'mensalidade') return t.source == 'mensalidade';
                                if (_transactionFilter == 'saque') return t.source == 'saque';
                                if (_transactionFilter == 'loja') return t.source == 'loja';
                                return true;
                              }).length}',
                              style: AppTheme.labelSmall.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Filter Chips
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Todas'),
                          selected: _transactionFilter == 'all',
                          onSelected: (_) => setState(() => _transactionFilter = 'all'),
                          backgroundColor: AppTheme.surface,
                          selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                          checkmarkColor: AppTheme.primary,
                          labelStyle: TextStyle(
                            color: _transactionFilter == 'all' ? AppTheme.primary : AppTheme.textPrimary,
                            fontWeight: _transactionFilter == 'all' ? FontWeight.w600 : FontWeight.w500,
                          ),
                          side: BorderSide(
                            color: _transactionFilter == 'all' ? AppTheme.primary : AppTheme.divider,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        FilterChip(
                          label: const Text('Mensalidades'),
                          selected: _transactionFilter == 'mensalidade',
                          onSelected: (_) => setState(() => _transactionFilter = 'mensalidade'),
                          avatar: Icon(
                            LucideIcons.creditCard,
                            size: 16,
                            color: _transactionFilter == 'mensalidade' ? AppTheme.primary : AppTheme.textSecondary,
                          ),
                          backgroundColor: AppTheme.surface,
                          selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                          checkmarkColor: AppTheme.primary,
                          labelStyle: TextStyle(
                            color: _transactionFilter == 'mensalidade' ? AppTheme.primary : AppTheme.textPrimary,
                            fontWeight: _transactionFilter == 'mensalidade' ? FontWeight.w600 : FontWeight.w500,
                          ),
                          side: BorderSide(
                            color: _transactionFilter == 'mensalidade' ? AppTheme.primary : AppTheme.divider,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        FilterChip(
                          label: const Text('Saques'),
                          selected: _transactionFilter == 'saque',
                          onSelected: (_) => setState(() => _transactionFilter = 'saque'),
                          avatar: Icon(
                            LucideIcons.banknote,
                            size: 16,
                            color: _transactionFilter == 'saque' ? AppTheme.primary : AppTheme.textSecondary,
                          ),
                          backgroundColor: AppTheme.surface,
                          selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                          checkmarkColor: AppTheme.primary,
                          labelStyle: TextStyle(
                            color: _transactionFilter == 'saque' ? AppTheme.primary : AppTheme.textPrimary,
                            fontWeight: _transactionFilter == 'saque' ? FontWeight.w600 : FontWeight.w500,
                          ),
                          side: BorderSide(
                            color: _transactionFilter == 'saque' ? AppTheme.primary : AppTheme.divider,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        FilterChip(
                          label: const Text('Loja'),
                          selected: _transactionFilter == 'loja',
                          onSelected: (_) => setState(() => _transactionFilter = 'loja'),
                          avatar: Icon(
                            LucideIcons.shoppingBag,
                            size: 16,
                            color: _transactionFilter == 'loja' ? AppTheme.primary : AppTheme.textSecondary,
                          ),
                          backgroundColor: AppTheme.surface,
                          selectedColor: AppTheme.primary.withValues(alpha: 0.15),
                          checkmarkColor: AppTheme.primary,
                          labelStyle: TextStyle(
                            color: _transactionFilter == 'loja' ? AppTheme.primary : AppTheme.textPrimary,
                            fontWeight: _transactionFilter == 'loja' ? FontWeight.w600 : FontWeight.w500,
                          ),
                          side: BorderSide(
                            color: _transactionFilter == 'loja' ? AppTheme.primary : AppTheme.divider,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ],
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
                      child: PolishSkeleton.shimmer(
                        child: Container(
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    childCount: 5,
                  ),
                ),
              )
            else if (_transactions.isEmpty)
              const SliverToBoxAdapter(
                child: PolishedEmptyState(
                  icon: LucideIcons.inbox,
                  title: 'Nenhuma transacao ainda',
                  subtitle:
                      'As transacoes aparecerao aqui quando seus alunos fizerem pagamentos pela plataforma',
                  accent: AppTheme.textSecondary,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      // Filter transactions based on selected filter
                      final filteredTransactions = _transactions.where((t) {
                        if (_transactionFilter == 'mensalidade') return t.source == 'mensalidade';
                        if (_transactionFilter == 'saque') return t.source == 'saque';
                        if (_transactionFilter == 'loja') return t.source == 'loja';
                        return true;
                      }).toList();

                      if (filteredTransactions.isEmpty) {
                        return const PolishedEmptyState(
                          icon: LucideIcons.inbox,
                          title: 'Nenhuma transacao encontrada',
                          subtitle: 'Nao ha transacoes deste tipo',
                          accent: AppTheme.textSecondary,
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _TransactionCard(transaction: filteredTransactions[index])
                            .entrance(index: index),
                      );
                    },
                    childCount: () {
                      final filteredTransactions = _transactions.where((t) {
                        if (_transactionFilter == 'mensalidade') return t.source == 'mensalidade';
                        if (_transactionFilter == 'saque') return t.source == 'saque';
                        if (_transactionFilter == 'loja') return t.source == 'loja';
                        return true;
                      }).toList();
                      return filteredTransactions.isEmpty ? 1 : filteredTransactions.length;
                    }(),
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
              if (transaction.fee != null && transaction.fee! > 0)
                Text(
                  'Taxa: ${currencyFormat.format(transaction.fee!)}',
                  style: AppTheme.labelSmall.copyWith(
                    color: Colors.grey[600],
                    fontSize: 11,
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
    final amountInCents = (amount * 100).round().toDouble();

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

/// TOTP Code Bottom Sheet - reusable 6-digit code input
class _TotpCodeBottomSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final Future<bool> Function(String code) onSubmit;

  const _TotpCodeBottomSheet({
    required this.title,
    required this.subtitle,
    required this.onSubmit,
  });

  @override
  State<_TotpCodeBottomSheet> createState() => _TotpCodeBottomSheetState();
}

class _TotpCodeBottomSheetState extends State<_TotpCodeBottomSheet> {
  final _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Digite o codigo de 6 digitos');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await widget.onSubmit(code);
      if (!success && mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Codigo invalido';
          _codeController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Erro de conexao';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    LucideIcons.shieldCheck,
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
                        widget.title,
                        style: AppTheme.titleLarge.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        widget.subtitle,
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

            // Error
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

            // Code input
            TextFormField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Codigo de verificacao',
                hintText: '000000',
                prefixIcon: Icon(LucideIcons.keyRound),
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: AppTheme.headlineSmall.copyWith(
                letterSpacing: 8,
                fontWeight: FontWeight.w700,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onFieldSubmitted: (_) => _handleSubmit(),
            ),
            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _handleSubmit,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(LucideIcons.shieldCheck),
                label: Text(_isLoading ? 'Verificando...' : 'Verificar'),
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
    );
  }
}
