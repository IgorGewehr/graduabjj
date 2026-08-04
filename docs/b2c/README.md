# docs/b2c — App do Lutador (GraduaBJJ): visão B2C

## TL;DR

O GraduaBJJ deixa de ser um painel de gestão renderizado para o aluno e vira o **app do lutador**: uma identidade portátil que o atleta abre **toda semana por vontade própria** — porque é ali que mora a prova de quem ele está se tornando — **com ou sem a academia no app**. O objetivo não é lucro, é **retenção de pessoas**: migrar da curva "fitness" (D30 ~3%, intenção que não sustenta) para a curva "social" (D30 ~5%+, motor = rede). A North-Star é **WAS-solo** (Lutadores Ativos Semanais Auto-Motivados: ≥1 ação de identidade/log/social que NÃO depende de presença marcada pela academia, medida por semana porque o BJJ se treina 2-4x/semana e o corpo exige descanso). O produto se constrói em três fases — **Identidade + Diário + Cards** (Fase 1, 100% portátil) → **Social & Descoberta** (Fase 2, exige a densidade que a Fase 1 cria) → **Arena & Ligas** (Fase 3, competição por último porque ranking sem dados é deserto e sem comunidade é tóxico) — sobre uma fundação aditiva (`fighterProfiles/{uid}` espelho PII-free + `onAttendanceWrite` materializando agregados; **nada é re-keyed, nada é movido**), com três guardrails inegociáveis: **mecânica de retenção ética** (streak semanal perdoável, nunca Duolingo diário), **prova verificada vs auto-declarado** (o moat) e **tom feito-por-quem-treina** (anti-AI-slop, faixa como herói, "oss" comedido).

## Ordem de leitura recomendada

> Comece pela síntese (o que foi **decidido**), depois desça para os documentos de detalhe (a **pesquisa** que fundamenta cada decisão).

1. **`00_PLANO_MESTRE`** *(síntese executiva — a visão, a North-Star WAS-solo, os guardrails e a kill-list num lugar só)*
2. **`01_ROADMAP`** *(o plano faseado Fase 0→1→2→3, com a sequência de build alinhada às features)*

Depois, os **8 documentos de detalhe originais** (pesquisa/design que fundamentou a síntese), agrupados por categoria:

### Pesquisa de mercado / retenção
3. `PESQUISA_RETENCAO_B2C_2026-06.md` *(ver nota de correção no topo do arquivo — parte dos benchmarks foi refutada por `PESQUISA_PSICOLOGIA_RETENCAO_RIVAIS_2026-07.md`)*
4. `PESQUISA_B2C_APROFUNDADA_2026-06.md`

### Cultura
5. `PESQUISA_CULTURA_LUTADOR_2026-06.md`

### Ideação de features
6. `IDEACAO_FEATURES_LUTADOR_2026-06.md`

### Design & UX
7. `UIUX_DESIGN_PORTAL_LUTADOR_2026-06.md`

### Arquitetura
8. `ARQUITETURA_IDENTIDADE_LUTADOR_2026-06.md`

> **Nota (2026-07):** os documentos `09_PREP_FASE_LUTADOR_2026-06.md` e
> `10_MULTIACADEMIA_STATUS_2026-06.md`, listados originalmente aqui, saíram
> desta pasta — cada um só continha o resumo do agente que os gerou ("Estrutura
> entregue: ...") em vez do conteúdo real (bug de geração, nunca corrigido).
> Foram movidos para `docs/arquivo/b2c_PREP_FASE_LUTADOR_2026-06_STUB_QUEBRADO.md`
> e `docs/arquivo/b2c_MULTIACADEMIA_STATUS_2026-06_STUB_QUEBRADO.md` (histórico,
> zero conteúdo útil). O estado real de multi-academia vive em
> `docs/MULTIACADEMIA_DESIGN_2026-06.md` (arquivado, histórico) e na seção de
> arquitetura de `ARQUITETURA_IDENTIDADE_LUTADOR_2026-06.md` acima.

> Observação: os documentos `00_PLANO_MESTRE` e `01_ROADMAP` consolidam e reconciliam os docs de detalhe abaixo. Onde eles se contradizem (ex.: posição do Diário de Rolagem, social na Fase 1 vs 2), a decisão final vive na síntese — os docs de detalhe preservam o raciocínio original.

## Segunda onda (jul/2026) — planos de feature específica

Depois da síntese inicial, cada evolução pontual ganhou seu próprio doc de
arquitetura (padrão: "Status de execução" no topo de cada um diz o que já foi
construído vs o que continua em aberto — **não estavam listados aqui antes**):

| Documento | O que traz | Status (ver header do próprio arquivo) |
|---|---|---|
| `JORNADA_MULTISPORT_PLANO.md` | Presenças/turmas/graduações/Perfil/Treinei coesos com multi-esporte no centro; auto-graduação com teto | Implementado |
| `GALERA_PARCEIROS_TREINEI_PLANO.md` | Parceiros de treino por co-presença, kudos, "dois números" (aula verificada vs sessão de tatame) | Kudos/rótulo evoluiu para o doc seguinte; `trainingPairs` (co-presença) ainda não construído |
| `GALERA_SOCIAL_FEED_PLANO.md` | Evolui o anterior: feed materializado (`feedPosts`) com controle de ruído | Implementado (feed); só falta a camada de audiência por co-presença |
| `REPAGINADA_ADMIN_ALUNO100_PLANO.md` | `onAttendanceWrite` como fundação única de 3 loops de retenção; Retenção 2.0/Radar do dia; design system unificado | F0-F4 implementadas; F5 (social profundo) em aberto |
| `STREAK_JORNADA_PLANO.md` | Streak por dias-esperados configuráveis, Jornada do visitante, Avatar do Lutador | Parcial — streak shipado com modelo mais simples (ISO-semanal) que o proposto |
| `ATIVACAO_PROFESSOR_2026-07.md` | Ativação do professor (chamada vazia, turmas, CSV, WhatsApp cobrança) | **Ativo/WIP nesta branch (ux-ativacao)** — não é histórico |
| `DIAGNOSTICO_RETENCAO_2026-07.md` | Diagnóstico de causas-raiz de retenção fraca (push, self-log, grafo social morto) | **Ativo/WIP nesta branch (ux-ativacao)** — não é histórico |
| `PESQUISA_PSICOLOGIA_RETENCAO_RIVAIS_2026-07.md` | Pesquisa aprofundada/verificada de psicologia de retenção + rivalidade; corrige benchmarks de `PESQUISA_RETENCAO_B2C_2026-06.md` | Pesquisa viva — citada diretamente pelo código (`oss_providers.dart`) |

---

*Branch de produção: `firebase-production` (Firestore `arpjj-76350`). Esta pasta descreve a estratégia B2C do app do lutador, não o backend Tatami do branch `migration`.*
