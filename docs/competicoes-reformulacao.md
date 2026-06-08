<!-- Gerado pelo workflow .claude/workflows/competicoes-reformulation-architecture.js -->
<!-- Conceito vencedor: Arena: cada campeonato vira uma história da equipe (hype → ao vivo → celebração) -->

# Liga & Arena GraduaBJJ — Reformulação do Módulo de Competições
## Blueprint de Arquitetura (Final)

> Síntese: espinha narrativa em 3 atos (**Arena**) + modelo de dados unificado `competitionEntries` (**Painel de Campeonatos**) + camada de Temporada/XP com recompensas reais (**Liga GraduaBJJ**). Construído sobre a infra de produção (`arpjj-76350`), com entrega faseada para conter o blast radius.

---

## 1. Visão geral

### O problema hoje
O módulo de Competições é **transacional e mudo**. O aluno se inscreve, o admin lança a medalha 1-a-1, e os números ficam presos em cards privados de "Conquistas". Concretamente:

- **Dados duplicados e divergentes:** enrollment vive em `competitionEnrollments`, resultado em `competitionResults`, e existem **duas implementações conflitantes de `getMedalCount`** (CompetitionService vs AchievementService) que podem discordar.
- **Professor = zero acesso.** Tudo é admin-only, sem framework de permissão.
- **Lançamento de resultado 1-a-1** via modal — insuportável com 20+ atletas.
- **Sem agregação:** não há dashboard de medalhas/participação da academia.
- **Dados coletados e inertes:** `transportPreference` e `registrationDeadline` existem mas ficam escondidos do aluno; fotos não têm link com o resultado (`photoId`/`resultId` ausentes).
- **Sem motivação social:** medalhas são stats privados; nenhum leaderboard, streak, ou prova social de que os colegas estão competindo.
- **Sem auditoria:** resultados não têm quem/quando, nem edição rastreável.

### A aposta
Transformar Competições em **a cabine de operações + a história compartilhada da equipe**, onde a gamificação é **subproduto de dados operacionais reais** — nunca pontos vazios.

1. **Uma espinha de dados limpa** (`competitionEntries`) que carrega inscrição → pesagem → resultado num único doc, dirigida por um **lifecycle explícito** (rascunho → inscrições → fechadas → ao vivo → resultados → encerrado).
2. **Cada campeonato é um arco em 3 atos:** **HYPE** (countdown, "Quem vai?", torcida) → **AO VIVO** (professor narra resultados pelo celular, cada medalha vira card de pódio) → **CELEBRAÇÃO** (highlight cards, post no Jornal, timeline).
3. **Uma Temporada por cima** com XP, Season Pass e **recompensas concretas configuradas pelo admin** (desconto na loja, assento prioritário no transporte, vaga de seminário) — a garantia anti-pontos-vazios.

**Princípio de design:** nada se constrói do zero que um sistema existente já faça. Conquistas/timeline renderizam XP e medalhas; `RankingService` ordena os pontos; `NotificationDispatcher` dispara o ciclo de vida; `FeatureId`/`AcademySettings` gateiam o módulo; `onCompetitionCreated` é o template das novas Cloud Functions.

---

## 2. Experiência por persona

### 2.1 Aluno

**Tela de campeonato em 3 estados visuais** (reescreve `competition_detail_screen.dart`):

| Estado | Gatilho (lifecycle) | O que o aluno vê |
|---|---|---|
| **HYPE** | `registrationOpen` / `registrationClosed` | Countdown grande ("Faltam 7 dias"), barra de progresso da inscrição, mural **"Quem vai?"** (avatares dos inscritos via `enrolledStudentIds` + `publicProfiles`), botão de **torcida** ("Bora!"), prazo em destaque que **bloqueia visualmente** quando fechado |
| **AO VIVO** | `ongoing` / `results` | Badge pulsante "Acontecendo agora", resultados pingando (stream in-app), torcida em tempo quase-real |
| **CONCLUÍDO** | `completed` | Pódio da equipe, galeria de fotos vinculadas aos resultados, highlight cards |

**Fluxos-chave:**

- **Inscrição em 1 toque com pré-preenchimento inteligente.** Faixa/idade vêm do cadastro; peso/modalidade lembrados da última `competitionEntry`. **Mata o hardcode `ageCategory='adult'`** (`competition_detail_screen.dart:944`) e a re-digitação. Toggle de transporte (preciso/próprio/a decidir) visível **na própria inscrição**. Concede **XP de inscrição (+10)** na hora — comprometer-se já recompensa.
- **Resultado entra automático** no perfil/timeline quando o professor publica (auto-registro manual mantido como fallback).
- **Highlight Card auto-gerado** após o resultado: PNG compartilhável (nome + medalha + faixa + campeonato + logo da academia) com botão "Compartilhar" e prompt imediato **"Adicionar foto do pódio"** — fecha o gap foto↔resultado.
- **Registrar derrota/participação honestamente** ainda rende **XP de Coragem (+20)** + badge **Guerreiro** — competir é recompensado, não só vencer.

**Telas novas/alteradas (aluno):**
- `portal/competitions_screen.dart` reformulada: **Hub da Temporada** no topo (barra de XP + tier atual + próxima recompensa + barra do Desafio da Equipe), abas Próximas/Inscrições/Histórico, **empty states com CTA ativo** ("Nenhuma agendada — peça um campeonato ao seu professor").
- **Carteira de Atleta / Estante de Medalhas** no perfil e `public_profile_screen.dart`: contagem ouro/prata/bronze + streak + próximo marco + Competitor Card compartilhável.
- **Leaderboard de Pódio da Temporada** reusando o layout de `ranking_screen.dart` (toggle: Pontos da Temporada / Presença).
- **Sua Jornada** (`timeline_screen.dart`) ganha eventos de XP/streak/quest de competição — **sem tela nova**, só popular.

### 2.2 Professor — *acesso habilitado pela primeira vez*

Nova permissão `competitions.manage` (escopo de turma/modalidade, **sem acesso financeiro**), reusando o padrão `monitorIds`/role existente. Professor **não pode deletar campeonato nem editar resultado finalizado sem auditoria**.

- **Modo "Dia da Competição" (mobile-first):** lista dos atletas inscritos do professor; para cada um, seletor rápido ouro/prata/bronze/participou em 2 toques. **Cada lançamento publica o card de pódio na hora** — o professor é o narrador ao vivo da equipe.
- **Mesa de Resultados (lançamento em lote):** roster completo como **uma lista editável**, posição por atleta numa passada, um único "Publicar resultados" grava tudo e gera achievements de uma vez. **Resolve a tediosidade do 1-a-1** (`competition_detail_screen.dart`).
- **Botão "Postar pódio da equipe no Jornal"** ao fechar: gera o post de celebração coletivo via `event_service`, notificando todos.
- **Painel de Hype / Caravana:** vê inscritos, quem precisa de transporte vs vagas, sugestão de auto-pareamento, e dispara nudge ("Faltam 3 dias / faltam vagas no transporte").
- **Desafio da Equipe:** define meta coletiva da temporada/evento ("30 inscrições" ou "10 pódios"), visível a todos como barra de progresso compartilhada.

### 2.3 Admin

- **Feature flags em Settings:** `competitionsEnabled` (liga o módulo) + `competitionHypeEnabled` (countdown/torcida/feed) + `competitionLeaderboardVisibleToStudents`, seguindo exatamente o padrão `storeEnabled`/`rankingVisibleToStudents`. `FeatureId.competitions` no `nav_catalog` + gate no `nav_resolver`.
- **CompetitionCommandScreen** (substitui `admin/competitions_screen.dart`): abas Próximas/Em andamento/Encerradas + dashboard de medalhas no topo; FAB "Anunciar Competição" com formulário de lifecycle/modalidades/taxa opcional.
- **CompetitionOpsSheet** (gestão do evento): sub-abas Inscritos (check-list) · Pesagem (peso aferido + **alerta de estouro de categoria**) · Resultados em lote · Transporte (roster carona/vagas) · Relatório/Export.
- **Dashboard de Estatísticas da Academia** (preenche o gap de agregação): total de medalhas por categoria/modalidade, tendência de participação por temporada, top performers, conversão inscrito→competiu, `teamPosition` agregada.
- **Gestão de Temporada:** criar Temporada (janela de datas + thresholds de tier + recompensas + regras de XP com defaults sãos), **encerrar para coroar campeões** e snapshot do Hall da Fama.
- **Taxa de inscrição opcional** via `PaymentService` (cobrança `pending→paid` ao lado de cada inscrito). **Auditar unidade reais×centavos antes de cobrar** (bug histórico).
- **Auditoria de resultados:** editar/corrigir com trilha `recordedBy`/`recordedAt`/`updatedBy`/`updatedAt` + re-sync idempotente do achievement.
- **(Fase 4, opcional) Modo Academia-vs-Academia** para franquias — explicitamente fora do v1 por cruzar isolamento de tenant.

---

## 3. Mecânicas de gamificação (e o benefício real de cada uma)

> Regra de ouro: **toda mecânica ancora num fato real ou numa recompensa concreta.** Pontos vazios são proibidos.

| Mecânica | Como funciona | Benefício real (anti-vaidade) |
|---|---|---|
| **Ledger de XP** | inscrição +10, check-in/pesagem +15, participar/resultado +25, bronze/prata/ouro +50/+75/+120, derrota honesta ("Coragem") +20. **Todos admin-tunáveis.** | XP alimenta a timeline que o aluno já possui e o Season Pass com recompensas concretas |
| **Season Pass (tiers)** | Estreante → Competidor → Veterano → Lenda. Cada tier desbloqueia recompensa **configurada pelo admin** (% desconto na loja, assento prioritário no transporte, vaga de seminário) | **A garantia anti-pontos-vazios.** Empty-state de setup força o admin a definir ao menos uma recompensa |
| **Torcida (cheers)** | contador social por atleta por evento; atleta recebe "X colegas estão te apoiando" | Reconhecimento entre pares barato e emocional, não placar abstrato |
| **Pontos de equipe** | ouro=9/prata=3/bronze=1 (IBJJF-like, configurável por `teamPointsConfig`); soma define `teamScoreNum` → sugere a colocação da equipe | Número que o professor entende e usa de verdade; alimenta leaderboard + card "Nossa equipe no \<campeonato\>" |
| **Badges narrativos** | Estreante (1ª competição), Primeira Medalha, **Guerreiro** (competiu sem medalhar — celebra coragem), Trinca, Multi-modalidade (Gi+No-Gi), Caravana (usou transporte da equipe), Anfitrião (competiu em casa) | Cada um é um `AchievementType.milestone` com `autoKey` idempotente; conta uma história real |
| **Streak de competição** | eventos/temporadas consecutivos com participação (badge em 3/5/10) | Recompensa consistência; renderizado via maquinaria `attendanceStreak` existente (`streakDays` já existe no Achievement) |
| **Desafio da Equipe** | barra coletiva ("Rumo a 30 inscrições") | Inscrição individual move visivelmente um objetivo do time — prova social que ataca a falta de motivação |
| **Leaderboard de Pódio da Temporada** | ranking por pontos de medalha no período | Prova social opt-in (`isProfilePublic`), hidratado por `publicProfiles` (sem PII) |
| **Highlight Card / Competitor Card (PNG)** | troféu compartilhável | Gamificação que dobra como marketing/recrutamento da academia |

**Integridade:** resultado auto-reportado pelo aluno **só conta XP no leaderboard público após confirmação do professor** (`recordedBy` setado). Badges escassos e ligados a fatos para não banalizar a competição real.

---

## 4. Modelo de dados e backend

### 4.1 Coleção unificada (a espinha) — *graft do Painel de Campeonatos*

**NOVA** `academies/{academyId}/competitionEntries/{entryId}` — consolida `competitionEnrollments` + `competitionResults` num doc por atleta-por-evento:

```
{
  competitionId, competitionName, seasonId,
  studentId, studentName, sport,
  status: enrolled | weighedIn | noShow | resulted,   // CompetitionEntryStatus enum
  // inscrição
  transportPreference, transportSeatConfirmed: bool,
  beltCategory, ageCategory, weightCategory, targetWeight,
  divisionType, modality,                              // pré-preenchidos
  enrolledAt, enrolledBy,
  // pesagem
  weighInWeight?, weighInAt,
  // resultado
  position?: gold | silver | bronze | participant,
  teamPoints?: num,                                    // derivado da position
  achievementId?, photoId?,                            // link result↔foto
  xpAwarded?: int,
  entryFeeFinancialId?,
  recordedBy?, recordedAt?, updatedBy?, updatedAt?     // auditoria
}
```

### 4.2 Extensões em coleções existentes

**`competitions`:**
```
status: CompetitionStatus { draft, registrationOpen, registrationClosed,
                            weighIn, ongoing, results, completed, cancelled }
seasonId, modalities: List<String>,
entryFeeCents?: int, teamPointsConfig: Map, squadMedalGoal?: int, federation?: String,
cheerCount: int,                  // agregado por CF
teamScoreNum: num,                // ⚠️ campo numérico NOVO (não sobrescreve teamPosition: String)
createdBy, completedBy, completedAt, updatedBy,
highlightPostId?                  // ref ao post do Jornal
// registrationDeadline, transportCapacity, enrolledStudentIds já existem
```
> **Decisão de reconciliação (resolve weakness do Arena):** `teamPosition` (String 'gold'/'silver'/'bronze') é **mantido** para o trophy showcase existente. Introduzimos **`teamScoreNum`** numérico separado para o cálculo de pontos; uma CF deriva a sugestão de `teamPosition` a partir de `teamScoreNum`, sem migrar o campo String.

**NOVA subcoleção** `.../competitions/{id}/cheers/{cheerId}`: `{fromUserId, toStudentId, createdAt}` — agregada por CF em `cheerCount` (cliente **nunca** lê a subcoleção direto, só o agregado, para conter custo de leitura).

**NOVA** `academies/{id}/competitionSeasons/{seasonId}` — *graft da Liga*:
```
{ name, startDate, endDate, status: active|closed, sport,
  tierThresholds: {competidor, veterano, lenda},
  tierPerks: {tier -> {type, value, label}},          // recompensas concretas
  xpRules: {enroll, checkin, participate, gold, silver, bronze, loss},
  teamChallenge: {goalType, target, progress},
  championStudentId?, createdBy }
```

**NOVA** `academies/{id}/competitionPoints/{studentId}_{seasonId}` — fonte do leaderboard, escrita por CF, **PII-free** para espelhamento:
```
{ studentId, seasonId, sport, totalXp, tier,
  breakdown: {enroll, checkin, medals, streak, loss},
  currentStreak, lastEventDate, rank }
```

**`AcademySettings`:** `competitionsEnabled` (default false), `competitionHypeEnabled` (default true), `competitionEntryFeesEnabled`, `competitionLeaderboardVisibleToStudents`, `competitionProfessorCanManage` + `updateCompetitionSettings` no `SettingsService`.

**`competitionPhotos`:** adicionar `resultId`/`entryId` (link foto↔resultado).

**`Achievement`:** **nenhum campo novo** — reusa `type=competition` (`position`) e `type=milestone` (`autoKey`/`iconKey`/`streakDays`).

**CONSOLIDAÇÃO crítica:** depreciar o `getMedalCount` duplicado em `CompetitionService`; **`AchievementService` vira fonte única** de medalhas/XP, com resultados escrevendo através dela. (Resolve o conflito de fonte-de-verdade antes de empilhar XP.)

### 4.3 Cloud Functions (todas idempotentes, modeladas em `onCompetitionCreated`)

| CF | Trigger | O que faz |
|---|---|---|
| `onCompetitionEntryResulted` | doc trigger em `competitionEntries` quando `status→resulted` | cria/atualiza `Achievement` idempotente (`autoKey=entryId`), computa XP por `xpRules`, upserta `competitionPoints`, recalcula tier, cunha marcos/streaks, gera highlight card, dispara `notifyCompetitionResult` |
| `recomputeCompetitionLeaderboard` | callable/scheduled | agrega `competitionPoints` por temporada/modalidade em doc espelho para o `RankingService` |
| `syncCompetitionPointsToPublicProfile` | onWrite `competitionPoints` | espelha tier/rank em `publicProfiles` via `PUBLIC_PROFILE_SAFE_FIELDS` |
| `closeSeason` | callable/admin | congela standings, seta `championStudentId`, cunha "Campeão da Temporada", broadcast |
| `scheduledCompetitionReminders` | pubsub diário | varre `status=registrationOpen/upcoming`, dispara T-7/T-3/T-1 |
| `onCheerCreated` | doc trigger em `cheers` | incrementa `cheerCount`, notifica o atleta torcido |
| `onCompetitionCreated` (estendido) | existente | respeita `competitionsEnabled`, segmenta por modalidade/elegibilidade |

### 4.4 Regras de segurança (Firestore)

- `competitionEntries` / `competitions`: admin **e** professor com `competitions.manage` podem escrever; professor **não** pode escrever `entryFeeFinancialId`/financials nem deletar competição; resultado finalizado só editável com trilha de auditoria.
- `competitionPoints` / `publicProfiles`: write **server-only** (CF), read conforme `isProfilePublic`.
- `cheers`: write autenticado da própria academia; agregação só por CF.

---

## 5. Reaproveitamento da infra existente

| Sistema | Como é reusado | Honestidade do reuso |
|---|---|---|
| **Conquistas + Sua Jornada** (`achievement_service`, `timeline_builder`, `timeline_screen`) | renderizam XP, streaks, medalhas, badges, campeão de temporada. `autoKey`/`streakDays`/`position`/`iconKey` já existem | **Plug-and-play** — só popular |
| **Notificações** (`notification_dispatcher`) | novos métodos `notifyCompetitionReminder`/`notifyCompetitionResult`/`notifyCheerReceived`/`notifyTierUp`/`notifySeasonChampion`. `NotificationType.competitionReminder` + `studentMilestone` já existem | **Alto reuso** (novos métodos no padrão existente) |
| **Perfis públicos** (`publicProfiles` + `PUBLIC_PROFILE_SAFE_FIELDS`) | leaderboard e mural "Quem vai?" sem PII; estende o sync para carregar tier/rank | **Plug-and-play** |
| **Pagamentos** (`PaymentService`/Asaas/MP) | taxa de inscrição como cobrança `pending→paid` | Reuso direto; prêmios multi-beneficiário ficam para fase posterior |
| **Feature flags** (`AcademySettings` + `FeatureId` + `nav_resolver`) | gate por academia igual store/ranking | **Plumbing net-new modesto** — `FeatureId.competitions` ainda não existe |
| **Ranking** (`RankingService` + `RankingEntry`) | reusa `RankingEntry` + hidratação `publicProfiles`; **a agregação de pontos é caminho NOVO** | ⚠️ **Adaptação, não plug-and-play.** `RankingService` é acoplado a `attendance_service` e ordena por contagem de presença num intervalo. Reusamos o **modelo e a hidratação**, mas o cálculo por medalha/XP é código novo (`recomputeCompetitionLeaderboard`) |
| **Jornal** (`event_service` + `event_detail_screen`) | post de celebração coletivo da equipe | Reuso direto |
| **CF template** (`onCompetitionCreated` + `sendToTopic`) | molde dos novos triggers | Reuso de padrão |

> **Correção explícita das weaknesses dos juízes:** o reuso de `RankingService` está marcado como **adaptação** (não plug-and-play); `teamPosition` String é **preservado** com `teamScoreNum` numérico novo ao lado; `FeatureId.competitions` é reconhecido como plumbing net-new.

---

## 6. Roadmap em fases (MVP → completo)

> Filosofia: fatiar o XL. Cada fase entrega valor isolado e é deployável sozinha. Branch alvo: **`firebase-production`**.

### Fase 0 — Fundação & consolidação · esforço **S** · *sem dependências*
- Consolidar `getMedalCount` → `AchievementService` como fonte única.
- `FeatureId.competitions` + `competitionsEnabled` em `AcademySettings` + gate no `nav_resolver` (módulo **off** por padrão).
- `CompetitionStatus` estendido para o lifecycle completo.
- **Entrega:** flag desliga/liga; nada quebra em prod.

### Fase 1 — Espinha unificada + lote + auto-achievement · esforço **L** · *depende de F0*
- `competitionEntries` com **dual-write** temporário + leitura back-compat de `enrollments`/`results`.
- Inscrição 1-toque pré-preenchida (mata `ageCategory='adult'`).
- **Mesa de Resultados** (lote) + `onCompetitionEntryResulted` (idempotente, `autoKey=entryId`).
- Permissão `competitions.manage` + regras Firestore + auditoria (`recordedBy`/`recordedAt`).
- Link foto↔resultado (`photoId`/`resultId`).
- **Script de migração** com dupla-escrita, validado em staging antes de prod.
- **Entrega:** professor opera; admin lança em lote; resultado vira achievement automático.

### Fase 2 — Arena (3 atos) + social · esforço **L** · *depende de F1*
- `competition_detail_screen` em HYPE/AO VIVO/CONCLUÍDO + mural "Quem vai?".
- Torcida (`cheers` + `onCheerCreated`) com agregado `cheerCount`.
- Modo "Dia da Competição" + "Postar pódio no Jornal".
- Highlight Card / Competitor Card (PNG) + prompt de foto pós-resultado.
- `scheduledCompetitionReminders` (T-7/T-3/T-1, in-app).
- **Entrega:** o loop emocional completo; o app "vive" o campeonato.

### Fase 3 — Temporada, XP, Season Pass & Leaderboard · esforço **L** · *depende de F1/F2*
- `competitionSeasons` + `competitionPoints` + ledger de XP + Season Pass com recompensas.
- `recomputeCompetitionLeaderboard` + `syncCompetitionPointsToPublicProfile` + `closeSeason`.
- Hub da Temporada no portal + Leaderboard de Pódio + Desafio da Equipe.
- Dashboard de Estatísticas da Academia.
- **Backfill idempotente** de resultados legados (via `autoKey`).
- **Entrega:** progressão sustentada + prova social + Hall da Fama.

### Fase 4 — Pesagem, transporte, taxas & inter-academia (opcional) · esforço **M–L** · *depende de F1/F3*
- Pesagem com alerta de estouro de categoria; Caravana board com auto-pareamento.
- Taxa de inscrição via `PaymentService` (**auditar reais×centavos primeiro**).
- (Opcional) Academia-vs-Academia — **só após revisão de privacidade cross-tenant**.

---

## 7. Riscos e mitigação

| Risco | Sev. | Mitigação |
|---|---|---|
| **Migração de dados em prod** (`arpjj-76350`): unificar 2 coleções em `competitionEntries` | Alto | Dual-write + leitura back-compat; script validado em staging; rollback por flag; migração em F1 isolada |
| **Conflito de fonte-de-verdade** (`getMedalCount` duplicado) | Alto | **F0 consolida antes** de empilhar XP — pré-requisito de tudo |
| **Push stubbed** (`fcmToken => null`): "ao vivo" e lembretes degradam para in-app | Alto | Stream in-app na F2; reativar FCM **antes** de prometer real-time; setar expectativa |
| **Nova superfície de segurança** (`competitions.manage` + regras) | Alto | Reusar padrão `monitorIds`/role; professor sem financials; `security-review` obrigatório na F1; testes de regras |
| **Reuso de ranking superestimado** | Médio | Tratado como **adaptação** no escopo; `recomputeCompetitionLeaderboard` é trabalho novo orçado na F3 |
| **`teamPosition` String vs pontos numéricos** | Médio | `teamScoreNum` novo separado; String preservado para o showcase existente |
| **Idempotência de achievements/posts** | Médio | `autoKey`/`highlightPostId` + query-before-create; re-trigger não duplica |
| **Pontos vazios** (admin deixa tier perks vazios) | Médio | Defaults sãos + empty-state que **força** ≥1 recompensa no setup |
| **Multi-esporte** (IBJJF vs Muay Thai vs Judô) | Médio | Temporadas/leaderboards **sport-scoped**; `teamPointsConfig` por federação |
| **Reais×centavos** (taxa de inscrição) | Médio | Auditar unidade antes de cobrar; taxas só na F4 |
| **Custo de leitura** (subcoleção `cheers`) | Médio | Cliente lê só `cheerCount` agregado por CF, nunca a subcoleção |
| **Sobre-gamificar / sobrecarga de UI** | Médio | **Faseamento** é a mitigação: aluno recebe um conceito por fase; badges escassos e ligados a fatos |
| **Resultado auto-reportado infla leaderboard** | Médio | XP público só conta após confirmação do professor (`recordedBy`) |
| **Inter-academia cruza isolamento de tenant** | — | **Fora do v1**; design cross-tenant + revisão de privacidade dedicados na F4 |

---

## 8. Métricas de sucesso

**Engajamento (aluno):**
- % de alunos que se inscrevem em ≥1 competição/temporada (meta: +30% vs baseline).
- Taxa de conclusão da inscrição 1-toque vs fluxo antigo.
- Nº de torcidas por evento; % de atletas que recebem ≥1 torcida.
- Adoção do compartilhamento de Highlight/Competitor Card (PNGs gerados).
- % de fotos vinculadas a resultado (gap fechado: meta >80%).

**Operacional (professor/admin):**
- Tempo médio de lançamento de resultados (lote vs 1-a-1; meta: −70%).
- % de competições com professor (não-admin) operando.
- % de competições com lifecycle completo (draft→completed) sem correção pós-publicação.
- Taxa de uso do dashboard de estatísticas e do roster de transporte.

**Progressão/retenção (Temporada):**
- Distribuição de tiers (quantos chegam a Veterano/Lenda).
- % de recompensas de tier resgatadas (valida que não são pontos vazios).
- Streak médio de competições; retenção de competidores temporada-a-temporada.
- Conversão inscrito→competiu.

**Integridade técnica:**
- Zero divergência entre medalhas exibidas e XP concedido (pós-consolidação F0).
- Zero achievements/posts duplicados (idempotência).
- Migração F1: 100% dos `enrollments`+`results` legados reconciliados sem órfãos.

---

### Resumo executivo
Comece pela **Fase 0** (consolidar `getMedalCount` + feature flag) — risco baixíssimo, desbloqueia tudo. **Fase 1** entrega o maior ganho operacional (espinha unificada + lote + professor). **Fases 2 e 3** entregam o coração emocional (Arena) e a progressão sustentada (Liga). Pagamentos/inter-academia ficam isolados na **Fase 4**, longe do caminho crítico. Cada fase é deployável atrás de flag em `firebase-production`, contendo o blast radius num módulo que tem usuários reais.
