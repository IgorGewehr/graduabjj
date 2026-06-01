import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_update_service.dart';

/// Checa UMA vez por sessão se há atualização na loja; o resultado fica em
/// cache no provider e o [UpdateBanner] reage a ele. Erros viram "sem
/// atualização" dentro do service (fail-safe), então isto nunca entra em
/// estado de erro de forma que atrapalhe a UI.
final appUpdateProvider = FutureProvider<AppUpdateStatus>((ref) {
  return AppUpdateService.check();
});
