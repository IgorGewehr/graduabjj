# 00 — PLANO MESTRE · App do Lutador (GraduaBJJ)

> **Status de execução (2026-07):** **Fases 0-2 largamente implementadas e
> deployadas** — `fighterProfiles/{uid}` (mirror global), dispatcher
> `onAttendanceWrite`, nav fighter-first `[Lutador·Cena·Treinei·Academia·
> Perfil]` (`portal_shell.dart:32-90`, verbatim), motor de cards
> (`share_card_service.dart`), oss/kudos (`oss_providers.dart`), Jornada
> multi-esporte, Retenção 2.0/Radar do dia, streak com freeze. **Fase 3 (Arena
> & Ligas — Mat Wars, Liga dos Faixas, `academyProfiles`/geohash) continua
> NÃO construída** — é o roadmap ainda em aberto. Ver
> `01_ROADMAP_IMPLEMENTACAO.md`, `REPAGINADA_ADMIN_ALUNO100_PLANO.md` e
> `STREAK_JORNADA_PLANO.md` para o detalhe de cada frente.

> Documento executivo e decidido. Integra e reconcilia os 8 documentos de pesquisa/design em `docs/b2c/`. Onde os docs se contradizem, este plano **decide** e marca a reconciliação. Linguagem: PT-BR. Data-base: jun/2026. Branch de produção: `firebase-production` (Firestore `arpjj-76350`).

---

## 1. Visão & North-Star

**A virada.** O GraduaBJJ nasceu como ferramenta de **gestão de academia** (B2B): presença, financeiro, graduação. Esta fase inverte a gravidade do produto — o herói deixa de ser a academia e passa a ser o **lutador**. O app precisa valer **mesmo sem a academia dentro dele**, retendo PESSOAS (não lucro) pela cultura, identidade, social e compartilhamento.

**Frase-norte:**
> *"O lutador volta ao app toda semana por vontade própria — porque ali mora a prova de quem ele está se tornando — treine onde treinar, com ou sem a academia no app."*

**North-Star (1 métrica): WAS-solo — Lutadores Ativos Semanais Auto-Motivados.**
Número de lutadores que, numa semana, executaram **≥1 ação de identidade, log ou social que NÃO depende da academia ter marcado presença** (logar uma rola, dar um oss, postar um card, ver o feed).

Por que **semanal** e não diário: o BJJ se treina 2-4x/semana e a fisiologia **exige descanso** — medir DAU puniria o corpo do atleta e mascararia o valor B2C. Por que **"solo"**: isola a tese central — o app vale a N=1, sem a academia no app.

**KPIs canônicos (o instrumento):**

| KPI | O que mede | Meta-direção |
|---|---|---|
| Retenção D1 / D7 / D30 | hábito bruto | migrar da curva **fitness** (D30 ~3%) para a curva **social** (D30 ~5%+) |
| % 1º log em 7 dias | ativação do hábito | sem o 1º registro, streak/Arsenal/Wrapped/cards ficam sem matéria-prima |
| **k viral** (cards gerados→compartilhados→cliques→cadastros) | aquisição orgânica | design goal: **cada graduação postada ≥1 visitante** ao perfil público |
| **% WAS-solo / WAS total** | virada B2C | termômetro direto de "o app vale sem a academia" |
| Streak-de-dupla / oss recíproco | efeito-rede | a retenção virou social, não solitária |

**A régua de toda decisão:** *move D1, D7 ou D30?* Vanity metric subindo **enquanto** um guardrail piora = feature reprovada.

---

## 2. Por quê — psicologia do lutador + mercado

Três fatos cruzados sustentam cada aposta deste plano.

1. **A curva azul (blue-belt curve) é um problema de retenção, não de técnica.** O BJJ tem evasão notória na faixa azul/roxa — exatamente quando a novidade acaba e o próximo marco está longe. A obsessão com "a cor da próxima faixa" acelera a desistência (faixas-pretas alertam contra isso). **Conclusão:** gamificar **processo** (mat-time, consistência, técnica, jornada), nunca a **faixa**.

2. **Health&Fitness retém pouco; Social retém o dobro.** Benchmark: fitness D1 ~20-27% / D7 ~7% / **D30 ~3%** ("baixado com alta intenção que não sustenta" = o padrão BJJ). Social/messaging chega a **D30 ~5% (~2x)** porque o motor é a **rede**, não a intenção individual. **A virada B2C é literalmente migrar de uma curva para a outra.**

3. **O log de baixíssima fricção é a FUNDAÇÃO do hábito e do growth orgânico** (Hevy/Strong/Strava). Não é "profundidade tardia": é a matéria-prima de streak, Arsenal, Wrapped e cards, e o motor de aquisição (cada usuário vira um outdoor). O modelo Strava ("You" como tela central, *Record* como gesto-mestre) é a referência arquitetural direta.

4. **Em 2026, "genérico" = "AI slop".** A tribo do BJJ execra o genérico: se o app cheira a template de IA, o lutador conclui em 2 segundos que "não foi gente de verdade que fez isso" — e nenhuma mecânica de streak segura quem já desconfia. **Craft humano visível é o fosso.**

5. **O moat é a tríade:** mecânica de retenção **ética** + **prova verificada** (verificado vs auto-declarado — que nenhum tracker auto-reportado tem) + **tom feito-por-quem-treina**.

---

## 3. O quê — os big bets priorizados

Ordenados por ROI sobre a North-Star.

1. **Diário de Rolagem 1-tap** *(promovido de Fase 3 → Fase 1)* — default "rolei hoje" em <10s, tudo opcional via chip; a tela de save **É** a recompensa ("rola nº 318 · 4ª semana seguida"). Requisito de produto explícito: **velocidade de log**. É a matéria-prima de tudo.
2. **Auto-log do dado verificado** — a presença real da academia vira entrada `verified` na timeline pessoal sem digitação (o "scrobble" do lutador). Alavanca social de altíssimo ROI, infra quase zero (depende só de `onAttendanceWrite`).
3. **Passaporte do Lutador** (Perfil → identidade) — faixa-herói + linhagem + selo *Verificado pela academia* + stats de orgulho. CRM (CPF/RG/saúde) desce para Configurações.
4. **Motor de Cards** + Card de Graduação (a **maior alavanca viral**), Finalização, Milestone, Streak, Beltday, Wrapped.
5. **Streak resiliente** — semanal + freeze + pausa-lesão 90d + earn-back + head-start endowed. Modelo Gentler/Whoop/Apple/Finch, **nunca** Duolingo diário.
6. **Semente social barata** — "oss/respeito" 1-toque sobre cards/perfis (fim da Fase 1).
7. **Kudos/Oss + Streak-de-Dupla** *(nº1 da Fase 2 — maior ROI social)*.
8. **Grafo cross-academy + feed fan-in** — descola a retenção da adoção da academia (o pivô central do B2C).
9. **Leaderboards segmentados + Mat Wars/Seleção do Estado + Ligas** *(Fase 3, por último)*.

---

## 4. Como — arquitetura + os 3 motores

**Tese de build:** a fundação pessoa↔ficha **já existe e é cost-safe** (`userAcademyMapping/{uid}` + `students.linkedUserId`, ambos com backfill aplicado). Os dois únicos blocos genuinamente novos são (1) um **mirror público person-level keyed por uid** (`fighterProfiles/{uid}`) e (2) a **materialização event-driven de agregados** começando por um trigger de attendance que **hoje não existe**. Todo o resto é generalização de código em produção.

**Regra de não-regressão absoluta:** cada passo só **ADICIONA** coleção/campo/trigger. **Nenhum doc é movido.** O app legado ignora o que não conhece. Trocar de academia continua sendo trocar 1 string.

**Linha de corte (autoridade do dado):** o dado pertence ao **LUTADOR** (global, portátil, sobrevive à troca/saída) ou à **ACADEMIA** (contextual, dono = quem lança)? Materializada em código como `enum NavDomain {lutador, academia}` + campo `domain` em `NavEntry`.

| Camada | Onde | Natureza |
|---|---|---|
| Perfil de lutador | `users/{uid}` (estender) | identidade portátil |
| **Agregados (núcleo)** | `users/{uid}/stats/aggregate` (CF-written) | derivado, 1 read serve passaporte/wrapped/streak |
| **Espelho público (NOVO)** | `fighterProfiles/{uid}` (raiz, PII-free, CF-written) | descoberta/feed/ranking leem só daqui |
| Logs pessoais (NOVO) | `users/{uid}/training_logs`, `/rolls` | nascem da pessoa |
| Grafo social (NOVO) | `users/{uid}/following`,`/followers`; `partners/`,`duels/` | person-level |
| **Source-of-truth (INALTERADO)** | `attendance`, `financials`, `beltProgressions`, `students` PII | dono = academia |

**Decisão crítica (contradição resolvida):** as pesquisas pedem "repromover `publicProfiles` para fighter-scoped". **Rejeitado.** O modelo é **ADITIVO, NUNCA RE-KEY**: adicionamos `fighterProfiles/{uid}` (pessoa) e `academyProfiles/{academyId}` (academia) na raiz e **mantemos** `academies/{id}/publicProfiles/{studentId}` intacto para ranking intra-academia. A intenção "fighter-scoped" é atendida pelo novo espelho, não pela destruição do legado.

**Os 3 motores reutilizáveis (construir 1×, reusar em N):**

- **MOTOR 1 — Cards.** Render **client-side default**: `RepaintBoundary→toImage(pixelRatio:3)→PNG→share_plus` (custo servidor $0, offline, watermark no widget tree). CF `cardOgImage` (node-canvas) **lazy** só no 1º miss de unfurl, PNG content-addressed cacheado. Spec doc único `users/{uid}/cards/{cardId}` (cardId determinístico) alimenta os dois renderers. Deep-link próprio (App/Universal Links).
- **MOTOR 2 — Agregação/Placar.** Substrato de Mat Wars, Seleção do Estado, leaderboards, ligas. Stats pessoais (baixo volume) = CF `onAttendanceWrite` com `FieldValue.increment` O(1). Placares de escopo (alta contenção) = **SCHEDULED por default** (cron fan-out, ~1 write/escopo), **LIVE sharded (K≈10)** só opt-in em escopos quentes. **Zero collectionGroup de scan.**
- **MOTOR 3 — Temporadas/Matchmaking (Liga dos Faixas).** Consome o Motor 2. CF mensal idempotente/resumível: fecha temporada lendo standings **já materializados** (nunca varre attendance bruto), semeia pods de ~30, batches ≤500.

**Feed = FAN-IN (pull), NUNCA fan-out-on-write.** Faixa-preta com 50k seguidores graduando não dispara 50k writes. Cliente lê própria `following` e faz `collectionGroup('activities').where('actorId','in',chunk10)` — o único collectionGroup permitido, sempre filtrado por `actorId`.

**LGPD by design, server-authoritative.** Opt-in granular **default FALSE** (doc nem nasce discoverable). Pessoa: só `geohashPublic` truncado 5 chars (~4.9km), origem = centro da cidade da primaryAcademy, **nunca** endereço residencial. Menores: CF deriva idade de `birthDate`, <18 força `discoverable=false`. Allowlist única `buildPublicProfileProjection` alimenta TODOS os mirrors (sem drift/vazamento). Erasure por cascata `onDelete`.

**Rules novas (catch-all nega tudo):** todo mirror/agregado/grafo é `allow write: if false` (só Admin SDK/CF). Agregados graváveis pelo dono seriam infláveis → CF-written, mirror `write:false`.

---

## 5. Design — princípios, nav fighter-first, cards

**Norte de design:** o teste de cada tela é *"um faixa-preta veria isso e acharia que foi feito por alguém de dentro, ou por um app de fitness qualquer?"*. Direção visual única = **"Linhagem"**. **Anti-AI-slop é pré-condição de credibilidade, não cosmético** — entra na Fase 1.

**Navegação fighter-first (modelo C, Strava "You"):**
```
[ Lutador ]  [ Cena ]  [ (•) Treinei ]  [ Academia ]  [ Perfil ]
   global      global     ação central      contextual      conta
```
- **Treinei** (centro, equivalente ao *Record*) resolve a fronteira no gesto mais usado: dentro da janela de check-in → presença **verificada**; fora → **self-log portátil**. Casa do Diário de Rolagem 1-tap. Lição Foursquare/Swarm: separar o loop de hábito num app/aba à parte é **fatal** — registro administrativo e check-in social são **a mesma ação**.
- O **AcademySwitcher sai da AppBar global** e vira header exclusivo da aba Academia; o `_AcademyIndicator` sai da home. É o sinal mais forte de que o resto do app é portátil. Sino de notificações permanece global.

**Paleta (decidida, não opção):** canvas tinta-osso quente (~#FAFAF7) no light + **dark mode obrigatório** (#0A0A0A, "o tatame à noite"). **Um único acento de marca** = vermelho-sangue/coral seco (~#B91C1C–#C2410C). **Separação sagrada:** as 10 cores de faixa são o material de marca mais valioso e **SÓ** representam uma faixa real; UI semântica usa neutros + o acento. **Roxo #7C3AED aposentado do chrome.**

**Tipografia:** display condensada industrial (Archivo/Anton/Druk-like) ALL-CAPS para heróis; Inter rebaixada a corpo/UI densa; **numerais tabulares em toda métrica**; escala number-first (40–56px em telas-marco).

**Checklist negativo (banir):** Inter como rosto · roxo no chrome · gradiente roxo→azul/arco-íris · confete multicolor · emoji-como-ícone · cantos fofos 12px+ · cards-dentro-de-cards · glassmorphism/neon · copy "AI cheerful".

**Voz:** "oss" é **tempero, não tapete** — variar léxico real BR (respeito, fechou, salve, rolar, drilar, raspar, finalizar). Oss em toda reação vira caricatura que a própria tribo zoa.

**Cards = "modo palco" separado do app utilitário.** Princípio-mestre: *monocromo + faixa + grão + tipografia de palco.* Canvas #0A0A0A sem gradiente; **a faixa da pessoa é a ÚNICA cor**; lockup GRADUABJJ + @graduabjj + QR discretos. **Um motor, N cards** — chassi de 5 zonas (Identidade · Herói · Título · Prova · Marca), formatos 9:16 e 1:1, 6 famílias (Graduação/Grau · Tapped · Milestone · Streak[semanas, nunca dias] · Beltday · Wrapped).

**Verificado vs auto-declarado** é distinção **rígida**: `✔︎ VERIFICADO via Academia X` (sólido, entra no ranking cross-academy) vs `○ auto-declarado` (contorno tracejado, fora do ranking). Componente `VerifiedSeal(state)`. **Disparo no pico emocional** (instante do registro pelo professor) E no momento social (domingo à noite/fim de mês), por push — teto ético **2-3 push social/semana, todo de humano real**.

---

## 6. Roadmap faseado

> **Sequência-mestra:** primeiro uma **identidade que vale a pena exibir** (portátil, vale a N=1, acumula dados, gera viral) → depois uma **cena para descobrir** (precisa da densidade que a Fase 1 criou) → só então **arenas para competir** (ranking sem dados é deserto, sem comunidade é tóxico).

### FASE 0 — Destravar o solo + fundação invisível (dupla)
- **Backend:** CF `onAttendanceWrite` (não existe hoje) resolve uid via `linkedUserId`, `increment` em `stats`, recompute de streak O(1), espelha em `fighterProfiles`. Generalizar `syncHighestBelt` para event-driven. Backfill **B4** (status enum tipado).
- **Frontend (blocker real):** hoje o free user cai em `/portal` **quebrado** (`PortalShell`/`home_screen` assumem `Student`/`settings` não-nulos). Criar **home solo** + **onboarding sem-academia** (faixa, time/linhagem, modalidades, `jiujitsuStartDate`) + reorganização UIUX fighter-first.
- **KPI:** % de free users que chegam a home solo funcional; conclusão de onboarding sem-academia. **Gate: nenhum free user cai em tela vazia.**

### FASE 1 — Identidade + Diário + Compartilhar *("dê algo que vale exibir")*
**Por quê primeiro:** 100% portátil, zero risco de cold-start, e é o que **acumula os dados** sem os quais Fases 2-3 ficam ocas. Cada lutador instalado vira um outdoor.
- `fighterProfiles/{uid}` + CF `syncFighterProfile` + backfill **B1/B2** (idempotente, `count()` por academia, batches ≤450).
- `users/{uid}/training_logs` + `rolls` + tela de log <10s.
- Streak engine CF (aposenta `getStudentStreak` de `attendance_service.dart:325`).
- Motor 1 client-side + deps `share_plus`/`screenshot`/`path_provider` → Cards de Graduação/Finalização/Milestone/Streak (imediatos: graduação e presença já existem).
- Quick wins ROI-Whoop (infra zero): Beltday, Patches/badges, Milestones automáticos, Wrapped. **B3-fix** das escritas de `promotedBy` começa aqui (lineage só depois).
- **Semente social:** oss 1-toque no fim da fase.
- **KPI:** adoção do Diário (% loga <10s); % com streak semanal ativo; **k viral**; lift de D7.

### FASE 2 — Social & Descoberta *("dê uma cena")* — **a virada de curva (D7→D30)**
**Por quê agora:** descoberta/grafo só têm valor com massa crítica de perfis ricos — que a Fase 1 encheu.
- **Kudos/Oss + Streak-de-Dupla** *(nº1, maior ROI; +22% conclusão)*.
- **Grafo cross-academy** + feed fan-in (`toggleFollow` transacional, `activities`).
- **Círculo/clube auto-formado (3-30 pessoas)** — accountability que sobrevive a troca/viagem/lesão.
- `academyProfiles/{academyId}` + geocode → **Mapa do Tatame**; `setFighterGeo` (geohash 5 chars, respeita `isMinor`) → **Lutadores Perto** (deps `ngeohash`/`dart_geohash`).
- Listas curadas + Top Four + ranking pareado de **gosto** (Beli, desarma toxicidade). Árvore de Linhagem (após B3).
- **KPI:** % com ≥1 follow; adoção streak-de-dupla; oss/usuário ativo; **D30 cruza ~5%+**; geo opt-in rate.

### FASE 3 — Arena & Cultura *("dê uma arena")* — por último
**Por quê:** competição é o engajamento mais potente **e o mais frágil** — exige densidade + dados consistentes. Sempre **segmentada, por consistência, fundo escondido, opt-in**.
- Leaderboards segmentados (teaser pode antecipar) → Mat Wars (`scope=academy`) + Seleção do Estado (`scope=state`) → Rivalidade 1v1/Desafio 30d (`duels`).
- Cartel do Atleta + Passaporte de Competição (**depende do sync de medalhas deferido no hotfix 2.5.1**) + B5 (catálogo de eventos).
- Arsenal/Pokédex (deriva do Diário maduro) + feed de cultura/lore.
- **Liga dos Faixas** (Motor 3, o investimento mais pesado) **fecha o ciclo** de retenção mensal.
- **KPI:** retenção mensal; % de pods cheios (nunca solo); 0 exposição pública de bottom.

---

## 7. Riscos & Kill-list

**KILL-LIST (o que NÃO construir):**

| # | NÃO construir | Em vez disso |
|---|---|---|
| K1 | Ranking **global** por performance ("quem luta melhor") | Bottom 40% reduz logs **53%**; Foursquare quebrou a 50M/dia. → Sempre **segmentado**, por consistência, fundo escondido, opt-in |
| K2 | Gamificação de **vaidade da faixa** | Premiar **processo** (mat-time/técnica/jornada), identidade não troféu |
| K3 | **Streak diário** + mascote-culpa + loss-framing (Duolingo trap) | Semanal + pausa-lesão 90d + earn-back; mais perdoável **aumenta** retenção |
| K4 | **Push spam / push do sistema** | Teto **2-3/semana**, todo de humano real |
| K5 | Estética **"AI-made"** | Acento de marca próprio, faixa-herói, foto real de tatame, oss comedido |
| K6 | **Privacidade frouxa** na descoberta | Geohash truncado, opt-in default FALSE, menores bloqueados server-side |
| K7 | **Urgência fabricada** (erro BeReal) | FOMO social real, registro passivo > obrigação ativa |
| K8 | **Vanity metrics** (lição Discord) | Encorajamento + identidade; diário **privado** valoriza registro honesto |
| K9 | **Paywall na camada social** | Free = social/identidade; Paid = performance ou camada academia (B2B) |
| K10 | **Feed fan-out-on-write** | Fan-in filtrado por `actorId` |
| K11 | **Loop de hábito em app/aba à parte** | Botão central "Treinei" — mesma ação, dois consumidores |
| K12 | **UGC de vídeo cedo** | Adiar; pipeline report/block + moderação antes |

**RISCOS PRINCIPAIS:** R1 LGPD (o mais sério — opt-in/geohash truncado/menores server-side/erasure por cascata); R3 ranking morto sem densidade (Fase 3 por último, pods de ~30, fallback regional); R4 integridade do self-report (verificado vs auto-declarado, agregados CF-written); R5 saúde do atleta/overtraining (banir badge "dias seguidos", pausa-lesão); R6 custo Firestore (zero collectionGroup não-filtrado, leitura de produto = 1 doc materializado); R7 tom incongruente; R9 dependências bloqueadoras (`promotedBy` legado bloqueia Linhagem; sync de medalhas deferido bloqueia card de pódio); R10 regulatório/FTC (cancelar tão fácil quanto assinar).

**GUARDRAILS (instrumentar desde o dia 1):** uninstall após push, opt-out de notificação, report/block rate, % de logs privados honestos (anti-curation-anxiety), tentativa de inflar ranking com self-log, sinal de overtraining. **Vanity metric subindo enquanto guardrail piora = feature reprovada.**

---

## 8. Documentos de detalhe (`docs/b2c/`)

- [PESQUISA_RETENCAO_B2C_2026-06.md](./PESQUISA_RETENCAO_B2C_2026-06.md) — mecânicas de retenção, curva fitness vs social, modelo de streak.
- [PESQUISA_CULTURA_LUTADOR_2026-06.md](./PESQUISA_CULTURA_LUTADOR_2026-06.md) — cultura do tatame, processo>faixa, léxico BR, anti-AI-slop.
- [PESQUISA_B2C_APROFUNDADA_2026-06.md](./PESQUISA_B2C_APROFUNDADA_2026-06.md) — Hevy/Strong/Strava, log de baixa fricção como fundação, benchmarks D1/D7/D30.
- [IDEACAO_FEATURES_LUTADOR_2026-06.md](./IDEACAO_FEATURES_LUTADOR_2026-06.md) — catálogo de features e big bets por fase.
- [UIUX_DESIGN_PORTAL_LUTADOR_2026-06.md](./UIUX_DESIGN_PORTAL_LUTADOR_2026-06.md) — nav fighter-first, Passaporte, sistema de cards, design system.
- [ARQUITETURA_IDENTIDADE_LUTADOR_2026-06.md](./ARQUITETURA_IDENTIDADE_LUTADOR_2026-06.md) — modelo de dados global vs academy-scoped, 3 motores, mirrors, LGPD.
- [PREP_FASE_LUTADOR_2026-06.md](./PREP_FASE_LUTADOR_2026-06.md) — preparação/sequência de build, backfills B1-B5, Fase 0 dupla.
- [MULTIACADEMIA_STATUS_2026-06.md](./MULTIACADEMIA_STATUS_2026-06.md) — estado da fundação multi-academia (`userAcademyMapping`, `linkedUserId`, transferência).

---

**Conclusão.** O risco maior não é técnico — é **trair a cultura para perseguir engajamento**. Cada item da kill-list aumenta uma métrica de vaidade enquanto destrói a retenção de pessoas — o oposto da tese. O plano confirma a direção certa quando a curva do app migra de "fitness" para "social" **sem** que os guardrails de privacidade, saúde do atleta e autenticidade piorem. A fundação (`onAttendanceWrite` + `fighterProfiles` + Diário) habilita simultaneamente a retenção individual (Fase 1) e alimenta os dados sem os quais Fases 2-3 ficam ocas.
