import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Feature flags da migração Firestore → Tatami.
///
/// **Estado pós-encerramento da migração** (Fase 1, 2026-05): a migração
/// foi concluída. Todas as flags têm default `true` e os call-sites nas
/// screens já não as consultam — Tatami é o único path. Esta classe é
/// mantida como **shim de compatibilidade** para:
///
///   - Testes de `domain_providers` que ainda parametrizam flags.
///   - Boot via Remote Config no `main.dart` (no-op funcional — qualquer
///     valor remoto continua sendo aceito, mas o default seguro agora é
///     "tudo ligado" caso o Remote Config esteja inacessível).
///
/// Próximo passo (Fase 3): marcar como `@Deprecated` para sinalizar
/// remoção futura sem quebrar consumers existentes.
@Deprecated(
  'A migração Firestore→Tatami foi concluída na Fase 1 (2026-05). '
  'Todos os flags retornam true por padrão; novos call-sites não devem '
  'mais consultar TatamiFlags — chame os providers Tatami diretamente. '
  'Mantido apenas para retrocompatibilidade dos testes e do bootstrap '
  'via Remote Config no main.dart.',
)
class TatamiFlags {
  const TatamiFlags({
    this.useTatamiIdentity = true,
    this.useTatamiReads = true,
    this.useTatamiWrites = true,
    this.useTatamiFinancials = true,
    this.useTatamiAttendance = true,
    this.useTatamiNotifications = true,
    this.useTatamiStore = true,
    this.useTatamiCompetitions = true,
  });

  final bool useTatamiIdentity;
  final bool useTatamiReads;
  final bool useTatamiWrites;
  final bool useTatamiFinancials;
  final bool useTatamiAttendance;
  final bool useTatamiNotifications;
  final bool useTatamiStore;
  final bool useTatamiCompetitions;

  /// Default pós-migração: tudo **ligado** (Tatami é o único path).
  /// O nome `allOff` é mantido por compatibilidade com overrides existentes
  /// em testes, mas semanticamente equivale a `allOn`.
  static const allOff = TatamiFlags();

  /// Alias explícito para o estado pós-migração. Preferir em código novo.
  static const allOn = TatamiFlags();

  TatamiFlags copyWith({
    bool? useTatamiIdentity,
    bool? useTatamiReads,
    bool? useTatamiWrites,
    bool? useTatamiFinancials,
    bool? useTatamiAttendance,
    bool? useTatamiNotifications,
    bool? useTatamiStore,
    bool? useTatamiCompetitions,
  }) =>
      TatamiFlags(
        useTatamiIdentity: useTatamiIdentity ?? this.useTatamiIdentity,
        useTatamiReads: useTatamiReads ?? this.useTatamiReads,
        useTatamiWrites: useTatamiWrites ?? this.useTatamiWrites,
        useTatamiFinancials: useTatamiFinancials ?? this.useTatamiFinancials,
        useTatamiAttendance: useTatamiAttendance ?? this.useTatamiAttendance,
        useTatamiNotifications:
            useTatamiNotifications ?? this.useTatamiNotifications,
        useTatamiStore: useTatamiStore ?? this.useTatamiStore,
        useTatamiCompetitions:
            useTatamiCompetitions ?? this.useTatamiCompetitions,
      );
}

/// Provider Riverpod para as flags. Default pós-migração = tudo **ligado**.
///
/// Tests podem sobrescrever via:
/// ```dart
/// ProviderScope(
///   overrides: [
///     tatamiFlagsProvider.overrideWithValue(
///       const TatamiFlags(useTatamiIdentity: false),
///     ),
///   ],
///   child: ...,
/// );
/// ```
///
/// Boot real da app sobrescreve este provider depois de ler o Remote Config
/// (no-op funcional pós-migração; consumir Remote Config continua só para
/// manter o flow operacional documentado).
final tatamiFlagsProvider = StateProvider<TatamiFlags>(
  (ref) => TatamiFlags.allOn,
);
