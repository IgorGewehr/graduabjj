# Guia de UI/UX & Design — Portal do Lutador (GraduaBJJ)

> **Status de execução (2026-07):** nav fighter-first e motor de cards
> **shipped** (`portal_shell.dart:32-90` espelha a lista de abas deste doc
> quase verbatim; `share_card_service.dart`/`fighter_share_card.dart`
> implementam o motor de cards; `brand_tokens.dart` traz paleta/dark mode) —
> a implementação real usa uma estrutura interna diferente do enum `NavDomain`
> proposto aqui, mas o resultado visível bate. Itens não reverificados:
> renomeação Perfil→Passaporte, redesign do pódio do Ranking. Mantido como
> referência de design.

> Documento de referência (PT-BR) consolidado a partir de quatro frentes de pesquisa: IA/navegação, linguagem visual anti-"AI-made", sistema de cards compartilháveis e crítica/redesign do portal atual. Norte único: **o app é a extensão da "terapia do tatame" e do orgulho do lutador — não um painel de gestão renderizado para o aluno.**

---

## 0. Tese de produto (a régua de toda decisão)

Existem **dois mundos** dentro do app e eles foram fundidos por construção histórica (o tema nasceu "baseado no webapp MarcusJJ", `theme.dart:5`):

- **LUTADOR** — global, portátil, retém sem academia: passaporte/perfil, jornada/linha do tempo, estrada da faixa, graduação (histórico), modalidades, ranking, competições/cartel, conquistas/patches, social/descoberta.
- **ACADEMIA** — contextual à academia selecionada: horários, presenças, reservar aula, financeiro/mensalidade, loja, jornal, treinos/vídeos/trocação prescritos, e o cockpit do monitor (chamada/alunos).

**Regra de corte (autoridade do dado):** o dado pertence ao lutador (global) ou à academia (contextual)? Essa pergunta resolve navegação, hierarquia visual e o que sobrevive quando o usuário troca/sai da academia.

**Teste de cada tela:** *"um faixa-preta veria isso e acharia que foi feito por alguém de dentro, ou por um app de fitness qualquer?"* Hoje a resposta é a segunda.

---

## 1. Princípios de design

### 1.1 Autenticidade > polimento
A tribo do BJJ "execra o genérico" e rejeita ativamente o que trata BJJ como qualquer workout. O antídoto consagrado contra a estética de IA é o **anti-polish controlado**: grão/textura, tipografia com caráter, ícones de biblioteca profissional (nunca emoji-como-ícone), grid editorial. Autenticidade verificável vale mais que perfeição de máquina.

### 1.2 Restraint + respeito + linhagem (tom "oss", não "yay")
O BJJ premia **consistência e jornada**, não vaidade de pódio. Celebração é monocromática e cultural, não confete arco-íris. A linhagem (quem promoveu, tempo na faixa) é o conteúdo emocional — não o troféu.

### 1.3 Identidade > marca
O produto é sobre **o lutador**, não sobre o GraduaBJJ. A marca só **assina**. Em cards e telas de orgulho, o herói é a faixa e o número da pessoa; a marca é discreta e onipresente (aquisição).

### 1.4 Distintividade ótima
Cada superfície precisa fazer **pertencer** (tribo do tatame) E **destacar** (a MINHA faixa, o MEU tempo). É o motor de compartilhamento.

### 1.5 Verificável como feature
A legitimidade que nenhum concorrente auto-reportado tem: **selo "Verificado pela academia"**. Distinção rígida e não-negociável entre verificado e auto-declarado.

### 1.6 Voz de tatame, em português
A camada verbal é parte da linguagem visual: oss, tatame, rolar/roll, drilar, linhagem. "Validar" → **"OSS"**. Empty states com tom de presença/respeito, não exclamação animada de fitness anglófono.

### 1.7 Anti-AI-made (checklist negativo)
Banir os tells: Inter como rosto do app, branco+cinza neutro, emoji espalhado como confete, **roxo #7C3AED (AI purple)** no chrome, gradiente arco-íris, confete multicolor, cantos "fofos" 12px+, vetor flat 100% sem textura.

---

## 2. Arquitetura de informação & navegação

### 2.1 Diagnóstico do estado atual
- **Seletor de academia mora na AppBar global** (`portal_shell.dart:124-127`, `AcademySwitcher` no `title`, montado em `:299`). Como está sempre presente sobre qualquer tela, sinaliza "tudo aqui é sobre esta academia" — inclusive ranking, jornada e faixa, que são portáteis. **Erro de IA nº 1.**
- **Bottom nav mistura os dois mundos sem rótulo** (`portal_shell.dart:72-92`): `[Início, Horários, Presenças, Perfil, Menu]`. **3 dos 5 slots primários são tarefas de academia.** O lutador abre o app e vê chores de compliance.
- **Home empilha os dois domínios numa coluna só** (`home_screen.dart:73-196`): 10 blocos de peso visual idêntico, sem zoneamento entre lutador e academia.
- **Catálogo agrupa por feature, não por domínio.** `NavSection` (`nav_catalog.dart:33-47`) tem `treinos/comunidade/conquistas/conta`; falta o nível acima: **a quem o dado pertence**. `PortalContextGate.multipleAcademies` (`:57`) trata multi-academia como item escondido em vez de eixo de contexto.

### 2.2 Modelo escolhido — "Lutador como tela central" (modelo Strava "You")
Avaliados três modelos; o vencedor é o **C**: o perfil de lutador vira a tela central (como Strava migrou de `Feed/Explore/Record/Profile/Training` para `Home/Maps/Record/Groups/You` em 2025), e a academia é rebaixada a um **container contextual próprio**. Mapeia 1:1: o lutador é o "You" portátil; a academia é o "Groups/Club" contextual. (Rejeitados: A = mínima mudança que não resolve; B = abas no topo que competem com a AppBar e escondem metade do produto atrás de swipe.)

### 2.3 Bottom nav proposta — "fighter-first"

```
[ Lutador ]  [ Cena ]  [ (•) Treinei ]  [ Academia ]  [ Perfil ]
   global      global      ação central     contextual     conta
```

1. **Lutador** (`/portal`) — hub de identidade portátil (o "You"/Passaporte). Só conteúdo global: faixa em destaque (`home_screen.dart:342` `AnimatedBelt`), stats de jornada (`:432` `_StatsCarousel`), Estrada da Faixa, conquistas/patches, gamificação. **Sem chrome de academia.** Ícone `LucideIcons.user`/escudo.
2. **Cena** (`/portal/cena`) — destino social/descoberta global: Ranking (`portal_ranking`), Competições/Cartel (`portal_competicoes`), roadmap Fase 2 (Mapa do Tatame, Lutadores Perto, Feed). É o slot "Liga" do Duolingo: motor de retenção, merece primeiro nível. Ícone `LucideIcons.globe`/`medal`.
3. **Treinei** (centro, ação) — equivalente ao **Record** da Strava. Botão central que unifica a fronteira no gesto mais usado: se há janela de check-in numa aula da academia → presença **verificada** (reusa `HomeHeroCard`, `home_screen.dart:119`); senão → self-log portátil. Resolve "academia vs global" no ponto exato onde os dois se encontram.
4. **Academia** (`/portal/academia`) — **o container contextual**, único lugar onde o seletor de academia aparece. Cabeçalho = academia atual; corpo = Horários, Presenças, Reservar, Financeiro, Loja, Jornal, Treinos/Vídeos/Trocação prescritos. Para monitor/professor, esta aba vira o **cockpit** (Chamada + Alunos) — move o role-swap de `portal_shell.dart:76-92` para dentro desta aba. Ícone `LucideIcons.school`/`building2`.
5. **Perfil** (`/portal/perfil`) — conta, configurações, edição do perfil público, privacidade (LGPD/descoberta opt-in), logout. O "Menu" sheet atual (`_showMoreMenu`, `:164`) **deixa de ser slot e some** — cada item migra para Lutador/Cena/Academia conforme o domínio.

### 2.4 Onde o seletor de academia se encaixa
- **Escopar à aba "Academia".** Vira o **header dessa aba** (chip nome + avatar; toque abre a folha de troca). Reusa `hasMultipleAcademiesProvider` (`portal_shell.dart:155`, `home_screen.dart:913`): single-academy mostra nome estático sem chrome de troca; multi-academy mostra chip clicável.
- **Remover `AcademySwitcher` do `title`** (`portal_shell.dart:299`) — o sinal mais forte de que o resto do app é portátil. O sino de notificações (`:301`) permanece global.
- `portal_academias` (`nav_catalog.dart:471-478`) deixa de ser item escondido por gate e vira a tela de gestão de vínculos dentro da aba Academia ("Minhas academias / adicionar").
- **Remover `_AcademyIndicator`** da aba Lutador (`home_screen.dart:908-967`) — só fazia sentido quando a home era academy-scoped.

### 2.5 Mudança estrutural no catálogo
Introduzir o nível de domínio acima de `NavSection`: criar `enum NavDomain { lutador, academia }` e um campo `final NavDomain domain;` em `NavEntry` (`nav_catalog.dart:60-123`). Abas/menu agrupam primeiro por `domain`, depois por `section`. Todo o resto (gates, feature flags, resolver) é reaproveitado sem reescrita.

**Re-tag de `kPortalNavCatalog` (`:349-479`):**

| Entry | Domínio | Slot |
|---|---|---|
| `portal_jornada` (`:374`) | lutador | Lutador |
| `portal_graduacao` (`:389`) | lutador | Lutador |
| `portal_evolucao` (`:381`) | lutador¹ | Lutador |
| `portal_modalidades` (`:396`) | lutador | Lutador |
| `portal_ranking` (`:428`) | lutador | Cena |
| `portal_competicoes` (`:436`) | lutador | Cena |
| `portal_comportamento` (`:443`) | lutador | Lutador (kids) |
| `portal_horarios` (`:350`) | academia | Academia |
| `portal_presencas` (`:358`) | academia | Academia |
| `portal_reservas` (`:365`) | academia | Academia |
| `portal_treinos` (`:404`) | academia² | Academia |
| `portal_trocacao` (`:412`) | academia² | Academia |
| `portal_videos` (`:420`) | academia² | Academia |
| `portal_financeiro` (`:451`) | academia | Academia |
| `portal_loja` (`:459`) | academia | Academia |
| `portal_academias` (`:471`) | academia | Academia (header/gestão) |

¹ Casos de fronteira: `portal_evolucao` (avaliação física) é gateado por feature de academia (`FeatureId.evolution`) mas é conceitualmente pessoal → exibir no domínio **lutador** com selo "dados da academia X". Idem `portal_graduacao`: histórico é identidade do lutador, mas cada grau é verificado pela academia → manter no Lutador com a distinção visual verificado/auto-declarado.
² `treinos/videos/trocacao` são conteúdo **prescrito pela academia**. Não confundir com o Diário/log pessoal (slot central "Treinei"), que é do lutador.

**`_QuickAccessSection`** (`home_screen.dart:620-730`, `_quickKeys` em `:627`) hoje mistura `portal_ranking` (lutador) com `portal_loja`/`portal_financeiro` (academia) num set hardcoded → dividir usando o novo campo `domain` como filtro.

---

## 3. Linguagem visual + crítica do tema atual

### 3.1 Crítica concreta (file:line)
- **Tipografia:** `theme.dart:51` `fontFamily = 'Inter'` é o "rosto da IA". A escala é tímida — maior estilo é `displayLarge` 32px/w700 (`:53-59`); não existe registro editorial/herói.
- **Emoji como sistema de ícones (tell nº1):** `stat_tile.dart:51-64,88` assume emoji como badge primário; 🔥 streak (`home_screen.dart:470`), 📅 (`:495`), 🏆 (`:509,518,525,828`), 🥇⭐🏆 (`competitions_screen.dart:276,297,322`), 🎉 (`workouts_screen.dart:709`). ~30 ocorrências de emoji-troféu no `lib/`. Culturalmente errado: o BJJ premia jornada, não vaidade de pódio.
- **Roxo + gradiente (os dois clichês literais de IA):** `home_screen.dart:824,882` `Colors.purple.withValues(alpha:0.1)` hardcoded fora do design system; `theme.dart:39` `beltPurple = #7C3AED` é o violet-500 do Tailwind; confete mistura roxo (`celebration.dart:48-54`); `LinearGradient` (`home_screen.dart:1075`). **Ressalva honesta:** roxo existe por razão real (cor de faixa); o problema é o roxo **vazando para chrome** (cards, badges, confete).
- **Paleta sem marca + sem dark mode:** `theme.dart:177` só expõe `lightTheme`; fundo branco fixo; acentos semânticos copiados do Tailwind (`success #22C55E`, `error #DC2626`...). **Zero cor de marca** — nenhum "laranja do BJJ".
- **Geometria fofa, zero textura:** cantos 12px (`:264`), chips pílula 20px (`:353`), badge 16px (`stat_tile.dart:74`), check pastel `alpha 0.12` (`celebration.dart:88-92`). Motion está **certo** (`polish_tokens.dart`: 150–400ms, easeOutCubic, stagger capado) — não mexer na física; falta significado.

### 3.2 A direção — "Linhagem"

**Paleta:**
- **Tinta, não branco puro:** `background #FFFFFF` → quase-branco quente "tatame/gi cru" (~#FAFAF7); `textPrimary` → preto real #0A0A0A. Contraste alto, editorial.
- **Dark mode obrigatório:** adicionar `darkTheme` com canvas #0A0A0A (`theme.dart:177`). A estética de tribo dura vive no preto; o cartão compartilhável pede fundo escuro para a faixa "saltar".
- **Um acento de marca dono:** recomendo um **vermelho-sangue/coral seco** (~#C2410C–#B91C1C), dialogando com a faixa preta-vermelha de mestre/coral (`theme.dart:46,499` já tem `beltRed`/coral). Vira "o laranja do Strava" do BJJ — CTA, streak vivo, marca no cartão. **Aposentar o roxo do chrome.**
- **Faixas = sistema cromático sagrado, separado do chrome:** as 10 cores de faixa (`theme.dart:37-46`) são o material de marca mais valioso. Regra rígida: cor-de-faixa só representa **uma faixa real**; UI semântica (sucesso/erro) usa neutros + o acento.

**Tipografia:**
- **Adicionar display face com caráter** (grotesca condensada/industrial tipo Archivo/Anton/Druk-like) em ALL-CAPS para títulos-herói, rótulos de seção e cards. Inter fica **só** para corpo/UI densa — deixa de ser a cara do app.
- **Numerais tabulares em TODA métrica** (`fontFeatures: [FontFeature.tabularFigures()]`): mat-time, streak, presenças, "8 meses na azul". Faz dado parecer instrumento de precisão.
- **Escala mais agressiva:** subir `displayLarge` (`theme.dart:53`) para 40–56px em telas-marco (graduação, Wrapped). Number-first: número grande herói, rótulo micro-caps com letter-spacing.

**Iconografia:**
- **Banir emoji do chrome.** `stat_tile.dart` deve preferir `IconData` (já suporta, `:55`); migrar todos os emoji para ícones de traço consistente (Lucide/Phosphor).
- **Onde emoji "celebra", trocar por glifo de cultura:** streak = contador tabular + mat-time, não 🔥; pódio = medalha verificada com selo, não 🏆; a faixa estilizada (graus/stripes) é o ícone-identidade dominante.
- **Emoji só sobrevive em conteúdo do usuário** (notas do diário, comentários/oss) — onde é a voz dele, não a da marca.

**Forma & textura:**
- **Reduzir raio:** cards 12→**8px** (`theme.dart:264`), chips pílula 20→**6–8px retângulo** (`:353`). Lê como fightwear/credencial, não bem-estar pastel.
- **Hairline preto, não cinza tímido:** bordas `divider #E5E5E5` (`:24,265`) → traço decidido 1px #1A1A1A no light.
- **Textura real:** headers de perfil e cards compartilháveis com **fotografia** (tatame, atleta, gi) sob overlay preto + tipografia branca; leve **grão/noise** no fundo escuro. É o que mais diferencia de "vetor flat de IA".

**Motion & celebração:**
- Manter a física (`polish_tokens.dart`). **Reescrever a celebração:** `Celebration.confetti` multicolor com roxo (`celebration.dart:23-69`) → numa graduação, a **faixa que "aperta"/o grau riscado na faixa**, com nome do professor e tempo na faixa anterior. Reservar "burst" para vitórias genuínas, **monocromático no acento de marca**. Som/haptic (`polish_button.dart:76`) é o lugar certo de intensidade.

---

## 4. Sistema de cards instagramáveis

### 4.1 Estado técnico (auditado)
- **`qr_flutter ^4.1.0` já existe** (`pubspec.yaml:54`) → QR/deep-link de graça.
- **Faltam `share_plus`, `screenshot`/`RepaintBoundary→toImage`, `path_provider`** — nenhuma ocorrência em `lib/`. Hoje gerar/postar card é literalmente impossível.
- Hero asset pronto: `lib/widgets/common/animated_belt.dart` (faixa multi-sport com morph) — candidato nº1 a herói visual.

### 4.2 Assinatura de marca (ownável, anti-AI-slop)
O app in-app continua utilitário; o **card é um registro visual separado — "modo palco"** (como Strava: app limpo / asset com mapa-herói).
- **Canvas:** quase-preto `#0A0A0A` ("o tatame à noite"), **sem gradiente** — fundo chapado com grão + trama de gi/kimono a ~4% de opacidade.
- **Cor:** **a faixa é a ÚNICA cor do card.** Todo o resto é tinta-osso `#F5F1E8`/cinza-fumaça. O "laranja do Strava" do GraduaBJJ não é cor fixa — é **a faixa da pessoa** (distintividade por construção).
- **Tipografia:** Inter pesos 800/900 com tracking apertado nos headlines + caps tracking-out nos rótulos; bundlar **uma display condensada só-para-cards** como "voz de palco".
- **Lockup:** `GRADUABJJ` tracked-out + `@graduabjj` + chip de QR (`qr_flutter`) para o perfil público.

> Princípio-mestre do card: **monocromo + faixa + grão + tipografia de palco.**

### 4.3 Chassi compartilhado (1 motor, N cards) — 5 zonas
```
┌─────────────────────────────────────────┐  1080 × 1920 (9:16 story)
│  ░░ zona-segura topo (IG UI) — 250px ░░  │
│  [avatar gi]  NOME DO LUTADOR        ✔︎  │  ZONA 1 · IDENTIDADE
│               Academia · Linhagem        │
│ ───────────────────────────────────────  │  hairline osso 1px @20%
│            ★ HERÓI VISUAL ★              │  ZONA 2 · HERÓI (~46% h)
│        (varia por tipo de card)          │
│  FAIXA ROXA                              │  ZONA 3 · TÍTULO
│  3ª graduação · 12 jun 2026              │  display condensada 96pt
│  ┌──────┬──────┬──────┐                  │  ZONA 4 · PROVA
│  │ 4a2m │  287 │  19  │                  │  2–4 números, Lucide
│  └──────┴──────┴──────┘                  │
│ ───────────────────────────────────────  │
│  GRADUABJJ   @graduabjj        [▣ QR]    │  ZONA 5 · MARCA/CTA
│  ░░ zona-segura base (IG UI) — 250px ░░  │
└─────────────────────────────────────────┘
```
Versão **1:1 (feed)** comprime: identidade no topo, herói central dominante, título+prova numa faixa inferior, lockup no canto.

### 4.4 As 6 famílias (herói por momento)
1. **Graduação / Grau** — *maior alavanca viral.* Herói = `AnimatedBelt` em estado final (faixa nova, gigante, sangrando a borda) + graus pop-in. Carrega **quem promoveu** e **tempo na faixa anterior**. Gatilho: instante em que o professor registra.
2. **Finalização / "Tapped"** — *assinatura técnica.* Herói = a técnica como tipografia gigante ("MATA-LEÃO", "TRIÂNGULO") + ícone de linha. Formato 1:1 (figurinha colecionável). Mostra faixa do oponente (sem nome) e data.
3. **Milestone** — *humblebrag aceito.* "100 treinos", "1.000 rounds". Herói = número colossal (count-up congelado) tinta-osso sobre preto.
4. **Streak** — *"sou quem não falta".* Herói = chama de linha (Lucide `flame`, não emoji) + número de **semanas** (nunca diário — anti-Duolingo). Copy de identidade, zero culpa.
5. **X meses de tatame / Beltday** — *reativação garantida.* Herói = timeline da faixa em mini-trilha (estações branca→atual, atual acesa). Dispara automático no aniversário da graduação.
6. **Wrapped / Recap (mês & ano)** — *máquina viral sazonal.* Carrossel de 4–6 cards 9:16 (swipe), cada slide um dado-identidade (horas, golpe assinatura, parceiro mais frequente, maior streak, "apelido de estilo"). Slide final = card-resumo postável + CTA.

### 4.5 Verificado vs. auto-declarado
- **Verificado:** selo `✔︎ VERIFICADO` tinta-osso sólida + "via Academia X". Entra em ranking cross-academy.
- **Auto-declarado:** tag discreta `○ auto-declarado`, contorno **tracejado**, fora do ranking competitivo. Permite o loop solo (cadastro free → card → aquisição) sem trair a cultura.
- Vira componente `VerifiedSeal(state: verified | selfDeclared)`.

### 4.6 Deep-link de aquisição (viral loop)
- Chip de QR → `https://gradua.bjj/u/{uid}?ref=card&type=graduacao`. Landing = **perfil público** (`publicProfiles`, espelho sem PII — já existe).
- Atribuição instrumentada (`cardId`, `type`, `ref`) → medir **k viral**. Meta de design: cada graduação postada ≥1 visitante ao perfil público.
- Convite contextual pós-share: "Quem mais treina com você? Convide seu parceiro de drill."

---

## 5. Redesign priorizado do portal atual (file:line)

### 5.1 Perfil → Passaporte do Lutador (maior oportunidade)
`profile_screen.dart` hoje é um **formulário de CRM**: hero → 2 stat cards → "GERENCIADO PELA ACADEMIA" → "MEUS DADOS" (saúde/tipo sanguíneo/CPF/RG/emergência) (`:96-191`). O hero surfaceia **status de matrícula/cobrança** (`:509-522`) — sinal errado na tela de identidade. Stats rasos: só presenças + tempo de treino (`:69-84`).

**Direção (BIG BET #1):** hero = belt grande herói + nome + apelido/"ring name" + **time/linhagem**; trocar status pill de matrícula por **selo "Verificado pela academia"**. Faixa de stats de orgulho: mat-time (anos/meses+horas), streak, medalhas, tempo na faixa, nº de modalidades. CTA primário **"Compartilhar passaporte"**. Empurrar CPF/RG/endereço/saúde/emergência para um **"Editar dados / Configurações"** secundário (`_DataTile :740`).

### 5.2 Ranking → arena aspiracional
`ranking_screen.dart` bem construído mas administrativo: título "Ranking de Turmas" (`:59`), linhas com "X treinos" (`:366`) = compliance de frequência. Lista plana (`_RankingTile :307`), top-3 só com disco maior (`_RankBadge :388`); sem pódio, sem "você está aqui", sem movimento; `SegmentedButton` Material genérico (`:257-299`).

**Direção:** pódio visual no topo (3 colunas, #1 elevado, belt color), **linha sticky do usuário** ("3º roxa de Curitiba"), indicador de movimento (subiu/caiu), belt color por linha. De "ranking da turma" (academia) para **leaderboard segmentável** (faixa/idade/cidade) = território Lutador.

### 5.3 Home → hierarquia e momento
- Manter e amplificar o `HomeHeroCard` (CTA único priorizado, `:114-124`) como "momento do dia".
- Stats carousel (`:433-557`, `viewportFraction 0.85`) esconde 2/3 dos dados atrás de swipe → trocar por **linha glanceável de 3**.
- Acessos rápidos (`:620-730`) estão enterrados no fim, abaixo da dobra após 9 blocos → **subir a descoberta**.
- Promover **streak/meta** a bloco-herói com peso visual real.

### 5.4 Matar tells de IA
- Emoji-como-ícone: `home_screen.dart:470,495,509,828`; `competitions_screen.dart:276,297,322`; `timeline_screen.dart:483,1060`.
- Gradiente genérico do card de graduação: `home_screen.dart:1075-1082` → belt color sólida + tipografia confiante.

### Tabela de prioridade (impacto × esforço)

| # | Mudança | Arquivo:linha | Por quê |
|---|---|---|---|
| P0 | Separar IA **Lutador vs Academia**; `NavDomain` + re-tag; bottom nav nova; tirar Horários/Presenças dos slots primários | `portal_shell.dart:33-92`, `nav_catalog.dart:32-47,349-479` | Resolve a confusão na raiz; libera slots de retenção |
| P0 | Remover `AcademySwitcher` global; escopar ao header da aba Academia; mover role-swap do monitor para dentro dela | `portal_shell.dart:299,76-92` | Sinaliza que o app é portátil |
| P0 | **Perfil → Passaporte**: belt-herói + apelido + linhagem + selo Verificado + stats de orgulho + CTA compartilhar; dados administrativos p/ secundário | `profile_screen.dart:60-191,467-525,509-522` | Transforma a tela mais administrativa no ativo de identidade |
| P1 | Matar emoji-como-ícone e gradientes genéricos | `home_screen.dart:470,495,509,828,1075-1082`; `competitions_screen.dart:276,297,322` | Remove tells "AI-made" |
| P1 | Tema com identidade: acento de marca, tinta+preto real, dark mode, raio 12→8, hairline escuro, display face, tabular figures | `theme.dart:16,20,24,33-46,51-75,177,264,353` | Linguagem autêntica vs SaaS neutro |
| P1 | **Ranking**: pódio, linha sticky "você", movimento, belt color, regional/segmentado | `ranking_screen.dart:59,257-299,307-452` | De compliance para arena |
| P2 | Celebração monocromática/cultural; remover roxo do confete | `celebration.dart:23-69,48-54` | Tom "oss", anti-confete genérico |
| P2 | `StatTile` default = ícone; subir acessos rápidos; linha de stats glanceável | `stat_tile.dart:55-64,88`; `home_screen.dart:189-192,433-557` | Hierarquia e descoberta |
| P2 | Status de matrícula sai da identidade → contexto só na aba Academia | `profile_screen.dart:509-522` | Separação conceitual |

---

## 6. Design system: reusar vs criar

### 6.1 Reusar (já existe e está bom)
- **`AnimatedBelt`** (`lib/widgets/common/animated_belt.dart`) — herói de identidade multi-sport. `AnimatedBelt(animate:false)` = `GraduationHero` em estado estático, render-to-image direto.
- **`AppTheme.getBeltColor`** (`theme.dart:465`) — alimenta a cor-herói por faixa/esporte (multi-sport de graça).
- **`PolishMotion`/`polish_tokens.dart`** — física de motion correta (150–400ms, easeOutCubic, stagger capado). Governa a preview animada na tela. **Não mexer.**
- **`PolishCard`, `StatTile`, `AnimatedCountUp`** — base da Zona-Prova e dos blocos. Unificar componentes que ainda usam `Card` Material default (`gamification_section.dart:58,145`).
- **`Celebration.confetti`** (`celebration.dart:23`) — dispara na tela no gatilho (graduação) e abre a folha "Gerar card" (ponte emocional → share). **Reescrever o visual** (monocromático/cultural), manter o mecanismo.
- **`qr_flutter`** (`pubspec.yaml:54`), `publicProfiles` (espelho sem PII), `push_notification_service` (gatilhos de beltday/recap).

### 6.2 Criar
**Dependências:** `share_plus`, `screenshot` (ou `RepaintBoundary` puro), `path_provider`.

**Tokens & tema:**
- `darkTheme` (canvas #0A0A0A) em `theme.dart`.
- `NavDomain` + campo `domain` em `NavEntry` (`nav_catalog.dart`).
- Display face condensada bundlada + estilos com `FontFeature.tabularFigures()`.

**Motor de cards** (`lib/widgets/polish/share/`, novo):
```
card_chassis.dart      → ShareCardChassis: 5 zonas + canvas grão/textura,
                         recebe format (story9x16 | post1x1) + heroBuilder.
card_hero_*.dart       → GraduationHero, SubmissionHero, MilestoneHero,
                         StreakHero, MatTimeHero, WrappedSlide (1 por família).
brand_lockup.dart      → BrandLockup: wordmark + handle + QrImageView(deepLink).
verified_seal.dart     → VerifiedSeal(state: verified | selfDeclared).
card_theme.dart        → ShareCardTokens: canvas #0A0A0A, ink #F5F1E8, grão,
                         pesos/tracking de palco, mapeia AppTheme.getBeltColor.
lib/services/
  card_export_service.dart → RepaintBoundary key → toImage(pixelRatio:3) →
                             PNG em path_provider tmp → Share.shareXFiles.
```
**Render off-screen:** card montado num `RepaintBoundary` de 1080px em árvore offstage (`Offstage`/`OverlayEntry`), capturado em pixelRatio alto. O usuário vê só a preview animada + botão "Compartilhar no story".

**Gatilhos:**

| Momento | Card | Disparo |
|---|---|---|
| Professor registra graduação/grau | Graduação | Imediato + `Celebration` reescrita |
| Presença cruza marco (100/1.000) | Milestone | Imediato, push |
| Fecha semana de streak | Streak | Domingo à noite |
| Aniversário de faixa | Beltday/Meses | Anual, push |
| Self-log de finalização | Tapped | Imediato |
| Fim de mês / dezembro | Recap/Wrapped | Agendado |

**Pronto pra ligar já:** graduação e presença existem hoje → Graduação/Milestone/Streak são imediatos. **Card de pódio depende do sync de medalhas de campeonato (deferido no hotfix 2.5.1)** — priorizar quando reativado.

---

### Arquivos-âncora
- `lib/core/navigation/nav_catalog.dart` — `NavDomain` + re-tag das 16 entradas
- `lib/screens/portal/portal_shell.dart` — bottom nav, remoção do switcher global, role-swap do monitor
- `lib/screens/portal/home_screen.dart` — split Lutador vs Academia, remoção do `_AcademyIndicator`, fim de emoji/gradiente
- `lib/screens/portal/profile_screen.dart` — Perfil → Passaporte
- `lib/screens/portal/ranking_screen.dart` — pódio + sticky + segmentação
- `lib/core/theme.dart` — acento de marca, dark mode, display face, tabular figures, raio/hairline
- `lib/widgets/polish/` (+ novo `share/`) — celebração cultural, `VerifiedSeal`, motor de cards