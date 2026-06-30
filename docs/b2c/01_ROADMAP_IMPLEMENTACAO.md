# Roadmap de Implementação — App do Lutador (GraduaBJJ)

> Documento de execução. Os 8 docs de `docs/b2c/` são a **pesquisa**; este é o **plano de build**. Aqui cada feature vira tarefa concreta de FRONT e BACK, com o PORQUÊ (gatilho de retenção que honra), a métrica que move e a ordem de dependências.
>
> **North-star:** WAS-solo — lutadores que numa semana fizeram ≥1 ação de identidade/log/social que **não depende da academia ter marcado presença**.
> **Frase-norte:** *"O lutador volta ao app toda semana por vontade própria — porque ali mora a prova de quem ele está se tornando — treine onde treinar, com ou sem a academia no app."*
>
> **Régua de toda decisão:** o dado pertence ao **LUTADOR** (global, portátil, retém sem academia) ou à **ACADEMIA** (contextual, morre na troca/saída)?
>
> **Regra de não-regressão absoluta:** cada passo só **ADICIONA** coleção/campo/trigger. Nenhum doc é movido. O app legado ignora o que não conhece. Trocar de academia continua sendo trocar 1 string.

---

## Mapa de fases (visão de uma tela)

| Fase | Tese | Entrega | Move |
|---|---|---|---|
| **0** | destravar o solo + fundação invisível | home solo, onboarding sem-academia, nav fighter-first, `onAttendanceWrite`, `fighterProfiles`, design system anti-slop | habilita tudo |
| **1** | "dê algo que vale exibir" (100% portátil) | Diário 1-tap, Passaporte, Streak resiliente, Motor de Cards, badges sobre dado existente, semente social (oss) | D1 / D7 + k viral |
| **2** | "dê uma cena" (precisa da densidade da F1) | oss/kudos, streak-de-dupla, grafo cross-academy + feed, círculos, Mapa do Tatame, listas | D7 → D30 (virada de curva) |
| **3** | "dê uma arena" (exige densidade + dados consistentes) | leaderboards segmentados, Mat Wars, Seleção do Estado, Cartel, Arsenal, Ligas | retenção mensal recorrente |

**Sequência-mestra:** identidade que vale exibir → cena para descobrir → arena para competir. Competição cedo = ranking morto.

---

## Os 3 motores reutilizáveis (construir 1×, reusar em N features)

Antes das fases, a infra compartilhada. Onde codar: `functions/engines/{cards,scoreboard,seasons}.js`, reusando helpers de `functions/server_functions.js`.

- **MOTOR 1 — Cards** (Fase 1). Render **client-side por default**: `RepaintBoundary → toImage(pixelRatio:3) → PNG → share_plus`, custo servidor $0, offline, watermark no widget tree. CF `cardOgImage` (node-canvas) só **lazy** no 1º miss de unfurl, PNG content-addressed cacheado. Spec doc único `users/{uid}/cards/{cardId}` (cardId determinístico) alimenta os dois renderers.
- **MOTOR 2 — Agregação/Placar** (Fase 3). Eventos → doc público sazonal `seasons/{seasonId}/scoreboards/{scopeId}`. Default **SCHEDULED** (~1 write/escopo/tick, zero hot-spot); LIVE sharded (K≈10) só opt-in em escopo quente. Substrato de Mat Wars, Seleção do Estado, leaderboards, ligas.
- **MOTOR 3 — Temporadas/Matchmaking** (Fase 3). Liga dos Faixas: CF `onSchedule('0 4 1 * *')` idempotente, lê standings JÁ materializados pelo Motor 2 (nunca varre attendance bruto), semeia pods de ~30 (`groupId = floor(idx/30)`), batches ≤500.

**Spine comum a todos:** chave = `uid` sempre · PII-safe via projeção única `buildPublicProfileProjection` / `PUBLIC_PROFILE_SAFE_FIELDS` (já exportada) · fan-out sem `collectionGroup` generalizando `forEachMpAcademy` → `forEachAcademy(label, filter, handler)` · idempotência por ids determinísticos.

---

## FASE 0 — Destravar o solo + fundação invisível

> **Fase dupla: backend (rollup invisível) + frontend (o free user hoje cai em `/portal` QUEBRADO).** Sem isso, nada do B2C tem valor diário e as fases seguintes ficam ocas.

### F0.1 — Trigger de agregação `onAttendanceWrite` (BACK, bloqueante de tudo)
- **PORQUÊ:** é o "scrobble" do lutador — a presença real vira dado pessoal **sem digitação**. Habilita streak, passaporte, cards e auto-log sem trigger storm.
- **BACK:**
  - Pré-requisito: denormalizar `uid` no doc de attendance na escrita (o check-in já conhece via `verifiedBy`/`linkedUserId`) + backfill dos legados.
  - CF `onAttendanceWrite`: resolve uid via `students.linkedUserId`, `FieldValue.increment` O(1) em `users/{uid}/stats/aggregate`, recompute de streak só desse uid, espelha em `fighterProfiles/{uid}`.
  - Anti-storm: escrever em coleção **diferente** da observada, `increment`, short-circuit em no-op.
  - Generalizar `syncHighestBelt` (hoje client-triggered, N reads, sem idempotência) → event-driven sobre `students/{sid}`. **Estender o trigger, não duplicar.**
- **Métrica:** agregados batem com `count()` de auditoria; 0 reprocessamento em writes idempotentes.

### F0.2 — Mirror `fighterProfiles/{uid}` (BACK)
- **PORQUÊ:** `users/{uid}` só o dono lê → não serve fonte pública. Tudo que é descoberta/feed/ranking lê **só** do mirror PII-free.
- **BACK:** coleção raiz `fighterProfiles/{uid}` (CF-written, PII-free via allowlist única). **Decisão crítica:** NÃO repromover `publicProfiles` para fighter-scoped — **ADICIONAR** o mirror raiz e **MANTER** `academies/{id}/publicProfiles/{studentId}` intacto p/ ranking intra-academia.
- **Rules:** `fighterProfiles` lê se `discoverable == true || dono`; `write: if false` (só Admin SDK/CF).

### F0.3 — Home solo + onboarding sem-academia (FRONT, blocker ignorado pela visão backend)
- **PORQUÊ:** hoje `PortalShell`/`home_screen` assumem `Student`/`settings` não-nulos → free user vê tela quebrada (`app.dart:551`). Sem home solo, modo solo não tem valor diário.
- **FRONT:**
  - Home solo para usuário `free` (sem academia): faixa-herói, streak, CTA do Diário, atalho de card.
  - Onboarding sem-academia: faixa auto-declarada, time/linhagem, modalidades (`styleTags[]`), `jiujitsuStartDate`.
  - Guards em `main.dart`/`PortalShell` para nunca cair em tela vazia.
- **Métrica (gate):** **nenhum** free user cai em tela vazia; % de onboarding sem-academia concluído.

### F0.4 — Navegação fighter-first + design system anti-slop (FRONT, pré-condição de credibilidade)
- **PORQUÊ:** num app de tribo dura, "parecer feito por IA" mata a retenção antes de qualquer streak. A nav fighter-first sinaliza que o app é **portátil**.
- **FRONT — Navegação:**
  - Bottom nav 5 slots: `[ Lutador | Cena | (•) Treinei | Academia | Perfil ]` (modelo Strava "You").
  - `enum NavDomain { lutador, academia }` + campo `domain` em `NavEntry`; agrupar primeiro por domain, depois por section. Re-tag das 16 entradas do catálogo.
  - **Remover** `AcademySwitcher` do title global e `_AcademyIndicator` da home; o seletor vira **header exclusivo da aba Academia**. Sino de notificações permanece global.
  - Fronteiras: graduação + avaliação física → **Lutador** (com selo "dados da academia X"); treinos/vídeos/trocação prescritos → **Academia**.
- **FRONT — Design system (`docs/b2c/UIUX_DESIGN_PORTAL_LUTADOR`):**
  - **Banir:** Inter como rosto · roxo `#7C3AED` no chrome · gradiente arco-íris/roxo→azul · confete multicolor · emoji-como-ícone (~30 hoje) · cantos 12px+ · cards-dentro-de-cards · glassmorphism.
  - **Paleta decidida:** canvas tinta-osso quente `~#FAFAF7` (light) + **dark mode obrigatório** `#0A0A0A`; **um único acento** vermelho-sangue/coral `~#B91C1C–#C2410C` para CTA/streak/marca.
  - **Separação sagrada:** as 10 cores de faixa SÓ representam faixa real; UI semântica usa neutros + o acento. Roxo aposentado do chrome.
  - **Tipografia:** display condensada industrial (Archivo/Anton/Druk-like) ALL-CAPS para heróis; Inter rebaixada a corpo; **numerais tabulares** (`FontFeature.tabularFigures`) em TODA métrica; escala number-first 40–56px em telas-marco.
  - **Forma/textura:** raio 12→8px; chips pílula → retângulo 6–8px (lê como fightwear); hairline preto 1px `#1A1A1A`; foto real de tatame/gi sob overlay + grão/noise.
  - **Voz:** "oss" como tempero, não tapete (variar respeito/fechou/salve/rolar/drilar/raspar/finalizar); empty states com tom de presença, zero exclamação fitness anglófona.
  - Manter a física de motion (`polish_tokens`, 150–400ms easeOutCubic) — mudar só o **significado** das celebrações.
- **Métrica:** teste qualitativo "feito por alguém de dentro?"; nav adotada sem regressão de fluxos legados.

### F0.5 — Backfill B4 (BACK, grátis, faça 1º)
- **BACK:** status enum tipado (`active | pending | archived | transferred`). Idempotente, itera `userAcademyMapping`, nunca `collectionGroup`.

**Ordem da Fase 0:** B4 → F0.1+F0.2 (mesmo fan-out: `fighterProfiles` inicial + agregados via `count()` por academia, batches ≤450) → F0.3 → F0.4.

---

## FASE 1 — Identidade + Diário + Compartilhar

> "Dê algo que vale a pena exibir." 100% portátil (`users/{uid}` + `fighterProfiles`), zero cold-start, e é o que **acumula os dados** sem os quais Fases 2-3 ficam ocas. Cada lutador instalado vira um outdoor.

### F1.1 — Diário de Rolagem 1-tap *(elevado de Fase 3 → 1; correção mais importante entre os docs)*
- **PORQUÊ:** Hevy/Strong provam que o log de baixíssima fricção é a **fundação** do hábito e do growth orgânico — matéria-prima de streak/Arsenal/Wrapped/cards. Gatilho: ativação do hábito (1º log nos 7 primeiros dias).
- **FRONT:**
  - Ancorado no botão central **"Treinei"**: dentro da janela de check-in da academia → presença **verificada**; fora → **self-log portátil**.
  - **Requisito de produto explícito:** velocidade de log — default "rolei hoje", **<10s**, 1-tap, tudo opcional via chip (duração/foco/notas).
  - **A tela de save É a recompensa:** "rola nº 318 · 4ª semana seguida".
  - Diário **privado** por design (anti-curation-anxiety: taps levados, treino ruim, lesão).
- **BACK:** `users/{uid}/training_logs/{id}` + `users/{uid}/rolls/{id}` (read+write dono). Denormalizar `uid` no doc. Auto-log: presença verificada vira entrada `verified` na timeline pessoal sem digitação.
- **Métrica:** % que loga em <10s; logs/usuário/semana; **% 1º log em 7 dias** (ativação).

### F1.2 — Passaporte do Lutador (BIG BET #1)
- **PORQUÊ:** identidade portátil que vale exibir; "você é um jiujiteiro", não troféu.
- **FRONT (Perfil → Passaporte):** hero = belt grande + nome + apelido/ring name + linhagem; trocar pill de matrícula/cobrança pelo selo **"Verificado pela academia"**; stats de orgulho (mat-time, streak semanal, medalhas, tempo na faixa); CTA primário **"Compartilhar passaporte"**. CPF/RG/saúde/emergência empurrados para **Configurações** secundário.
- **BACK:** `users/{uid}/stats/aggregate` (1 read serve o passaporte) já materializado pelo `onAttendanceWrite`; `fighterProfiles/{uid}` como landing público dos cards.
- **Métrica:** % que abre o Passaporte; cliques em "Compartilhar".

### F1.3 — Streak resiliente (aposenta `getStudentStreak` / `attendance_service.dart:325`)
- **PORQUÊ:** streak punitivo (Duolingo diário) incentiva treinar lesionado e zera → abandono. Tornar o streak **mais perdoável aumenta** retenção e é **segurança física**.
- **BACK (CF-written, não inflável pelo cliente):** modelo Gentler/Whoop/Apple/Finch — **semanal** + freeze + **pausa-lesão 90d** + earn-back 7d + **head-start endowed** no onboarding. Nunca terminal.
- **FRONT:** widget de streak na home solo; badge **jamais** premia "7 dias seguidos" (anti-overtraining).
- **Métrica:** % com streak semanal ativo; streak 7+ (âncora ~2,4x retenção).

### F1.4 — Motor de Cards (MOTOR 1) + Card de Graduação
- **PORQUÊ:** o card é **a maior alavanca viral** — cada graduação postada deve trazer ≥1 visitante ao perfil público. "Modo palco" separado do app utilitário.
- **FRONT:**
  - **Deps faltantes hoje:** `share_plus` + `screenshot`/`RepaintBoundary→toImage` + `path_provider`. (`qr_flutter` e `AnimatedBelt` já existem.)
  - Render off-screen `RepaintBoundary` 1080px, `pixelRatio: 3`.
  - **Princípio-mestre:** monocromo + faixa + grão + tipografia de palco. Canvas `#0A0A0A` sem gradiente; **a faixa da pessoa é a ÚNICA cor**; resto tinta-osso `#F5F1E8`; lockup `GRADUABJJ` + `@graduabjj` + QR discretos.
  - Chassi de 5 zonas (Identidade/Herói/Título/Prova/Marca), formatos **9:16** (story) e **1:1** (feed), `heroBuilder` por família.
  - **Disparo no PICO emocional** (instante em que o professor registra) E no momento social (domingo à noite / fim de mês), por **push**.
- **BACK:** spec doc `users/{uid}/cards/{cardId}` (cardId determinístico). CF `cardOgImage` lazy só no 1º unfurl. Deep-link próprio (App/Universal Links — Dynamic Links descontinuado) → perfil público com params `cardId/type/ref` para medir **k**.
- **Pronto p/ ligar já** (graduação e presença existem): Graduação/Grau · Milestone · Streak. Tapped/Finalização e Beltday em seguida.
- **Verificado vs auto-declarado (rígido):** `✔︎ VERIFICADO via Academia X` (sólido, entra no ranking cross-academy) vs `○ auto-declarado` (contorno tracejado, fora do ranking). Componente único `VerifiedSeal(state)`.
- **Métrica:** **k viral** = cards gerados → compartilhados → cliques no deep-link → cadastros atribuídos.

### F1.5 — Quick wins sobre dado existente (ROI Whoop, infra zero)
- **PORQUÊ:** re-embrulhar presença/faixa/horas em conquista visível tem o ROI mais alto e infra zero.
- **Reusam o que já temos:**
  - **Beltday/Meses na faixa** → card (push já existe).
  - **Patches/badges** sobre `achievements`/`timeline` existentes.
  - **Milestones automáticos** (rola nº 100/500/1000, X meses na faixa) sobre `stats/aggregate`.
  - **BJJ Wrapped** mensal + anual sobre `totals` (Wrapped = card do Motor 1 sobre o agregado). Tom "equilíbrio, não burnout".
- **Métrica:** adoção de cards de quick win; lift de D7.

### F1.6 — Semente social barata (fim da fase)
- **PORQUÊ:** puxa uma primitiva social para começar a acumular o efeito-rede antes da Fase 2 (mitiga cold-start do grafo).
- **FRONT/BACK:** "oss/respeito" de **1-toque** sobre `publicProfiles`/cards. Sem feed ainda — só a reação.

### F1.7 — B3-fix `promotedBy` (começa aqui)
- **BACK:** corrigir **escritas novas** de graduação (uid + nome do staff logado). Legado é literal `'admin'`/`'Administrador'` → **sem backfill confiável**. Lineage (Fase 2) só depois desta correção. Não bloqueia a Fase 1.

**Ordem da Fase 1:** F1.1 (Diário, matéria-prima) → F1.3 (Streak) em paralelo com F1.2 (Passaporte) → F1.4 (Motor de Cards) → F1.5 (quick wins) → F1.6 (semente social) · F1.7 corre em background.

---

## FASE 2 — Social & Descoberta

> "Dê uma cena." Descoberta e grafo só têm valor com massa crítica de perfis ricos — que a Fase 1 encheu. Aqui mora a retenção de verdade (o moat do Strava é a rede). **Features ordenadas por ROI.**

### F2.1 — Kudos/Oss + Streak-de-Dupla *(prioridade nº1 — maior ROI social)*
- **PORQUÊ:** Friend Streak +22%; reação social +34% de streak; o BJJ já treina a dois. Push social vem de **humano real** ("Fulano deu oss").
- **FRONT:** reação oss/kudos no feed; UI de streak-de-dupla (você + parceiro bateram a semana).
- **BACK:** `users/{uid}/following` + `/followers`; raiz `partners/`, `duels/`. `activities` subcollection. Callable `toggleFollow` (transação, valida `allowFollow`, incrementa contadores).
- **Métrica:** oss/comentário por usuário ativo; adoção de streak-de-dupla.

### F2.2 — Grafo cross-academy + Feed
- **PORQUÊ:** **o pivô central do B2C** — descola a retenção da adoção da academia.
- **BACK — FEED = FAN-IN (PULL), NUNCA FAN-OUT-ON-WRITE.** Faixa-preta com 50k seguidores graduando NÃO dispara 50k writes. Cliente lê própria `following` e faz `collectionGroup('activities').where('actorId','in',chunk10).orderBy('createdAt')`. Único `collectionGroup` permitido = filtrado por `actorId`. `feedCache` por CF só como otimização futura p/ power-followers.
- **FRONT:** feed assíncrono da Cena; seguir lutadores de qualquer academia.
- **Índice:** `activities` COLLECTION_GROUP (`actorId` + `createdAt`).
- **Métrica:** % com ≥1 follow; seguidos/usuário; **D30 cruza ~5%+** (entrada na curva social).

### F2.3 — Círculo/clube auto-formado (3–30 pessoas)
- **PORQUÊ:** container de accountability que **sobrevive** a troca de academia/viagem/lesão (≠ turma da academia). Grupos peer-led sem métricas tiveram +42% adesão.
- **BACK:** coleção de círculos person-level; membership bounded.
- **FRONT:** criar/entrar em círculo; feed/streak do círculo.

### F2.4 — Mapa do Tatame + Lutadores Perto (LGPD by design — risco mais sério)
- **PORQUÊ:** o gesto diário "onde rolo hoje?".
- **BACK:**
  - `academyProfiles/{academyId}` raiz + CF `syncAcademyProfile` (geocode 1×). **Geo exato permitido** (endereço comercial).
  - **Pessoa:** callable `setFighterGeo` → geohash **truncado 5 chars** (~4.9km), origem = **centro da cidade** da primaryAcademy, **nunca** endereço residencial nem coordenada exata.
  - **Opt-in granular default FALSE** (doc nem nasce discoverable). **Menores:** CF calcula idade de `birthDate`, `<18` força `discoverable=false` e **não emite geohash** (a CF é a fronteira — rules não têm a idade).
  - Queries por raio ≤9 ranges, zero `collectionGroup`. Erasure por cascata `onDelete users/{uid}`.
  - **Deps novas:** `ngeohash` (Node) + `dart_geohash` (Flutter) — único bloco genuinamente novo.
- **FRONT:** mapa de academias; "Lutadores Perto" opt-in.
- **Índices:** `fighterProfiles` (`discoverable`+`geohashPublic` / +`primarySport` / +`geoRegion`+`followersCount`); `academyProfiles` (`listed`+`geohash`).
- **Métrica:** geo opt-in rate (com guardrail de privacidade); report/block rate.

### F2.5 — Listas curadas + Top Four + ranking de GOSTO
- **PORQUÊ:** identidade simpática que **desarma a toxicidade** do leaderboard; custo de conteúdo quase zero.
- **FRONT:** Top Four (Letterboxd); ranking pareado de gosto (Beli: "gostou mais de treinar aqui ou no X?").

### F2.6 — Árvore de Linhagem (depende de F1.7)
- **PORQUÊ:** identidade cultural (quem te promoveu).
- **BACK:** bloqueada por `promotedBy` — só após F1.7 corrigir as escritas novas. Comunicar como limitação de produto para dados legados.

**Ordem da Fase 2:** F2.1 (nº1 ROI) → F2.2 (grafo/feed, o pivô) → F2.3 → F2.4 (geo) → F2.5 → F2.6 (gated por F1.7).

---

## FASE 3 — Competição & Ligas

> "Dê uma arena." Engajamento mais potente **e mais frágil** — exige densidade (Fases 1-2) e dados consistentes. **Sempre segmentado, por consistência, fundo escondido, opt-in.** Ranking global humilha 99% (bottom 40% reduz logs em 53%).

### F3.1 — Leaderboards segmentados (quick win / teaser pode antecipar)
- **PORQUÊ:** competição saudável; o bottom 40% sob ranking global some seus logs.
- **BACK (Motor 2):** reads só do mirror `fighterProfiles`. Coortes faixa/peso/cidade/círculo/streak. Ranquear **consistência/progresso** (nunca "quem luta melhor"). Reusa padrão de `getAttendanceRanking`.
- **FRONT:** **fundo da tabela escondido**, opt-in, segmentação visível.
- **Guardrail:** só dado **verificado** entra no ranking cross-academy; self-log fica fora.

### F3.2 — Mat Wars (Guerra de Academias) + Seleção do Estado
- **PORQUÊ:** identidade tribal; o gancho que faz a academia **querer** estar no app.
- **BACK (Motor 2):** `scope=academy` head-to-head em 1 read; `scope=state` só muda a chave. SCHEDULED default; LIVE sharded só em escopo quente. `seasons/{seasonId}/scoreboards/{scopeId}`, temporada nova = parent novo, antigas `status:closed` imutáveis.
- **Risco (R2 toxicidade):** narrativa de **diversão, não culpa**; nunca expor publicamente quem perde sem consentimento.

### F3.3 — Cartel do Atleta + Passaporte de Competição
- **PORQUÊ:** prova de competição verificável.
- **BACK:** depende do **sync de medalhas de campeonato** (deferido no hotfix 2.5.1) + B5 (catálogo de eventos IBJJF/AJP) + `partners`/`duels`. Priorizar quando o sync for reativado.

### F3.4 — Arsenal + Pokédex + feed de cultura/lore
- **PORQUÊ:** set incompleto = motivo de abrir HOJE; razão de voltar em dia de folga.
- **BACK:** Arsenal **deriva do Diário maduro** (F1.1) — só ligar quando houver volume de logs.
- **FRONT:** Pokédex de técnicas; feed de cultura (técnica do dia, linhagem, debates).

### F3.5 — Duelos 1v1 / Desafio 30 dias
- **BACK:** `duels` person-level. **Sempre opt-in, reversível, copy de encorajamento, nunca humilhação pública.**

### F3.6 — Liga dos Faixas (MOTOR 3 — investimento mais pesado, FECHA o ciclo)
- **PORQUÊ:** retenção mensal recorrente (alvo do salto Duolingo 12%→55%, churn 47%→28%).
- **BACK (Motor 3):** CF `onSchedule('0 4 1 * *')` idempotente/resumível: fecha anterior lendo standings JÁ materializados (nunca varre attendance bruto), semeia pods de ~30 (`groupId = floor(idx/30)`, **fallback regional** p/ nunca deixar o lutador solo numa cidade vazia), batches ≤500. ~12 runs pesados/ano só nas bordas.
- **Métrica:** densidade de liga (% de pods ≥ cheios); retenção mensal; saúde do ranking (0 exposição de bottom).

### F3.7 — Push de retenção social + "Seu Ano no Tatame"
- **FRONT/BACK:** push humano ≤2-3/semana; Wrapped mensal e anual (card do Motor 1).
- **Guardrail (R10/FTC):** cancelar tão fácil quanto assinar.

**Ordem da Fase 3:** F3.1 (teaser pode antecipar) → F3.2 → F3.5 → F3.4 (gated por volume do Diário) → F3.3 (gated por sync de medalhas + B5) → F3.6 (fecha o ciclo) → F3.7.

---

## Backfills — ordem canônica

1. **B4** — status enum tipado (`active|pending|archived|transferred`). Grátis, faça **1º**.
2. **B1 + B2** — mesmo fan-out: `fighterProfiles` inicial + agregados (`totalAttendance`/`medalCount`/`streak` via `count()` por academia). Idempotente (set/merge), batches ≤450, itera `userAcademyMapping`, **nunca** `collectionGroup`.
3. **B3-fix** — `promotedBy` (corrigir escritas novas; lineage só depois).
4. **B5** — catálogo de eventos IBJJF/AJP (Fase 2/3).

---

## Rules & índices novos (resumo de segurança)

- **Catch-all nega tudo:** todo mirror/agregado/grafo é `allow write: if false` (só Admin SDK/CF).
- `fighterProfiles` lê se `discoverable==true || dono`; `academyProfiles` se `listed==true`; `stats` só dono read; `training_logs`/`rolls` read+write dono.
- **Índices compostos:** `fighterProfiles` (discoverable+geohashPublic / +primarySport / +geoRegion+followersCount); `academyProfiles` (listed+geohash); `activities` (COLLECTION_GROUP actorId+createdAt).
- **Deps novas:** `share_plus`/`screenshot`/`path_provider` (Fase 1, Flutter); `ngeohash` (Node) + `dart_geohash` (Flutter) (Fase 2).

---

## Quick-wins que reusam o que já existe (ligar primeiro)

| Quick win | Reusa | Fase | Esforço |
|---|---|---|---|
| Auto-log da presença verificada na timeline | `onAttendanceWrite` + timeline existente | 1 | baixo |
| Badges/níveis sobre presença/faixa/horas | `achievements` + `stats/aggregate` | 1 | baixo (infra zero) |
| Card de Graduação / Milestone / Streak | graduação + presença já existem | 1 | médio (deps de share) |
| Beltday push → card | push já existe | 1 | baixo |
| BJJ Wrapped | `stats/aggregate` (totals) | 1 | médio |
| Leaderboard segmentado | `getAttendanceRanking` + `fighterProfiles` | 3 (teaser) | médio |
| Mat Wars head-to-head | `forEachAcademy` + Motor 2 | 3 | alto |
| Multi-academia / transferência | já provado em produção | — | reuso direto |

---

## Guardrails transversais (instrumentar desde o dia 1)

Vanity metric subindo **enquanto** guardrail piora = **feature reprovada** (Manipulation Matrix).

- **Uninstall após push** + **opt-out de notificação** (gatilho do teto 2-3/sem).
- **Report/block rate** no feed e Lutadores Perto.
- **% de logs privados honestos** (taps levados, treino ruim, lesão) — anti-curation-anxiety; se cair, o feed está canibalizando o diário.
- **Tentativa de inflar ranking com self-log** (proporção self-declared vs verified em escopo competitivo).
- **Sinal de overtraining** — treinos em sequência sem descanso / em lesão declarada; o app **sugere pausa**, não premia.
- **Streak nunca punitivo** — badge não premia "X dias seguidos".
- **Privacidade** — só dado que o usuário escolheu publicar aparece; menores bloqueados server-side.

---

## Definition of Done por fase

- **Fase 0:** 0 free users em tela quebrada; `onAttendanceWrite` em prod com agregados auditados; nav fighter-first sem regressão; design system anti-slop aplicado ao chrome.
- **Fase 1:** Diário <10s em prod; k viral instrumentado (cada graduação postada ≥1 visitante); streak resiliente substitui `getStudentStreak`; D7 acima do baseline fitness.
- **Fase 2:** feed fan-in sem `collectionGroup` não-filtrado; geo opt-in com LGPD by design; D30 cruza ~5%+ (curva social).
- **Fase 3:** leaderboards segmentados sem exposição de bottom; Liga dos Faixas com pods ≥ cheios; retenção mensal recorrente medida.

---

*Arquivo: `docs/b2c/01_ROADMAP_IMPLEMENTACAO.md`. Fonte: integração dos 8 docs de `docs/b2c/` + arquitetura code-verified. Regra-mãe: aditivo, nunca re-key; portátil, nunca dependente da academia.*
