# Repaginada Admin/Professor + Aluno 100% — Plano (b2c)

> **Status de execução (2026-07): F0-F4 IMPLEMENTADAS E DEPLOYADAS.**
> `onAttendanceWrite` dispatcher, `computeRetentionDaily`, `bluesRisk`,
> Retenção promovida no `nav_catalog.dart:174-179` (não é mais órfã), "Radar
> do dia" no dashboard, `brand_tokens.dart` (design system unificado), e o
> passo de modalidades no onboarding (F4) shipped em commit recente. **Só a F5
> (`trainingPairs`, social profundo) continua em aberto** — mesma peça
> pendente descrita em `GALERA_PARCEIROS_TREINEI_PLANO.md`.

> Documento de ARQUITETURA (não implementado). Base: GraduaBJJ Flutter + Firebase (arpjj-76350), branch `b2c`.
> Escopo READ-ONLY já mapeado (2 varreduras admin + 2 varreduras aluno, 2026-07-01) — este doc é o roteiro acionável.
> Missão única deste plano: **reduzir churn de aluno da academia**. Toda decisão abaixo responde a "isso ajuda a manter o aluno treinando?".

---

## Resumo executivo — decisões-chave

1. **Uma fundação serve três frentes.** A CF `onAttendanceWrite` (prevista na Fase 0 do plano mestre B2C e nunca construída) passa a existir e alimenta simultaneamente: (a) agregados de retenção no doc do aluno (radar de churn do admin), (b) materialização server-side do feed (hoje owner-driven, morre quando o aluno some), (c) avaliação de pushes do aluno (streak em risco, goal-gradient de graduação). Um investimento de backend, três loops de retenção.
2. **Retenção 2.0 = de relatório a radar.** O motor de score existente (`RetentionService`, sólido) é promovido: score persistido por CF, tela no menu (hoje `/admin/retencao` é ÓRFÃ — não está no `nav_catalog`), lista acionável (WhatsApp 1-tap, push, registrar contato) e série histórica. O loop fecha: identificar → agir → registrar → medir recuperação.
3. **Canal de mensagem NÃO-financeira nasce.** O proxy tensorroot e a callable de broadcast já existem no backend — só não têm UI nem template de reengajamento. Hoje o admin só consegue falar com o aluno para COBRAR.
4. **Design system: um DNA, duas vozes.** Tokens de marca únicos (`blood` canônico `0xFFB91C1C`, `bone` canônico `0xFFF4F3EF`) consumidos por `FighterTheme` (voz de tatame, aluno) e `AppTheme` (voz de ferramenta, admin). Hoje há **5 vermelhos e 2 bones** no app e o `FighterTheme` mal é usado até pelo lado fighter.
5. **Dashboard do professor vira "Radar do dia"**: HOJE (aulas + chamada 1-tap) · RISCO (top alunos esfriando) · ENGAJAMENTO (streaks, feed, elegíveis a graduação) · FINANCEIRO (condensado, mantém). Hoje o dashboard é 100% gestão+financeiro, cego para o mundo B2C que o aluno vive.
6. **Aluno 100% = fechar os 9 gaps mapeados**, sendo o nº 1 os pushes do loop de treino/social (hoje FCM só envia cobrança e reserva) e o nº 2 o feed materializado no servidor.
7. **Métrica nova e canônica: churn real mensal** (transições `active → inactive/transferred` com timestamp — hoje nem existe `statusChangedAt`). O "relatório de churn" atual mede risco, nunca o churn consumado.
8. **Kill-list herdada dos planos B2C** continua valendo: streak nunca punitivo, self-log nunca alimenta ranking/graduação, bottom do ranking nunca exposto, push com cap + opt-out + quiet hours.

---

## 1. Diagnóstico (estado real, com âncoras)

### 1.1 Admin/professor — estrutura boa, linguagem velha

| Achado | Evidência |
|---|---|
| Shell maduro: catálogo único de nav (Sidebar/Rail/BottomNav do mesmo `kAdminNavCatalog`), gating por papel/flag com estado `locked` (discovery) | `admin_shell.dart`, `nav_catalog.dart:152-346`, `nav_resolver.dart:65` |
| Dashboard cego para o B2C: só gestão+financeiro; zero presença/frequência/retenção/streaks/social | `admin_dashboard_screen.dart` (welcome, checklist, quick actions, stats, mensalidades) |
| Tela de Retenção ÓRFÃ: `/admin/retencao` existe (`app.dart:1227`) mas não está no `nav_catalog`; só se chega ao churn pela aba dentro de Relatórios, que DUPLICA a tela byte-a-byte | `retention_screen.dart:15`, `reports_screen.dart:126-215, 2475` |
| "Social" é enxerto visual: única tela admin em linguagem fighter, com cores locais hardcoded (mais um "blood": `0xFFB3261E`) | `admin_social_screen.dart:40,139-141` |
| 6 destinos financeiros com fronteiras confusas: Financeiro, Cobrança, Relatórios, Relatórios financeiros, Assinaturas, Alunos pagantes | `nav_catalog.dart` seção FINANCEIRO + `financial_reports_screen.dart`, `paying_students_screen.dart` |
| Telas-monólito: `student_detail` 5.5k linhas, `settings` 3.5k, `financial` 3.4k, `reports` 3.3k | `lib/screens/admin/` |
| Onboarding não pergunta modalidade(s); tour vende só gestão/MP, zero lado fighter | `create_academy_screen.dart:426`, `onboarding_gate.dart:96` |
| Bug: cobrar da tela financeira mostra o link do WhatsApp num SNACKBAR em vez de abrir | `financial_screen.dart:1574-1594` |
| Datas sem acento no dashboard ("Terca", "Sabado", "Marco") | `admin_dashboard_screen.dart:88-100` |
| `fl_chart` está no pubspec mas nenhuma tela admin usa; "gráficos" são barras de `Container` na mão | `pubspec.yaml:63`, `reports_screen.dart:1044-1053` |

### 1.2 O relatório de churn hoje (e por que "dá pra melhorar bastante")

Motor: `RetentionService.calculateStudentRisk` (`retention_service.dart:188-396`) — score 0-100 com 4 fatores (queda de frequência 15d vs 15d = 40 pts; inatividade = 30; atraso financeiro = 20; tempo de casa = 10). Classificação ≥75 crítico / ≥50 alto / ≥25 médio.

Limitações concretas:
1. **Client-side e efêmero** — recalcula tudo a cada abertura, baixa TODOS os payments da academia (`retention_screen.dart:80`); nada persiste, não escala.
2. **Sem tendência** — nenhuma série histórica; impossível saber se o churn está melhorando ou se uma ação funcionou.
3. **Não mede churn real** — só risco de alunos ativos; transição para `inactive`/`transferred` é manual e sem timestamp.
4. **Zero ação** — "Ações Sugeridas" são texto estático (`retention_screen.dart:700-729`); único botão do detalhe é "Fechar". Não liga, não abre WhatsApp, não envia push, não registra contato.
5. **Invisível** — fora do menu; risco não aparece na lista de alunos (`students_list_screen` não filtra por inatividade) nem na ficha (`student_detail` não tem "dias sem treinar").
6. **Matéria-prima faltando** — não existe `lastAttendanceDate` em lugar NENHUM (grep vazio em lib/ e functions/); streak é computado por CF mas vira só achievement, não campo consultável.

### 1.3 Aluno — o que falta para o 100%

Gaps confirmados na varredura do portal/fighter (todos já discutidos nos planos B2C, aqui consolidados como checklist de fechamento):

| # | Gap | Âncora |
|---|---|---|
| A1 | **Zero push do loop de treino/social** — FCM só envia financeiro/reserva (e os pushes de marco de `server_functions.js:1605-1626` só disparam no recompute); nada de streak em risco, like recebido, parceiro graduou, "hoje tem treino" | `functions/server_functions.js` |
| A2 | **Feed owner-driven** — post só nasce quando o AUTOR reabre o app (`_emitFeedPosts` client-side, `friend_providers.dart:199-372`); espiral: aluno desengajado → feed vazio → menos motivo pra voltar | `friend_providers.dart` |
| A3 | Campo `note` ("FOCO DO DIA") existe no modelo/service mas está morto na UI do diário | `training_log.dart:54`, fase reward do `diario_screen.dart` |
| A4 | Rótulo "TREINOS" cru — falta "AULAS VERIFICADAS" (com selo) vs "SESSÕES DE TATAME" | plano GALERA_PARCEIROS F0 |
| A5 | Perfil de visitante ainda em 3 abas GRADUAÇÕES/COMPETIÇÕES/FOTOS | `public_profile_screen.dart:72`; plano STREAK_JORNADA §4 |
| A6 | Streak por dias-esperados não implementado (vigora o semanal) | STREAK_JORNADA_PLANO F1 |
| A7 | `trainingPairs` (co-presença "47x juntos") + streak-de-dupla ausentes | GALERA_PARCEIROS F3 |
| A8 | Ranking global sem mitigação para o bottom 40% (pesquisa: reduz atividade em ~53%) | `PESQUISA_RETENCAO_B2C` |
| A9 | Higiene: `friendsActivityProvider` vestigial, fallback `likeCount()` por `.count()`, 41 cores hardcoded em `timeline_screen.dart` | `friend_providers.dart:475-554`, `feed_posts_service.dart` |

---

## 2. Fundação de dados — CF `onAttendanceWrite` + agregados de retenção

**A peça que destrava tudo.** Trigger Firestore em `academies/{aid}/attendance/{attId}` (create + delete, nunca só create — chamada em lote usa `bulkMarkPresent` e presenças podem ser removidas).

### 2.1 O que a CF escreve (fan-out)

**(a) Agregados de retenção no doc do aluno** (mesmo doc de `attendanceCount`, `student.dart:305-306`), sob um mapa `retention`:

```
retention: {
  lastAttendanceDate: Timestamp,     // o campo nº 1 que falta hoje
  attendanceLast7d: int,             // janelas rolantes mantidas pelo job diário
  attendanceLast30d: int,
  weeklyBuckets: { '2026-W27': 3, ... },  // últimas ~9 semanas ISO, poda automática
  riskScore: int, riskLevel: 'low|medium|high|critical',
  riskComputedAt: Timestamp,
}
```

No write de attendance a CF atualiza `lastAttendanceDate` + incrementa o bucket da semana (barato, incremental). Score completo fica com o job diário (2.2).

**(b) Materialização do feed** — a CF dispara o recompute dos marcos feed-relevantes do aluno afetado (streak milestone, mat milestone, weekly_volume da semana fechada), gravando em `feedPosts` com os MESMOS doc-ids determinísticos e invariantes do plano GALERA_SOCIAL_FEED (create-if-absent, respeita `hiddenByAuthor`/`hiddenByStaff`). O `_emitFeedPosts` client-side vira fallback e depois morre. Resolve A2.

**(c) Avaliação de push** (ver §9.1): goal-gradient de graduação (cruzou ≥80% das presenças para o próximo grau → push), marco de streak.

### 2.2 Job diário agendado `computeRetentionDaily`

Espelha o padrão de `processAcademyGamification`. Por academia: 1 query de attendance dos últimos 30d agrupada por aluno + pagamentos vencidos (reusa a regra canônica de `retention_service.dart:307-341`) → grava `retention.*` em cada aluno ativo e um snapshot agregado:

```
academies/{aid}/retentionSnapshots/{YYYY-MM-DD}: {
  atRisk: {critical: n, high: n, medium: n}, activeStudents: n,
  churnedThisMonth: n,                // transições consumadas (2.3)
  avgWeeklyAttendance: x, contactsMade: n, recoveredAfterContact: n,
}
```

Doc pequeno, 1/dia/academia — série histórica barata que hoje não existe. A fórmula do score v1 é o PORT fiel do Dart (40/30/20/10) para manter continuidade; v2 adiciona sinais B2C (§3.6).

### 2.3 Churn consumado (a métrica que não existe)

- `Student` ganha `statusChangedAt: Timestamp` + `statusChangeReason: string?` — gravados em TODA transição de status (hoje a transição é manual e sem data).
- O job diário conta transições `active → inactive|transferred` do mês → `churnedThisMonth` no snapshot → **taxa de churn real mensal** no relatório.
- **Sugestão, nunca automação**: aluno com >45 dias sem presença e sem contato registrado aparece como "sugerir inativar" na Retenção. Marcar inativo continua decisão humana (inativar errado bagunça cobrança).

### 2.4 Rules, privacidade, backfill

- CF escreve via Admin SDK (bypassa rules). Rules novas: nenhuma obrigatória — docs de aluno já são staff-only; `retentionSnapshots` ganha rule read-only para staff (`isAcademyStaff`), write nenhum (só CF).
- **`retention.*`, `riskScore` e `contactLog` NUNCA vão para `publicProfiles`/`fighterProfiles`** — dado interno da academia, invisível ao aluno (LGPD + não estigmatizar).
- **Backfill B-R1** (`functions/scripts/backfill_retention.js`): varre attendance dos últimos 60d por academia e semeia `retention.*` + `statusChangedAt=null`. Sem ele o radar nasce dizendo que todo mundo está a 999 dias sem treinar. Runbook padrão: **backfill → rules/índices → CF → app**.

---

## 3. Retenção 2.0 — do relatório ao radar acionável

### 3.1 Promover a tela

- Entra no `nav_catalog` seção GESTÃO como **"Retenção"**, logo após Alunos (`requiresPermission: students:manage` ou `financial?` → decisão: `students:manage`, retenção é gestão de pessoas, não dinheiro).
- A aba Retenção dentro de Relatórios (`reports_screen.dart:2475`) é REMOVIDA (duplicação byte-a-byte) e vira link "Ver Retenção".
- A tela passa a ler os campos persistidos (`retention.*`) — abre instantânea, sem varrer payments no client. O `RetentionService` client vira só formatação/apresentação.

### 3.2 Lista acionável (o coração da mudança)

Cada aluno em risco ganha três ações reais no lugar do texto estático:

1. **WhatsApp 1-tap** — reusa a infra da Cobrança (`billing_reminder_service.dart:838`) com **templates novos de reengajamento** (`type: 'retention_reengagement'` no payload do proxy tensorroot): "sentimos sua falta" (7-14d), "volta pro tatame" (15-30d), "seu professor quer te ver" (30d+). Mensagem em nome da ACADEMIA, editável antes de enviar. Fallback `wa.me` + `launchUrl` quando canais desabilitados (e corrigir o bug do snackbar em `financial_screen.dart:1594` de quebra).
2. **Push in-app** — para aluno com conta vinculada: notificação "seu professor mandou um salve" via `sendUserNotification` (callable já existe, `server_functions.js:1989`, sem UI hoje).
3. **Registrar contato** — grava em `academies/{aid}/retentionContacts/{autoId}`:

```
{ studentId, channel: 'whatsapp|push|phone|inperson', byUid, at: Timestamp,
  templateId?, note?, outcome: 'pending' | 'recovered' | 'lost' }
```

O job diário fecha o loop sozinho: contato `pending` + presença do aluno em ≤14 dias → `outcome: 'recovered'`. Isso dá a métrica que importa: **taxa de recuperação pós-contato**, exibida no topo da tela ("De 12 contatados este mês, 7 voltaram").

### 3.3 Risco visível onde o professor já trabalha

- **Lista de alunos**: filtro novo "Sem treinar há 7/14/30+ dias" + badge de risco no card (`students_list_screen.dart:36-45` já tem o padrão de filtros).
- **Ficha do aluno**: chip "Última presença há N dias" + risco + mini-strip das últimas 8 semanas (dado já no `weeklyBuckets`), no header do `student_detail_screen.dart`.
- **Dashboard**: bloco RADAR (§6).

### 3.4 Score v2 (depois do v1 estar rodando)

Sinais novos, todos já disponíveis pós-fundação: streak semanal caiu de ativo para zero (peso alto — perda de hábito), no-show em reservas (`class_bookings_admin_screen` já marca), engajamento social zerado (aluno que nunca abre o app não recebe nudge barato — priorizar contato humano), booking cancelado repetido. Manter a fórmula versionada (`riskFormulaVersion: 2`) para o snapshot histórico não virar salada.

---

## 4. Comunicação não-financeira (canal novo)

- **Broadcast da academia**: UI para a callable `sendAcademyNotification` (`server_functions.js:1940-1983`, hoje órfã de UI) — "Avisar todos": aviso de horário, evento, mutirão de graduação. Entrada: Jornal (checkbox "enviar push ao publicar") + botão no dashboard.
- **Opt-out granular do aluno**: `users/{uid}.notificationPrefs: { social: bool, training: bool, academy: bool, billing: true (não desligável) }` — respeitado por TODA CF antes de `sendToUser`. Tela: Perfil do aluno > Notificações.
- **Guardrails de canal** (herdados da pesquisa B2C, agora aplicados): máx. 3 pushes de retenção/semana por aluno, quiet hours 21h–8h locais, instrumentar uninstall-após-push e opt-out rate desde o dia 1. WhatsApp de reengajamento: máx. 1/14 dias por aluno (anti-assédio; é o professor falando, não spam de máquina).

---

## 5. Design system — um DNA, duas vozes

### 5.1 Consolidação de tokens (pré-requisito de qualquer repaginada)

Hoje: 5 "vermelhos de marca" (`fighter_theme.dart:44` `0xFFB91C1C`; `admin_social_screen.dart:141` `0xFFB3261E`; `create_academy_screen.dart:22` `0xFFE0301E`; `AppTheme.error` `0xFFDC2626`; `bloodDeep` `0xFF7F1D1D`) e 2 "bones" (token `0xFFFAFAF7` vs `0xFFF4F3EF` usado de fato no portal). Nem o lado fighter usa o próprio `FighterTheme` (só `academia_hub_screen.dart` importa; `timeline_screen.dart` tem 41 cores na mão).

Decisões:
- **`blood` canônico = `0xFFB91C1C`** (o token oficial do FighterTheme). `AppTheme.error 0xFFDC2626` PERMANECE como cor semântica de erro (erro ≠ marca). Morrem: `0xFFB3261E` e `0xFFE0301E`.
- **`bone` canônico = `0xFFF4F3EF`** (o que está em produção visual; corrigir o token, não as telas).
- Nasce `lib/core/brand_tokens.dart` (ou seção `Brand` dentro de `fighter_theme.dart`): `blood`, `bloodDeep`, `bone`, `ink`, `ash` + tipografia de display (w900/uppercase/tabular). `FighterTheme` E `AppTheme` passam a consumir os mesmos valores.
- Varredura de hardcodes com prioridade: `create_academy_screen.dart` (13), `timeline_screen.dart` (41), `admin_social_screen.dart` (7), `competitions_screen.dart` (9) — trocar por token quando a tela for tocada, sem big-bang.

### 5.2 A voz do admin (o que muda e o que NÃO muda)

O admin é FERRAMENTA: densidade, fundo claro, leitura rápida — isso fica. O que muda é o DNA compartilhado:

- **Acento `blood`** em CTAs primárias e estados ativos (hoje o acento é preto `#111111` — o preto vira estrutura, o sangue vira ação).
- **Headers de seção em voz fighter** (uppercase, w800/900, tracking) — mesma assinatura tipográfica do portal, escala menor.
- **Números tabulares** em todo stat/KPI (`FontFeature.tabularFigures()` — o admin é cheio de números que hoje "dançam").
- **Componentes compartilhados**: stat card, chip de faixa/modalidade (`sports.dart` já dá a cor), strip de 8 semanas, avatar — extraídos para `lib/widgets/shared/` e usados dos dois lados (o aluno vê a MESMA strip de semanas que o professor vê na ficha dele — coerência de produto).
- `admin_social_screen.dart` deixa de ser forasteiro e vira a REFERÊNCIA do padrão novo, mas re-plugada nos tokens (some o `_blood` local).
- Desktop: adoção de `ContentBounded`/`kContentMaxWidth*` nas telas que a repaginada tocar (a fundação de `responsive.dart` é boa; a dívida é adoção, `responsive.dart:38-41`).

---

## 6. Dashboard do professor — "Radar do dia"

Reordenação por valor de decisão (o que o professor precisa DECIDIR hoje), substituindo o dashboard atual (welcome + checklist + quick actions + stats + mensalidades):

1. **HOJE** — aulas do dia (da grade de `classes`) com atalho de chamada 1-tap por turma + reservas/fila do dia. A Chamada é a ação nº 1 do professor e hoje custa 2+ navegações.
2. **RADAR DE RETENÇÃO** — "N alunos esfriando" + top 3-5 por risco (nome, dias sem treinar, 1-tap WhatsApp) + taxa de recuperação do mês → link Retenção. Lê `retention.*`/snapshot — zero custo de query pesada.
3. **ENGAJAMENTO (B2C)** — o termômetro que não existe: streaks ativos na academia (nº de alunos com streak ≥4 semanas), posts/likes da semana (feed que ele já modera no Social), **elegíveis a graduação** (`graduation_screen` já computa; graduação é O evento de retenção do BJJ) e **marcos para reconhecer na aula** ("Pedro fechou 52 semanas") — ponte app → tatame, custo zero, muito BJJ.
4. **FINANCEIRO** — condensa o que existe (card Mensalidades + alertas), sem perder nada; continua gateado por `financial:view`.

Quick fixes que entram junto: datas com acento (`admin_dashboard_screen.dart:88-100`), `AnimatedCountUp` mantido, checklist de ativação ganha os passos B2C (§8).

---

## 7. Navegação e telas admin — consolidação

### 7.1 Menu

- **FINANCEIRO: 6 → 3 destinos.** `Financeiro` (operação: mensalidades/planos/pagamentos; absorve Alunos pagantes como filtro) · `Cobrança` (inadimplência, mantém) · `Relatórios` (absorve `financial_reports_screen` como aba; Retenção SAI daqui). `Assinaturas` vira seção dentro de Financeiro ou Configurações>Financeiro (é setup, não operação diária).
- **GESTÃO ganha "Retenção"** (após Alunos). Ordem proposta: Dashboard · Alunos · **Retenção** · Chamada · Turmas · Reservas · Graduação · Social · Campeonatos · Musculação · Jornal.
- **Loja**: fundir `store_orders_screen` + `store_orders_admin_screen` (papéis sobrepostos hoje).
- **Bottom nav mobile**: Dashboard · Chamada · Alunos · Retenção (se `students:manage`; senão Turmas) · Menu.

### 7.2 Telas-monólito

Sem big-bang de refactor. Regra: **decompor quando tocar**. Este plano toca `admin_dashboard` (reescrita §6), `retention_screen` (reescrita §3), `students_list` (filtros/badge), `student_detail` (header + chip risco — extrair o header como widget é o primeiro corte do monólito de 5.5k linhas), `reports_screen` (remoção da aba duplicada + `fl_chart` nos gráficos de presença — a lib já está no pubspec, não usada no admin).

---

## 8. Onboarding do professor — nascer no mundo novo

- **Passo "Modalidades" na criação da academia** (`create_academy_screen.dart`, entre ACADEMIA e PRONTO): multi-select do catálogo `sports.dart` + principal. A academia deixa de nascer "genérica" num produto que virou multi-esporte; alimenta defaults de turma/graduação.
- **Tour atualizado** (`onboarding_gate.dart:96`): dos 3 slides atuais (gestão/MP), acrescentar 1 slide do lado fighter — "seus alunos têm um app de lutador: streak, jornada, feed — alunos engajados não cancelam". O professor precisa saber que isso existe para promover na academia (adoção do portal pelos alunos é pré-requisito de todos os loops B2C).
- **Activation checklist** (`activation_checklist.dart`) ganha 2 passos B2C: "Convide seus alunos para o app" (código de vínculo + link) e "Publique o 1º aviso no Jornal". A meta do checklist muda de "academia configurada" para "academia configurada E alunos dentro do app".

---

## 9. Aluno 100% — fechamento dos gaps

### 9.1 Pushes do loop de treino/social (A1 — o gap nº 1 do produto)

Todos server-side (CF), todos respeitando `notificationPrefs` + caps (§4). Em ordem de valor:

| Push | Gatilho | Fonte de dados |
|---|---|---|
| **Streak em risco** | qui/sex: streak ativo (≥2 semanas) e semana ISO atual sem treino (attendance ∪ training_logs) | `retention.weeklyBuckets` + `users/{uid}/training_logs` |
| **Hoje tem treino** | CF horária: turma do aluno começa em ~2h | grade de `classes` + matrícula |
| **Goal-gradient de graduação** | `onAttendanceWrite`: cruzou ≥80% das presenças p/ próximo grau ("faltam 3 aulas!") | progresso que o card de graduação já calcula |
| **Like recebido** | `onFeedLikeWrite` (CF já existe, `feed_like_counter.js` — só acrescentar o send) | `likes/` |
| **Parceiro graduou/marco** | na materialização do post (§2.1b), notificar a audiência do autor | `feedPosts` + parceiros |
| **Recap semanal** | dom 19h: "Sua semana: 3 treinos, 12 rolas — streak 9 semanas" | agregados da semana |

Regras: streak em risco NUNCA em tom de culpa (voz: "a semana ainda tá aberta"); recap só se houve ≥1 treino (nunca "sua semana: 0"); ranking JAMAIS em push (A8).

### 9.2 Feed server-side (A2)

Coberto pela fundação §2.1(b). Critério de pronto: aluno que não abre o app há 3 semanas gradua → post aparece para os parceiros no mesmo dia.

### 9.3 Quick wins de UI (frente independente, zero backend)

- **A3** — expor "FOCO DO DIA" (TextField ≤140 chars) na fase reward do diário; o campo `note` já persiste.
- **A4** — rótulos: "AULAS VERIFICADAS" (com selo) e "SESSÕES DE TATAME" no Lutador/Jornada/perfil (plano GALERA F0).
- **A5** — perfil de visitante → 2 abas **JORNADA | FOTOS** (plano STREAK_JORNADA §4; pré-requisito de likes/perfis valerem a visita).
- **A8** — na tabela de ranking, para quem está fora do topo: destacar "seu recorde pessoal"/posição entre parceiros em vez da posição global; nunca push de queda.

### 9.4 Streak por dias-esperados (A6)

Executar o `STREAK_JORNADA_PLANO.md` F1-F2 como está (client-side, `expectedTrainingDays`, fallback ao semanal para quem não configurar). Sinergia nova: o push "streak em risco" (§9.1) fica MUITO melhor com dias-esperados ("seu treino de quarta é hoje") — implementar o streak antes do push refinado.

### 9.5 Social profundo (A7)

`trainingPairs` por co-presença + streak-de-dupla, conforme `GALERA_PARCEIROS_TREINEI_PLANO.md` F3 (CF + backfill, o componente mais pesado — permanece por último). Nota: a CF `onAttendanceWrite` da fundação §2 é o MESMO trigger que o plano de pares precisa — implementar a fundação já deixando o fan-out extensível (um dispatcher, N handlers).

### 9.6 Higiene (A9)

Remover `friendsActivityProvider`/`FriendActivity` vestigiais (`friend_providers.dart:475-554`), remover fallback `likeCount()` por `.count()`, migrar hardcodes de `timeline_screen.dart` para tokens quando tocada.

---

## 10. Rules / CFs / índices / backfills — consolidado

| Peça | Tipo | Novo/Muda |
|---|---|---|
| `onAttendanceWrite` (dispatcher: retenção + feed + push) | CF trigger | **novo** |
| `computeRetentionDaily` | CF scheduled | **novo** |
| `classReminderHourly` | CF scheduled | **novo** |
| `weeklyRecapSunday` + `streakRiskCheck` | CF scheduled | **novo** |
| Send de push em `onFeedLikeWrite` | CF | muda (`feed_like_counter.js`) |
| Template `retention_reengagement` no proxy tensorroot | integração | **novo** (server + client) |
| `retention.*` + `statusChangedAt` no Student | campos | **novo** (Admin SDK; sem rule nova) |
| `academies/{aid}/retentionSnapshots` | coleção | **novo** — rule: read staff, write ninguém |
| `academies/{aid}/retentionContacts` | coleção | **novo** — rule: read/write `isAcademyStaff` |
| `users/{uid}.notificationPrefs` | campo | **novo** — owner-writable (rules atuais já cobrem) |
| Backfill **B-R1** `backfill_retention.js` | script | **novo** — roda ANTES da CF |
| Índice attendance `(date)` range por academia p/ job diário | índice | verificar (já existe `(studentId,date)` e `(classId,date)`) |

Invariantes preservados (não-negociáveis): self-log NUNCA alimenta ranking/graduação; `riskScore`/`contactLog` NUNCA visíveis ao aluno nem espelhados em `publicProfiles`/`fighterProfiles`; feed respeita `hiddenByAuthor`/`hiddenByStaff` em qualquer rewrite; doc-ids determinísticos em tudo que é idempotente.

---

## 11. Roadmap faseado

Duas trilhas paralelizáveis: **BACKEND** (fundação/CF) e **FRONT** (UI que não depende de dado novo). Runbook de cada fase que toca dados: **backfill → rules/índices → CF → app**.

### F0 — Fundação + quick fixes (destrava tudo)
- BACK: B-R1 backfill → rules (`retentionSnapshots`, `retentionContacts`) → CF `onAttendanceWrite` (retenção + feed) → `computeRetentionDaily`.
- FRONT (paralelo, zero backend): `brand_tokens.dart` + correção do bone/blood; Retenção no `nav_catalog`; fix `launchUrl` da cobrança (`financial_screen.dart:1594`); datas acentuadas; A3 (FOCO DO DIA) + A4 (rótulos).
- **DoD:** todo aluno ativo tem `retention.lastAttendanceDate` correto; feed materializa sem o autor abrir o app.

### F1 — Retenção 2.0 (admin)
- Tela nova acionável (WhatsApp reengajamento + push + registrar contato + outcomes automáticos); filtros/badge na lista de alunos; chip + strip na ficha; remoção da aba duplicada em Relatórios; churn real no snapshot.
- **DoD:** professor acha um aluno sumido em ≤3 toques e o contata em 1; taxa de recuperação aparece no app.

### F2 — Pushes do aluno
- `notificationPrefs` + tela de prefs; streak em risco, hoje-tem-treino, goal-gradient, like, parceiro, recap. Instrumentar uninstall/opt-out junto.
- **DoD:** aluno com streak ativa e semana vazia recebe o nudge; nenhum push fora de quiet hours/caps.

### F3 — Dashboard "Radar do dia" + navegação consolidada
- Dashboard novo (§6); financeiro 6→3; bottom nav com Retenção; broadcast UI (Jornal + dashboard); `fl_chart` em Relatórios.
- **DoD:** ação nº 1 do dia (chamada) e aluno em risco nº 1 estão a 1 toque do login do professor.

### F4 — Onboarding + Aluno polimento
- Passo Modalidades + tour com slide fighter + checklist B2C; A5 (perfil 2 abas); A6 (streak dias-esperados, plano STREAK F1-F2); A8 (ranking bottom); A9 (higiene).

### F5 — Social profundo
- `trainingPairs` + streak-de-dupla (GALERA F3, reusa o dispatcher de F0); reconhecimento de marcos no dashboard do professor fecha o ciclo app ↔ tatame.

---

## 12. Métricas & guardrails

**North-star deste plano: churn real mensal por academia** (novo, mensurável a partir de F0/F1). Sustentada por WAS-solo (plano mestre B2C) do lado do aluno.

| Métrica | Fase | Fonte |
|---|---|---|
| Churn real mensal (active→inactive/transferred) | F1 | `statusChangedAt` + snapshot |
| % alunos em risco contatados / semana | F1 | `retentionContacts` |
| Taxa de recuperação pós-contato (voltou em ≤14d) | F1 | outcome automático |
| Lift de presença pós-push (streak risco / hoje-tem-treino) | F2 | attendance vs grupo sem push |
| Uninstall-após-push, opt-out rate | F2 | instrumentação obrigatória |
| D7/D30 do portal + WAS | F2+ | plano mestre |

**Guardrails (reprovam feature, Manipulation Matrix do plano mestre):** streak nunca punitivo; push nunca envergonha (sem "você sumiu", sem posição de ranking); riskScore invisível ao aluno; WhatsApp de reengajamento é voz do PROFESSOR, cap 1/14d; nada de auto-inativar aluno sem humano; vanity metric subindo com guardrail piorando = rollback.

---

## 13. Fora de escopo (explícito)

- Refactor big-bang das telas-monólito (regra: decompor quando tocar).
- Kudos como coleção separada (superado por `feedPosts`+`likes`).
- Automação de cobrança nova (Cobrança atual atende; este plano só conserta o `launchUrl` e reusa o canal).
- Desktop/hardware (plano próprio: `PLANO_DESKTOP_HARDWARE_2026-06.md`) — este plano apenas não piora (usa `ContentBounded` no que tocar).
- Score de risco com ML — a fórmula versionada resolve; sofisticação sem loop de ação fechado é vaidade.
