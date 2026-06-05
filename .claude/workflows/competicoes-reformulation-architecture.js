export const meta = {
  name: 'competicoes-reformulation-architecture',
  description: 'Map the current Competitions feature per persona, generate 3 divergent gamified-yet-useful reformulation concepts, judge them, and synthesize one architecture proposal',
  phases: [
    { title: 'Understand', detail: 'parallel readers: backend/data, admin/professor UI, student UI, reusable infra (gamification/ranking/notifications)' },
    { title: 'Design', detail: '3 divergent reformulation concepts (gamification-first, operations/utility-first, engagement/social-first)' },
    { title: 'Judge', detail: 'panel scores each concept on gamification, utility, intuitiveness, feasibility, reuse' },
    { title: 'Synthesize', detail: 'single architecture proposal merging the winner + best grafts' },
  ],
}

const ROOT = '/Users/igorgewehr/WebstormProjects/graduabjj'

const UNDERSTAND_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['area', 'summary', 'capabilities', 'painPoints', 'reusableInfra'],
  properties: {
    area: { type: 'string' },
    summary: { type: 'string' },
    capabilities: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'persona', 'file', 'howItWorks'],
        properties: {
          name: { type: 'string' },
          persona: { type: 'string', enum: ['student', 'professor', 'admin', 'system'] },
          file: { type: 'string' },
          howItWorks: { type: 'string' },
        },
      },
    },
    painPoints: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'persona', 'severity', 'detail'],
        properties: {
          title: { type: 'string' },
          persona: { type: 'string', enum: ['student', 'professor', 'admin', 'system'] },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          detail: { type: 'string' },
        },
      },
    },
    reusableInfra: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'file', 'howItHelps'],
        properties: {
          name: { type: 'string' },
          file: { type: 'string' },
          howItHelps: { type: 'string' },
        },
      },
    },
  },
}

const CONCEPT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['name', 'thesis', 'forStudents', 'forProfessors', 'forAdmins', 'gamification', 'dataModelChanges', 'screens', 'reusesInfra', 'risks', 'effort'],
  properties: {
    name: { type: 'string' },
    thesis: { type: 'string', description: 'one-paragraph core idea / point of view' },
    forStudents: { type: 'array', items: { type: 'string' } },
    forProfessors: { type: 'array', items: { type: 'string' } },
    forAdmins: { type: 'array', items: { type: 'string' } },
    gamification: { type: 'array', items: { type: 'string' }, description: 'concrete mechanics (points, badges, streaks, brackets, leaderboards, challenges...)' },
    dataModelChanges: { type: 'array', items: { type: 'string' }, description: 'collections/fields/Cloud Functions to add or change' },
    screens: { type: 'array', items: { type: 'string' }, description: 'new or reworked screens/flows, noting the persona' },
    reusesInfra: { type: 'array', items: { type: 'string' }, description: 'existing systems leveraged (timeline/achievements, ranking, notifications, public profiles, payments)' },
    risks: { type: 'array', items: { type: 'string' } },
    effort: { type: 'string', enum: ['S', 'M', 'L', 'XL'] },
  },
}

const JUDGE_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['conceptName', 'scores', 'total', 'strengths', 'weaknesses', 'verdict'],
  properties: {
    conceptName: { type: 'string' },
    scores: {
      type: 'object',
      additionalProperties: false,
      required: ['gamification', 'utility', 'intuitiveness', 'feasibility', 'reuse'],
      properties: {
        gamification: { type: 'integer', minimum: 0, maximum: 10 },
        utility: { type: 'integer', minimum: 0, maximum: 10 },
        intuitiveness: { type: 'integer', minimum: 0, maximum: 10 },
        feasibility: { type: 'integer', minimum: 0, maximum: 10 },
        reuse: { type: 'integer', minimum: 0, maximum: 10 },
      },
    },
    total: { type: 'integer' },
    strengths: { type: 'array', items: { type: 'string' } },
    weaknesses: { type: 'array', items: { type: 'string' } },
    verdict: { type: 'string' },
  },
}

// ---------- Phase 1: Understand ----------
phase('Understand')
const UNDERSTAND = [
  {
    key: 'backend-data',
    prompt: `Map the CURRENT Competitions feature's data + backend in the GraduaBJJ Flutter/Firebase app. Read under ${ROOT}: lib/services/competition_service.dart, lib/models/competition*.dart (CompetitionResult, CompetitionPhoto, any Competition model), and grep functions/index.js + functions/server_functions.js for 'competi'/'competition'. Report: the data model (collections, fields, shapes), what CRUD/queries exist, any Cloud Functions, how competition results tie to a student, and how photos are stored. Capabilities by persona, pain points, and reusable infra. Return via StructuredOutput.`,
  },
  {
    key: 'admin-professor-ui',
    prompt: `Map the CURRENT Competitions experience for ADMIN/PROFESSOR in GraduaBJJ. Grep ${ROOT}/lib for 'Competi'/'competi' in lib/screens/admin and anywhere a professor/admin creates competitions, registers students, enters results/medals, uploads photos. Read the relevant screens. Report exactly what an admin/professor can do today, the flows/steps involved, friction/pain points, and what's missing. Capabilities by persona, pain points, reusable infra. Return via StructuredOutput.`,
  },
  {
    key: 'student-ui',
    prompt: `Map the CURRENT Competitions experience for the STUDENT in GraduaBJJ. Read ${ROOT}/lib/screens/portal/public_profile_screen.dart (Competições tab), any portal competition screens, and how a student sees/registers for competitions and sees their results/medals/photos. Report what a student can do and see today, the engagement level, friction, and what's missing for it to feel useful + fun. Capabilities by persona, pain points, reusable infra. Return via StructuredOutput.`,
  },
  {
    key: 'reusable-infra',
    prompt: `Inventory the systems in GraduaBJJ we could REUSE to make Competitions gamified and useful. Read/scan under ${ROOT}/lib: achievement/timeline/gamification (lib/services/achievement_service.dart, timeline_screen.dart, models/achievement*), ranking (lib/services/ranking_service.dart), notifications (search 'notification'/push), public profiles + the publicProfiles mirror, payments (lib/services/payment_service.dart for paid entries), and the nav/feature-flag system (lib/core/navigation/, AcademySettings). For each: what it does and how it could plug into a competitions reformulation (e.g. award medals to the timeline, competition leaderboards via ranking infra, entry fees via payments, reminders via notifications). Return capabilities (persona 'system'), pain points if any, and reusableInfra. Return via StructuredOutput.`,
  },
]
const SCOPE = '\n\nSCOPE LIMIT (important): read at most ~8 files and run at most ~12 greps; do NOT read whole large files — use targeted grep + offset reads; keep each howItWorks/detail to 1-2 sentences. Wrap up within a few minutes and return the StructuredOutput — partial-but-returned beats exhaustive-but-stalled.'
const understandResults = (await parallel(
  UNDERSTAND.map((u) => () =>
    agent(u.prompt + SCOPE, { label: `understand:${u.key}`, phase: 'Understand', schema: UNDERSTAND_SCHEMA, agentType: 'Explore' })
  )
)).filter(Boolean)

const understandContext = JSON.stringify(
  understandResults.map((r) => ({
    area: r.area,
    summary: r.summary,
    capabilities: r.capabilities,
    painPoints: r.painPoints,
    reusableInfra: r.reusableInfra,
  })),
  null,
  2
)
log(`Understand complete: ${understandResults.length} areas mapped`)

// ---------- Phase 2: Design (3 divergent concepts) ----------
phase('Design')
const LENSES = [
  {
    key: 'gamification-first',
    angle: `GAMIFICATION-FIRST. Lead with game mechanics that drive motivation: XP/points for competing, medal cabinet, brackets, academy-vs-academy or intra-academy leaderboards, seasonal championships, challenges/quests, streaks, badges, shareable cards. Make competing feel like leveling up — but keep every mechanic tied to a real benefit.`,
  },
  {
    key: 'operations-first',
    angle: `OPERATIONS/UTILITY-FIRST. Lead with making competitions effortless and genuinely useful for professors/admins: one place to announce a competition, collect sign-ups, track who's going, manage weigh-ins/categories, batch-enter results, auto-generate the academy's medal tally and reports, and feed results to student profiles automatically. Gamification is the byproduct of clean data.`,
  },
  {
    key: 'engagement-social',
    angle: `ENGAGEMENT/SOCIAL-FIRST. Lead with the social/emotional loop: hype before (countdown, "who's in"), live-ish during (cheer/support, results as they come), celebration after (auto-generated highlight cards, podium moments on the timeline and academy feed/Jornal), peer recognition. Turn each competition into a shared academy story.`,
  },
]
const concepts = (await parallel(
  LENSES.map((l) => () =>
    agent(
      `You are a senior product architect reformulating the COMPETITIONS module of GraduaBJJ (a Brazilian Flutter/Firebase martial-arts academy app: BJJ, Muay Thai, Judô, etc.). Design a BIG, cohesive reformulation from this lens:\n\n${l.angle}\n\nGround every idea in the CURRENT state and reusable infra mapped here:\n${understandContext}\n\nRequirements: it must be more PRACTICAL, INTUITIVE and INTERESTING for students AND professors AND admins; gamified yet genuinely USEFUL (no empty points). Prefer reusing the existing timeline/achievements, ranking, notifications, public profiles, payments and feature-flag systems over building from scratch. Be concrete: name collections/fields/Cloud Functions, the screens/flows per persona, and the gamification mechanics. Return via StructuredOutput.`,
      { label: `concept:${l.key}`, phase: 'Design', schema: CONCEPT_SCHEMA }
    )
  )
)).filter(Boolean)
log(`Design complete: ${concepts.length} concepts generated`)

// ---------- Phase 3: Judge ----------
phase('Judge')
const judgments = (await parallel(
  concepts.map((c) => () =>
    agent(
      `Score this Competitions-reformulation concept for GraduaBJJ on a 0-10 scale per axis: gamification (motivating + fun), utility (real value to all 3 personas), intuitiveness (easy to grasp/use), feasibility (buildable on the existing Flutter/Firebase app + reusable infra), reuse (leverages existing systems vs reinventing). Be a tough, fair judge. Give total = sum, concrete strengths/weaknesses, and a one-line verdict.\n\nConcept:\n${JSON.stringify(c, null, 2)}\n\nReusable infra context:\n${understandContext}\n\nReturn via StructuredOutput.`,
      { label: `judge:${c.name}`, phase: 'Judge', schema: JUDGE_SCHEMA }
    )
  )
)).filter(Boolean)

const ranked = [...judgments].sort((a, b) => b.total - a.total)
log(`Judging complete. Ranking: ${ranked.map((j) => `${j.conceptName}=${j.total}`).join(', ')}`)

// ---------- Phase 4: Synthesize ----------
phase('Synthesize')
const proposal = await agent(
  `You are the lead architect. Produce the FINAL Competitions reformulation architecture proposal for GraduaBJJ, in Brazilian Portuguese, as a clear Markdown document. Build on the highest-scoring concept but GRAFT the best ideas from the others. It must serve students, professors and admins, and be gamified yet useful.\n\nCONCEPTS:\n${JSON.stringify(concepts, null, 2)}\n\nJUDGE SCORES (ranked):\n${JSON.stringify(ranked, null, 2)}\n\nCURRENT STATE + REUSABLE INFRA:\n${understandContext}\n\nStructure the document:\n1. Visão geral (o problema hoje + a aposta)\n2. Experiência por persona (Aluno / Professor / Admin) — o que muda, telas/fluxos\n3. Mecânicas de gamificação (e o benefício real de cada uma)\n4. Modelo de dados e backend (coleções, campos, Cloud Functions, regras)\n5. Reaproveitamento da infra existente (timeline/conquistas, ranking, notificações, perfis públicos, pagamentos, feature flags)\n6. Roadmap em fases (MVP → completo), com esforço relativo e dependências\n7. Riscos e mitigação\n8. Métricas de sucesso\nSeja concreto e acionável — isto será o blueprint de implementação.`,
  { label: 'synthesize', phase: 'Synthesize' }
)

return {
  understandAreas: understandResults.map((r) => r.area),
  topPainPoints: understandResults
    .flatMap((r) => r.painPoints || [])
    .filter((p) => p.severity === 'high')
    .map((p) => ({ persona: p.persona, title: p.title })),
  concepts: concepts.map((c) => ({ name: c.name, thesis: c.thesis, effort: c.effort })),
  ranking: ranked.map((j) => ({ concept: j.conceptName, total: j.total, scores: j.scores })),
  winner: ranked[0]?.conceptName,
  proposal,
}
