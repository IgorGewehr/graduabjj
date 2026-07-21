import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/navigator_key.dart';
import 'analytics_service.dart';

/// Background message handler. MUST be a top-level / static function annotated
/// with `@pragma('vm:entry-point')`. We don't need to do work here — when the
/// app is backgrounded/terminated the OS shows the notification from the
/// `notification` payload automatically; the tap is handled on resume.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Real FCM push (A2/F2). The Cloud Functions already send to
/// `users/{uid}/fcmTokens/*` (doc id == token); this registers/cleans those
/// tokens and routes taps to `data.actionUrl`. Same public interface as the
/// previous stub, so the existing call sites (main.dart, auth_provider) work.
class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _fcmToken;
  bool _initialized = false;

  String? get fcmToken => _fcmToken;

  // TAREFA 2 (jul/2026) — kill-switch remoto do FCM no iOS -----------------
  //
  // O crash do commit 1ddf1e7 é NATIVO dentro do init do firebase_messaging
  // em iOS 26 (não é uma exceção Dart — o try/catch de initialize() abaixo
  // NÃO pega esse tipo de crash). Como não dá pra eliminar o crash nativo só
  // no lado Dart, a defesa é dupla: (1) main.dart adia o init do iOS pra
  // DEPOIS do 1º frame, então se ele voltar a ocorrer o usuário já viu a UI
  // em vez de tela branca instantânea; (2) este interruptor remoto — se o
  // crash reaparecer em campo, vira `appConfig/flags.fcmIosEnabled=false` no
  // console do Firestore e NENHUM app volta a chamar o plugin no iOS a
  // partir da PRÓXIMA abertura, sem precisar de uma nova build.
  //
  // Máquina de estados (por que cache local em vez de ler o Firestore direto
  // no boot):
  //   • Boot ATUAL   → decide com o valor CACHEADO em SharedPreferences
  //     (leitura local e rápida; NUNCA bloqueia nem arrisca o boot com uma
  //     chamada de rede antes do init do FCM).
  //   • Boot ATUAL, em background (fire-and-forget, só depois do init) →
  //     busca `appConfig/flags` no Firestore e regrava o cache — efeito só
  //     no PRÓXIMO boot.
  //   • Doc/campo ausente ou de tipo errado → mantém o cache como está
  //     (default TRUE na 1ª leitura = FCM religado, que é o que esta tarefa
  //     pede).
  static const _iosKillSwitchPrefsKey = 'fcm_ios_enabled';

  /// Valor cacheado que decide se o FCM inicializa NESTA abertura do app no
  /// iOS. Local/síncrono-rápido de propósito — ver nota de máquina de
  /// estados acima.
  Future<bool> iosKillSwitchCachedValue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_iosKillSwitchPrefsKey) ?? true;
    } catch (e) {
      // Sem acesso ao cache (raríssimo) → mantém o default religado; a pior
      // consequência é tentar inicializar mesmo com o switch em OFF, nunca
      // o contrário (não queremos apagar push por uma falha de disco).
      debugPrint('[push] iOS kill-switch cache read error: $e');
      return true;
    }
  }

  /// Atualiza o cache local a partir de `appConfig/flags`, em BACKGROUND —
  /// o chamador NUNCA deve dar `await` nisto durante o boot (o ponto é
  /// justamente preparar o PRÓXIMO boot sem atrasar o atual). Best-effort:
  /// falha de rede/permissão não deve gerar crash nem retry.
  Future<void> syncIosKillSwitchInBackground() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('appConfig')
          .doc('flags')
          .get();
      final enabled = snap.data()?['fcmIosEnabled'];
      if (enabled is bool) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_iosKillSwitchPrefsKey, enabled);
      }
      // Campo ausente/tipo errado → não mexe no cache (mantém o valor já em
      // uso, seja o default TRUE ou o último sincronizado com sucesso).
    } catch (e) {
      debugPrint('[push] iOS kill-switch sync error: $e');
    }
  }

  /// One-time setup (called from main, before auth). Safe to call without a
  /// logged-in user; token persistence happens on [onUserLogin].
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      await _messaging.requestPermission(
          alert: true, badge: true, sound: true);

      // iOS: also surface notifications while the app is in the foreground.
      await _messaging.setForegroundNotificationPresentationOptions(
          alert: true, badge: true, sound: true);

      // Tap handling (warm start + cold start).
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTapNavigation);
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _handleTapNavigation(initial);

      // Keep the stored token fresh — o FCM roda esse refresh
      // periodicamente ao longo de toda a vida do app, não só no login,
      // então TAREFA 1 ("token em toda abertura autenticada") já estava
      // parcialmente coberta aqui. catchError defensivo: uma falha de
      // escrita no Firestore (rede, permissão transitória) não pode virar
      // um erro não tratado dentro do stream do plugin nativo.
      _messaging.onTokenRefresh.listen((t) {
        _fcmToken = t;
        _saveToken(t).catchError((e) {
          debugPrint('[push] onTokenRefresh save error: $e');
        });
      });
    } catch (e) {
      debugPrint('[push] initialize error: $e');
    }
  }

  /// Fetch the device token and persist it under the signed-in user.
  Future<void> onUserLogin() async {
    // GUARD (iOS 26): quando initialize() não rodou (main.dart pula o FCM no
    // iOS porque o firebase_messaging crasha NATIVAMENTE — try/catch Dart não
    // pega), NUNCA tocar o plugin: qualquer chamada nativa reativa o caminho
    // crashante. Sem init não há token registrado, então não há o que fazer.
    if (!_initialized) return;
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        _fcmToken = token;
        await _saveToken(token);
      }
    } catch (e) {
      debugPrint('[push] onUserLogin error: $e');
    }
  }

  /// Remove this device's token so a logged-out device stops receiving push.
  Future<void> onUserLogout() async {
    // GUARD (iOS 26): idem onUserLogin — sem initialize() não existe token
    // salvo em users/{uid}/fcmTokens para limpar; o getToken() de fallback era
    // justamente a 1ª chamada nativa da sessão e o risco de crash no logout.
    if (!_initialized) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      // Só o cache — sem fallback getToken() no logout (chamada nativa extra
      // desnecessária: se não temos token cacheado, nada foi salvo nesta run).
      final token = _fcmToken;
      if (uid != null && token != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('fcmTokens')
            .doc(token)
            .delete();
      }
    } catch (e) {
      debugPrint('[push] onUserLogout error: $e');
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    if (!_initialized) return;
    try {
      await _messaging.subscribeToTopic(topic);
    } catch (e) {
      debugPrint('[push] subscribeToTopic error: $e');
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    if (!_initialized) return;
    try {
      await _messaging.unsubscribeFromTopic(topic);
    } catch (e) {
      debugPrint('[push] unsubscribeFromTopic error: $e');
    }
  }

  /// Kept for interface compatibility (no role-based topics for now).
  void setUserRole({required bool isAdmin}) {}

  Future<void> _saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(token) // doc id == token (matches the server's cleanup path)
        .set({
      'token': token,
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Routes a tapped notification to `data.actionUrl` (TAREFA 3).
  ///
  /// Reusa o MESMO vocabulário/mecanismo das notificações internas: a
  /// NotificationsScreen navega com `context.push(notification.actionUrl!)`
  /// e o notification_dispatcher.dart gera valores como '/portal/financeiro'
  /// e '/portal/diario' — strings de rota do GoRouter já registradas em
  /// app.dart. Não há tradução especial a fazer aqui: `GoRouter.go(url)`
  /// entende essas rotas do mesmo jeito.
  ///
  /// Blindagem: actionUrl ausente/vazio/malformado NUNCA pode impedir o app
  /// de abrir — nesse caso a navegação é simplesmente pulada e o fluxo
  /// padrão (splash → redirect por role, ver routerProvider em app.dart)
  /// assume normalmente, como se a notificação não tivesse rota nenhuma.
  /// `ctx.mounted` cobre o Navigator ter sido descartado entre o tap e o 1º
  /// frame; o try/catch cobre uma rota desconhecida ou qualquer erro interno
  /// do GoRouter (cai na tela "Página não encontrada" de app.dart em vez de
  /// propagar e crashar). Funciona tanto pra app frio (getInitialMessage,
  /// chamado em initialize()) quanto pra app quente (onMessageOpenedApp).
  void _handleTapNavigation(RemoteMessage message) {
    final url = message.data['actionUrl'];
    // Analytics (jul/2026): mede taps em push — fria (getInitialMessage) e
    // quente (onMessageOpenedApp) passam pelo MESMO ponto, então um único
    // log aqui cobre os dois casos. actionUrl ausente/malformado ainda conta
    // como um tap (vira string vazia) — a validação abaixo só decide se HÁ
    // navegação, não se o tap aconteceu.
    AnalyticsService.logPushOpened(url is String ? url : '');
    if (url is! String || url.isEmpty || !url.startsWith('/')) {
      if (url != null) {
        debugPrint('[push] actionUrl malformado ignorado: $url');
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      try {
        GoRouter.of(ctx).go(url);
      } catch (e) {
        // Nunca deixa um deep-link ruim derrubar o app — o usuário só fica
        // onde já estava (splash/portal), sem navegação nenhuma.
        debugPrint('[push] navigation error: $e');
      }
    });
  }
}

/// Global instance.
final pushNotificationService = PushNotificationService();
