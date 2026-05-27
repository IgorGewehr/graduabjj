# Roadmap — Paywall / Assinatura (Cakto)

Status do paywall do GraduaBJJ e o que falta, organizado por fases pra ir
implementando aos poucos. Modelo de negócio: SaaS B2B, **só o dono paga**,
alunos usam grátis. Trial inicial de **7 dias** (`AppConstants.trialDays`,
aplicado a academias **novas**). Provedor: **Cakto** (recorrente).

Planos (produto "BJJEasy" no Cakto, 3 ofertas):
- Mensal R$ 89,99 — `pay.cakto.com.br/eo9omtc_889968`
- Trimestral R$ 224,99 — `pay.cakto.com.br/xisui3m`
- Anual R$ 854,99 — `pay.cakto.com.br/38yfe5r`

---

## 📍 Onde paramos (sessão de 2026-05-27)

- **Webhook `caktoWebhook`: no ar e validado** (evento de teste = 200). Secret
  real do Cakto = `e3386f97-69fd-4ec2-8ca3-d42d933fa3a7` (já setado em
  `CAKTO_WEBHOOK_SECRET`). `data` é array (`data[0]`), idempotência por `data.id`.
  Deploy feito pela conta `lanzanag@gmail.com` (projeto `arpjj-76350`).
- **Trial = `createdAt + 7` (autoritativo)** pra todas as academias; `trialEndsAt`
  antigo (30d) é ignorado. Pagantes/cortesia via `paidUntil`/`freeOverride`.
- **Teste do gate no emulador ficou pendente:** o emulador estava **sem
  internet** (Firestore offline, servindo cache antigo) → o paywall não atualizou.
  Resolver: religar a rede do emulador (cold boot) e testar de novo.
- **`trialExpiryReminder`** (e-mail de trial) escrita mas **deploy bloqueado por
  IAM** (conta é `functions.developer`, não `admin`).
- **`functions/.env`** tem `NOTIFICATION_API_KEY` (gitignored).
- Academia de teste: "Lobisomens Jiu Jitsu", id `nZJ00BMyGJ8xJGPQzVKL`, owner
  `yCcUbU5oxBQJrRhqyTIWB4sV4X43`. `createdAt` foi posto em 15/mai pra testar o gate.

## 🧭 Próximos passos (executar 1 por 1)

O núcleo (trial → paywall → checkout → webhook libera acesso, com desconto) já
funciona ponta a ponta. O que falta, em ordem:

1. [~] **Testar o webhook** — evento de teste do Cakto retorna **200 OK** ✅
   (secret + parsing + resolução por e-mail funcionando). Correções aplicadas:
   `secret` real do Cakto = `e3386f97-...` (o configurado "não afeta"); `data`
   é **array** (usa `data[0]`); `src`/academyId vem em `sck`. **Falta** uma
   **compra real** pra confirmar o grant (gravar `paidUntil`) e capturar os
   `offer.id` reais de cada plano.
2. [ ] **Observar na compra real + ajustar o webhook** (redeploy é update, dá
   pra fazer aqui):
   - **Sequência de eventos** — ver se a compra dispara só `purchase_approved`
     ou também `subscription_created` (e os `data.id` de cada). Já há
     idempotência por `data.id`; se vierem ids diferentes pra mesma cobrança,
     conceder só no `purchase_approved`.
   - **`offer.id` reais** → setar `CAKTO_OFFER_MENSAL/TRIMESTRAL/ANUAL` (hoje cai
     no fallback por nome da oferta, que já funciona).
   - **Nomes reais dos eventos de falha** → alinhar `pastDueEvents`.

> QA (pré-teste) aplicado: marca BJJEasy no paywall (logo + textos), idempotência
> por `data.id` no webhook, cosmético. Pendente de revisão à parte (fora do
> paywall): guard de papel nas rotas `/admin/*`.
3. [ ] **Deploy da `trialExpiryReminder`** (Fase 3, e-mail de trial) — precisa
   de conta **Owner** (IAM `functions.admin`). Bloqueado hoje.
4. [ ] **Commit/push** de todo o código local (Fase 1 + 2 + 3 + trial + createdAt).
5. [ ] **Marcar pagantes externos** (`paidUntil`/`freeOverride`) — lista do Igor.
6. [ ] **Nº real de WhatsApp de suporte** (trocar placeholder em `constants.dart`).
7. [ ] **Publicar a build** com o gate → liga o paywall pros usuários (após 5+6).

Opcionais / depois:
- [ ] **Push FCM** (feature média; hoje é stub — ver Fase 3).
- [ ] Preços no **Remote Config** (Fase 4).
- [ ] **Deep link** de retorno (deprioritizado — o gate já cai sozinho ao voltar).
- [ ] **Dívida técnica:** runtime Node 20 (descontinua out/2026), upgrade do
  `firebase-functions`, apagar o secret órfão `NOTIFICATION_API_KEY`.

---

## ✅ Já implementado

- [x] **Webhook Cakto** (`functions/index.js` → `caktoWebhook`): valida pelo
  `secret` do corpo, eventos `purchase_approved`/`subscription_created`/
  `subscription_renewed`/`refund`/`chargeback`/`subscription_canceled`, resolve
  academia por `src` (fallback e-mail→dono), `offer.id`→período, estende
  `paidUntil` sem encurtar renovação.
- [x] **Gate do admin** (`admin_shell.dart`): se `hasAccess == false`, troca a
  área admin pela paywall. Aluno (portal) não é afetado.
- [x] **Tela de paywall** (`paywall_screen.dart`): 3 planos, CTA abre checkout,
  "já paguei", suporte. Botão de fechar opcional (`showClose`).
- [x] **Checkout com identidade** (`paywall_screen.dart`): pré-preenche
  `?email=&confirmEmail=` (e-mail do admin) + `src=<academyId>`.
- [x] **URLs reais do Cakto** (`constants.dart`).
- [x] **Banner de trial** (`admin_shell.dart`): "Faltam X dias de trial" no topo
  do admin, vermelho nos últimos 3 dias, abre a paywall ao tocar.

---

## 🚩 Fase 0 — Bloqueadores de lançamento (antes de publicar build com o gate)

> Sem isso, ou trava academia que não devia, ou o pagamento não conclui.

- [x] **Trial ancorado em `createdAt` (substitui o script de migração geral)**
  - Trial efetivo = `trialEndsAt` explícito **OU** `createdAt + trialDays`
    (`AcademySubscription.effectiveTrialEndsAt`). Logo, **toda academia** (antiga
    ou nova) é tratada pela mesma regra: criada há +7 dias e sem pagar → paywall.
  - Sem `createdAt` E sem doc → mantém liberada (não bloqueia por falta de dado).
  - **Não precisa mais de script de migração** pra expirar trials da base legada.
- [ ] **Pagantes externos — marcar antes do deploy** — `CRÍTICO`
  - Quem pagou **fora do Cakto** (PIX/manual) não tem `paidUntil` → cairia no
    paywall pela regra acima. `hasAccess` já prioriza `paidUntil`/`freeOverride`
    sobre o trial, então **basta marcar** essas academias:
    - `subscription.paidUntil = <data paga até>` (recomendado — expira e migra
      pro Cakto na renovação), ou
    - `subscription.freeOverride = true` (cortesia/parceria indefinida).
  - **Depende do Igor** fornecer a **lista** de quem pagou externamente (só ele
    sabe). Passo manual/targetado no Firestore — não é script grande.
- [ ] **(Opcional) Janela maior pra base legada** — se quiser dar respiro, dá pra
  usar `createdAt + N` maior só pras antigas em vez de bloquear na hora.
- [ ] **Config do Cakto em produção** (Gustavo tem acesso ao painel Cakto; o
  deploy + secrets do Firebase é com o Igor)
  - [ ] `firebase functions:secrets:set CAKTO_WEBHOOK_SECRET`
  - [ ] Env dos offer IDs: `CAKTO_OFFER_MENSAL`, `CAKTO_OFFER_TRIMESTRAL`,
    `CAKTO_OFFER_ANUAL` (pegar via compra de teste)
  - [ ] Cadastrar a URL do webhook no painel Cakto + marcar os eventos
  - [ ] `firebase deploy --only functions:caktoWebhook`
- [ ] **Confirmar nomes reais dos eventos do Cakto** na doc deles (o filtro do
  webhook é restritivo; eventos não tratados retornam 200 sem ação).
- [ ] **Número real de suporte no WhatsApp** (`constants.dart:42` está com
  placeholder `wa.me/5500000000000`).

---

## 🟡 Fase 1 — UX essencial do fluxo de assinatura

- [x] **Banner "faltam X dias"** (feito).
- [x] **Polling pós-checkout** no botão "Já paguei" — loading + re-checagem por
  ~30s (lê o doc no servidor a cada 3s) aguardando `paidUntil`; o gate cai
  sozinho ao confirmar; timeout avisa "ainda processando".
- [x] **Desconto 50% no 1º mês (3 primeiros dias, só Mensal)** — `ALTA`
  - App: badge "-50% 1º mês" + preço riscado; quando `isTrialing && primeiros 3
    dias && plano Mensal`, anexa `?coupon=bonusbjjeasy` na URL do Mensal.
  - Cakto: cupom `bonusbjjeasy` (50%, só 1ª cobrança) já criado; aplica
    automático via URL (`?coupon=`, confirmado em teste). Recorrência segue
    R$ 89,99/mês. Controlado por `AppConstants.caktoMensalPromoCoupon`.

---

## 🟢 Fase 2 — Robustez e fluxo de retorno

- [x] **Rota `/paywall` no GoRouter** (`app.dart`) — rota navegável (showClose),
  usada pelo banner de trial (`context.push('/paywall')`) e disponível pra deep
  link. O gate do AdminShell continua renderizando inline.
- [~] **Tela "pagamento recusado" (`pastDue`)** —
  - [x] App: `PaywallScreen(pastDue: true)` com texto "atualize seu pagamento";
    o gate mostra essa variante quando `subscription.status == past_due`.
  - [x] Webhook: branch que marca `status: past_due` em eventos de falha de
    renovação (nomes **a confirmar** com evento real do Cakto — defensivos).
  - [ ] **Redeploy** do webhook com esse handler (vai junto com os offer IDs,
    após o teste de compra) + confirmar os nomes reais dos eventos de falha.
- [x] ~~Trigger `onAcademyCreate`~~ — redundante (trial ancorado em `createdAt`).
- [ ] **Deep link de retorno pós-pagamento** — `DEPRIORIZADO`: ao voltar do
  browser, o stream do `subscriptionProvider` reconecta e o gate **já cai
  sozinho** quando o webhook gravou o `paidUntil` (+ polling do "Já paguei"). O
  deep link só pouparia a troca de app — baixo ROI vs. config nativa (intent
  filters/universal links) + return URL no Cakto.

---

## 🔵 Fase 3 — Comunicação e retenção

- [~] **E-mail 2 dias antes de expirar o trial** — `trialExpiryReminder`
  (onSchedule diário 13:00 BRT) em `functions/index.js`. Busca academias com
  `subscription.trialEndsAt` em ~48h (sem pagar/override/já avisado), pega o
  e-mail do dono (Auth) e manda via notification-server (`/api/send-email`,
  appId `gestao-raiz` = SMTP do BJJEasy). Dedup via `subscription.trialReminderSentAt`.
  Chave em `functions/.env` (`NOTIFICATION_API_KEY`, gitignored).
  - [x] Código + validação (`node --check`).
  - [ ] **Deploy bloqueado por IAM**: a conta atual é `functions.developer` (não
    `functions.admin`) e não consegue setar o invoker da função agendada.
    **Igor** precisa: dar `roles/functions.admin` à conta **ou** rodar
    `firebase deploy --only functions:trialExpiryReminder`.
- [ ] **Push (FCM)** — não viável hoje: `push_notification_service` é stub (sem
  tokens). Feature separada e maior (cliente + APNs do iOS).
- [ ] **Lembretes de renovação / falha de cobrança** (recorrência).

> Nota: criei um secret `NOTIFICATION_API_KEY` no Secret Manager antes de
> trocar pra `.env` — ficou órfão/inofensivo (pode apagar depois).

---

## ⚪ Fase 4 — Configuração e escala

- [ ] **Preços/planos no Remote Config** (`constants.dart` → Firebase Remote
  Config) pra mudar preço sem publicar build.

---

## ⚠️ Notas técnicas (não esquecer)

- `hasSubscriptionAccessProvider` defaulta `true` em **loading** e **error** —
  sem flicker, mas falha de rede **não bloqueia** (porta dos fundos intencional).
- Trial é setado **no cliente** (não em CF) → ver Fase 2 (trigger).
- O **deploy da function não bloqueia ninguém**; o bloqueio só vale numa **build
  nova do app**.
- `subscription.plan = 'pro'` cai em `free` no enum (proposital): acesso é
  dirigido só pelo `paidUntil`, que expira certinho. **Não** setar
  `premium`/`enterprise` (dariam acesso permanente).
