# SPEC — Onboarding Moderno (Dono + Aluno), branch `ux-ativacao`

Fecha os 9 gaps do scorecard. Cada decisão abaixo resolve uma ambiguidade específica do scorecard e cita o arquivo:linha que ela reusa ou altera. Nenhuma decisão fica em aberto para quem for implementar.

---

## 0. Decisões de arquitetura (resolvem as ambiguidades antes de qualquer tela)

**0.1 — Novo Wizard obrigatório pós-cadastro, rota `/admin/comece-aqui`, gate sem backfill.**
Mostra **se e somente se** `!hasClass && !hasStudent && !hasAttendance` — os mesmos três sinais que `ActivationChecklist` já computa (`lib/widgets/onboarding/activation_checklist.dart:101-120`, providers `classesProvider`/`_activationStudentsExistProvider:569`/`_activationAttendanceExistProvider:578`) — **e** o dono não tiver pulado antes. Isso evita qualquer migração: uma academia com qualquer progresso prévio (mesmo criada há anos) nunca vê o wizard. Dismissal persistido em `academies/{id}/settings/onboarding` campo `wizardSkippedAt` (doc novo, mesmo padrão de `dismissOnboardingStep`/`onboardingDismissedSteps` já usado por `SettingsService`/`academySettingsProvider`). Redirect no router segue o padrão já existente de `appBootstrapProvider`/`_LandingLatch` (`lib/providers/portal_providers.dart:186-199`) — não inventa um mecanismo de gate novo.

**0.2 — O aha (cobrança) mora dentro do wizard, com preview funcionando SEM Mercado Pago.**
Reusa `BillingNotificationService.applyMessageTemplate` + `defaultWhatsAppTemplates['D+1']` (`lib/services/billing_reminder_service.dart:714-721,1224-1237`). `injectPaymentInfo` (764-786) já remove o bloco `[[PIX]]…[[/PIX]]` quando não há PIX — então a bolha de WhatsApp renderiza **de verdade**, com dados de exemplo, mesmo antes do MP estar conectado. É o mecanismo exato que resolve "aha antes do MP connect" sem nenhuma lógica nova de template.
Ativar a automação reusa literalmente os dois setters que o dialog de Configurações já chama juntos (`billing_reminders_screen.dart:2563-2584`): `BillingReminderService.saveNotificationSettings(...)` (`whatsappEnabled`+`includePaymentLink`, doc `settings/billingReminders`) e `.setAutoTuitionEnabled(true)` (doc `settings/billing`, `billing_reminder_service.dart:556-563`). Só muda **onde** esse toggle aparece pela primeira vez.

**0.3 — "Cobrança-teste no SEU WhatsApp" — reuso quase total, zero contaminação de dados financeiros.**
Client cria um financial sintético com `status:'test'` (nunca `'pending'`/`'overdue'`) e **sem** `referenceMonth` real. `BillingReminderService.getOverdueWithStages` só inclui `status=='overdue'||status=='pending'` (`billing_reminder_service.dart:239`) e `getByMonth`/`generateMonthlyTuitions` (`payment_service.dart:444-460,863-991`) filtram por `referenceMonth` exato — então o registro de teste é automaticamente invisível em toda tela financeira, sem nenhum filtro novo. Se MP conectado, gera PIX real via `MercadoPagoService.createPixPayment` (`lib/services/mercado_pago_service.dart:56-84`) apontando pro doc de teste; se não, segue com PIX vazio (mesma degradação graciosa de produção). Envio via `BillingNotificationService.sendWhatsApp` (`billing_reminder_service.dart:882-953`) — é um POST autocontido pro proxy externo, `studentId`/`financialId` são só metadados soltos (sem lookup server-side), logo IDs sintéticos são seguros. Telefone-alvo: `Academy.phone`; se vazio, pede inline 1x e persiste.

**0.4 — CF `decideJoinRequest` passa a ler `academy.profile` (o bug crítico do scorecard).**
Em `functions/index.js:660-684` (branch `createNew`), 1 leitura adicional de `academies/{academyId}` campo `profile` antes do `tx.set`. `fitness` → grava `sports:['musculacao'], primarySport:'musculacao'`, **sem** `currentBelt`/`currentStripes`/`sportData` (mesma lógica que `auth_provider.dart:521-525` já usa ao criar a conta da academia). `fight`/`hybrid` → comportamento **idêntico ao atual**, zero regressão. Isso corrige em cascata o filtro de `musculacao_admin_screen.dart:49` sem tocar nessa tela.

**0.5 — `showsBeltCulture` ganha 1 call site real.**
`lib/screens/fighter/lutador_hub_screen.dart`, `_Header(...)` (chamado linha 138): condicionar a linha de faixa/grau a `academyVocabProvider`-derivado `showsBeltCulture`. A provider já é lida na mesma tela (linha 108) pro fallback de nome — é adicionar 1 condicional a um widget que já tem o dado em mãos, sem plumbing nova.

**0.6 — Checklist ganha profile-awareness de graça.**
`ActivationChecklist` já lê `academySettingsProvider` (linha 73), cujo `AcademySettings.profile` (`lib/services/settings_service.dart:303,476`) hoje é ignorado. Passa a computar `final profile = AcademyProfileExtension.fromString(settings.profile);` e usar em dois pontos: esconder "Crie sua 1ª turma" quando `profile == fitness`; inserir o novo passo "Ative a cobrança automática".

**0.7 — Novo provider leve para status de automação (usado por checklist, dashboard e wizard).**
`billingAutomationStatusProvider` — `FutureProvider` que combina `BillingReminderService(academyId).getNotificationSettings()` (`whatsappEnabled`) + `.getAutoTuitionEnabled()`. Não existe hoje fora de `billing_reminders_screen.dart._loadData` (linhas ~90-105) — extrair para provider compartilhado é o único jeito limpo de reusar esse estado em 3 telas diferentes sem 3 leituras redundantes.

---

## 1. Fluxo do DONO, tela a tela

### 1.0 Cadastro — **inalterado**
`lib/screens/auth/create_academy_screen.dart:781-830` — picker "Que tipo de academia?" já existe e já funciona bem. Não mexer (menos é mais: não retrabalhar o que já está certo).

### 1.1 Wizard "Comece em 3 minutos" — `/admin/comece-aqui` (NOVO)

Layout comum a todos os passos: 1 tela cheia, 1 ação primária óbvia (preto, full-width), 1 link secundário discreto "Pular"/"Agora não". Barra de progresso fina no topo (3-4 passos conforme perfil). Nenhum passo pede mais de 1 campo obrigatório.

#### FIGHT / HYBRID

**Passo W1 — "Crie sua turma de hoje"**
- Reusa **exatamente** a UI e a lógica de `_showQuickCreateClassSheet` (`lib/screens/admin/attendance_screen.dart:998-1150+`): campo único "Nome da turma", horário/dias colapsados em "Mais opções" (não travar o professor aqui — mesma decisão já documentada no comentário da linha 993-997). Promovida de bottom-sheet-dentro-da-chamada para tela cheia do wizard.
- Copy: título "Crie sua turma de hoje" · subtítulo "Só o nome — dá pra editar tudo depois." · placeholder "Ex.: Turma das 19h".
- CTA primário: "Criar e continuar". Sem CTA de pular (turma é pré-requisito mecânico da chamada nesse perfil).
- Reuso de service: `ClassService(academyId).create(name:, schedule:)` — mesma chamada de `attendance_screen.dart:1048-1060`.
- Taps-alvo: **2** (nome + criar).

**Passo W2 — "Quem treina hoje?"**
- Se já existem alunos sem turma: lista com checkbox, **todos pré-marcados** (mesmo padrão `enrollAllStudents` de `attendance_screen.dart:1005,1062-1068`).
- Se não existe nenhum aluno: campo rápido "Nome + telefone", botão "Adicionar mais" em loop — reusa a MESMA função de 1-toque já citada no diagnóstico do dono (`attendance_screen.dart:893-911`); não duplicar esse fluxo.
- Copy: "Quem treina hoje?" · "Marque quem já é seu aluno — o resto você adiciona depois."
- CTA secundário: "Pular, adiciono depois" → segue pro W3 sem bloquear.
- Taps-alvo: **1** (confirmar pré-marcados) a N (cadastro do zero).

**Passo W3 — COBRANÇA (o aha) — ver seção 1.2, comum a todos os perfis.**

**Passo W4 — "Sua primeira chamada"**
- Abre `attendance_screen.dart` **pré-filtrada** na turma criada em W1, com os alunos de W2 já matriculados. Zero mudança na mecânica da chamada em si (já é 1 tap por aluno).
- Banner leve no topo: "Toque no nome de quem chegou." — some após o 1º toque.
- Ao concluir (ou pular): bottom-sheet de celebração leve — reusa `Celebration.confetti(context)` (`lib/widgets/polish/celebration.dart:23`, já usado em `qr_scan_screen.dart:454` e outras 8+ telas) em vez de inventar uma engine de confete nova.
- CTA final: "Ir para o Painel" → `context.go('/admin')`, marca `wizardSkippedAt`/conclusão.
- Taps-alvo: **1 por aluno presente** + 1 (fechar celebração).

#### FITNESS

Sem conceito de turma — reforça o pivô ("sem-faixa, sem-turma"). Wizard de **2 passos** em vez de 4.

**Passo W1 — "Convide quem já treina com você"**
- Mostra o código único da academia (`joinCode`, já usado em `submitJoinRequest`, `functions/index.js:469-476`) com botão compartilhar (share_plus, já usado no app para códigos de convite).
- Copy: "Convide seus alunos" · "Compartilhe o código — eles se cadastram sozinhos e você só aprova."
- CTA secundário: "Prefiro cadastrar eu mesmo" → mesmo add-rápido do W2 fight.
- Taps-alvo: **1** (compartilhar) ou N (cadastro manual).

**Passo W2 — COBRANÇA (o aha) — idêntico ao W3 do fight, seção 1.2.**

**Tela final — "Pronto! O check-in já está ativo"**
- Informativa, sem ação obrigatória: `studentCheckinEnabled` já nasce `true` na criação da conta (`lib/providers/auth_provider.dart:516`) — não precisa de toggle aqui, só mostrar o que o aluno vai ver (preview do botão CHECK-IN do hub do lutador).
- CTA: "Ir para o Painel".

#### HYBRID
Segue o fluxo FIGHT integralmente (turma + chamada) — hybrid mantém vocabulário e mecânica `fight` por decisão já registrada em `core/academy_vocab.dart:106-111` (`_hybrid = _fight`). Zero trabalho extra: hybrid não precisa de um terceiro conjunto de telas.

---

### 1.2 Passo COBRANÇA (comum a fight/hybrid/fitness) — o aha

Extraído como **componente único reusável** `BillingActivationStep` (novo widget), usado pelo wizard (W3/W2 acima) **e** pelo passo novo do checklist (seção 1.3) — não duplicar essa tela em dois lugares.

**Copy:**
- Título: "Como vai funcionar a cobrança"
- Subtítulo: "Quando o aluno atrasar, o app manda essa mensagem sozinho pelo WhatsApp."
- Bolha de chat (fundo verde-claro, estilo WhatsApp) renderizando **de verdade** `BillingNotificationService(academyId, academyName).applyMessageTemplate(defaultWhatsAppTemplates['D+1'], 'Aluno (exemplo)', valor, DateTime.now(), 1, pixCode: null, ticketUrl: null)` — valor vem de `activePlansProvider` se já existir um plano; senão 1 campo inline "Quanto custa sua mensalidade?" pré-preenchido `R$ 150,00`.
- Se sem PIX (MP não conectado): legenda pequena abaixo da bolha — "Sem código PIX ainda. Conecte o Mercado Pago quando quiser para incluir o pagamento automático."
- Dois switches inline (pré-marcados **ON** nesta tela — só aqui o default muda de OFF pra ON, porque é o próprio ato de "ativar" que o dono está decidindo):
  - "Cobrar automaticamente pelo WhatsApp" → `whatsappEnabled`
  - "Gerar a mensalidade sozinha todo mês" → `autoTuitionEnabled`
- CTA primário preto: **"Ativar cobrança automática"** → `BillingReminderService(academyId).saveNotificationSettings(BillingNotificationSettings(whatsappEnabled:true, includePaymentLink:true))` + `.setAutoTuitionEnabled(true)` (mesmos dois setters de `billing_reminders_screen.dart:2563-2584`).
- CTA secundário texto: "Agora não, prefiro cobrar na mão" → não escreve nada, segue o wizard com os toggles OFF (comportamento atual preservado).
- Link terciário: "Testar essa mensagem no meu WhatsApp agora" → abre o fluxo 0.3 (funciona independente de ter ativado ou não).
- Taps-alvo: **1** (ativar) a **3** (ativar + testar + confirmar telefone se vazio).

---

### 1.3 Checklist "Comece por aqui" — reordenado + 1 passo novo

`lib/widgets/onboarding/activation_checklist.dart:122-176`. Nova ordem (money-first, por diretiva já registrada em `docs/b2c/ATIVACAO_PROFESSOR_2026-07.md` linha 47):

| # | id | Título | Visível quando | `done` | Mudança |
|---|----|--------|-----------------|--------|---------|
| 1 | `profile` | Perfil da academia | sempre | igual hoje | inalterado |
| 2 | `class` | Crie sua 1ª turma | `!profile.isFitness` | igual hoje | **NOVO**: escondido para fitness (0.6) |
| 3 | `plan` | Planos e mensalidade | sempre | igual hoje | inalterado |
| 4 | `billing` | **Ative a cobrança automática** | sempre | `billingAutomationStatusProvider.whatsappEnabled == true` | **NOVO** — subtítulo "Mensagem de WhatsApp com PIX, sozinha, quando o aluno atrasar". Rota: `/admin/comece-aqui/cobranca` (mesmo `BillingActivationStep` de 1.2). `dismissible: true` |
| 5 | `mp` | Conecte o Mercado Pago | sempre | igual hoje | subtítulo atualizado: "Para incluir PIX automático nas cobranças e receber online" (deixa claro que WhatsApp funciona sem MP) |
| 6 | `students` | Cadastre seus alunos | sempre | igual hoje | inalterado |
| 7 | `attendance` | Registre a 1ª presença/check-in | sempre | igual hoje | copy condicional: "check-in" para fitness (usa `vocab`), "presença" para fight/hybrid — texto, sem mudança de lógica |

Isso vale tanto para academias novas que passaram pelo wizard (checklist já nasce com o passo 4 concluído) quanto para as **existentes** que nunca verão o wizard — é o único jeito de a decisão do dono chegar à base instalada.

### 1.4 Dashboard — banner de automação (sem mudar o CTA primário diário)

`lib/screens/admin/admin_dashboard_screen.dart` — o CTA primário "Chamada" (`_buildQuickActions`, linha 317-356) **permanece Chamada**: é a ação operacional diária real do professor, em qualquer perfil, e sobrescrevê-la destruiria o hábito que o app já ensinou. O que resolve a crítica do scorecard é diferente: adicionar, logo abaixo do `ActivationChecklist` (linha 136-139) e **antes** de `_buildQuickActions`, o banner de automação **reusado 1:1** de `billing_reminders_screen.dart:327-371` (`_buildAutomationBanner`), gated por `!billingAutomationStatusProvider.whatsappEnabled`. Ele some sozinho assim que a cobrança é ativada (mesma lógica condicional que já existe). Isso garante que o aha não vire um evento único e esquecível do dia 1 — ele persiste visível até o dono realmente decidir (ligar ou dispensar via checklist).

---

## 2. Fluxo do ALUNO, tela a tela

### 2.0 Register → "Tenho código de acesso" — **inalterado**
`lib/screens/auth/register_screen.dart:106`. 1 tap.

### 2.1 Inserir código → CF `submitJoinRequest`
`functions/index.js:462-543`. **Mudança única**: logo após `await reqRef.set(payload, {merge:true})` (linha 528), adicionar `await notifyAdminCF(academyId, 'join_request_new', 'Nova solicitação', '${fullName} pediu para entrar na sua academia', {studentId: null})` — reusa o helper já usado em 15+ pontos do backend (`functions/server_functions.js:636-655`). Fecha o gap "zero push" do scorecard sem CF nova.

### 2.2 Tela "aguardando aprovação" — **inalterada, é ponto forte (score 7)**
`lib/screens/fighter/lutador_hub_screen.dart` — `_pendingHero` (211-249) + `_whileWaitingCard` (253-275). Não mexer.

### 2.3 Radar do dia do professor ganha visibilidade da fila (NOVO)
`lib/screens/admin/widgets/dashboard_radar_sections.dart` — nova seção reusando o componente `_Section` já existente (linha 22+), mostrando `pendingJoinRequestsCountProvider` (`lib/providers/join_request_providers.dart:44`) quando `> 0`, linkando para `/admin/alunos/solicitacoes` (mesma rota do botão já existente em `students_list_screen.dart:452`). Não duplica o badge de Alunos — só adiciona um segundo ponto de descoberta, que hoje não existe fora dessa aba.

### 2.4 Professor aprova — `join_requests_screen.dart` (UI inalterada)
Só o **backend** muda (`decideJoinRequest`, decisão 0.4).

### 2.5 Primeira sessão pós-aprovação — `lutador_hub_screen.dart`
Header (`_Header`, linha 138) some faixa/grau quando `!showsBeltCulture` (decisão 0.5). Resto do hub (streak, missão, `_FirstStepCard`) já é agnóstico o bastante via `vocab.comebackHeadline`/`hubLabel` — não mexer.

### 2.6 Efeito cascata corrigido automaticamente
`lib/screens/admin/musculacao_admin_screen.dart:49` filtra por `sports.contains(SportId.musculacao)` — assim que 0.4 estiver no ar, o aluno fitness aparece ali sem nenhuma mudança nessa tela.

---

## 3. O que cortar/adiar

- **Não pedir horário/dias da turma no W1** — mantém colapsado em "Mais opções" (decisão já documentada no código, `attendance_screen.dart:993-997`: exigir isso aqui trava o professor).
- **Não editar templates de mensagem no wizard** — edição de texto cru continua só em Configurações avançadas (`billing_reminders_screen.dart:2447-2464`), nunca exposta no fluxo de ativação.
- **Não incluir canal Email no wizard** — só WhatsApp+PIX é o flagship validado; Email fica em Configurações, fora do caminho crítico.
- **Não forçar conexão do Mercado Pago no wizard** — decisão explícita do dono: MP vem depois do aha. O preview funciona sem ele (0.2); o passo MP continua isolado no checklist (posição 5).
- **Não perguntar "quanto custa a mensalidade" se já existe plano** — puxar de `activePlansProvider`; só perguntar quando a academia realmente não tem nenhum plano ainda (evita redundância e mais um campo).
- **Não adicionar toggle de modo de check-in (manual vs QR) no wizard fitness** — fica no default atual (`musculacaoCheckinMode`), fora do escopo do dia 1.
- **Não crescer o checklist além de 1 passo novo** — a literatura (Userpilot 2025, 19,2% de conclusão média) indica que checklist mais longa converte pior; resistir à tentação de adicionar mais itens "enquanto está mexendo".
- **Adiar validação forte de CPF/CNPJ no cadastro** — já sinalizado como P2 de menor prioridade no diagnóstico anterior (`docs/b2c/ATIVACAO_PROFESSOR_2026-07.md` linha 65); fora do escopo desta spec de onboarding, não bloquear a fatia de cobrança por causa disso.
- **Não criar uma segunda tela de "adicionar aluno" no wizard** — reusar a mesma função de 1-toque que a Chamada já usa (`attendance_screen.dart:893-911`); duplicar esse fluxo é dívida técnica desnecessária.

---

## 4. Ordem de implementação em fatias aditivas

Cada fatia é shippable e testável isoladamente; academias existentes ficam intocadas até a fatia que as afeta ser explicitamente descrita.

**Fatia 1 — Correção de dado no backend (sem UI).**
`decideJoinRequest` lê `academy.profile` (0.4). Fight/hybrid: comportamento idêntico. Fitness: grava `sports:['musculacao']` corretamente. Zero risco de regressão; corrige só cadastros **futuros** (backfill de fichas fitness já erradas é um script separado, fora desta spec).

**Fatia 2 — Hub do aluno.**
`showsBeltCulture` no `_Header` (0.5). Puramente condicional sobre dado já disponível na tela.

**Fatia 3 — Checklist atualizado (sem wizard ainda).**
Reordena + esconde `class` para fitness + adiciona passo `billing` (seção 1.3) + novo `billingAutomationStatusProvider` (0.7). **Esta fatia sozinha já entrega o aha pra base instalada inteira**, sem esperar pelo wizard.

**Fatia 4 — Banner no Dashboard.**
Reusa `_buildAutomationBanner` no Dashboard (1.4), gated pelo mesmo provider da Fatia 3.

**Fatia 5 — Componente `BillingActivationStep`.**
Extrai o conteúdo do passo COBRANÇA (1.2) como widget único, usado hoje só pelo link do checklist (Fatia 3) — prepara o terreno para o wizard sem repetir código.

**Fatia 6 — "Cobrança-teste no seu WhatsApp".**
Financial sintético + `sendWhatsApp` (0.3). Aditiva, opcional, acessível a partir do `BillingActivationStep` e do banner de `/admin/cobranca`.

**Fatia 7 — Wizard completo `/admin/comece-aqui` + gate de redirect.**
Monta os passos por perfil (seção 1.1) reusando as Fatias 5+6 e os componentes já existentes (`_showQuickCreateClassSheet`, add-rápido de aluno). Gate explícito (0.1) garante que só academias genuinamente vazias o veem — zero risco pra base instalada.

**Fatia 8 — Push + Radar do dia para solicitações pendentes.**
`notifyAdminCF` em `submitJoinRequest` (2.1) + seção nova em `DashboardRadarCard` (2.3).

**Fatia 9 — Instrumentação (seção 5).**
Não é uma fatia isolada no fim — cada evento entra junto da fatia que o gera (ex.: `wizard_step_viewed` nasce com a Fatia 7, `billing_automation_enabled` nasce com a Fatia 3).

---

## 5. Métricas de ativação a instrumentar

Eventos concretos (client + CF), todos com `academyId` e `profile`:

- `academy_created {profile}`
- `join_request_submitted {academyId}` / `join_request_approved {academyId, minutesToApproval, profile}` (fecha o "canal com tração comprovada é o aluno" do doc anterior)
- `checklist_step_billing_viewed` / `billing_automation_enabled {source: 'checklist'|'wizard'|'settings', whatsappEnabled, autoTuitionEnabled}` / `billing_automation_test_sent {hasPix}`
- `wizard_started` / `wizard_step_viewed {step}` / `wizard_step_skipped {step}` / `wizard_completed` / `wizard_abandoned {lastStep}`
- `first_class_created {source: 'wizard'|'chamada_empty_state'|'turmas'}` (a fonte distingue o CTA já existente do wizard novo)
- `first_attendance_recorded {minutesSinceAcademyCreated}` — a métrica-mestra já sugerida no diagnóstico anterior (`docs/b2c/ATIVACAO_PROFESSOR_2026-07.md` linha 173)
- `owner_d1_return` / `owner_d7_return`
- Sentinela derivada (não é evento, é query agendada): **"estado Kimura"** — academias com `students>0` E (`classes==0` OU todas as turmas com `studentIds` vazio) — conceito já definido no doc anterior (linha 174); deve tender a zero em contas novas pós-Fatia 7.

---

**Arquivos centrais para quem for implementar** (releitura rápida antes de começar):
`lib/widgets/onboarding/activation_checklist.dart`, `lib/screens/admin/admin_dashboard_screen.dart`, `lib/screens/admin/billing_reminders_screen.dart` (linhas 322-371 e 2217-2420), `lib/services/billing_reminder_service.dart` (classes `BillingReminderService` 183-567 e `BillingNotificationService` 665-1340), `lib/services/mercado_pago_service.dart`, `functions/index.js` (linhas 462-543 e 574-756), `lib/models/academy.dart` (254-430), `lib/core/academy_vocab.dart`, `lib/screens/fighter/lutador_hub_screen.dart` (80-275), `lib/screens/admin/attendance_screen.dart` (977-1150), `lib/screens/admin/student_form_screen.dart` (1563-1866), `lib/core/navigation/nav_catalog.dart`.

---

## Scorecard

- Time-to-value (dono): 3/10 — O aha real que o dono decidiu priorizar — cobrança automática com preview de WhatsApp+PIX — não existe em nenhuma tela (grep confirmado: zero hits fora de node_modules para preview/teste de cobrança). O que existe hoje: register → create_academy_screen → AdminShell → CTA primário 'Chamada' (admin_dashboard_screen.dart:319-328, isPrimary:true) → checklist de 6 passos onde 'Registre a 1ª presença' é o ÚLTIMO (activation_checklist.dart:166-173). Isso é o oposto do padrão validado (aha em <5min, na 1ª sessão) e do que o próprio dono pediu.
- Nº de decisões antes do aha (dono): 4/10 — Sem wizard forçado, o dono precisa decidir/executar sozinho: nome+logo → criar turma → criar plano → (opcional MP) → cadastrar aluno → registrar presença — 5-6 decisões sequenciais e nenhuma delas é 'ligar cobrança automática', que fica 2 telas + 1 diálogo abaixo (Dashboard→Financeiro/Cobrança→banner 'Ligar'→dialog com 2 switches, billing_reminders_screen.dart:322-371 + _showSettingsDialog ~2217+). Autópsia citada no próprio contexto (19/36 mortes no setup sem 1ª chamada) mostra que o funil atual já falhava nisso mesmo antes da automação virar prioridade.
- Aha engineering — cobrança automática: 1/10 — Decisão do dono zero implementada. CTA primário do dashboard continua 'Chamada' (admin_dashboard_screen.dart:319-328); checklist não tem passo de cobrança/WhatsApp; nenhuma tela renderiza {nome}/{valor}/{pix} preenchidos fora de um envio real — o preenchimento real só roda dentro de _runBulkSendCore no momento do disparo (billing_reminder_service.dart), nunca antes. Pior: mesmo pelo caminho manual, a tela de Cobrança fica vazia no dia 1 porque getOverdueWithStages descarta vencimentos futuros (billing_reminder_service.dart:251 'if (daysOverdue < 0) continue') — não há atalho técnico para forçar uma demo no dia do cadastro. A ideia 'Cobrança-teste no SEU WhatsApp' já estava desenhada em doc interno (02/jul) e segue não-construída.
- Adequação à persona não-técnica / generalismo (fitness vs luta): 2/10 — O picker 'Que tipo de academia?' (Wave A) é cosmético: `isFitness`/`showsBeltCulture` (academy.dart:425,430) e AcademyVocab só são lidos em 3 telas do ALUNO (lutador_hub_screen.dart:108, diario_screen.dart, portal_shell.dart:248) — verificado: zero ocorrências em admin_dashboard_screen.dart, activation_checklist.dart e nav_catalog.dart. `showsBeltCulture` tem ZERO call sites em todo o repo (grep confirmado). Pior ainda no lado servidor: decideJoinRequest (functions/index.js linha ~664-676) grava `sports:['bjj'], currentBelt:'white'` para TODO self-onboarding novo, mesmo numa academia 100% fitness, sem NUNCA ler `academy.profile` — contradiz o próprio comentário de arquitetura em academy.dart:254-267 ('No belt/grade culture should surface... for fitness'). Efeito em cascata: esse aluno some da tela de gestão de Musculação (musculacao_admin_screen.dart:49 filtra por `sports.contains(musculacao)`) e o header do hub do aluno mostra faixa/grau incondicionalmente (lutador_hub_screen.dart:136-146, chamado antes de qualquer branch condicional).
- Empty states / dado populado vs formulário vazio: 2/10 — Padrão validado no benchmark (Autopilot/demo journeys) é mostrar dado preenchido antes de pedir configuração real. O app faz o oposto no ponto mais crítico: o diálogo de config de cobrança mostra só o TEMPLATE CRU com placeholders literais {nome}/{valor}/{pix} (TextFormField, billing_reminders_screen.dart ~2447-2464), nunca uma prévia renderizada com dados de exemplo. Tela de Cobrança em si fica vazia no dia 1 (nenhum overdue possível ainda). Nenhuma tela do fluxo usa dados-amostra fixos para mostrar 'como vai ficar' antes de o dono configurar de verdade.
- Onboarding do aluno — UX de espera: 7/10 — Ponto forte real: self-log 'Treinei' funciona sem ficha/academia (dá valor real durante a espera) e a tela 'aguardando aprovação' é honesta, sem prazo prometido (lutador_hub_screen.dart: branch `pending != null` → `_pendingHero` + `_whileWaitingCard`). Gap fica na descoberta pelo professor: zero push, zero presença no dashboard 'Radar do dia' — só um badge dentro de Alunos, então a fila pode ficar invisível para o dono horas/dias, quebrando a promessa implícita de aprovação rápida.
- Checklist como mecanismo de ativação: 3/10 — Literatura (Userpilot 2025, 188 empresas) mostra conclusão média de checklist de só 19,2% — checklist sozinha não força comportamento. O app tem só checklist (activation_checklist.dart, 6 passos, dismissible só no MP linha ~156) sem nenhum wizard guiado que force a 1ª ação em sequência curta. Passo de cobrança automática nem existe na lista — o benchmark pede exatamente o wizard 'primeira chamada/cobrança em 3 minutos' já desenhado em docs/b2c/ATIVACAO_PROFESSOR_2026-07.md §3 mas não implementado nesta branch.
- Diferenciação vs. concorrência BR (Tecnofit/EVO/RegyBox): 5/10 — Nenhum concorrente BR pesquisado oferece self-serve puro (todos exigem CS/treinamento/call Zoom antes do trial) — nisso o GraduaBJJ já larga na frente estruturalmente (sem call humana obrigatória). Mas essa vantagem estrutural não está sendo capitalizada: sem o wizard de 3min + aha de cobrança, o app desperdiça a única alavanca que o tornaria realmente mais rápido que os incumbentes — hoje é 'self-serve mas lento/confuso', não 'self-serve e rápido'.
- Becos/erros corrigidos nesta wave (crédito onde é devido): 7/10 — Os dois becos literais do diagnóstico anterior foram de fato fechados: Chamada com 0 turmas agora tem CTA 'Criar minha primeira turma' com sheet 1-campo + matricular-todos pré-marcado; form de aluno agora matricula em turma via chips com pré-seleção. Isso reduz fricção mecânica real. Não é suficiente sozinho porque não toca nas duas decisões estratégicas (aha=cobrança, generalismo fitness) que são o cerne do pivô atual.
- Mobile UX / fricção de toques: 6/10 — Onde os fluxos existem (turma, matrícula, checklist), a mecânica em si é enxuta (sheet 1-campo, chips pré-marcados, 1 dialog). O problema não é a UX local de cada tela — é a ausência de uma sequência guiada que amarre as telas certas na ordem certa; hoje o dono navega por menu livre, não por wizard, então o custo cognitivo de 'o que fazer agora' fica alto mesmo com telas individualmente rápidas.

## Veredito

Não, não está moderno nem eficiente o suficiente — e a lacuna não é de polimento, é estratégica: as duas decisões que o próprio dono tomou (aha=cobrança automática com preview real de WhatsApp+PIX; generalismo fitness sem jargão de faixa) têm zero implementação verificável no código desta branch, apesar da Wave A ter corrigido de verdade os dois becos mecânicos do diagnóstico anterior (chamada sem turma, aluno sem turma). Concretamente: o CTA primário do dashboard continua sendo 'Chamada' (admin_dashboard_screen.dart:319-328, isPrimary:true) e não cobrança; o checklist de 6 passos não tem nenhum passo de cobrança/WhatsApp e ainda deixa 'Registre a 1ª presença' por último (activation_checklist.dart:166-173); nenhuma tela do repo renderiza uma mensagem de WhatsApp com {nome}/{valor}/{pix} preenchidos fora de um envio real (grep confirmado, zero hits); e a tela de Cobrança fica estruturalmente vazia no dia 1 porque a query descarta vencimentos futuros (billing_reminder_service.dart:251). No lado do aluno, o problema é mais grave que cosmético: o picker 'Que tipo de academia?' não tem nenhum call site na área admin nem no backend — a Cloud Function de aprovação (functions/index.js ~664-676) grava BJJ/faixa-branca em TODO aluno self-onboarded, inclusive academias 100% fitness, contradizendo o próprio comentário de arquitetura do modelo (academy.dart:254-267) e deixando esses alunos invisíveis na tela de gestão de Musculação. Contra o benchmark (aha em <5min/1ª sessão, dado populado > formulário vazio, checklist sozinha converte só 19,2%), o app está preso num modelo pré-pivô: turma-first, chamada-first, cego a profile — exatamente o oposto da direção que o dono já decidiu e documentou. A vantagem estrutural real (nenhum concorrente BR é self-serve puro) existe mas está sendo desperdiçada por falta do wizard forçado e do preview de cobrança, que são os dois investimentos que fechariam a lacuna."
