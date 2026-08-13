import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/feedback_utils.dart';
import '../../models/billing_payment_preference.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/billing_provider.dart';
import '../../services/firebase_service.dart';
import '../../services/billing_reminder_service.dart';
import '../../services/payment_service.dart';
import '../../services/plan_service.dart';
import '../../widgets/cached_image.dart';
import '../../widgets/common/academy_page_header.dart';
import '../../widgets/common/billing_automation_banner.dart';
import '../../widgets/polish/polish.dart';
import 'widgets/billing_payment_actions.dart';

/// Admin Billing Reminders Screen ("Cobrança").
///
/// UX 2026-07 (NOTAS_FINANCEIRO_2026-07.md, feedback do dono): a régua
/// D+0/D+1/D+3/D+7/D+15/D+30 é jargão interno de engenharia — a tela virou
/// uma LISTA ÚNICA de devedores ordenada por dias de atraso, com um botão
/// "Cobrar todos" e o status da automação em destaque. Os dados/serviços por
/// estágio (getOverdueWithStages, sendBulk*ForStage, etc.) continuam
/// existindo por baixo sem nenhuma mudança — só a apresentação agrega.
class AdminBillingRemindersScreen extends ConsumerStatefulWidget {
  final String? initialFinancialId;

  const AdminBillingRemindersScreen({super.key, this.initialFinancialId});

  @override
  ConsumerState<AdminBillingRemindersScreen> createState() =>
      _AdminBillingRemindersScreenState();
}

class _AdminBillingRemindersScreenState
    extends ConsumerState<AdminBillingRemindersScreen> {
  // Data
  Map<BillingStage, List<Map<String, dynamic>>> _overdueStages = {
    BillingStage.created: [],
    BillingStage.upcoming: [],
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
  // AUDITORIA: doc separado de _notificationSettings (settings/billing, não
  // settings/billingReminders) — ver BillingReminderService.getAutoTuitionEnabled.
  // Pré-carregado aqui (junto do resto) para que o dialog de configurações
  // abra com o valor já disponível, sem precisar de FutureBuilder/spinner.
  bool _autoTuitionEnabled = false;
  bool _isLoading = true;
  bool _isSending = false;
  bool _didOpenInitialCharge = false;
  String _chargeFilter = 'all';

  // Progressive disclosure: stats agregados + quebra por tempo de atraso
  // ficam colapsados atrás de "Ver detalhes" (dono: tela virou "sala de
  // controle simples").
  bool _showDetails = false;

  late BillingReminderService _billingService;
  BillingNotificationService? _notificationService;

  final _currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _billingService = BillingReminderService(FirebaseService.academyId);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final academyId = FirebaseService.academyId;
      _billingService = BillingReminderService(academyId);

      final results = await Future.wait([
        _billingService.getCollectibleWithStages(),
        _billingService.getCollectionStats(),
        _billingService.getStudentContacts(),
        _billingService.getNotificationSettings(),
        _billingService.getAutoTuitionEnabled(),
      ]);

      // Get academy name for notification service
      final academyDoc = await FirebaseFirestore.instance
          .collection('academies')
          .doc(academyId)
          .get();
      final academyName = academyDoc.data()?['name'] as String? ?? 'Academia';

      final notifSettings = results[3] as BillingNotificationSettings;

      setState(() {
        _overdueStages =
            results[0] as Map<BillingStage, List<Map<String, dynamic>>>;
        _stats = results[1] as CollectionStats;
        _studentContacts = results[2] as Map<String, StudentContact>;
        _notificationSettings = notifSettings;
        _autoTuitionEnabled = results[4] as bool;
        _notificationService = BillingNotificationService(
          academyId: academyId,
          academyName: academyName,
          customTemplates: notifSettings.messageTemplates,
        );
        _isLoading = false;
      });
      _openInitialChargeIfNeeded();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        FeedbackUtils.showError(context, 'Erro ao carregar dados: $e');
      }
    }
  }

  /// Todos os devedores, achatados e ordenados por dias de atraso (desc) —
  /// a lista única que substitui as abas D+0..D+30. Cada item mantém o par
  /// (BillingStage, dados) porque o estágio real ainda é necessário por
  /// baixo (template de mensagem, PIX, log de contato); só não aparece mais
  /// na UI.
  List<MapEntry<BillingStage, Map<String, dynamic>>> get _sortedCharges {
    final all = <MapEntry<BillingStage, Map<String, dynamic>>>[];
    for (final stage in BillingStage.values) {
      for (final item in _overdueStages[stage] ?? const []) {
        all.add(MapEntry(stage, item));
      }
    }
    all.sort((a, b) {
      final da = a.value['daysOverdue'] as int? ?? 0;
      final db = b.value['daysOverdue'] as int? ?? 0;
      return db.compareTo(da);
    });
    return all;
  }

  List<MapEntry<BillingStage, Map<String, dynamic>>> get _filteredCharges {
    return _sortedCharges.where((entry) {
      final days = entry.value['daysOverdue'] as int? ?? 0;
      if (_chargeFilter == 'upcoming') return days <= 0;
      if (_chargeFilter == 'overdue') return days > 0;
      return true;
    }).toList();
  }

  void _openInitialChargeIfNeeded() {
    final financialId = widget.initialFinancialId;
    if (_didOpenInitialCharge || financialId == null || financialId.isEmpty) {
      return;
    }
    for (final entry in _sortedCharges) {
      if (entry.value['id'] == financialId) {
        final contact = _studentContacts[entry.value['studentId']];
        _didOpenInitialCharge = true;
        if (contact?.effectivePhone == null ||
            contact!.effectivePhone!.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              FeedbackUtils.showWarning(
                context,
                'Aluno sem telefone para receber a cobrança.',
              );
            }
          });
          return;
        }
        if (!(_notificationService?.hasWhatsAppApi ?? false)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              FeedbackUtils.showWarning(
                context,
                'O canal de WhatsApp ainda não está configurado.',
              );
            }
          });
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showSendDialog(
            mode: 'whatsapp',
            financialItem: entry.value,
            stage: entry.key,
            contact: contact,
          );
        });
        return;
      }
    }
  }

  /// Rótulo humano do estágio para a área "Ver detalhes" — a régua D+N é
  /// jargão de engenharia; aqui vira faixa de dias, sem código interno.
  String _humanStageLabel(BillingStage stage) {
    switch (stage) {
      case BillingStage.created:
        return 'Parcela criada';
      case BillingStage.upcoming:
        return 'A vencer';
      case BillingStage.d0:
        return 'Vence hoje';
      case BillingStage.d1:
        return '1-2 dias de atraso';
      case BillingStage.d3:
        return '3-6 dias de atraso';
      case BillingStage.d7:
        return '7-14 dias de atraso';
      case BillingStage.d15:
        return '15-29 dias de atraso';
      case BillingStage.d30:
        return '30+ dias de atraso';
    }
  }

  @override
  Widget build(BuildContext context) {
    final charges = _filteredCharges;
    final canConfirmManualPix =
        ref.watch(currentUserProvider).valueOrNull?.role == UserRole.admin;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          AcademyPageHeader(
            compact: true,
            title: 'Cobrança',
            leading: Navigator.canPop(context)
                ? IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(LucideIcons.arrowLeft, size: 20),
                    tooltip: 'Voltar',
                  )
                : null,
            actions: [
              IconButton(
                onPressed: _showCreateChargeModal,
                icon: const Icon(LucideIcons.plusCircle, size: 20),
                tooltip: 'Nova Cobrança',
              ),
              IconButton(
                onPressed: () => _showSettingsDialog(),
                icon: const Icon(LucideIcons.settings, size: 20),
                tooltip: 'Configurações',
              ),
              IconButton(
                onPressed: _loadData,
                icon: const Icon(LucideIcons.refreshCw, size: 20),
                tooltip: 'Atualizar',
              ),
            ],
          ),
          Expanded(
            child: Stack(
              children: [
                _isLoading
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: PolishSkeleton.list(count: 6),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: CustomScrollView(
                          slivers: [
                            // Status da automação em destaque — o "aha" da
                            // cobrança: liga sozinho, ou CTA pra ligar.
                            SliverToBoxAdapter(child: _buildAutomationBanner()),
                            SliverToBoxAdapter(child: _buildAutomationCard()),

                            // API Warning (nenhum canal configurado ainda)
                            if (_notificationSettings != null &&
                                !(_notificationService?.hasWhatsAppApi ??
                                    false) &&
                                !(_notificationService?.hasEmailApi ?? false))
                              SliverToBoxAdapter(child: _buildApiWarning()),

                            // Botão primário "Cobrar todos (N)"
                            SliverToBoxAdapter(
                              child: _buildBulkAllButton(charges),
                            ),

                            SliverToBoxAdapter(child: _buildChargeFilters()),

                            // Stats/estágios — atrás de "Ver detalhes"
                            SliverToBoxAdapter(
                              child: _buildDetailsDisclosure(),
                            ),

                            const SliverToBoxAdapter(
                              child: SizedBox(height: 4),
                            ),

                            // Lista única de devedores, por dias de atraso
                            if (charges.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: PolishedEmptyState(
                                  icon: LucideIcons.checkCircle,
                                  title: _chargeFilter == 'overdue'
                                      ? 'Nenhum pagamento em atraso'
                                      : 'Nenhuma cobrança em aberto',
                                  subtitle: _chargeFilter == 'overdue'
                                      ? 'Tudo em dia por aqui.'
                                      : 'As novas parcelas aparecerão aqui.',
                                  accent: AppTheme.success,
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  96,
                                ),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) => _buildPaymentItem(
                                      charges[index].value,
                                      charges[index].key,
                                      canConfirmManualPix: canConfirmManualPix,
                                    ).entrance(index: index),
                                    childCount: charges.length,
                                  ),
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
          ),
        ],
      ),
    );
  }

  Widget _buildApiWarning() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                'Este build foi iniciado sem as configuracoes das APIs de WhatsApp e e-mail. Reinicie o app com os dart-defines do notification server.',
                style: AppTheme.bodySmall.copyWith(color: AppTheme.warning),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Status da automação em destaque (dono: "o aha da cobrança automática").
  /// SPEC_ONBOARDING_2026-07.md §1.4/Fatia 4 — extraído para
  /// `widgets/common/billing_automation_banner.dart` e reusado 1:1 pelo
  /// Dashboard, para não duplicar esta UI em dois lugares. O CTA "Ligar" (só
  /// visível quando desligada) agora abre o novo passo `BillingActivationStep`
  /// (`/admin/comece-aqui/cobranca`, com preview real da mensagem) em vez do
  /// dialog cru abaixo — que continua acessível pelo ícone de engrenagem no
  /// topo desta tela.
  Widget _buildAutomationBanner() => const BillingAutomationBanner();

  Widget _buildAutomationCard() {
    final whatsappEnabled = _notificationSettings?.whatsappEnabled ?? false;
    final notifyOnCreation = _notificationSettings?.notifyOnCreation ?? false;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.bot, size: 16, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Automação de cobrança',
                      style: AppTheme.labelLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _showSettingsDialog,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(LucideIcons.pencil, size: 14),
                  label: const Text('Editar', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Gerar mensalidades automaticamente'),
              subtitle: Text(
                'Na virada do mês, gera as mensalidades de todos os planos ativos (diariamente às 6h).',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              secondary: Icon(
                LucideIcons.repeat,
                color: _autoTuitionEnabled
                    ? AppTheme.success
                    : AppTheme.textSecondary,
              ),
              value: _autoTuitionEnabled,
              activeThumbColor: AppTheme.success,
              contentPadding: EdgeInsets.zero,
              dense: true,
              onChanged: (value) async {
                setState(() => _autoTuitionEnabled = value);
                try {
                  await _billingService.setAutoTuitionEnabled(value);
                  ref.invalidate(billingAutomationStatusProvider);
                  if (mounted) {
                    FeedbackUtils.showSuccess(
                      context,
                      value
                          ? 'Geração automática ativada!'
                          : 'Geração automática desativada.',
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    FeedbackUtils.showError(context, 'Erro ao atualizar: $e');
                  }
                }
              },
            ),
            const Divider(height: 16),
            SwitchListTile(
              title: const Text('Avisar quando a parcela for criada'),
              subtitle: Text(
                'Envia automaticamente o template "Parcela criada" assim que uma nova cobrança ficar disponível.',
                style: AppTheme.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              secondary: Icon(
                LucideIcons.bell,
                color: notifyOnCreation
                    ? AppTheme.success
                    : AppTheme.textSecondary,
              ),
              value: notifyOnCreation,
              activeThumbColor: AppTheme.success,
              contentPadding: EdgeInsets.zero,
              dense: true,
              onChanged: whatsappEnabled
                  ? (value) async {
                      final currentSettings =
                          _notificationSettings ??
                          BillingNotificationSettings();
                      final updatedSettings = currentSettings.copyWith(
                        notifyOnCreation: value,
                      );
                      setState(() => _notificationSettings = updatedSettings);
                      try {
                        await _billingService.saveNotificationSettings(
                          updatedSettings,
                        );
                        ref.invalidate(billingAutomationStatusProvider);
                        if (mounted) {
                          FeedbackUtils.showSuccess(
                            context,
                            value
                                ? 'Aviso de parcela criada ativado!'
                                : 'Aviso de parcela criada desativado.',
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          FeedbackUtils.showError(
                            context,
                            'Erro ao atualizar: $e',
                          );
                        }
                      }
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChargeFilters() {
    final all = _sortedCharges.length;
    final upcoming = _sortedCharges
        .where((entry) => (entry.value['daysOverdue'] as int? ?? 0) <= 0)
        .length;
    final overdue = all - upcoming;

    Widget filter(String value, String label, int count) {
      final selected = _chargeFilter == value;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => setState(() => _chargeFilter = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppTheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 5,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              '$label  $count',
              textAlign: TextAlign.center,
              style: AppTheme.labelMedium.copyWith(
                color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            filter('all', 'Todas', all),
            filter('upcoming', 'A vencer', upcoming),
            filter('overdue', 'Vencidas', overdue),
          ],
        ),
      ),
    );
  }

  /// Progressive disclosure: estatísticas agregadas + quebra por tempo de
  /// atraso, colapsadas atrás de "Ver detalhes" (não competem com a lista
  /// de devedores/ação primária por espaço no topo).
  Widget _buildDetailsDisclosure() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _showDetails = !_showDetails),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _showDetails ? 'Ocultar detalhes' : 'Ver detalhes',
                    style: AppTheme.labelMedium.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _showDetails
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_showDetails) ...[
            const SizedBox(height: 8),
            _buildStatsHeader(),
            const SizedBox(height: 12),
            _buildStageBreakdown(),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  /// Quebra por tempo de atraso (era a régua D+N) com rótulo humano e uma
  /// ação "Cobrar" por faixa — reusa o mesmo `_showBulkSendDialog` de
  /// sempre, só que a partir do painel de detalhes em vez de uma aba.
  Widget _buildStageBreakdown() {
    if (_stats == null) return const SizedBox.shrink();
    final entries = BillingStage.values
        .where((s) => (_stats!.byStage[s]?.count ?? 0) > 0)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    final hasChannel =
        ((_notificationSettings?.whatsappEnabled ?? false) &&
            (_notificationService?.hasWhatsAppApi ?? false)) ||
        ((_notificationSettings?.emailEnabled ?? false) &&
            (_notificationService?.hasEmailApi ?? false));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Por tempo de atraso',
            style: AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ...entries.map((stage) {
            final data = _stats!.byStage[stage]!;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _stageColor(stage),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_humanStageLabel(stage)} — ${data.count} '
                      '${data.count == 1 ? 'aluno' : 'alunos'} — '
                      '${_currencyFormat.format(data.amount)}',
                      style: AppTheme.bodySmall,
                    ),
                  ),
                  if (hasChannel)
                    TextButton(
                      onPressed: () => _showBulkSendDialog(stage),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text(
                        'Cobrar',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ============================================
  // Bulk "Cobrar todos" (todos os estágios de uma vez)
  // ============================================
  Widget _buildBulkAllButton(
    List<MapEntry<BillingStage, Map<String, dynamic>>> debtors,
  ) {
    if (debtors.isEmpty) return const SizedBox.shrink();
    final hasChannel =
        ((_notificationSettings?.whatsappEnabled ?? false) &&
            (_notificationService?.hasWhatsAppApi ?? false)) ||
        ((_notificationSettings?.emailEnabled ?? false) &&
            (_notificationService?.hasEmailApi ?? false));
    if (!hasChannel) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                onPressed: () => _confirmSendAll(debtors),
                icon: const Icon(LucideIcons.send, size: 16),
                label: Text('Cobrar todos (${debtors.length})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
      ),
    );
  }

  /// Confirmação leve antes de disparar "Cobrar todos": mostra quantos
  /// telefones/emails serão alcançados. Sem editor de mensagem única aqui —
  /// os alunos estão em estágios diferentes, cada um recebe o texto (padrão
  /// ou customizado em Configurações) correspondente ao PRÓPRIO atraso.
  void _confirmSendAll(
    List<MapEntry<BillingStage, Map<String, dynamic>>> debtors,
  ) {
    if (_notificationService == null) return;
    final allItems = debtors.map((e) => e.value).toList();
    final recipients = _notificationService!.collectRecipientsForStage(
      financials: allItems,
      contacts: _studentContacts,
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(LucideIcons.send, color: AppTheme.success, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Cobrar todos (${debtors.length})',
                  style: AppTheme.titleLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Envia a mensagem pelo WhatsApp/Email para as '
                '${debtors.length} cobranças exibidas. Cada aluno recebe o '
                'texto adequado ao vencimento da parcela.',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
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
                  Icon(LucideIcons.mail, size: 14, color: AppTheme.info),
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
                      style: AppTheme.bodySmall.copyWith(color: Colors.orange),
                    ),
                  ],
                ),
              ],
            ],
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
              onPressed: () {
                Navigator.pop(dialogContext);
                _sendAllOverdue(debtors);
              },
              icon: const Icon(LucideIcons.send, size: 16),
              label: const Text('Enviar Agora'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
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

  /// Envia a cobrança "Cobrar todos" percorrendo cada estágio não-vazio e
  /// reutilizando o MESMO núcleo de envio de `_executeBulkSendNew`
  /// (`_runBulkSendCore` — PIX best-effort, recheck de pago, log de
  /// contato), só que acumulando o resultado de todos os estágios em UM
  /// dialog final em vez de um por estágio.
  Future<void> _sendAllOverdue(
    List<MapEntry<BillingStage, Map<String, dynamic>>> debtors,
  ) async {
    if (_notificationService == null) return;
    if (!(_notificationSettings?.whatsappEnabled ?? false) &&
        !(_notificationSettings?.emailEnabled ?? false)) {
      FeedbackUtils.showError(
        context,
        'Nenhum canal de notificacao esta habilitado. Habilite WhatsApp ou Email nas configuracoes.',
      );
      return;
    }

    final grouped = <BillingStage, List<Map<String, dynamic>>>{};
    for (final entry in debtors) {
      grouped.putIfAbsent(entry.key, () => []).add(entry.value);
    }
    final nonEmptyStages = grouped.keys.toList();
    if (nonEmptyStages.isEmpty) return;

    setState(() => _isSending = true);
    final aggregated = _BulkSendOutcome();
    try {
      for (final stage in nonEmptyStages) {
        final items = grouped[stage] ?? [];
        final message = _notificationService!.generateGenericStageMessage(
          stage,
        );
        final subject = _notificationService!.generateGenericEmailSubject(
          stage,
        );
        final outcome = await _runBulkSendCore(
          stage: stage,
          allItems: items,
          messageTemplate: message,
          subjectTemplate: subject,
        );
        aggregated.merge(outcome);
      }

      if (!aggregated.hadItemsToSend) {
        if (mounted) {
          FeedbackUtils.showInfo(
            context,
            aggregated.alreadyPaidSkipped > 0
                ? 'Todas as ${aggregated.alreadyPaidSkipped} cobrancas ja foram pagas — nada a enviar.'
                : 'Nada a enviar.',
          );
        }
      } else if (mounted) {
        _showBulkServerResultDialog(
          aggregated.toResult(),
          alreadyPaidSkipped: aggregated.alreadyPaidSkipped,
          waWithLink: aggregated.waWithLink,
          waWithoutLink: aggregated.waWithoutLink,
          missingCpfNames: aggregated.missingCpfNames.toList(),
          linkIntended:
              (_notificationSettings?.includePaymentLink ?? false) &&
              (_notificationSettings?.whatsappEnabled ?? false),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        FeedbackUtils.showError(context, 'Erro no envio em massa: $e');
      }
    } finally {
      setState(() => _isSending = false);
    }
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
          ).entrance(index: 0),
          const SizedBox(width: 12),
          _buildStatCard(
            icon: LucideIcons.users,
            label: 'Inadimplentes',
            value: '${_stats!.totalStudentsOverdue}',
            color: AppTheme.warning,
          ).entrance(index: 1),
          const SizedBox(width: 12),
          _buildStatCard(
            icon: LucideIcons.trendingUp,
            label: 'Taxa Recuperacao',
            value: '${_stats!.recoveryRate.toStringAsFixed(1)}%',
            color: AppTheme.success,
          ).entrance(index: 2),
          const SizedBox(width: 12),
          _buildStatCard(
            icon: LucideIcons.clock,
            label: 'Media Dias Atraso',
            value: '${_stats!.averageDaysOverdue} dias',
            color: AppTheme.info,
          ).entrance(index: 3),
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

  Color _stageColor(BillingStage stage) {
    switch (stage) {
      case BillingStage.created:
        return AppTheme.info;
      case BillingStage.upcoming:
        return AppTheme.primary;
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

  Widget _buildPaymentItem(
    Map<String, dynamic> item,
    BillingStage stage, {
    required bool canConfirmManualPix,
  }) {
    final studentName = item['studentName'] as String? ?? '';
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final dueDate = item['dueDate'] as DateTime;
    final daysOverdue = item['daysOverdue'] as int? ?? 0;
    final financialId = item['id'] as String? ?? '';
    final studentId = item['studentId'] as String? ?? '';
    final contact = _studentContacts[studentId];
    final phone = contact?.effectivePhone;
    final email = contact?.effectiveEmail;
    final hasWhatsApp = _notificationService?.hasWhatsAppApi ?? false;
    final hasEmail = _notificationService?.hasEmailApi ?? false;
    final photoUrl = contact?.photoUrl;

    final whatsappAction = phone != null && phone.isNotEmpty
        ? ElevatedButton.icon(
            onPressed: hasWhatsApp
                ? () => _showSendDialog(
                    mode: 'whatsapp',
                    financialItem: item,
                    stage: stage,
                    contact: contact!,
                  )
                : () => FeedbackUtils.showInfo(
                    context,
                    'WhatsApp indisponivel neste build. Reinicie o app com a configuracao do notification server.',
                  ),
            icon: const Icon(LucideIcons.messageCircle, size: 16),
            label: const Text('Cobrar aluno'),
            style: ElevatedButton.styleFrom(
              backgroundColor: hasWhatsApp
                  ? AppTheme.success
                  : AppTheme.textDisabled,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
          )
        : null;
    final emailAction = email != null && email.isNotEmpty
        ? IconButton(
            onPressed: hasEmail
                ? () => _showSendDialog(
                    mode: 'email',
                    financialItem: item,
                    stage: stage,
                    contact: contact!,
                  )
                : () => FeedbackUtils.showInfo(
                    context,
                    'E-mail indisponivel neste build. Reinicie o app com a configuracao do notification server.',
                  ),
            icon: const Icon(LucideIcons.mail, size: 20),
            color: hasEmail ? AppTheme.info : AppTheme.textDisabled,
            tooltip: 'Enviar cobranca individual por e-mail',
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(8),
          )
        : null;
    final secondaryActions = <Widget>[
      if (phone != null && phone.isNotEmpty)
        IconButton(
          onPressed: () async {
            final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
            final uri = Uri.parse('tel:$digits');
            if (await launchUrl(uri)) return;
            if (!mounted) return;
            FeedbackUtils.showInfo(context, 'Ligar para $studentName: $phone');
          },
          icon: const Icon(LucideIcons.phone, size: 20),
          color: AppTheme.textSecondary,
          tooltip: 'Telefone',
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(8),
        ),
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
      if (canConfirmManualPix)
        IconButton(
          onPressed: () => _confirmManualPixPayment(item),
          icon: const Icon(LucideIcons.badgeCheck, size: 20),
          color: AppTheme.success,
          tooltip: 'Confirmar PIX pessoal recebido',
          constraints: const BoxConstraints(),
          padding: const EdgeInsets.all(8),
        ),
      IconButton(
        onPressed: () => _confirmDelete(item),
        icon: const Icon(LucideIcons.trash2, size: 20),
        color: AppTheme.error,
        tooltip: 'Excluir Cobrança',
        constraints: const BoxConstraints(),
        padding: const EdgeInsets.all(8),
      ),
    ];

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
                        daysOverdue < 0
                            ? 'Vence em ${-daysOverdue} dia(s)'
                            : daysOverdue == 0
                            ? 'Vence hoje'
                            : '$daysOverdue dia(s) em atraso',
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

            BillingPaymentActions(
              primaryAction: whatsappAction,
              emailAction: emailAction,
              secondaryActions: secondaryActions,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmManualPixPayment(Map<String, dynamic> item) async {
    final studentName = item['studentName'] as String? ?? 'Aluno';
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final financialId = item['id'] as String? ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var receiptChecked = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Confirmar PIX pessoal'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aluno: $studentName\n'
                    'Valor: ${_currencyFormat.format(amount)}',
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppTheme.warning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      'O PIX pessoal não possui confirmação automática. '
                      'Ao continuar, a cobrança será quitada e qualquer '
                      'pagamento concorrente do Mercado Pago será cancelado.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: receiptChecked,
                    onChanged: (value) =>
                        setDialogState(() => receiptChecked = value == true),
                    title: const Text(
                      'Conferi o recebimento na conta da academia',
                    ),
                    subtitle: const Text(
                      'A confirmação ficará registrada com seu usuário e data.',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: receiptChecked
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: const Text('Confirmar recebimento'),
              ),
            ],
          ),
        );
      },
    );

    if (confirm == true) {
      try {
        final academyId = FirebaseService.academyId;
        await PaymentService(academyId).confirmManualPix(financialId);
        if (mounted) {
          FeedbackUtils.showSuccess(
            context,
            'PIX pessoal confirmado e cobrança quitada!',
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          FeedbackUtils.showError(context, e.toString());
        }
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> item) async {
    final studentName = item['studentName'] as String? ?? 'Aluno';
    final amount = (item['amount'] as num?)?.toDouble() ?? 0;
    final financialId = item['id'] as String? ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Cobrança'),
        content: Text(
          'Deseja EXCLUIR permanentemente a cobrança de R\$ ${amount.toStringAsFixed(2)} para $studentName?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final academyId = FirebaseService.academyId;
        await PaymentService(academyId).delete(financialId);
        if (mounted) {
          FeedbackUtils.showSuccess(context, 'Cobrança excluída!');
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          FeedbackUtils.showError(context, 'Erro ao excluir: $e');
        }
      }
    }
  }

  // ============================================
  // Send Dialog (individual)
  // ============================================
  Future<void> _showSendDialog({
    required String mode,
    required Map<String, dynamic> financialItem,
    required BillingStage stage,
    required StudentContact contact,
  }) async {
    if (_notificationService == null) return;

    final studentName = financialItem['studentName'] as String? ?? '';
    final amount = (financialItem['amount'] as num?)?.toDouble() ?? 0;
    final dueDate = financialItem['dueDate'] as DateTime;
    final daysOverdue = financialItem['daysOverdue'] as int? ?? 0;

    String message;
    String subject = '';
    BillingPaymentInstruction paymentInstruction =
        const BillingPaymentInstruction.none();

    if (mode == 'whatsapp') {
      // Preview is read-only: payment data is resolved only by the backend at
      // send time, so opening this dialog never creates a PIX attempt.
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

    if (!mounted) return;

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
                if (mode == 'whatsapp') ...[
                  Text(
                    'Previa do template oficial aprovado na Meta. O texto do WhatsApp nao pode ser editado.',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: messageController,
                  readOnly: mode == 'whatsapp',
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
                  paymentInstruction: paymentInstruction,
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
    BillingPaymentInstruction paymentInstruction =
        const BillingPaymentInstruction.none(),
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

      // M4: re-read live status before charging. If it was paid (or is no
      // longer collectible) since the list was loaded, SKIP — never re-charge.
      final paidIds = await _billingService.getPaidFinancialIds([financialId]);
      if (paidIds.contains(financialId)) {
        if (mounted) {
          FeedbackUtils.showInfo(
            context,
            'Cobranca ja paga — envio ignorado para $studentName.',
          );
        }
        await _loadData();
        return;
      }

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
          paymentInstruction: paymentInstruction,
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
          Celebration.confetti(context);
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

                      // WhatsApp uses the approved Meta template. This field
                      // remains editable only for the e-mail channel.
                      Text(
                        recipients.emails.isNotEmpty
                            ? 'Mensagem do e-mail'
                            : 'Previa do template oficial do WhatsApp',
                        style: AppTheme.labelMedium,
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: messageController,
                        readOnly: recipients.emails.isEmpty,
                        maxLines: 6,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          helperText: recipients.emails.isNotEmpty
                              ? 'Este texto afeta somente o e-mail. O WhatsApp usa o template aprovado na Meta.'
                              : 'O texto do WhatsApp nao pode ser editado.',
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
  /// Wraps [_runBulkSendCore] with the single-stage UI lifecycle (loading
  /// flag, one result dialog, reload) — this is what `_showBulkSendDialog`
  /// calls for a single stage. `_sendAllOverdue` calls `_runBulkSendCore`
  /// directly, once per non-empty stage, and shows ONE aggregated dialog
  /// instead — same core send logic, different UI wrapper.
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
      final allItems = _overdueStages[stage] ?? [];
      final outcome = await _runBulkSendCore(
        stage: stage,
        allItems: allItems,
        messageTemplate: message,
        subjectTemplate: subject,
      );

      if (!outcome.hadItemsToSend) {
        if (mounted) {
          FeedbackUtils.showInfo(
            context,
            outcome.alreadyPaidSkipped > 0
                ? 'Todas as ${outcome.alreadyPaidSkipped} cobrancas ja foram pagas — nada a enviar.'
                : 'Nada a enviar.',
          );
        }
        await _loadData();
        return;
      }

      if (mounted) {
        _showBulkServerResultDialog(
          outcome.toResult(),
          alreadyPaidSkipped: outcome.alreadyPaidSkipped,
          waWithLink: outcome.waWithLink,
          waWithoutLink: outcome.waWithoutLink,
          missingCpfNames: outcome.missingCpfNames.toList(),
          linkIntended:
              (_notificationSettings?.includePaymentLink ?? false) &&
              (_notificationSettings?.whatsappEnabled ?? false),
        );
      }
      // Refresh so the just-paid/charged items reflect current state.
      await _loadData();
    } catch (e) {
      if (mounted) {
        FeedbackUtils.showError(context, 'Erro no envio em massa: $e');
      }
    } finally {
      setState(() => _isSending = false);
    }
  }

  /// Core send loop for one stage — extracted verbatim from the original
  /// single-stage `_executeBulkSendNew` so both the single-stage flow and
  /// the new "Cobrar todos" (all stages) flow share the exact same PIX
  /// generation / paid-recheck / send / contact-log logic. Does NOT touch
  /// `_isSending`, does NOT show a dialog and does NOT reload — callers own
  /// that lifecycle.
  Future<_BulkSendOutcome> _runBulkSendCore({
    required BillingStage stage,
    required List<Map<String, dynamic>> allItems,
    required String messageTemplate,
    required String subjectTemplate,
  }) async {
    final outcome = _BulkSendOutcome();

    // M4: re-read live status for the whole batch and DROP anything already
    // paid (or no longer collectible) before sending. Surface the skip count.
    final paidIds = await _billingService.getPaidFinancialIds(
      allItems.map((i) => i['id'] as String? ?? ''),
    );
    final items = allItems
        .where((i) => !paidIds.contains(i['id'] as String? ?? ''))
        .toList();
    outcome.alreadyPaidSkipped = allItems.length - items.length;

    if (items.isEmpty) return outcome;
    outcome.hadItemsToSend = true;

    // Payment instructions are resolved server-side per financial at send
    // time. Listing/previewing a batch must never pre-generate PIX attempts.
    final includePix = _notificationSettings?.includePaymentLink ?? false;
    final whatsappOn = _notificationSettings?.whatsappEnabled ?? false;

    for (final item in items) {
      final studentId = item['studentId'] as String? ?? '';
      final contact = _studentContacts[studentId];
      if (contact == null) continue;

      final studentName = item['studentName'] as String? ?? '';
      final amount = (item['amount'] as num?)?.toDouble() ?? 0;
      final dueDate = item['dueDate'] as DateTime;
      final daysOverdue = item['daysOverdue'] as int? ?? 0;
      final financialId = item['id'] as String? ?? '';

      // Email + base message: no PIX block (markers auto-strip).
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

      const paymentInstruction = BillingPaymentInstruction.none();

      // Send WhatsApp (only if enabled in settings)
      final phone = contact.effectivePhone;
      if ((_notificationSettings?.whatsappEnabled ?? false) &&
          phone != null &&
          phone.isNotEmpty) {
        outcome.waTotal++;
        final result = await _notificationService!.sendWhatsApp(
          phone: phone,
          studentName: studentName,
          studentId: studentId,
          financialId: financialId,
          amount: amount,
          dueDate: dueDate,
          daysOverdue: daysOverdue,
          stage: stage,
          paymentInstruction: paymentInstruction,
        );
        if (result.success) {
          outcome.waSent++;
          // The exact payment mode is selected server-side. Until the dispatch
          // job projection exposes it, count the intent without claiming that
          // a link was attached.
          if (includePix && whatsappOn) {
            outcome.waWithoutLink++;
          }
        } else {
          outcome.waFailed++;
          outcome.failures.add(
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
        outcome.emTotal++;
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
          outcome.emSent++;
        } else {
          outcome.emFailed++;
          outcome.failures.add(
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

    return outcome;
  }

  // ============================================
  // Bulk Server Result Dialog
  // ============================================
  void _showBulkServerResultDialog(
    BulkServerResult result, {
    int alreadyPaidSkipped = 0,
    int waWithLink = 0,
    int waWithoutLink = 0,
    List<String> missingCpfNames = const [],
    bool linkIntended = false,
  }) {
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
                if (!result.scheduled &&
                    ((result.whatsapp.sent ?? 0) + (result.email.sent ?? 0)) >
                        0) ...[
                  const SuccessCheck(size: 64),
                  const SizedBox(height: 12),
                ],
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

                // M4: charges that were already paid and got skipped.
                if (alreadyPaidSkipped > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.info.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.checkCircle,
                          size: 16,
                          color: AppTheme.info,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$alreadyPaidSkipped ja paga(s), ignorada(s)',
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.info,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Payment instruction outcome for WhatsApp sends.
                if (linkIntended && (waWithLink > 0 || waWithoutLink > 0)) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: waWithoutLink > 0
                          ? AppTheme.warning.withValues(alpha: 0.08)
                          : AppTheme.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.creditCard,
                          size: 16,
                          color: waWithoutLink > 0
                              ? AppTheme.warning
                              : AppTheme.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'WhatsApp — com forma de pagamento: $waWithLink / somente lembrete: $waWithoutLink',
                                style: AppTheme.bodySmall.copyWith(
                                  color: waWithoutLink > 0
                                      ? AppTheme.warning
                                      : AppTheme.success,
                                ),
                              ),
                              if (missingCpfNames.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Alguns alunos sem forma de pagamento também estão sem CPF. Verifique o Mercado Pago, a chave PIX pessoal e o CPF do pagador:',
                                  style: AppTheme.labelSmall.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  missingCpfNames.join(', '),
                                  style: AppTheme.labelSmall.copyWith(
                                    color: AppTheme.warning,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

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
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              LucideIcons.xCircle,
                              size: 14,
                              color: AppTheme.error,
                            ),
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
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.recipient,
                                  style: AppTheme.bodySmall.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
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
  // Create Charge Modal (Plano vs Cobrança Única)
  // ============================================
  Future<void> _showCreateChargeModal() async {
    final academyId = FirebaseService.academyId;

    List<StudentContact> students = _studentContacts.values.toList();
    if (students.isEmpty) {
      try {
        final loadedContacts = await _billingService.getStudentContacts();
        students = loadedContacts.values.toList();
      } catch (_) {}
    }

    if (students.isEmpty) {
      if (mounted) {
        FeedbackUtils.showError(
          context,
          'Nenhum aluno encontrado para criar cobrança.',
        );
      }
      return;
    }

    // Load available plans
    List<Plan> plans = [];
    try {
      plans = await PlanService(academyId).list();
    } catch (e) {
      print('Erro ao carregar planos: $e');
    }

    String selectedStudentId = students.first.studentId;
    String chargeType = 'monthly_tuition';
    String? selectedPlanId = plans.isNotEmpty ? plans.first.id : null;

    final amountController = TextEditingController(
      text:
          (plans.isNotEmpty
                  ? plans.first.getStudentValue(selectedStudentId)
                  : 100.0)
              .toStringAsFixed(2),
    );
    final descController = TextEditingController(
      text: plans.isNotEmpty
          ? 'Mensalidade - ${plans.first.name}'
          : 'Mensalidade do Plano',
    );
    DateTime selectedDueDate = DateTime.now().subtract(const Duration(days: 3));

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final selectedStudent = students.firstWhere(
              (s) => s.studentId == selectedStudentId,
              orElse: () => students.first,
            );

            Plan? selectedPlan;
            if (plans.isNotEmpty && selectedPlanId != null) {
              selectedPlan = plans.firstWhere(
                (p) => p.id == selectedPlanId,
                orElse: () => plans.first,
              );
            }

            // If Plano do Aluno is selected, enforce the plan's fixed due day
            if (chargeType == 'monthly_tuition' && selectedPlan != null) {
              final targetDay = selectedPlan.getStudentDueDay(
                selectedStudentId,
              );
              final maxDays = DateUtils.getDaysInMonth(
                selectedDueDate.year,
                selectedDueDate.month,
              );
              final validDay = targetDay > maxDays ? maxDays : targetDay;
              if (selectedDueDate.day != validDay) {
                selectedDueDate = DateTime(
                  selectedDueDate.year,
                  selectedDueDate.month,
                  validDay,
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            LucideIcons.plusCircle,
                            color: AppTheme.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Criar Nova Cobrança',
                          style: AppTheme.titleLarge.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Student dropdown
                    Text('Aluno *', style: AppTheme.labelMedium),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedStudentId,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      items: students.map((s) {
                        return DropdownMenuItem<String>(
                          value: s.studentId,
                          child: Text(
                            s.studentName,
                            style: AppTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() {
                            selectedStudentId = val;
                            if (chargeType == 'monthly_tuition' &&
                                selectedPlan != null) {
                              final planVal = selectedPlan.getStudentValue(
                                selectedStudentId,
                              );
                              amountController.text = planVal.toStringAsFixed(
                                2,
                              );
                              final targetDay = selectedPlan.getStudentDueDay(
                                selectedStudentId,
                              );
                              final maxDays = DateUtils.getDaysInMonth(
                                selectedDueDate.year,
                                selectedDueDate.month,
                              );
                              final validDay = targetDay > maxDays
                                  ? maxDays
                                  : targetDay;
                              selectedDueDate = DateTime(
                                selectedDueDate.year,
                                selectedDueDate.month,
                                validDay,
                              );
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // Charge Type Selector
                    Text('Tipo de Cobrança *', style: AppTheme.labelMedium),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Plano do Aluno'),
                            selected: chargeType == 'monthly_tuition',
                            onSelected: (_) {
                              setSheetState(() {
                                chargeType = 'monthly_tuition';
                                if (selectedPlan != null) {
                                  descController.text =
                                      'Mensalidade - ${selectedPlan.name}';
                                  final planVal = selectedPlan.getStudentValue(
                                    selectedStudentId,
                                  );
                                  amountController.text = planVal
                                      .toStringAsFixed(2);
                                  final targetDay = selectedPlan
                                      .getStudentDueDay(selectedStudentId);
                                  final maxDays = DateUtils.getDaysInMonth(
                                    selectedDueDate.year,
                                    selectedDueDate.month,
                                  );
                                  final validDay = targetDay > maxDays
                                      ? maxDays
                                      : targetDay;
                                  selectedDueDate = DateTime(
                                    selectedDueDate.year,
                                    selectedDueDate.month,
                                    validDay,
                                  );
                                } else {
                                  descController.text = 'Mensalidade do Plano';
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Cobrança Única'),
                            selected: chargeType == 'avulsa',
                            onSelected: (_) {
                              setSheetState(() {
                                chargeType = 'avulsa';
                                descController.text = 'Cobrança Avulsa';
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // If Plano do Aluno -> Show Plan Selector Dropdown
                    if (chargeType == 'monthly_tuition') ...[
                      Text('Selecione o Plano *', style: AppTheme.labelMedium),
                      const SizedBox(height: 6),
                      if (plans.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Nenhum plano cadastrado na academia. Crie um plano em Financeiro > Planos.',
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.warning,
                            ),
                          ),
                        )
                      else
                        DropdownButtonFormField<String>(
                          value: selectedPlanId,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          items: plans.map((p) {
                            final val = p.getStudentValue(selectedStudentId);
                            final due = p.getStudentDueDay(selectedStudentId);
                            return DropdownMenuItem<String>(
                              value: p.id,
                              child: Text(
                                '${p.name} — R\$ ${val.toStringAsFixed(2)}/mês (Venc. dia $due)',
                                style: AppTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setSheetState(() {
                                selectedPlanId = val;
                                final plan = plans.firstWhere(
                                  (p) => p.id == val,
                                );
                                final planVal = plan.getStudentValue(
                                  selectedStudentId,
                                );
                                amountController.text = planVal.toStringAsFixed(
                                  2,
                                );
                                descController.text =
                                    'Mensalidade - ${plan.name}';
                                final targetDay = plan.getStudentDueDay(
                                  selectedStudentId,
                                );
                                final maxDays = DateUtils.getDaysInMonth(
                                  selectedDueDate.year,
                                  selectedDueDate.month,
                                );
                                final validDay = targetDay > maxDays
                                    ? maxDays
                                    : targetDay;
                                selectedDueDate = DateTime(
                                  selectedDueDate.year,
                                  selectedDueDate.month,
                                  validDay,
                                );
                              });
                            }
                          },
                        ),
                      const SizedBox(height: 14),
                    ],

                    // Description Field
                    Text('Descrição / Referência', style: AppTheme.labelMedium),
                    const SizedBox(height: 6),
                    TextField(
                      controller: descController,
                      style: AppTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: chargeType == 'monthly_tuition'
                            ? 'Ex: Mensalidade - Meta'
                            : 'Ex: Aula Particular, Exame de Faixa...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Amount Field
                    Text('Valor (R\$) *', style: AppTheme.labelMedium),
                    const SizedBox(height: 6),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: AppTheme.bodyMedium,
                      decoration: InputDecoration(
                        prefixText: 'R\$ ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Due Date Picker
                    Text(
                      chargeType == 'monthly_tuition' && selectedPlan != null
                          ? 'Data de Vencimento (Dia ${selectedPlan.getStudentDueDay(selectedStudentId)} fixo pelo plano) *'
                          : 'Data de Vencimento *',
                      style: AppTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final planDueDay =
                            chargeType == 'monthly_tuition' &&
                                selectedPlan != null
                            ? selectedPlan.getStudentDueDay(selectedStudentId)
                            : null;

                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDueDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365 * 5),
                          ),
                          selectableDayPredicate: planDueDay != null
                              ? (DateTime day) {
                                  final maxDays = DateUtils.getDaysInMonth(
                                    day.year,
                                    day.month,
                                  );
                                  final validDay = planDueDay > maxDays
                                      ? maxDays
                                      : planDueDay;
                                  return day.day == validDay;
                                }
                              : null,
                          locale: const Locale('pt', 'BR'),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDueDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.divider),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.calendar, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('dd/MM/yyyy').format(selectedDueDate),
                              style: AppTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () async {
                          final parsedAmount = double.tryParse(
                            amountController.text.replaceAll(',', '.'),
                          );
                          if (parsedAmount == null || parsedAmount <= 0) {
                            FeedbackUtils.showError(
                              ctx,
                              'Informe um valor válido maior que zero.',
                            );
                            return;
                          }

                          try {
                            final refMonth =
                                '${selectedDueDate.year}-${selectedDueDate.month.toString().padLeft(2, '0')}';

                            await PaymentService(academyId).create(
                              studentId: selectedStudent.studentId,
                              studentName: selectedStudent.studentName,
                              value: parsedAmount,
                              dueDate: selectedDueDate,
                              type: chargeType,
                              planId: chargeType == 'monthly_tuition'
                                  ? selectedPlanId
                                  : null,
                              description: descController.text.trim().isNotEmpty
                                  ? descController.text.trim()
                                  : (chargeType == 'monthly_tuition'
                                        ? 'Mensalidade do Plano'
                                        : 'Cobrança Avulsa'),
                              referenceMonth: refMonth,
                              paymentMethodPolicy:
                                  chargeType == 'monthly_tuition'
                                  ? (selectedPlan?.paymentMethodPolicy ??
                                        PaymentMethodPolicy.both)
                                  : PaymentMethodPolicy.both,
                            );

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                            }
                            if (mounted) {
                              FeedbackUtils.showSuccess(
                                context,
                                'Cobrança criada com sucesso!',
                              );
                              _loadData();
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              FeedbackUtils.showError(
                                ctx,
                                'Erro ao criar cobrança: $e',
                              );
                            }
                          }
                        },
                        child: Text(
                          'Criar Cobrança',
                          style: AppTheme.titleSmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
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
    bool includePaymentLink = _notificationSettings?.includePaymentLink ?? true;
    bool notifyOnCreation = _notificationSettings?.notifyOnCreation ?? false;
    final dueSoonOffsets = <int>{...?_notificationSettings?.dueSoonOffsets};
    // Pré-carregado em _loadData (doc settings/billing, separado dos demais
    // toggles acima que moram em settings/billingReminders).
    bool autoTuitionEnabled = _autoTuitionEnabled;
    // Clone current templates or start empty
    final emailSubjectTemplates = Map<String, String>.from(
      _notificationSettings?.messageTemplates?.emailSubject ?? {},
    );
    final emailBodyTemplates = Map<String, String>.from(
      _notificationSettings?.messageTemplates?.emailBody ?? {},
    );
    bool showTemplates = false;
    int selectedStageIdx = 0;
    const stageKeys = [
      'CREATED',
      'UPCOMING',
      'D+0',
      'D+1',
      'D+3',
      'D+7',
      'D+15',
      'D+30',
    ];
    const stageLabels = [
      'Parcela criada',
      'A vencer',
      'Vence hoje',
      '1–2 dias',
      '3–6 dias',
      '7–14 dias',
      '15–29 dias',
      '30+ dias',
    ];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final stageKey = stageKeys[selectedStageIdx];

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
                        title: const Text('Automacao via WhatsApp'),
                        subtitle: Text(
                          'Envia sozinho nos momentos configurados. O botão Cobrar continua disponível para envios manuais.',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        secondary: Icon(
                          LucideIcons.phone,
                          color: whatsappEnabled
                              ? AppTheme.success
                              : AppTheme.textSecondary,
                        ),
                        value: whatsappEnabled,
                        activeThumbColor: AppTheme.success,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setDialogState(() => whatsappEnabled = value);
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Cobrança via Email'),
                        secondary: Icon(
                          LucideIcons.mail,
                          color: emailEnabled
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                        ),
                        value: emailEnabled,
                        activeThumbColor: AppTheme.primary,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setDialogState(() => emailEnabled = value);
                        },
                      ),
                      SwitchListTile(
                        title: const Text(
                          'Incluir forma de pagamento nas mensagens',
                        ),
                        subtitle: Text(
                          'Usa a preferencia definida em Financeiro: Mercado Pago ou PIX pessoal, com fallback automatico.',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        secondary: Icon(
                          LucideIcons.creditCard,
                          color: includePaymentLink
                              ? AppTheme.success
                              : AppTheme.textSecondary,
                        ),
                        value: includePaymentLink,
                        activeThumbColor: AppTheme.success,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setDialogState(() => includePaymentLink = value);
                        },
                      ),

                      const Divider(height: 24),

                      // ============================================
                      // Automação: geração de mensalidades + régua de
                      // WhatsApp (o switch de WhatsApp fica acima, em
                      // "Canais de Cobranca" — aqui só a flag nova).
                      // ============================================
                      Text('Automacao', style: AppTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        'Controle o que roda sozinho, sem voce precisar abrir o app.',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Gerar mensalidades automaticamente'),
                        subtitle: Text(
                          'Na virada do mes, gera as mensalidades de todos os planos ativos (diariamente as 6h). Planos mensais no cartao continuam pela assinatura automatica.',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        secondary: Icon(
                          LucideIcons.repeat,
                          color: autoTuitionEnabled
                              ? AppTheme.success
                              : AppTheme.textSecondary,
                        ),
                        value: autoTuitionEnabled,
                        // AUDITORIA: `activeThumbColor` (não `activeColor`,
                        // já deprecated) — mesma cor/densidade visual dos
                        // switches vizinhos, sem introduzir warning novo.
                        activeThumbColor: AppTheme.success,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          setDialogState(() => autoTuitionEnabled = value);
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Avisar quando a parcela for criada'),
                        subtitle: Text(
                          'Envia automaticamente o template "Parcela criada" assim que uma nova cobrança ficar disponível.',
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        secondary: Icon(
                          LucideIcons.bell,
                          color: notifyOnCreation
                              ? AppTheme.success
                              : AppTheme.textSecondary,
                        ),
                        value: notifyOnCreation,
                        activeThumbColor: AppTheme.success,
                        contentPadding: EdgeInsets.zero,
                        onChanged: whatsappEnabled
                            ? (value) =>
                                  setDialogState(() => notifyOnCreation = value)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Avisos antes e no dia do vencimento',
                        style: AppTheme.labelMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'O aluno é avisado no app e, com WhatsApp automático ligado, recebe também o template "A vencer".',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [7, 3, 2, 1, 0].map((days) {
                          return FilterChip(
                            label: Text(
                              days == 0
                                  ? 'No vencimento'
                                  : '$days dia${days == 1 ? '' : 's'} antes',
                            ),
                            selected: dueSoonOffsets.contains(days),
                            onSelected: (selected) => setDialogState(() {
                              if (selected) {
                                dueSoonOffsets.add(days);
                              } else {
                                dueSoonOffsets.remove(days);
                              }
                            }),
                          );
                        }).toList(),
                      ),

                      const Divider(height: 24),

                      // Template Editor Toggle
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Templates oficiais e e-mail',
                            style: AppTheme.titleSmall,
                          ),
                          TextButton(
                            onPressed: () {
                              setDialogState(
                                () => showTemplates = !showTemplates,
                              );
                            },
                            child: Text(
                              showTemplates ? 'Ocultar' : 'Configurar',
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'O WhatsApp usa modelos aprovados na Meta. Apenas os textos de e-mail podem ser editados.',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),

                      if (showTemplates) ...[
                        const SizedBox(height: 12),

                        // Stage selector chips
                        Wrap(
                          spacing: 6,
                          children: List.generate(stageKeys.length, (i) {
                            return ChoiceChip(
                              label: Text(
                                stageLabels[i],
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

                        // WhatsApp official template info (read-only)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.success.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.success.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    LucideIcons.checkCircle,
                                    size: 14,
                                    color: AppTheme.success,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      stageKey == 'CREATED' ||
                                              stageKey == 'UPCOMING'
                                          ? 'WhatsApp - modelo Meta ainda nao disponivel ($stageKey)'
                                          : 'WhatsApp - modelo oficial Meta ($stageKey)',
                                      style: AppTheme.labelSmall.copyWith(
                                        color: AppTheme.success,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                stageKey == 'CREATED' || stageKey == 'UPCOMING'
                                    ? 'Esta etapa continua disponivel para notificacoes internas e e-mail. O WhatsApp sera ignorado ate existir um template aprovado.'
                                    : BillingNotificationService
                                              .defaultWhatsAppTemplates[stageKey] ??
                                          '',
                                style: AppTheme.bodySmall.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Email subject
                        Text('Assunto do e-mail', style: AppTheme.labelMedium),
                        const SizedBox(height: 6),
                        TextFormField(
                          key: ValueKey(
                            'email_subj_${stageKey}_${emailSubjectTemplates[stageKey]}',
                          ),
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
                        Text('Corpo do e-mail', style: AppTheme.labelMedium),
                        const SizedBox(height: 6),
                        TextFormField(
                          key: ValueKey(
                            'email_body_${stageKey}_${emailBodyTemplates[stageKey]}',
                          ),
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
                                emailSubjectTemplates.remove(stageKey);
                                emailBodyTemplates.remove(stageKey);
                              });
                            },
                            child: Text(
                              'Restaurar padrão deste momento',
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
                        emailSubject: emailSubjectTemplates,
                        emailBody: emailBodyTemplates,
                      );

                      final newSettings = BillingNotificationSettings(
                        whatsappEnabled: whatsappEnabled,
                        emailEnabled: emailEnabled,
                        includePaymentLink: includePaymentLink,
                        notifyOnCreation: notifyOnCreation,
                        dueSoonOffsets: dueSoonOffsets.toList()
                          ..sort((a, b) => b.compareTo(a)),
                        messageTemplates: templates,
                      );

                      // Mesmo fluxo/botão dos demais toggles: salva os dois
                      // docs juntos (settings/billingReminders +
                      // settings/billing) para que "Salvar" seja uma ação
                      // única e previsível para o admin.
                      await Future.wait([
                        _billingService.saveNotificationSettings(newSettings),
                        _billingService.setAutoTuitionEnabled(
                          autoTuitionEnabled,
                        ),
                      ]);

                      setState(() {
                        _notificationSettings = newSettings;
                        _autoTuitionEnabled = autoTuitionEnabled;
                        // Update notification service with new templates
                        _notificationService?.customTemplates = templates;
                      });
                      // Fatia 0.7: o banner desta tela (BillingAutomationBanner)
                      // e o checklist/Dashboard leem `billingAutomationStatusProvider`
                      // — invalida pra refletir o novo estado sem esperar o
                      // próximo rebuild natural do provider.
                      ref.invalidate(billingAutomationStatusProvider);

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

/// Accumulator for `_runBulkSendCore` — mutable counters filled in by a
/// single-stage run; `merge` folds another stage's outcome in so
/// "Cobrar todos" can show ONE combined result dialog instead of one per
/// stage. Mirrors the fields `_showBulkServerResultDialog` already expects.
class _BulkSendOutcome {
  int waSent = 0;
  int waFailed = 0;
  int waTotal = 0;
  int emSent = 0;
  int emFailed = 0;
  int emTotal = 0;
  int alreadyPaidSkipped = 0;
  int waWithLink = 0;
  int waWithoutLink = 0;
  bool hadItemsToSend = false;
  final List<BulkFailure> failures = [];
  final Set<String> missingCpfNames = {};

  void merge(_BulkSendOutcome other) {
    waSent += other.waSent;
    waFailed += other.waFailed;
    waTotal += other.waTotal;
    emSent += other.emSent;
    emFailed += other.emFailed;
    emTotal += other.emTotal;
    alreadyPaidSkipped += other.alreadyPaidSkipped;
    waWithLink += other.waWithLink;
    waWithoutLink += other.waWithoutLink;
    hadItemsToSend = hadItemsToSend || other.hadItemsToSend;
    failures.addAll(other.failures);
    missingCpfNames.addAll(other.missingCpfNames);
  }

  BulkServerResult toResult() {
    return BulkServerResult(
      success: true,
      scheduled: false,
      whatsapp: BulkChannelSummary(
        total: waTotal,
        sent: waSent,
        failed: waFailed,
      ),
      email: BulkChannelSummary(total: emTotal, sent: emSent, failed: emFailed),
      failures: failures,
    );
  }
}
