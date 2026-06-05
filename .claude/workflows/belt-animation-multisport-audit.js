export const meta = {
  name: 'belt-animation-multisport-audit',
  description: 'Audit AnimatedBelt quality across all sports (esp. Muay Thai 2 federations) on profile + dashboard, verify findings, synthesize a prioritized fix list',
  phases: [
    { title: 'Audit', detail: 'parallel readers: sports ladders, AnimatedBelt widget, Muay Thai federations, screen usage' },
    { title: 'Verify', detail: 'adversarially verify each high/medium finding against the code' },
    { title: 'Synthesize', detail: 'dedupe + prioritized fix plan' },
  ],
}

const ROOT = '/Users/igorgewehr/WebstormProjects/graduabjj'

const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['area', 'summary', 'findings'],
  properties: {
    area: { type: 'string' },
    summary: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'severity', 'file', 'detail', 'suggestedFix'],
        properties: {
          title: { type: 'string' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          file: { type: 'string', description: 'path:line' },
          detail: { type: 'string' },
          suggestedFix: { type: 'string' },
        },
      },
    },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['title', 'isReal', 'confidence', 'reasoning', 'finalFix'],
  properties: {
    title: { type: 'string' },
    isReal: { type: 'boolean' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    reasoning: { type: 'string' },
    finalFix: { type: 'string' },
  },
}

const DIMENSIONS = [
  {
    key: 'sports-ladders',
    prompt: `Read ${ROOT}/lib/core/sports.dart in full. For EVERY SportId, audit whether its grade ladder is complete and animation-ready for the AnimatedBelt "evolution morph" widget. Specifically check, per sport:
- Does getGradesForSport return a non-empty ordered ladder of GradeDefinition? Any sport with an EMPTY ladder (e.g. musculacao with GradeSystem.none) — confirm AnimatedBelt degrades gracefully (no crash, sensible single-color render).
- Does each grade have: id, a body color (getGradeColor), a human label (getGradeLabel), and where relevant a tipColor / adornment (ponta) and isBlackBelt flag?
- Are there grades whose color is near-white / light (needs a border) and is that derivable from luminance?
- Identify any sport whose ladder ordering would make the color sweep look wrong (e.g. non-monotonic, missing intermediate colors, duplicate ids).
List concrete gaps. Each finding: title, severity, file as path:line, detail, suggestedFix. Return via the StructuredOutput tool.`,
  },
  {
    key: 'animatedbelt-widget',
    prompt: `Read ${ROOT}/lib/widgets/common/animated_belt.dart in full. Audit the AnimatedBelt widget for multi-sport correctness and animation quality. Check:
- _sportLadder() and _buildTimeline(): does the sweep path correctly use the sport's ladder, including the unknown/above-black grade fallback? Any off-by-one in sublist? What happens when targetIndex is the first element (length-1 list)?
- _sweepColor / _currentGradeKey: correct interpolation across intermediate grade colors per sport; easing.
- _BeltVisual: tipColor/ponta adornment rendering, light-body border via luminance, black-belt holder color, middle stripe conventions (-white/-black/coral). Are these generic enough for non-BJJ sports (Muay Thai prajied tip, Judo, Luta Livre) or do any BJJ-specific assumptions leak?
- didUpdateWidget: re-runs timeline on sportId/belt/stripes change?
- Stripes/graus rendering for sports that don't use stripes (supportsStripes=false) — is it suppressed appropriately?
Each finding: title, severity, file path:line, detail, suggestedFix. Return via StructuredOutput.`,
  },
  {
    key: 'muaythai-federations',
    prompt: `Focus on Muay Thai's TWO federations (CBMT vs CBMTT) end-to-end. Read ${ROOT}/lib/core/sports.dart (search resolveMuaythaiVariant, muaythaiVariantCbmt, getGradesForSport muaythaiVariant param, the two prajied ladders), ${ROOT}/lib/widgets/common/animated_belt.dart (how it resolves the variant: it calls resolveMuaythaiVariant(widget.belt) from the stored grade id), and ${ROOT}/lib/services/settings_service.dart (muaythaiGradeSystem field). 
CRITICAL question to answer: AnimatedBelt only receives sportId + belt id and resolves the federation variant from the BELT ID alone. The academy's authoritative federation is AcademySettings.muaythaiGradeSystem, which AnimatedBelt does NOT receive. 
- Is there any grade id that is ambiguous between CBMT and CBMTT (same id, different color/order)? If so, the morph could pick the WRONG ladder/colors when resolving from the belt id alone.
- Do BOTH federation ladders sweep correctly (colors, order, tip adornments)?
- Where is muaythaiGradeSystem read to drive grade SELECTION elsewhere, and is the belt animation consistent with it?
Each finding: title, severity, file path:line, detail, suggestedFix. Return via StructuredOutput.`,
  },
  {
    key: 'screen-usage',
    prompt: `Audit how the belt animation is USED on the student-facing screens. Read these and report whether each passes sportId correctly, keys the widget to re-run the morph on sport/grade change, and shows a correct non-BJJ grade label:
- ${ROOT}/lib/screens/portal/profile_screen.dart (the _HeroHeader AnimatedBelt + non-BJJ label)
- ${ROOT}/lib/screens/portal/home_screen.dart (_WelcomeHeaderWithBelt AnimatedBelt, the ValueKey, multi-sport pill)
- ${ROOT}/lib/screens/portal/public_profile_screen.dart (_ProfileHeader AnimatedBelt + GradeBadge)
- ${ROOT}/lib/screens/admin/student_detail_screen.dart (AnimatedBelt with sportId)
Check specifically: which sport is chosen (primary sport vs selected modalidade), does switching modalidade re-run the morph (ValueKey includes sport?), and for Muay Thai is the federation/variant correctly reflected in the displayed label and belt. Note any screen that hardcodes BJJ assumptions or omits sportId.
Each finding: title, severity, file path:line, detail, suggestedFix. Return via StructuredOutput.`,
  },
]

phase('Audit')
const audits = await parallel(
  DIMENSIONS.map((d) => () =>
    agent(d.prompt, { label: `audit:${d.key}`, phase: 'Audit', schema: FINDINGS_SCHEMA })
  )
)

const allFindings = audits
  .filter(Boolean)
  .flatMap((a) => (a.findings || []).map((f) => ({ ...f, area: a.area })))

log(`Audit produced ${allFindings.length} raw findings across ${audits.filter(Boolean).length} dimensions`)

// Verify only high/medium findings adversarially; keep low as-is.
const toVerify = allFindings.filter((f) => f.severity === 'high' || f.severity === 'medium')

phase('Verify')
const verdicts = await parallel(
  toVerify.map((f) => () =>
    agent(
      `Adversarially verify this belt-animation finding against the actual code. Default to isReal=false unless you can point to the exact code that proves it.
Finding: "${f.title}"
Area: ${f.area}
File: ${f.file}
Detail: ${f.detail}
Proposed fix: ${f.suggestedFix}
Read the referenced file(s) under ${ROOT} and decide: is this a REAL issue that degrades the belt animation for some sport (esp. Muay Thai federations)? Give a final, minimal fix if real. Return via StructuredOutput.`,
      { label: `verify:${f.area}`, phase: 'Verify', schema: VERDICT_SCHEMA }
    ).then((v) => ({ ...f, verdict: v }))
  )
)

const confirmed = verdicts
  .filter(Boolean)
  .filter((x) => x.verdict && x.verdict.isReal)
const lowSeverity = allFindings.filter((f) => f.severity === 'low')

phase('Synthesize')
const synthesis = await agent(
  `You are synthesizing a belt-animation multi-sport audit into a prioritized, de-duplicated fix plan for the GraduaBJJ Flutter app. 
CONFIRMED findings (verified against code): ${JSON.stringify(confirmed.map((c) => ({ title: c.title, area: c.area, severity: c.severity, file: c.file, detail: c.detail, fix: c.verdict.finalFix })), null, 2)}
LOW-severity (unverified) findings: ${JSON.stringify(lowSeverity.map((f) => ({ title: f.title, file: f.file, fix: f.suggestedFix })), null, 2)}
Produce a clear, ordered fix plan grouped by file, each item with a one-line rationale and the concrete code change. Put Muay Thai federation correctness first if present. Be concise and actionable — this becomes the implementation checklist.`,
  { label: 'synthesize', phase: 'Synthesize' }
)

return {
  totalRaw: allFindings.length,
  confirmedCount: confirmed.length,
  confirmed: confirmed.map((c) => ({ title: c.title, area: c.area, severity: c.severity, file: c.file, fix: c.verdict.finalFix, confidence: c.verdict.confidence })),
  lowSeverity: lowSeverity.map((f) => ({ title: f.title, file: f.file })),
  fixPlan: synthesis,
}
