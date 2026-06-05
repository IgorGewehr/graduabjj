export const meta = {
  name: 'aula-particular-turmas-architecture',
  description: 'Architect: 1:1 private paid lesson that grants attendance (no plan/turma) + turmas filters & bulk "add all" mirroring the chamada UX',
  phases: [
    { title: 'Understand', detail: 'Explore: cobrança avulsa+MP, chamada/attendance, turmas mgmt, student fields (categoria/gênero)' },
    { title: 'Plan', detail: 'one detailed implementation plan per feature' },
    { title: 'Synthesize', detail: 'single ordered blueprint (PT-BR) with phases + risks' },
  ],
}

const ROOT = '/Users/igorgewehr/WebstormProjects/graduabjj'
const SCOPE = '\n\nSCOPE LIMIT: read at most ~8 files and ~12 greps; use targeted grep+offset reads, do NOT read whole large files; keep each item to 1-2 sentences. Wrap up in a few minutes and return StructuredOutput — partial-but-returned beats exhaustive-but-stalled.'

const UNDERSTAND_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['area', 'summary', 'capabilities', 'painPoints', 'reusableInfra'],
  properties: {
    area: { type: 'string' }, summary: { type: 'string' },
    capabilities: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['name', 'file', 'howItWorks'], properties: { name: { type: 'string' }, file: { type: 'string' }, howItWorks: { type: 'string' } } } },
    painPoints: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['title', 'detail'], properties: { title: { type: 'string' }, detail: { type: 'string' } } } },
    reusableInfra: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['name', 'file', 'howItHelps'], properties: { name: { type: 'string' }, file: { type: 'string' }, howItHelps: { type: 'string' } } } },
  },
}
const PLAN_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['feature', 'summary', 'dataModel', 'backend', 'ui', 'edgeCases', 'reuses', 'openQuestions', 'effort'],
  properties: {
    feature: { type: 'string' }, summary: { type: 'string' },
    dataModel: { type: 'array', items: { type: 'string' } },
    backend: { type: 'array', items: { type: 'string' } },
    ui: { type: 'array', items: { type: 'string' } },
    edgeCases: { type: 'array', items: { type: 'string' } },
    reuses: { type: 'array', items: { type: 'string' } },
    openQuestions: { type: 'array', items: { type: 'string' } },
    effort: { type: 'string', enum: ['S', 'M', 'L', 'XL'] },
  },
}

phase('Understand')
const U = [
  { key: 'cobranca-avulsa-mp', prompt: `Map the existing one-off charge ("cobrança avulsa") for a student and how it links to Mercado Pago checkout. Read ${ROOT}/lib/services/payment_service.dart, the aluno→financeiro UI that creates an avulsa charge (grep lib/screens for 'avulsa'/'cobrança'/'Cobrar'), and the MP checkout (grep functions/index.js for 'createMercadoPagoCheckout'/'preference'/'mercadopago'). Report: how an avulsa charge is created, its data shape, and whether/how it generates an MP checkout/preference and gets marked paid (webhook).` },
  { key: 'chamada-attendance', prompt: `Map how attendance ("presença") is recorded. Read ${ROOT}/lib/services/attendance_service.dart (markPresent, the attendance doc shape, classId/className), and the chamada (roll-call) UI under lib/screens (grep 'chamada'/'markPresent'/'attendance_screen'), including any bulk "mark all" buttons and filters. Report how a single attendance is created and what a "class" attendance requires (classId etc.) — so we can grant attendance for a 1:1 private lesson that has no turma.` },
  { key: 'turmas-mgmt', prompt: `Map turmas (classes) management. Read ${ROOT}/lib/models for the class model (BJJClass — studentIds, category, schedule), and the admin screen that manages a class's students (grep lib/screens/admin for 'turma'/'class'/'studentIds'/'gerenciar'). Report how students are added to a class today and where a "add all / filter adult|kids|gênero" would plug in.` },
  { key: 'student-fields', prompt: `Map the Student model fields relevant to filtering: category (adult/kids — StudentCategory), gender/sexo, sports, status. Read ${ROOT}/lib/models/student.dart. Report exact field names/enums so bulk-add filters (adulto/kids, masculino/feminino) can be built, and note the chamada screen's existing filters to mirror.` },
]
const understand = (await parallel(U.map((u) => () => agent(u.prompt + SCOPE, { label: `understand:${u.key}`, phase: 'Understand', schema: UNDERSTAND_SCHEMA, agentType: 'Explore' })))).filter(Boolean)
const ctx = JSON.stringify(understand, null, 2)
log(`Understand: ${understand.length} areas`)

phase('Plan')
const FEATURES = [
  { key: 'aula-particular', prompt: `Design the "Aula particular 1:1" feature for GraduaBJJ. A student pays for a SINGLE private lesson (e.g. R$150), one-off — NOT added to a financial plan nor to a turma. Reuse the existing one-off charge ("cobrança avulsa") + MP checkout. CRUCIAL extra: when such a lesson is paid/given, the student must EARN an attendance (presença) exactly as if marked in a class roll-call — design the most efficient, practical way to do this (e.g. a synthetic/virtual class id like 'aula_particular', or an attendance doc with a private-lesson marker), reusing attendance_service.markPresent and keeping attendanceCount/streak/ranking consistent. Specify data model, backend (incl. whether attendance is granted on payment confirmation via webhook or manually by staff), UI per persona (admin creates the private lesson + price; student pays; attendance appears), edge cases, what it reuses, and open questions.` },
  { key: 'turmas-bulk-filtros', prompt: `Design the turmas "gerenciar alunos" improvements for GraduaBJJ, mirroring the chamada UX: (1) a filter toggle for turma ADULTO vs KIDS; (2) a "marcar/adicionar todos" button that adds all matching students to the class in one tap (e.g. all adults to an adult class); (3) extra filters like gênero (masculino/feminino) and categoria. It should feel just like the chamada buttons. Specify the data model touched (BJJClass.studentIds), backend (batch update), UI per persona, edge cases (already-enrolled, large rosters, undo), what it reuses from the chamada screen, and open questions.` },
]
const plans = (await parallel(FEATURES.map((f) => () => agent(`You are a senior Flutter/Firebase architect. Ground everything in the current code mapped here:\n${ctx}\n\nProduce a concrete, buildable implementation plan.\n\n${f.prompt}\n\nReturn via StructuredOutput.`, { label: `plan:${f.key}`, phase: 'Plan', schema: PLAN_SCHEMA }))) ).filter(Boolean)
log(`Plans: ${plans.length}`)

phase('Synthesize')
const doc = await agent(`Você é o arquiteto-líder. Escreva, em PT-BR e em Markdown, o blueprint de implementação unificado para duas features do GraduaBJJ (app Flutter/Firebase de academia de luta), prontas para virar tarefas.\n\nPLANOS:\n${JSON.stringify(plans, null, 2)}\n\nESTADO ATUAL + INFRA:\n${ctx}\n\nEstrutura: 1) Visão geral; 2) Aula particular 1:1 (modelo de dados, backend incl. como a presença é concedida, UI por persona, casos de borda); 3) Turmas — filtros adulto/kids + gênero e "adicionar todos" (espelhando a chamada); 4) Reaproveitamento da infra (cobrança avulsa, MP, attendance_service, chamada); 5) Roadmap em fases com esforço; 6) Riscos e perguntas em aberto. Seja concreto e acionável.`, { label: 'synthesize', phase: 'Synthesize' })

return { understandAreas: understand.map((u) => u.area), features: plans.map((p) => ({ feature: p.feature, effort: p.effort, openQuestions: p.openQuestions })), blueprint: doc }
