import 'package:flutter_riverpod/flutter_riverpod.dart';
// TODO(tatami): descomentar quando contactLogProvider for migrado para tatami.
// import '../api/repositories.dart';
import '../services/billing_reminder_service.dart';
import 'selected_academy_provider.dart';

/// Billing reminder service provider.
///
/// Mantido para operações sem equivalente direto no tatami:
///   - getStudentContacts (leitura de students com phone/email/guardian)
///   - getCollectionStats (métricas agregadas de inadimplência)
///   - getNotificationSettings / saveNotificationSettings (billingReminders subcol)
///   - logContactAttempt (escrita em billingContactLog — callers em
///     billing_reminders/ ainda dependem do BillingContactLog model)
///
/// TODO(tatami): quando o backend expor:
///   - GET /v1/academies/{id}/financials/reports/monthly com métricas de
///     inadimplência → migrar getCollectionStats para financialRepoProvider.getMonthlyReport
///   - GET /v1/academies/{id}/billing-contacts com filtro student_id →
///     migrar contactLogProvider para financialRepoProvider.listBillingContactsForFinancial
///   - PUT /v1/academies/{id}/settings/billing_reminders →
///     migrar getNotificationSettings/saveNotificationSettings para settingsRepoProvider
final billingReminderServiceProvider = Provider<BillingReminderService>((ref) {
  final academyId = ref.watch(selectedAcademyIdProvider) ?? '';
  return BillingReminderService(academyId);
});

/// Overdue payments grouped by stage.
// TODO(tatami): substituir por tatami quando backend expor collection stages.
final overdueStagesProvider = FutureProvider<Map<BillingStage, List<Map<String, dynamic>>>>((ref) async {
  final service = ref.watch(billingReminderServiceProvider);
  return service.getOverdueWithStages();
});

/// Collection stats.
// TODO(tatami): substituir por financialRepoProvider.getMonthlyReport quando
// backend expor métricas de inadimplência agregadas.
final collectionStatsProvider = FutureProvider<CollectionStats>((ref) async {
  final service = ref.watch(billingReminderServiceProvider);
  return service.getCollectionStats();
});

/// Contact log for a specific financial.
///
/// TODO(tatami): migrar para financialRepoProvider.listBillingContactsForFinancial
/// quando os callers em billing_reminders/ forem adaptados para ApiBillingContact
/// (retorno do repo) em vez de BillingContactLog (modelo Firestore legado).
/// Mantém Firestore enquanto billing_reminders/contact_dialog.dart e
/// billing_reminders/individual_send_executor.dart não forem atualizados.
final contactLogProvider = FutureProvider.family<List<BillingContactLog>, String>((ref, financialId) async {
  // TODO(tatami): endpoint pending —
  //   financialRepoProvider.listBillingContactsForFinancial retorna
  //   ApiBillingContact; callers precisam adaptar antes de migrar.
  final service = ref.watch(billingReminderServiceProvider);
  return service.getContactLog(financialId);

  // Future migration (após adaptar callers):
  // final academyId = ref.watch(selectedAcademyIdProvider) ?? '';
  // final page = await ref.read(financialRepoProvider)
  //     .listBillingContactsForFinancial(academyId, financialId);
  // return page.items.map(...).toList();
});
