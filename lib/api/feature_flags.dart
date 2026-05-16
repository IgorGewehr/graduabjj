import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Feature flags da migração Firestore → Tatami.
///
/// Hoje os valores são `const` hardcoded (todos false). Quando o Firebase
/// Remote Config estiver provisionado, esta classe vai ler de lá no boot
/// da app e atualizar o `tatamiFlagsProvider` — os call-sites não mudam.
///
/// O contrato com cada PR de wiring é:
///   - Mergeado com a flag default `false` → comportamento legacy (Firestore).
///   - Operacional ativa a flag em canary 10% → 50% → 100% por academia.
///   - Após estabilidade comprovada (>7d sem rollback), próximo PR remove
///     o branch legacy e a flag (Sprint 8 — encerramento Firestore).
class TatamiFlags {
  const TatamiFlags({
    this.useTatamiIdentity = false,
    this.useTatamiReads = false,
    this.useTatamiWrites = false,
    this.useTatamiFinancials = false,
    this.useTatamiAttendance = false,
    this.useTatamiNotifications = false,
    this.useTatamiStore = false,
    this.useTatamiCompetitions = false,
  });

  final bool useTatamiIdentity;
  final bool useTatamiReads;
  final bool useTatamiWrites;
  final bool useTatamiFinancials;
  final bool useTatamiAttendance;
  final bool useTatamiNotifications;
  final bool useTatamiStore;
  final bool useTatamiCompetitions;

  /// Default seguro: tudo desligado. Comportamento idêntico ao app legacy.
  static const allOff = TatamiFlags();

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

/// Provider Riverpod para as flags. Default = tudo desligado (legacy).
///
/// Tests podem sobrescrever via:
/// ```dart
/// ProviderScope(
///   overrides: [
///     tatamiFlagsProvider.overrideWithValue(
///       TatamiFlags(useTatamiIdentity: true),
///     ),
///   ],
///   child: ...,
/// );
/// ```
///
/// Boot real da app sobrescreve este provider depois de ler o Remote Config:
/// ```dart
/// final fetched = await FirebaseRemoteConfig.instance.fetchAndActivate();
/// container.read(tatamiFlagsProvider.notifier).state = TatamiFlags(
///   useTatamiIdentity:
///       FirebaseRemoteConfig.instance.getBool('useTatamiIdentity'),
///   ...,
/// );
/// ```
final tatamiFlagsProvider = StateProvider<TatamiFlags>(
  (ref) => TatamiFlags.allOff,
);
