import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/billing_reminder_service.dart';
import 'selected_academy_provider.dart';

/// Billing reminder service provider
final billingReminderServiceProvider = Provider<BillingReminderService>((ref) {
  final academyId = ref.watch(selectedAcademyIdProvider) ?? '';
  return BillingReminderService(academyId);
});

/// Overdue payments grouped by stage
final overdueStagesProvider = FutureProvider<Map<BillingStage, List<Map<String, dynamic>>>>((ref) async {
  final service = ref.watch(billingReminderServiceProvider);
  return service.getOverdueWithStages();
});

/// Collection stats
final collectionStatsProvider = FutureProvider<CollectionStats>((ref) async {
  final service = ref.watch(billingReminderServiceProvider);
  return service.getCollectionStats();
});

/// Contact log for a specific financial
final contactLogProvider = FutureProvider.family<List<BillingContactLog>, String>((ref, financialId) async {
  final service = ref.watch(billingReminderServiceProvider);
  return service.getContactLog(financialId);
});
