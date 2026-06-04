// Pure helpers for "requisitos compostos" de graduação (B2) — sem deps de
// Flutter/Firestore, testáveis. Combinam a elegibilidade por presença (que já
// existe) com o domínio de técnicas do currículo e o tempo-em-faixa.

/// Política da academia sobre as técnicas do currículo na graduação.
/// `informative` (default) = só mostra; `required` = bloqueia a promoção até
/// atingir o % mínimo de técnicas dominadas.
const String graduationSkillInformative = 'informative';
const String graduationSkillRequired = 'required';

/// Fatores de técnica para a faixa atual.
class GraduationSkillFactors {
  /// Técnicas dominadas / total cadastradas para a faixa.
  final int done;
  final int total;

  /// Percentual dominado (0–100), ou null quando não há currículo cadastrado.
  final double? pct;

  /// A política exige técnicas (`required`).
  final bool required;

  /// Requisito de técnicas atendido. Sempre true quando a política é
  /// informativa OU quando não há currículo cadastrado para a faixa (não dá
  /// para exigir o que não foi definido).
  final bool met;

  const GraduationSkillFactors({
    required this.done,
    required this.total,
    required this.pct,
    required this.required,
    required this.met,
  });
}

/// Calcula os fatores de técnica a partir das contagens já apuradas.
/// [policy] = informative|required; [minSkillPct] = % mínimo quando required.
GraduationSkillFactors computeSkillFactors({
  required int dominatedCount,
  required int totalForGrade,
  required String policy,
  required int minSkillPct,
}) {
  final total = totalForGrade < 0 ? 0 : totalForGrade;
  final done = dominatedCount.clamp(0, total);
  final pct = total == 0 ? null : (done / total) * 100.0;
  final required = policy == graduationSkillRequired;
  // Sem currículo (total 0) nunca bloqueia. Com currículo e required, exige o %.
  final met = !required || total == 0 || (pct ?? 0) >= minSkillPct;
  return GraduationSkillFactors(
    done: done,
    total: total,
    pct: pct,
    required: required,
    met: met,
  );
}

/// Tempo-em-faixa (em dias) a partir da data da última promoção naquela
/// modalidade; se nunca houve promoção, cai para a data de início. Null quando
/// nenhuma data está disponível. Apenas informativo nesta fase (não bloqueia).
int? daysInBelt({DateTime? lastPromotion, DateTime? startDate, required DateTime now}) {
  final ref = lastPromotion ?? startDate;
  if (ref == null) return null;
  final d = now.difference(ref).inDays;
  return d < 0 ? 0 : d;
}
