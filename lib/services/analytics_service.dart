import 'dart:io' show Platform;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

/// Wrapper fino sobre o Firebase Analytics — fundação de medição do produto
/// (jul/2026). Diagnóstico: o app tinha ZERO analytics — nenhum logEvent em
/// lugar nenhum — e o north-star (WAS-solo: sessões ativas semanais iniciadas
/// pelo aluno) não tinha como ser medido. Este service é o único ponto de
/// contato com o plugin; nenhum outro arquivo deve importar
/// `firebase_analytics` diretamente.
///
/// Gate de plataforma: o app também compila pra Windows desktop
/// (lib/core/platform_support.dart), onde `firebase_analytics` não tem
/// implementação nativa — qualquer chamada lá estoura MissingPluginException.
/// Por isso [_enabled] restringe a Android/iOS e TODO método público faz
/// no-op silencioso fora disso, com try/catch em volta da chamada real:
/// analytics é telemetria — nunca pode ser o motivo de um crash em produção.
///
/// ── CONTRATO DE EVENTOS (snake_case, estável — isso vira dashboard) ────────
///   app_open_auth    → sessão autenticada "pousou" (1x por sessão de
///                       processo; ver lib/app.dart, latch _sessionLanded).
///   push_opened       → tap numa notificação push (fria ou quente).
///                        param: action_url (String, pode ser vazio).
///   checkin_scanned    → check-in confirmado (QR de turma ou musculação).
///                        param: kind ('qr' | 'musculacao').
///   feed_viewed        → aba Galera/Cena aberta (1x por entrada na tela).
///   hub_viewed         → hub do Lutador aberto (1x por entrada na tela).
///   treinei_logged     → registro manual de "treinei hoje".
///                        param: comeback (int 0/1 — volta após hiato).
///   share_card         → compartilhamento de um card (perfil/conquista/etc).
///                        param: card_type (String).
///   screen_view        → navegação entre rotas (via [logScreenView] manual
///                        OU via o FirebaseAnalyticsObserver do GoRouter, ver
///                        lib/app.dart routerProvider).
/// ─────────────────────────────────────────────────────────────────────────
class AnalyticsService {
  AnalyticsService._();

  static final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  /// Só Android/iOS têm implementação nativa do plugin — mesmo padrão de
  /// [PlatformSupport] (lib/core/platform_support.dart).
  static bool get _enabled =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Observer pronto pra plugar no `observers:` do GoRouter
  /// (lib/app.dart routerProvider) — `null` fora de mobile, então o caller
  /// só precisa fazer `if (AnalyticsService.observer != null) ...`.
  /// GoRouter não seta `name:` nas rotas deste app, então o extractor default
  /// cai no template do path (`state.path`, ex. `/portal/profile/:id`), que é
  /// exatamente o que queremos: agregável, sem PII de id dinâmico no valor.
  static FirebaseAnalyticsObserver? get observer =>
      _enabled ? FirebaseAnalyticsObserver(analytics: _analytics) : null;

  /// Núcleo comum a todo evento: no-op fora de mobile, nunca propaga exceção.
  static Future<void> _log(String name, [Map<String, Object>? params]) async {
    if (!_enabled) return;
    try {
      await _analytics.logEvent(name: name, parameters: params);
    } catch (e) {
      debugPrint('[analytics] logEvent($name) error: $e');
    }
  }

  /// Sessão autenticada "pousou" no destino pós-login (portal/admin).
  /// 1x por sessão de processo — ver latch em lib/app.dart.
  static Future<void> logAppOpenAuthenticated() => _log('app_open_auth');

  /// Tap numa notificação push, fria (cold start) ou quente (app já aberto).
  static Future<void> logPushOpened(String actionUrl) =>
      _log('push_opened', {'action_url': actionUrl});

  /// Check-in confirmado — QR de turma (`kind: 'qr'`) ou QR fixo da
  /// musculação (`kind: 'musculacao'`).
  static Future<void> logCheckinScanned({required String kind}) =>
      _log('checkin_scanned', {'kind': kind});

  /// Aba Galera/Cena aberta (feed social — parceiros/academia).
  static Future<void> logFeedViewed() => _log('feed_viewed');

  /// Hub do Lutador aberto (tela inicial pós-login do app do aluno).
  static Future<void> logHubViewed() => _log('hub_viewed');

  /// Registro manual de "treinei hoje" (fora de check-in por QR/catraca).
  /// [comeback] = true quando o registro encerra um hiato (métrica de
  /// retenção). Firebase só aceita String/num como valor de parâmetro — bool
  /// vira 0/1.
  static Future<void> logTreineiLogged({required bool comeback}) =>
      _log('treinei_logged', {'comeback': comeback ? 1 : 0});

  /// Compartilhamento de um card (perfil, conquista, marco etc).
  static Future<void> logShareCard(String cardType) =>
      _log('share_card', {'card_type': cardType});

  /// `screen_view` manual — usar apenas onde o FirebaseAnalyticsObserver do
  /// GoRouter não cobre (ex.: uma sub-view dentro da mesma rota que troca de
  /// aba sem navegar).
  static Future<void> logScreenView(String screenName) async {
    if (!_enabled) return;
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (e) {
      debugPrint('[analytics] logScreenView($screenName) error: $e');
    }
  }

  /// Contexto de usuário para segmentação no console — uid do Firebase Auth
  /// (já é o identificador usado no resto do app) + academia/role, sem PII
  /// além disso (sem nome, email, telefone).
  static Future<void> setUserContext({
    required String uid,
    String? academyId,
    String? role,
  }) async {
    if (!_enabled) return;
    try {
      await _analytics.setUserId(id: uid);
      if (academyId != null) {
        await _analytics.setUserProperty(
          name: 'academy_id',
          value: academyId,
        );
      }
      if (role != null) {
        await _analytics.setUserProperty(name: 'role', value: role);
      }
    } catch (e) {
      debugPrint('[analytics] setUserContext error: $e');
    }
  }
}
