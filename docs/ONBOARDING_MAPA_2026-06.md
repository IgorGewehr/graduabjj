# MAPA DE ONBOARDING PREMIUM — GraduaBJJ

> Base consolidada (PT-BR) para a fase de DESENHO + IMPLEMENTAÇÃO. Sintetiza jornadas por papel, momentos de valor, pontos de injeção técnica, persistência e inventário de design system. Verdade-norte: **o app já conhece o papel** (vem do convite/cadastro) → ramificar automaticamente, nunca perguntar "quem é você".

---

## 1. Resumo executivo

**Problema.** Hoje NÃO existe nenhum onboarding/tour em nenhum dos três papéis (confirmado por grep: zero hits de onboarding/tour/coachmark/spotlight em `lib/`). Os três caem "frios" na sua home, com tudo zerado (admin) ou sem explicação da mecânica central (aluno/professor). O resultado é abandono nos primeiros minutos e features de alto valor que ficam invisíveis atrás de feature-flags, gates de permissão e do 5º slot "Menu".

**Tese.** Onboarding **ramificado por papel**, interativo, skippable e persistido (some pra sempre ao concluir), desenhado contra o *aha moment* de cada persona — não contra "telas vistas":

| Papel | Aha moment | Padrão dominante | Métrica-norte |
|---|---|---|---|
| **Aluno** | Fazer/ver o 1º check-in e ver faixa+streak subir | Carrossel curto de valor (3 telas) + coachmark no check-in + confete + streak | % de 1º check-in em 48h |
| **Admin/dono** | Academia "viva": 1º aluno ativo + 1º pagamento | Checklist de ativação "Configure sua academia" com barra de progresso | time-to-first-active-student; time-to-first-payment |
| **Professor** | 1ª chamada da turma em segundos / 1ª graduação | Coachmark na chamada + destaque "marcar todos" + just-in-time na graduação | % de 1ª chamada no 1º acesso |

**Princípios transversais (2025/2026).** Time-to-value acima de tudo; value-first (não feature-first); progressive disclosure (just-in-time, não despejo inicial); tudo skippable e persistido; permissão de push pedida SÓ após o 1º valor; celebração (confete) reservada a ahas reais e marcos genuínos; todo empty state vira CTA que ensina.

**Restrições de arquitetura que moldam o desenho:**
- O papel "professor" está **partido em dois shells** (AdminShell vs Portal-monitor) conforme histórico/permissões — o onboarding precisa funcionar nos dois e não assumir um layout único.
- Persistência tem **grão diferente por papel**: aluno = por usuário (Firestore, cross-device); admin = por academia (evento único de setup).
- Visibilidade de features é altíssimamente variável (feature-flags + permissões + gates de portal) — o onboarding NÃO pode prometer telas que aquele usuário não tem.

---

## 2. Aluno — top funções a destacar (priorizadas)

**Loop de valor central:** treinar → check-in (presença) → ver streak/stats subir → progredir rumo à próxima faixa → competir/rankear. Pagamento e loja vivem na seção "Conta".

### Prioridade MUST-SHOW (núcleo do onboarding)
1. **Check-in / Presença** — `/portal/horarios` (check-in na janela) + `/portal/presencas` (histórico). É a AÇÃO CENTRAL.
   - *Aha:* tocar "Fazer check-in" → confete + streak e contador de treinos subindo na hora.
   - *Gate:* `studentCheckinEnabled`. Presenças sempre visível.
2. **Graduação / Faixa** — `/portal/graduacao` + `AnimatedBelt` no header da home.
   - *Aha:* animação da faixa varrer até o grau atual + barra "Faltam X aulas" enchendo → confete "Meta atingida!".
   - *Gate:* belt no header sempre; card+checklist exigem `autoGraduationEnabled` + `graduationProgressVisibleToStudents`.
3. **Financeiro / Mensalidade** — `/portal/financeiro`.
   - *Aha:* pagar via PIX em segundos sem falar com a recepção; cobrança vira "paga".
   - *Gate:* portalGate `hasPlan` (some se aluno sem plano) + `isPaymentEnabled`.

### Prioridade NICE-TO-SHOW (mencionar, não centralizar)
4. **Ranking de Turmas** — `/portal/ranking` (`rankingVisibleToStudents`). Competição saudável que puxa frequência.
5. **Competições / Campeonatos** — `/portal/competicoes` (sempre). Countdown "faltam X dias" + inscrição + medalha no perfil.
6. **Jornada + Jornal/Eventos** — `/portal/linha-do-tempo` (sempre) + `/portal/jornal` (`journalVisibleToStudents`). Pertencimento e descoberta de eventos.
7. **Perfil + Perfil público** — `/portal/perfil` (`isProfilePublic` p/ visibilidade externa). "Cartão de visita" de atleta.

### SECONDARY (não tocar no onboarding inicial)
8. Loja (`storeEnabled` + `storePublished`) · 9. Reservar aula (`bookingEnabled`) · 10. Evolução física (`physicalEvolutionEnabled`).

### Pain points de 1º acesso (o onboarding precisa resolver)
- **Check-in invisível fora da janela** (30min antes → 1h depois): quem abre em outro horário não descobre que existe nem onde fazer → **coachmark deve ensinar ONDE fica, mesmo sem janela aberta**.
- **Menu altamente variável**: features importantes escondidas no 5º slot "Menu" (bottom sheet) → o carrossel deve apontar onde mora cada coisa, mas só prometer o que o gate liga.
- **Conta não vinculada** (`currentStudentProvider == null`): home genérica "Aluno", heroes vazios, "Perfil não vinculado" → beco sem saída. Onboarding deve detectar e orientar a vincular (Código de equipe).
- **Flags desligadas viram dead-ends** ("Indisponível — instrutor não habilitou") → não destacar features gateadas-OFF.
- **Financeiro some sem plano** (portalGate `hasPlan`) → não prometer pagamento se não há plano.
- **Multimodalidade sutil**: pílula "{n} modalidades" e seletor de esporte (troca faixa/ranking/presenças) pouco evidentes → vale 1 coachmark se multiSport.
- **Mudança súbita de layout** ao virar monitor (Chamada/Alunos no lugar de Horários/Presenças) sem aviso.

---

## 3. Admin — checklist de ativação (caso mais crítico)

**Aha moment:** academia "viva" — 1º aluno dentro + 1ª presença/pagamento. Tela "0 alunos / 0 receita" = abandono garantido.

**Padrão:** **Checklist de ativação "Configure sua academia"** fixo no topo do dashboard, com barra de progresso (padrão Slack/Notion/Stripe). NÃO carrossel. Cada item abre o fluxo e volta marcando concluído; checklist some/colapsa em 100%.

### Ordem de ativação real (dependências encadeadas hoje IMPLÍCITAS)
A sequência abaixo respeita os pré-requisitos ocultos: chamada exige turma; cobrança exige plano; receber dinheiro exige MP conectado **+ KYC aprovado + chave PIX**.

**Checklist proposto (☐ 0/6):**
1. ☐ **Complete o perfil da academia** (nome, logo, modalidades) — `/admin/configuracoes`.
2. ☐ **Crie sua 1ª turma/horário** — `/admin/turmas` (FAB "Nova Turma"). *Pré-requisito da chamada.*
3. ☐ **Configure planos e mensalidade** — `/admin/financeiro` aba Planos (mostra "Receita esperada/mês"). *Pré-requisito da cobrança.*
4. ☐ **Conecte o Mercado Pago** — `MercadoPagoConnectScreen` (OAuth full-screen, confete em "Conectado!"). **O MAIOR aha econômico** (dinheiro cai direto na conta, sem taxa da plataforma) — hoje ENTERRADO em Configurações. **Elevar ao checklist é a recomendação #1.** Sinalizar KYC + chave PIX como sub-etapa.
5. ☐ **Convide seus alunos** — Código de equipe `/codigo-equipe` (share WhatsApp/link). *Alavanca de rede — sem isso, alunos cadastrados não acessam o portal.*
6. ☐ **Registre a 1ª presença** — `/admin/chamada` (exige turma criada). O uso diário que prende a academia ao app.

> **Item "Ligar funcionalidades"** (`/admin/configuracoes` > Funcionalidades) entra como passo opcional/descoberta: toggles de Loja, Ranking, Jornal, Graduação automática, Musculação, Treinos, Vídeos, Reserva, Trocação, Evolução, Gamificação, Check-in, Controle de acesso. Muitos módulos vêm OFF e ficam "locked"/"hidden" → o dono não sabe que existem. Mostrar "ative e o app do aluno ganha essas abas".

### Funções-âncora do admin
- **Dashboard** `/admin` — saudação, 3 quick actions (Chamada, Novo Aluno, Financeiro), stats (Alunos Ativos/Receita do Mês), Mensalidades, Alertas de inadimplência. *Hospeda o checklist.*
- **Cadastrar / Importar alunos** — `/admin/alunos/novo` (multi-modalidade) + `/admin/importar-alunos` (wizard CSV 4 passos).
- **Cobrança** `/admin/cobranca` (lembretes WhatsApp/email, fecha funil de inadimplência) · **Graduação** `/admin/graduacao` · **Loja** `/admin/loja`.

### Pain points de 1º acesso
- Dashboard vazio ambíguo (zeros ≈ falha de carregamento; mitigado por `_loadError`, mas sem CTA de primeiros passos).
- Ordem de ativação implícita + pré-requisitos ocultos (turma→chamada; plano→cobrança; MP+KYC→receber).
- **MP enterrado** — maior aha econômico não exposto no dashboard.
- Módulos OFF/locked/hidden não descobríveis sem abrir Configurações.
- Vincular alunos (Código de equipe) fácil de esquecer.
- **KYC silencioso**: mesmo após "Conectado!", recebimento pode travar por documentos pendentes + falta de chave PIX.
- Funil financeiro encadeado mal sinalizado: plano → matricular no plano → gerar mensalidades → registrar/cobrar.

---

## 4. Professor

**Contexto crítico:** professor = `UserRole.instructor` com **capacidade VARIÁVEL**. Por padrão TODO instrutor só tem `events:manage` (Jornal). Tudo o mais (chamada, alunos, graduação, competições, financeiro) depende de `extraPermissions` que o ADMIN concede. **Fork de shell:** instrutor "puro"/com financeiro/graduação/competições → **AdminShell**; instrutor promovido de aluno só com `attendance:take` → **Portal como monitor** (bottom-nav Início/Chamada/Alunos/Perfil/Menu).

**Aha moment:** 1ª chamada da turma em segundos e/ou 1ª graduação — sentir que a gestão da aula ficou trivial.

**Padrão:** mini-welcome (1-2 telas) + coachmark na ação central + just-in-time na graduação. Menos passos que o admin.

### Funções a destacar (gateadas por permissão — só mostrar o que ele tem)
1. **Chamada** — `/admin/chamada` ou `/portal/chamada` (`attendance:take`). Marcar turma inteira em massa; "marcar todos" é o ganho de tempo que vende o produto. **Ação central do coachmark.**
2. **Graduação** — `/admin/graduacao` (`graduation:manage` + feature `autoGraduationEnabled`, lockable). Just-in-time ao abrir perfil do aluno.
3. **Alunos** — `/admin/alunos` (qualquer `students:*`). Perfil, presenças, faixa, histórico num lugar.
4. **Jornal** — `/admin/jornal` (`events:manage`, **padrão de todo instrutor**). É a 1ª coisa que um professor recém-promovido consegue fazer sem depender do admin → bom ponto de partida.
5. Turmas `/admin/turmas` (sempre) · Ranking `/admin/ranking` (sempre) · Financeiro/Cobrança (`financial:view`) · Conteúdo (Treinos/Vídeos/Combinações/Loja — só feature-flags, sem permissão).

### Pain points de 1º acesso
- **Capacidades invisíveis/não-descobríveis**: permissão ausente fica "hidden" (some, sem pista), diferente de feature-flag que vira cadeado. Dois professores veem shells totalmente diferentes e nenhum sabe "o que pedir ao admin".
- **Fork de shell confunde a identidade**: ganhar uma permissão nova pode "teletransportar" o professor entre shells entre sessões, sem aviso.
- **Graduação concedida mas bloqueada**: tem `graduation:manage` mas feature OFF (e Configurações é adminOnly) → "tenho a permissão mas não consigo usar".
- **Incoerências de exposição**: pode IMPORTAR alunos sem `students:*`; vê/edita Conteúdo/Loja sendo "só de chamada".
- **Limites não comunicados**: nunca vê Configurações/Código de equipe/paywall, sem mensagem "isso é com o admin" — a porta simplesmente não existe.

---

## 5. Padrão de onboarding recomendado por papel (sequência de telas/momentos)

### (a) ALUNO — carrossel curto de valor + coachmark + confete + streak
1. **Welcome carousel — 3 telas de VALOR, puláveis** (personalizar com nome real da academia):
   - "Registre sua presença e veja sua evolução" (faixa animada).
   - "Acompanhe sua frequência e o ranking da academia."
   - "Tudo aqui: avisos, eventos e sua jornada na [academia]."
2. **Coachmark único no dashboard:** spotlight no check-in — "Toque aqui sempre que treinar." (Mostrar ONDE fica mesmo fora da janela.) Um coachmark, não tour.
3. **1º check-in → confete** + faixa/progress subindo. Esse é o aha.
4. **Empty states que ensinam** nas abas vazias (histórico: "Seus treinos vão aparecer aqui — registre sua presença hoje").
5. **Permissão de push AQUI** (após 1º check-in): "quer ser avisado de eventos e da sua graduação?".
6. **Streak** introduzido após alguns check-ins ("3 treinos esta semana 🔥").
- *Caso "não vinculado":* se `currentStudentProvider == null`, desviar para orientação de Código de equipe em vez do carrossel padrão.

### (b) ADMIN — checklist de ativação com barra de progresso
1. Card **"Comece por aqui"** fixo no topo do dashboard, progresso 0/6 (seção 3).
2. Cada item abre o fluxo e volta marcando concluído (barra enche).
3. **Empty states viram CTA do checklist** (lista vazia → "Convide seus alunos" → link).
4. **Celebração** ao completar checklist ("Sua academia está no ar! 🎉") + 1º aluno ativo + 1º pagamento (ahas de negócio).
5. **Convite como alavanca de rede** — destaque, link curto, share WhatsApp.
6. Checklist some/colapsa em 100%.

### (c) PROFESSOR — coachmark na chamada + just-in-time na graduação
1. Mini welcome (1-2 telas ou direto ao shell): "Faça a chamada da turma em segundos e acompanhe a evolução dos seus alunos."
2. **Coachmark na ação central** ("Fazer chamada") na 1ª vez na lista de turmas.
3. Fluxo de chamada guiado 1x: destacar **"marcar todos presentes"**.
4. **Empty state** se sem turma: "Peça ao admin para te vincular a uma turma" (ou "Crie sua turma" conforme permissão).
5. **2º destaque just-in-time**: graduação ao abrir perfil do aluno ("Aqui você atualiza a faixa e o progresso").
6. **Celebração discreta** na 1ª chamada e na 1ª graduação.
- *Cuidado fork de shell:* o tour deve resolver o papel pelo shell efetivo (AdminShell vs Portal-monitor), não pelo `role` cru.

---

## 6. Injeção técnica + persistência

### ONDE plugar (recomendado)
**Builder Stack do `MaterialApp.router` em `lib/app.dart:203-216`** — já hospeda overlay que "vive acima do GoRouter e sobrevive a rebuilds do router" (comentário `lib/app.dart:221-222`). Adicionar widget irmão:
```
child: Stack(children: [
  child!,
  if (isCreatingAccount) _AccountCreationOverlay(...),   // lib/app.dart:208-214
  const _OnboardingGate(),                                // <-- novo
]),
```
**`_OnboardingGate`** (novo, ex. `lib/widgets/onboarding/onboarding_gate.dart`) observa:
- `appBootstrapProvider` (`lib/providers/portal_providers.dart:186`) → só pinta quando `AppBootstrapStatus.ready` (gatilho reativo correto, NÃO o bool não-reativo `_sessionLanded` em `lib/app.dart:439`),
- `currentUserProvider` (`lib/providers/auth_provider.dart:69`) → split por papel: `isAdmin || isInstructor` em `/admin` → tour admin; student em `/portal` → tour aluno,
- a seen-flag → só pinta se null/false,
- rota atual = landing root do papel (`/portal` ou `/admin`).

*Rejeitados:* redirect com rota `/onboarding` dedicada (`lib/app.dart:504-543`) = mais pesado (4º estado no latch + branch `isAuthRoute||isSplash`). Injeção por-shell (`PortalShell.build` ~`lib/screens/portal/portal_shell.dart:252` / `AdminShell.build` `lib/screens/admin/admin_shell.dart:29`) = funciona e dá separação limpa, mas overlay é destruído/reconstruído a cada navegação de aba e fica abaixo das transições do router. Usar só se quiser o tour clipado ao corpo do shell.

### COMO persistir "já viu" — grão por papel
**ALUNO = por usuário (Firestore, cross-device):**
- Add `DateTime? onboardingSeenAt` em `GlobalUser` (`lib/models/user.dart:75-202`: campo + `fromMap` ~124 + `toFirestore` ~144).
- Ler via `globalUserProvider` (`lib/providers/auth_provider.dart:37`, já busca `users/{uid}`).
- Escrever via `globalUserService.updateGlobalUser(uid, {'onboardingSeenAt': FieldValue.serverTimestamp()})` (`lib/services/global_user_service.dart:116`) — mesmo path de edição de perfil; sem novo service. **Verificar** que a regra `users/{uid}` é owner-write amplo (não field-whitelist).
- Opcional: espelhar em SharedPreferences (bool) como cache local para suprimir flash de 1 frame antes do Firestore retornar. `shared_preferences ^2.3.4` está declarado (`pubspec.yaml:51`) mas **hoje sem uso** — seria o 1º uso real.

**ADMIN = por academia (evento único de setup):**
- Add `DateTime? onboardingCompletedAt` em `AcademySettings` (`lib/services/settings_service.dart:112+`, `fromFirestore` ~382 + map writer).
- Novo `SettingsService.markOnboardingCompleted()` espelhando `updateJournalVisibility` (`lib/services/settings_service.dart:758`): `_academyRef.update({'onboardingCompletedAt': FieldValue.serverTimestamp()})`; `_academyRef = academies/{academyId}` (`lib/services/settings_service.dart:502`).
- Ler via `academySettingsProvider` (`lib/providers/portal_providers.dart:155`, já no bootstrap).
- **Caveat:** academy-level é compartilhado entre todos os admins/instrutores da academia (quem logar 1º dispensa). Se quiser tour de UI **por-admin**, guardar separado em `users/{uid}.adminTourSeenAt` (mesmo mecanismo do aluno). Client writes OK nos dois (rules já permitem admin escrever `academies/{id}`).

### Detecção de 1º acesso
- **Aluno recém-vinculado:** `GlobalUser.onboardingSeenAt == null` + `bootstrap==ready` + `role==student` + em `/portal`. O momento "freshly linked" vem do CF `joinAcademy` (`auth_provider.dart:405-419` / `579-616`) — flag ainda null → tour dispara. (Secundário disponível: `AcademyDetail.joinedAt/approvedAt`, `lib/models/user.dart:263/331`, mas o null-flag basta.)
- **Academia recém-criada:** `AcademySettings.onboardingCompletedAt == null`. Criada em `AuthService.createAcademyAccount` (`lib/providers/auth_provider.dart:484-566`) sem campo; 1º login do dono resolve `/admin` (branch `lib/app.dart:507-510`) com flag null → wizard dispara. (Heurística secundária "academia vazia" = zero-students, mas o null-flag dispensa query extra.)

### Arquivos a criar/editar
- `lib/models/user.dart` — `GlobalUser.onboardingSeenAt` (+ opcional `adminTourSeenAt`).
- `lib/services/settings_service.dart` — `AcademySettings.onboardingCompletedAt` + `markOnboardingCompleted()`.
- `lib/app.dart:208-214` — montar `const _OnboardingGate()`.
- Novo `lib/widgets/onboarding/onboarding_gate.dart` + telas do tour.
- `firestore.rules` — **verificar** (provavelmente sem mudança) owner-write `users/{uid}` e admin-write `academies/{id}` não são field-whitelisted.

*Âncoras-chave:* landing decisions `lib/app.dart:504-543`; landing latch `lib/app.dart:439/556`; overlay-in-Stack `lib/app.dart:203-216`; bootstrap gate `lib/providers/portal_providers.dart:186-213`; user fetch `lib/providers/auth_provider.dart:69-202`; settings ref `lib/services/settings_service.dart:502`; settings write precedent `lib/services/settings_service.dart:758`; global user write `lib/services/global_user_service.dart:116-137`.

---

## 7. Design system: blocos reutilizáveis + gaps a criar

### Tokens (todos `static const`, `lib/core/theme.dart`, classe `AppTheme`)
- **Neutros (paleta P&B minimalista):** `primary #111111`, `primaryLight #333333`, `primaryDark #000000`, `surface #FFFFFF`, `surfaceVariant #F5F5F5`, `textPrimary #171717`, `textSecondary #666666`, `divider #E5E5E5`, `border #E0E0E0`.
- **Semânticos (+par Light p/ badges):** `success #22C55E`/`successLight #DCFCE7`, `warning`/`warningLight`, `error`/`errorLight`, `info #3B82F6`/`infoLight`.
- **Faixas (acentos por slide):** `beltBlue/Purple/Brown/Yellow/Orange/Green/Red/Grey/Black/White`; helper `AppTheme.getBeltColor(String)`.
- **Tipografia (Inter):** `displayLarge` 32/w700 … `labelSmall` 10/letterSpacing 0.5 (ideal eyebrow "PASSO 1 DE 4"). `.copyWith()` p/ w800.

### Kit de polish reutilizável (`lib/widgets/polish/*`, barrel `polish.dart`) — REAPROVEITAR, não recriar
- **Motion (`PolishMotion`, polish_tokens.dart):** durations `fast 150` / `normal 320` / `slow 400` / `countUp 600`; `staggerStep 55ms` + `staggerDelay(i)`; curves `entrance easeOutCubic`; `slideBegin 0.06`, `pressScale 0.97`. **Usar SEMPRE, sem números mágicos.**
- **Entrances (extension):** `.entrance(index:i)` (fade+slide-up staggered p/ revelar título/subtítulo/CTA em cascata) · `.fadeInQuick()`.
- **Celebração:** `Celebration.confetti(context)` (burst one-shot via OverlayEntry — slide final/aha) · `SuccessCheck(size:)` (check com scale easeOutBack — conclusão).
- **Botões/interação:** `PolishButton(label,icon,isLoading,onPressed,expand,color,radius:14)` (CTA "Próximo"/"Começar", haptic+spinner) · `Pressable(onTap,scale)` (coachmark targets, cards de escolha) · `PolishCard(child,onTap,gradient,elevated,radius:12,border)`.
- **Progresso/números:** `AnimatedProgressBar(value 0..1)` (barra topo do onboarding + checklist admin) · `AnimatedCountUp(value,prefix,suffix,style)` (stats "248 alunos") · `StatTile(icon,value,countValue,label,color,gradient)`.
- **Loading:** `PolishSkeleton.{list,grid,stats,card,avatar,header,bar,shimmer}`.

### Padrões inline a copiar (não recriar)
- **Gradiente herói premium** (de `home_hero_card.dart` `_CheckinHero`): `LinearGradient([primaryLight, primaryDark], topLeft→bottomRight)` + `borderRadius 18` + `boxShadow(primaryDark@0.30, blur 18, offset 0,6)`. Look "card escuro caro".
- **Shimmer em loop** (flutter_animate): `.animate(onPlay:(c)=>c.repeat()).shimmer(duration:1800.ms, delay:1200.ms, color: Colors.white@0.22)` — destacar CTA do último slide.
- **Dot indicator** (de `home_screen.dart` ~537): `AnimatedContainer(200ms, width: active?20:8, height:8, color: active?textPrimary:divider, radius:4)`.
- **PageView + PageController + onPageChanged** — padrão já em ~10 telas; sem dep nova.

### Primitivas de dependências
flutter_animate 4.5.2 (`.fadeIn/slideY/scale/shimmer/then/repeat`, `1800.ms`) · confetti 0.8.0 (já em `Celebration.confetti`) · shimmer 3.0 · lucide_icons 0.257.0 (`LucideIcons.userCheck/calendarClock/sparkles/trophy/qrCode/dumbbell/users/arrowRight`) · flutter_svg 2.0.17 **instalado mas sem uso e sem assets** (único asset: `assets/images/bjjeasy_logo.png`). **Sem Lottie/Rive.**

### GAPS a criar (SEM nova dependência)
1. **Scaffold de onboarding** — `OnboardingScreen` (PageView) do zero.
2. **`PageDots(count,currentPage)`** — extrair p/ polish kit o indicador hoje hard-coded inline em `home_screen.dart`/stats_carousel.
3. **`SpotlightOverlay` (coachmark)** — novo: `Stack` + `CustomPainter` (`BlendMode.clear`/`Path.combine` recorta o buraco) + balão de dica + `Pressable`. Molde de inserção/remoção = `Celebration.confetti` (OverlayEntry).
4. **Ilustrações** — recomendado zero-dep: ícone Lucide grande em círculo tintado `accent@0.10` (mesma linguagem do `PolishedEmptyState`: ícone 32-56). Clímax = `SuccessCheck` + confetti.
5. **(Opcional) tokenizar** `AppTheme.heroGradient` + BoxShadow herói (hoje inline em home_hero_card).

### Receita rápida (bloco → uso)
Slide: `PolishCard(elevated:true)` ou gradiente herói · ícone-ilustração: círculo `accent@0.10` + Lucide (cor = belt do slide) · entrada: `.entrance(index:i)` escalonado · progresso: `AnimatedProgressBar((page+1)/total)` + dots · navegação: PageView + `PolishButton('Próximo'/'Começar', LucideIcons.arrowRight)` · clímax: `SuccessCheck()` + `Celebration.confetti(context)`.

**Arquivos-chave:** `/Users/igorgewehr/WebstormProjects/graduabjj/lib/core/theme.dart` · `/Users/igorgewehr/WebstormProjects/graduabjj/lib/widgets/polish/` (polish.dart, polish_tokens.dart, entrance.dart, celebration.dart, polish_button.dart, polish_card.dart, polished_empty_state.dart, animated_progress.dart, animated_count_up.dart, stat_tile.dart, pressable.dart, skeleton_helpers.dart) · `/Users/igorgewehr/WebstormProjects/graduabjj/lib/widgets/portal/home_hero_card.dart` · `/Users/igorgewehr/WebstormProjects/graduabjj/lib/screens/portal/home_screen.dart` (~537) · `/Users/igorgewehr/WebstormProjects/graduabjj/lib/app.dart` (~203-216, 439, 504-557) · `/Users/igorgewehr/WebstormProjects/graduabjj/lib/services/settings_service.dart` · `/Users/igorgewehr/WebstormProjects/graduabjj/pubspec.yaml`.

---

## 8. Decisões a tomar antes de implementar (perguntas em aberto)

1. **Coachmark/Spotlight no v1?** É um GAP de engenharia real (`CustomPainter` + recorte + OverlayEntry). Opções: (a) v1 só carrossel + empty states + confete, coachmark em v2; (b) construir spotlight já no v1 (esforço maior, mas é o que diferencia o aluno e o professor). **Recomendação:** carrossel/checklist no v1; spotlight como fast-follow.
2. **Professor — qual shell guia o tour?** Resolver pelo shell **efetivo** (AdminShell vs Portal-monitor), não pelo `role`. Decidir: tour único que se adapta, ou dois mini-tours. E como lidar com o "teletransporte" entre shells quando ganha permissão nova (re-disparar? avisar?).
3. **Admin — checklist por academia (compartilhado) vs tour de UI por-admin?** `onboardingCompletedAt` em `AcademySettings` é academy-level (1º admin dispensa pra todos). Precisamos também de `users/{uid}.adminTourSeenAt`? Provável **sim**: checklist de setup = academia; tour de UI = por pessoa.
4. **Mercado Pago no checklist é passo obrigatório ou opcional?** É o maior aha econômico, mas envolve KYC + chave PIX (etapas externas e demoradas). Como representar "conectado mas KYC pendente" no progresso sem travar o restante?
5. **Convite de aluno — link compartilhável existe?** O best-practice pede "link de convite + WhatsApp share" para reduzir fricção. Hoje há **Código de equipe** (`/codigo-equipe`). Decidir se basta o código ou se criamos deep-link/short-link de convite (escopo extra).
6. **Push permission — quando e como?** Confirmar que o app pede push só **após o 1º check-in** (aluno) e não no splash. Há infra de push (módulo push mencionado no histórico)? Mapear o ponto de request.
7. **Instrumentação das métricas-norte** — existe analytics? Precisamos instrumentar: aluno→1º check-in 48h; admin→time-to-first-active-student + time-to-first-payment; professor→1ª chamada no 1º acesso. **Sem isso, o onboarding não é otimizável.** Decidir ferramenta/eventos.
8. **Aluno "não vinculado" (`currentStudentProvider==null`)** — fluxo dedicado de "vincule sua conta" (Código de equipe) é parte do onboarding v1 ou tratado à parte? É um beco sem saída hoje.
9. **Personalização barata (2-4 perguntas)?** Best-practice sugere; mas regra: cada pergunta DEVE mudar algo visível. Para o aluno o papel já vem pronto — vale perguntar objetivo/frequência? Provavelmente **não no v1** (risco de personalização teatral).
10. **Skip/persistência:** confirmar que "Pular" também grava a flag (não reaparece) e definir se há entrada manual para rever o tour (ex.: em Perfil/Ajuda).
11. **`firestore.rules`:** confirmar que owner-write `users/{uid}` e admin-write `academies/{id}` não são field-whitelisted (bloqueariam os novos campos). Verificação rápida antes de codar.