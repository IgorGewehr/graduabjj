import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/billing_reminder_service.dart';
import 'selected_academy_provider.dart';

/// Billing reminder service provider
// TODO(tatami): BillingReminderService.getOverdueWithStages e getCollectionStats
// usam Firestore diretamente (leitura de 'payments'). A tela billing_reminders_screen
// já usa tatami para listar financials (tatamiPaymentsLegacyProvider). Quando o
// backend expor endpoint de collection-stats, migrar para financialRepoProvider.
final billingReminderServiceProvider = Provider<BillingReminderService>((ref) {
  final academyId = ref.watch(selectedAcademyIdProvider) ?? '';
  return BillingReminderService(academyId);
});

/// Overdue payments grouped by stage
// TODO(tatami): substituir por tatami quando backend expor collection stages.
final overdueStagesProvider = FutureProvider<Map<BillingStage, List<Map<String, dynamic>>>>((ref) async {
  final service = ref.watch(billingReminderServiceProvider);
  return service.getOverdueWithStages();
});

/// Collection stats
// TODO(tatami): substituir por financialRepoProvider.getMonthlyReport quando
// backend expor métricas de inadimplência agregadas.
final collectionStatsProvider = FutureProvider<CollectionStats>((ref) async {
  final service = ref.watch(billingReminderServiceProvider);
  return service.getCollectionStats();
});

/// Contact log for a specific financial
final contactLogProvider = FutureProvider.family<List<BillingContactLog>, String>((ref, financialId) async {
  final service = ref.watch(billingReminderServiceProvider);
  return service.getContactLog(financialId);
});
