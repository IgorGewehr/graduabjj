import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/tatami_client.dart';

/// Base URL do Tatami injetada via --dart-define.
///
/// Local dev:    flutter run --dart-define=TATAMI_BASE_URL=http://localhost:8080
/// Staging:      --dart-define=TATAMI_BASE_URL=https://api.staging.tatami.dev
/// Production:   --dart-define=TATAMI_BASE_URL=https://api.tatami.dev
const _defaultBaseUrl = String.fromEnvironment(
  'TATAMI_BASE_URL',
  defaultValue: 'https://tatami.tensorroot.com',
);

/// Cliente HTTP único compartilhado pela app.
///
/// Mantido vivo durante toda a sessão; o token Firebase é refrescado por
/// request via interceptor — nenhum cache adicional necessário aqui.
final tatamiClientProvider = Provider<TatamiClient>((ref) {
  return TatamiClient(baseUrl: _defaultBaseUrl);
});
