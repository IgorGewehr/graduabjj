import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/academy.dart';
import '../providers/portal_providers.dart';

// =============================================================================
// Academy Vocabulary — terminology resolver by academy profile
// =============================================================================
//
// CONTRACT
// --------
// The app is used by pure martial-arts academies, pure fitness/musculação
// gyms, and hybrids of the two (see [AcademyProfile] in models/academy.dart).
// Copy that assumes "lutador"/"tatame"/faixa culture reads wrong for a
// fitness-only CT. Rather than sprinkle `if (profile == ...)` checks through
// every screen, every user-facing term that varies by profile lives HERE,
// once, keyed by [AcademyProfile].
//
// This is intentionally NOT an i18n framework — no ARB files, no locale
// negotiation, no pluralization engine. It's a flat, static lookup table:
// profile in, terms out. Keep it that way; if a screen needs something this
// file doesn't have, add the term here rather than hardcoding it locally.
//
// HOW TO ADD A TERM
// ------------------
// 1. Add a `final String yourTerm;` (or `final String? yourTerm;` when a
//    profile genuinely has none, like [greetingInterjection]) field to
//    [AcademyVocab].
// 2. Pass it in the `const AcademyVocab._(...)` constructor call for EVERY
//    profile constant below ([_fight], [_fitness]  — [_hybrid] currently
//    aliases [_fight], see note there).
// 3. Use it at the call site:
//      - Inside a ConsumerWidget/ConsumerState: `ref.watch(academyVocabProvider).yourTerm`
//      - Anywhere you already have an [AcademyProfile] in hand (e.g. a
//        loaded `Academy`): `AcademyVocab.of(profile).yourTerm`
//
// Never hardcode BJJ-flavored copy in a screen when a generic equivalent
// belongs here instead — that defeats the whole point of this file.
//
// ZERO-REGRESSION RULE
// ---------------------
// [_fight] values must always match the literal strings the app shipped with
// pre-multimodalidade (before this file existed). Every academy without an
// explicit `profile` field defaults to [AcademyProfile.fight] (see
// [AcademyProfileExtension.fromString]), so this file must NEVER change what
// existing academies see. When adding a term, copy the CURRENT hardcoded
// string into [_fight] verbatim — don't rephrase it "while you're in there".
// =============================================================================

/// Resolved terminology for one [AcademyProfile]. Immutable, cheap to
/// construct — instances are the `static const` profile constants below, so
/// [AcademyVocab.of] never allocates.
class AcademyVocab {
  /// Como chamar um membro da academia (singular, minúsculo).
  /// 'lutador' (fight/hybrid) / 'aluno' (fitness).
  final String memberNoun;

  /// Plural de [memberNoun]. 'lutadores' / 'alunos'.
  final String memberNounPlural;

  /// Onde o treino acontece (minúsculo). 'tatame' / 'academia'.
  final String trainingPlace;

  /// Headline do estado de "comeback" (voltou a treinar depois de sumir —
  /// o momento em que retenção mais importa). ALL CAPS, como usado na UI.
  final String comebackHeadline;

  /// Interjeição de saudação/cumprimento marcial (ex.: reação "Oss" a um
  /// post). `null` quando o perfil não tem essa cultura (fitness) — o
  /// call site deve tratar `null` ocultando o elemento, não substituindo por
  /// outra palavra.
  final String? greetingInterjection;

  /// Nome da aba/hub central de identidade do usuário no app (bottom nav +
  /// headers relacionados). 'Lutador' (fight/hybrid) / 'Treino' (fitness).
  final String hubLabel;

  const AcademyVocab._({
    required this.memberNoun,
    required this.memberNounPlural,
    required this.trainingPlace,
    required this.comebackHeadline,
    required this.greetingInterjection,
    required this.hubLabel,
  });

  /// Vocabulário original do app — INTOCÁVEL (ver ZERO-REGRESSION RULE acima).
  static const AcademyVocab _fight = AcademyVocab._(
    memberNoun: 'lutador',
    memberNounPlural: 'lutadores',
    trainingPlace: 'tatame',
    comebackHeadline: 'DE VOLTA AO TATAME',
    greetingInterjection: 'Oss',
    hubLabel: 'Lutador',
  );

  static const AcademyVocab _fitness = AcademyVocab._(
    memberNoun: 'aluno',
    memberNounPlural: 'alunos',
    trainingPlace: 'academia',
    comebackHeadline: 'DE VOLTA AO TREINO',
    greetingInterjection: null,
    hubLabel: 'Treino',
  );

  /// Academias híbridas ensinam artes marciais (além da musculação), então
  /// mantêm o vocabulário `fight` — é a cultura esperada por quem treina
  /// BJJ/Muay Thai/etc ali. Alias explícito (não apenas "cai no default") pra
  /// deixar a decisão documentada; se um termo específico de híbrido surgir,
  /// vira uma constante própria sem mexer em [_fight].
  static const AcademyVocab _hybrid = _fight;

  /// Resolve o vocabulário para [profile]. Nunca lança, nunca é assíncrono —
  /// é só uma seleção entre 3 constantes.
  static AcademyVocab of(AcademyProfile profile) {
    switch (profile) {
      case AcademyProfile.fitness:
        return _fitness;
      case AcademyProfile.hybrid:
        return _hybrid;
      case AcademyProfile.fight:
        return _fight;
    }
  }
}

/// Riverpod access ponto único: resolve o vocabulário da academia ATUAL a
/// partir de [academySettingsProvider]. Enquanto carrega ou quando não há
/// academia (aluno solo), cai no default 'fight' — o MESMO default de
/// [AcademyProfileExtension.fromString] — então nunca há flash de copy
/// errada antes do settings resolver.
///
/// Uso: `ref.watch(academyVocabProvider).comebackHeadline`.
final academyVocabProvider = Provider<AcademyVocab>((ref) {
  final settings = ref.watch(academySettingsProvider).valueOrNull;
  final profile = AcademyProfileExtension.fromString(settings?.profile);
  return AcademyVocab.of(profile);
});
