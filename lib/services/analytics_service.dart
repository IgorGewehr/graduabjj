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
///   join_request_submitted → aluno enviou o código e criou a solicitação de
///                        entrada (SPEC_ONBOARDING_2026-07.md §5). Chamar no
///                        client logo após `submitJoinRequest` retornar
///                        sucesso (ver team_service.dart/link_code_screen.dart
///                        — fora do território desta fatia, método deixado
///                        pronto para o call site).
///                        param: academy_id (String).
///   join_request_approved → professor aprovou uma solicitação pendente.
///                        Chamar após `decideJoinRequest` retornar sucesso com
///                        action:'approved' (ver join_requests_screen.dart).
///                        params: academy_id (String), minutes_to_approval
///                        (int — createdAt da solicitação até agora), profile
///                        (String — 'fight'/'fitness'/'hybrid').
///   checklist_step_billing_viewed → passo "Ative a cobrança automática" foi
///                        aberto (checklist ou wizard, SPEC_ONBOARDING_2026-07
///                        §1.3/§5). Ver [logChecklistBillingViewed].
///   billing_automation_enabled → dono ligou a automação de cobrança (os dois
///                        setters de whatsappEnabled/autoTuitionEnabled).
///                        params: source ('checklist'|'wizard'|'settings'),
///                        whatsapp_enabled (0/1), auto_tuition_enabled (0/1).
///                        Ver [logBillingAutomationEnabled].
///   billing_automation_test_sent → cobrança-teste (financial sintético
///                        status:'test') disparada pro WhatsApp do próprio
///                        dono. param: has_pix (0/1). Ver [logBillingTestSent].
///   wizard_started      → wizard `/admin/comece-aqui` montado (1x por entrada
///                        na tela — SPEC_ONBOARDING_2026-07.md §1.1/§5).
///                        param: profile. Ver [logWizardStarted].
///   wizard_step_viewed  → um passo do wizard ficou visível (troca de step
///                        interna, sem navegação de rota). params: step,
///                        profile. Ver [logWizardStepViewed].
///   wizard_step_skipped → o dono usou o link secundário de um passo pra
///                        avançar sem completar a ação primária (ex.: "Pular,
///                        adiciono depois"). params: step, profile.
///                        Ver [logWizardStepSkipped].
///   wizard_completed    → o dono chegou ao fim do wizard e tocou "Ir para o
///                        Painel". param: profile. Ver [logWizardCompleted].
///   wizard_abandoned    → o dono saiu do wizard pelo link de dispensa global
///                        (fora dos "pular" por-passo) antes de completar.
///                        params: last_step, profile. Ver [logWizardAbandoned].
///   first_class_created → uma turma foi criada. param: source
///                        ('wizard'|'chamada_empty_state'|'turmas') — distingue
///                        o CTA já existente do wizard novo.
///                        Ver [logFirstClassCreated].
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

  /// Check-in confirmado — QR de turma (`kind: 'qr'`), QR fixo da musculação
  /// (`kind: 'musculacao'`), botão sem-turma do próprio aluno (`kind:
  /// 'button'`) ou a equipe marcando por ele, aluno sem app (`kind:
  /// 'staff'` — students_list_screen.dart, modalidades sem-turma).
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

  /// Aluno enviou o código da academia e criou uma solicitação de entrada
  /// (SPEC_ONBOARDING_2026-07.md §5, decisão 2.1).
  static Future<void> logJoinRequestSubmitted({required String academyId}) =>
      _log('join_request_submitted', {'academy_id': academyId});

  /// Professor aprovou uma solicitação de entrada pendente.
  /// [minutesToApproval] = minutos entre `createdAt` da solicitação e a
  /// decisão — mede a velocidade real de aprovação (gap identificado no
  /// scorecard: fila podia ficar invisível horas/dias).
  static Future<void> logJoinRequestApproved({
    required String academyId,
    required int minutesToApproval,
    required String profile,
  }) =>
      _log('join_request_approved', {
        'academy_id': academyId,
        'minutes_to_approval': minutesToApproval,
        'profile': profile,
      });

  /// Passo/tela "Ative a cobrança automática" foi visto — checklist
  /// (`/admin/comece-aqui/cobranca`) ou, futuramente, um passo do wizard.
  static Future<void> logChecklistBillingViewed() =>
      _log('checklist_step_billing_viewed');

  /// Dono ligou a automação de cobrança — [source] distingue de onde veio a
  /// ação ('checklist', 'wizard' ou 'settings', o dialog de sempre).
  static Future<void> logBillingAutomationEnabled({
    required String source,
    required bool whatsappEnabled,
    required bool autoTuition,
  }) =>
      _log('billing_automation_enabled', {
        'source': source,
        'whatsapp_enabled': whatsappEnabled ? 1 : 0,
        'auto_tuition_enabled': autoTuition ? 1 : 0,
      });

  /// Cobrança-teste enviada pro WhatsApp do próprio dono (preview real antes
  /// de ativar de vez). [hasPix] = true quando o Mercado Pago já estava
  /// conectado e a mensagem saiu com PIX de verdade.
  static Future<void> logBillingTestSent({required bool hasPix}) =>
      _log('billing_automation_test_sent', {'has_pix': hasPix ? 1 : 0});

  /// Wizard `/admin/comece-aqui` montado (SPEC_ONBOARDING_2026-07.md §1.1,
  /// Fatia 7) — 1x por entrada na tela, não por troca de passo.
  static Future<void> logWizardStarted({required String profile}) =>
      _log('wizard_started', {'profile': profile});

  /// Um passo do wizard ficou visível. [step] é um id estável ('class',
  /// 'students', 'billing', 'attendance', 'invite', 'done').
  static Future<void> logWizardStepViewed({
    required String step,
    required String profile,
  }) =>
      _log('wizard_step_viewed', {'step': step, 'profile': profile});

  /// O dono usou o link secundário do passo pra avançar sem completar a ação
  /// primária (ex.: "Pular, adiciono depois", "Agora não, prefiro cobrar na
  /// mão") — diferente de [logWizardAbandoned], que é sair do wizard inteiro.
  static Future<void> logWizardStepSkipped({
    required String step,
    required String profile,
  }) =>
      _log('wizard_step_skipped', {'step': step, 'profile': profile});

  /// O dono chegou ao último passo e tocou "Ir para o Painel".
  static Future<void> logWizardCompleted({required String profile}) =>
      _log('wizard_completed', {'profile': profile});

  /// O dono saiu do wizard pelo link de dispensa GLOBAL (chrome do wizard,
  /// disponível em todo passo exceto W1 fight/hybrid) antes de completar.
  /// [lastStep] é o id do passo em que ele estava ao sair.
  static Future<void> logWizardAbandoned({
    required String lastStep,
    required String profile,
  }) =>
      _log('wizard_abandoned', {'last_step': lastStep, 'profile': profile});

  /// Uma turma foi criada — [source] distingue de onde veio ('wizard',
  /// 'chamada_empty_state' — o CTA já existente na Chamada sem turmas — ou
  /// 'turmas' — criação normal pela tela de Turmas).
  static Future<void> logFirstClassCreated({required String source}) =>
      _log('first_class_created', {'source': source});

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
