import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sparring_engine.dart';
import '../services/training_log_service.dart';
import 'auth_provider.dart';
import 'friend_providers.dart';

/// INSIGHTS de sparring do PRÓPRIO lutador (Treinei/Jornada).
///
/// Fonte: `users/{uid}/training_logs` (self-log, 1 read bounded) + as datas de
/// graduação já materializadas em [myShowcaseProvider] (reusa o cache, não relê
/// attendance). Retorna `null` quando não há usuário ou nenhuma sessão com
/// count>0 — nesse caso a UI omite a seção.
///
/// ANTI-FRAUDE: só lê `training_logs`; graduação continua vindo só de
/// `attendance` verificada. Invalidar após cada save/edit/delete de log.
final sparringInsightsProvider = FutureProvider<SparringInsights?>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  final uid = user?.id;
  if (uid == null) return null;

  final logs = await TrainingLogService(uid).recent(limit: 300);
  // Datas de graduação (por esporte) p/ delimitar "N rolas até a faixa X".
  // Solo (sem academia) → showcase null → só totais/recorde/tendência.
  final showcase = await ref.watch(myShowcaseProvider.future);

  return SparringEngine.compute(
    logs: logs,
    graduations: showcase?.graduations ?? const [],
  );
});
