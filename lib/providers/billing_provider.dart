import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/billing_reminder_service.dart';
import '../services/firebase_service.dart';

/// Billing reminder service provider
final billingReminderServiceProvider = Provider<BillingReminderService>((ref) {
  return BillingReminderService(FirebaseService.academyId);
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

// ============================================
// Automation status (SPEC_ONBOARDING_2026-07.md §0.7)
// ============================================

/// Status combinado da automação de cobrança — WhatsApp (`settings/billingReminders`
/// .whatsappEnabled) + geração automática de mensalidade (`settings/billing`
/// .autoTuitionEnabled). Único lugar que lê os dois docs juntos fora de
/// `billing_reminders_screen.dart._loadData` (~linhas 79-85), reusado pelo
/// checklist "Comece por aqui", pelo banner do Dashboard e pelo passo
/// `BillingActivationStep`.
class BillingAutomationStatus {
  final bool whatsappEnabled;
  final bool autoTuitionEnabled;

  const BillingAutomationStatus({
    required this.whatsappEnabled,
    required this.autoTuitionEnabled,
  });
}

/// `FutureProvider` leve — qualquer tela que ligue/desligue a automação deve
/// chamar `ref.invalidate(billingAutomationStatusProvider)` logo após salvar
/// para que o checklist/banner/passo reflitam o novo estado sem esperar o
/// próximo rebuild natural do provider.
final billingAutomationStatusProvider =
    FutureProvider<BillingAutomationStatus>((ref) async {
  final service = ref.watch(billingReminderServiceProvider);
  final results = await Future.wait([
    service.getNotificationSettings(),
    service.getAutoTuitionEnabled(),
  ]);
  final settings = results[0] as BillingNotificationSettings;
  final autoTuition = results[1] as bool;
  return BillingAutomationStatus(
    whatsappEnabled: settings.whatsappEnabled,
    autoTuitionEnabled: autoTuition,
  );
});
