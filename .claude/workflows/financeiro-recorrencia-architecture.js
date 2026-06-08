export const meta = {
  name: 'financeiro-recorrencia-architecture',
  description: 'Architect: recurring plans (Netflix-like subscription, fixed months, card-only auto-charge on a day) + per-plan payment-method selection (card/pix/both) + deep Mercado Pago integration audit',
  phases: [
    { title: 'Understand', detail: 'Explore: MP integration (checkout/preapproval/webhooks), plans model + billing today, payment methods, avulsa→MP linkage' },
    { title: 'Plan', detail: 'recurring subscription design + payment-method selection design' },
    { title: 'Synthesize', detail: 'single finance blueprint (PT-BR) with MP specifics, phases, risks' },
  ],
}

const ROOT = '/Users/igorgewehr/WebstormProjects/graduabjj'
const SCOPE = '\n\nSCOPE LIMIT: read at most ~10 files and ~14 greps; targeted grep+offset reads, do NOT dump whole large files; keep items to 1-2 sentences. Wrap up in a few minutes and return StructuredOutput — partial-but-returned beats exhaustive-but-stalled.'

const UNDERSTAND_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['area', 'summary', 'capabilities', 'gaps', 'reusableInfra'],
  properties: {
    area: { type: 'string' }, summary: { type: 'string' },
    capabilities: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['name', 'file', 'howItWorks'], properties: { name: { type: 'string' }, file: { type: 'string' }, howItWorks: { type: 'string' } } } },
    gaps: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['title', 'detail'], properties: { title: { type: 'string' }, detail: { type: 'string' } } } },
    reusableInfra: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['name', 'file', 'howItHelps'], properties: { name: { type: 'string' }, file: { type: 'string' }, howItHelps: { type: 'string' } } } },
  },
}
const PLAN_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['feature', 'summary', 'dataModel', 'mpIntegration', 'backend', 'ui', 'edgeCases', 'reuses', 'openQuestions', 'effort'],
  properties: {
    feature: { type: 'string' }, summary: { type: 'string' },
    dataModel: { type: 'array', items: { type: 'string' } },
    mpIntegration: { type: 'array', items: { type: 'string' }, description: 'specific Mercado Pago APIs/objects: preference vs preapproval/subscription, webhooks, card token, billing day' },
    backend: { type: 'array', items: { type: 'string' } },
    ui: { type: 'array', items: { type: 'string' } },
    edgeCases: { type: 'array', items: { type: 'string' }, description: 'failed charge, retries, cancel, card expiry, end after N months, proration' },
    reuses: { type: 'array', items: { type: 'string' } },
    openQuestions: { type: 'array', items: { type: 'string' } },
    effort: { type: 'string', enum: ['S', 'M', 'L', 'XL'] },
  },
}

phase('Understand')
const U = [
  { key: 'mp-integration', prompt: `Audit the Mercado Pago integration in GraduaBJJ end-to-end. Read ${ROOT}/functions/index.js and functions/server_functions.js (grep 'mercadopago'/'createMercadoPagoCheckout'/'preference'/'preapproval'/'subscription'/'webhook'/'application_fee'/'split') and ${ROOT}/lib/services/payment_service.dart. Report: how checkout is created (Preference API?), whether recurring/preapproval (subscriptions) is used at all, how webhooks confirm payment, split/marketplace config, and what's MISSING for true recurring card subscriptions. capabilities, gaps, reusableInfra.` },
  { key: 'plans-billing', prompt: `Map the financial PLANS model and billing today. Grep ${ROOT}/lib for plan models/services ('plan'/'Plano'/'plan_service'/'subscription'/'recorr'/'mensalidade'/'billing'/'fatura'). Read the plan model + service. Report: plan fields (price, period, recurrence), how charges/invoices are generated (manual? cron?), whether plans support a FIXED number of months, and how payment methods are currently chosen. capabilities, gaps, reusableInfra.` },
  { key: 'payment-methods-and-avulsa', prompt: `Map (a) how payment method (cartão vs PIX) is selected today for a charge/plan, and (b) the one-off charge ("cobrança avulsa") → MP checkout linkage. Grep ${ROOT}/lib and functions for 'pix'/'card'/'cartao'/'payment_method'/'avulsa'. Report whether a charge/plan can be restricted to card-only or pix-only today, the in-app checkout flow the student uses to pay, and whether avulsa is correctly wired to MP checkout + webhook confirmation. capabilities, gaps, reusableInfra.` },
]
const understand = (await parallel(U.map((u) => () => agent(u.prompt + SCOPE, { label: `understand:${u.key}`, phase: 'Understand', schema: UNDERSTAND_SCHEMA, agentType: 'Explore' })))).filter(Boolean)
const ctx = JSON.stringify(understand, null, 2)
log(`Understand: ${understand.length} areas`)

phase('Plan')
const FEATURES = [
  { key: 'assinatura-recorrente', prompt: `Design a TRUE recurring subscription for GraduaBJJ plans, Netflix-style, on Mercado Pago. Requirements: a plan can be recurring (e.g. R$200/month), CARD-ONLY, lasting a FIXED number of months (e.g. 8), where after the student subscribes once in the app checkout, MP auto-charges the card on a specific billing day each month — no manual action. Specify the exact MP mechanism (preapproval/subscription "Assinaturas" API vs recurring preference, card tokenization, billing_day, end after N months / total occurrences), the data model (plan.recurring, months, billingDay, paymentMethods, mpPreapprovalId, status), backend Cloud Functions + webhooks (authorized_payment, recurring charge events, mark each month paid, end automatically after N), the in-app subscribe flow, and edge cases (charge failure/retry, card expiry, cancel, dunning). Return via StructuredOutput.` },
  { key: 'selecao-metodos-pagamento', prompt: `Design per-plan/per-charge PAYMENT METHOD selection for GraduaBJJ: the admin chooses whether a plan/charge can be paid by cartão only, PIX only, or both. This must flow into the MP checkout (restrict payment_methods accordingly) and into recurring subscriptions (which are card-only). Specify the data model (paymentMethods enum/flags on plan & charge), how it constrains the MP Preference/preapproval, UI for the admin to pick, and how the student checkout reflects it. Note the interaction with the recurring subscription (card-only) and with PIX one-off. Return via StructuredOutput.` },
]
const plans = (await parallel(FEATURES.map((f) => () => agent(`You are a senior payments architect for a Brazilian Flutter/Firebase app using Mercado Pago (already integrated for one-off checkout). Ground everything in the current code mapped here:\n${ctx}\n\nDesign a concrete, buildable plan. Be specific about Mercado Pago APIs and objects.\n\n${f.prompt}`, { label: `plan:${f.key}`, phase: 'Plan', schema: PLAN_SCHEMA }))) ).filter(Boolean)
log(`Plans: ${plans.length}`)

phase('Synthesize')
const doc = await agent(`Você é o arquiteto-líder de pagamentos. Escreva, em PT-BR e em Markdown, o blueprint financeiro do GraduaBJJ, pronto para implementação.\n\nPLANOS:\n${JSON.stringify(plans, null, 2)}\n\nAUDITORIA DO ESTADO ATUAL (MP, planos, métodos, avulsa):\n${ctx}\n\nEstrutura: 1) Diagnóstico do MP hoje (o que já funciona x o que falta p/ recorrência); 2) Assinatura recorrente tipo Netflix (mecanismo exato no Mercado Pago — preapproval/Assinaturas, dia de cobrança, fim após N meses, cartão tokenizado), modelo de dados, Cloud Functions + webhooks, fluxo do app; 3) Seleção de métodos de pagamento (cartão/PIX/ambos) por plano e cobrança; 4) Cobrança avulsa: confirmar/consertar a ligação com o checkout do MP e webhook; 5) Reaproveitamento da infra existente; 6) Roadmap em fases com esforço e dependências; 7) Riscos (falha de cobrança, retries/dunning, expiração de cartão, cancelamento, conciliação) e perguntas em aberto. Seja concreto e acionável — vira o blueprint de implementação financeira.`, { label: 'synthesize', phase: 'Synthesize' })

return { understandAreas: understand.map((u) => u.area), gaps: understand.flatMap((u) => (u.gaps || []).map((g) => g.title)), features: plans.map((p) => ({ feature: p.feature, effort: p.effort, openQuestions: p.openQuestions })), blueprint: doc }
