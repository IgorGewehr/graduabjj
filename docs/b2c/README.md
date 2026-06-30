# docs/b2c — App do Lutador (GraduaBJJ): visão B2C

## TL;DR

O GraduaBJJ deixa de ser um painel de gestão renderizado para o aluno e vira o **app do lutador**: uma identidade portátil que o atleta abre **toda semana por vontade própria** — porque é ali que mora a prova de quem ele está se tornando — **com ou sem a academia no app**. O objetivo não é lucro, é **retenção de pessoas**: migrar da curva "fitness" (D30 ~3%, intenção que não sustenta) para a curva "social" (D30 ~5%+, motor = rede). A North-Star é **WAS-solo** (Lutadores Ativos Semanais Auto-Motivados: ≥1 ação de identidade/log/social que NÃO depende de presença marcada pela academia, medida por semana porque o BJJ se treina 2-4x/semana e o corpo exige descanso). O produto se constrói em três fases — **Identidade + Diário + Cards** (Fase 1, 100% portátil) → **Social & Descoberta** (Fase 2, exige a densidade que a Fase 1 cria) → **Arena & Ligas** (Fase 3, competição por último porque ranking sem dados é deserto e sem comunidade é tóxico) — sobre uma fundação aditiva (`fighterProfiles/{uid}` espelho PII-free + `onAttendanceWrite` materializando agregados; **nada é re-keyed, nada é movido**), com três guardrails inegociáveis: **mecânica de retenção ética** (streak semanal perdoável, nunca Duolingo diário), **prova verificada vs auto-declarado** (o moat) e **tom feito-por-quem-treina** (anti-AI-slop, faixa como herói, "oss" comedido).

## Ordem de leitura recomendada

> Comece pela síntese (o que foi **decidido**), depois desça para os documentos de detalhe (a **pesquisa** que fundamenta cada decisão).

1. **`00_PLANO_MESTRE`** *(síntese executiva — a visão, a North-Star WAS-solo, os guardrails e a kill-list num lugar só)*
2. **`01_ROADMAP`** *(o plano faseado Fase 0→1→2→3, com a sequência de build alinhada às features)*

Depois, os **8 documentos de detalhe**, agrupados por categoria:

### Pesquisa de mercado / retenção
3. `PESQUISA_RETENCAO_B2C_2026-06.md`
4. `PESQUISA_B2C_APROFUNDADA_2026-06.md`

### Cultura
5. `PESQUISA_CULTURA_LUTADOR_2026-06.md`

### Ideação de features
6. `IDEACAO_FEATURES_LUTADOR_2026-06.md`

### Design & UX
7. `UIUX_DESIGN_PORTAL_LUTADOR_2026-06.md`

### Arquitetura
8. `ARQUITETURA_IDENTIDADE_LUTADOR_2026-06.md`
9. `PREP_FASE_LUTADOR_2026-06.md`

### Status atual
10. `MULTIACADEMIA_STATUS_2026-06.md`

> Observação: os documentos `00_PLANO_MESTRE` e `01_ROADMAP` consolidam e reconciliam os 8 docs de detalhe abaixo. Onde os 8 se contradizem (ex.: posição do Diário de Rolagem, social na Fase 1 vs 2), a decisão final vive na síntese — os docs de detalhe preservam o raciocínio original.

## Mapa dos documentos (uma linha cada)

| # | Documento | O que traz |
|---|---|---|
| 00 | **PLANO_MESTRE** | Síntese executiva: visão única, North-Star WAS-solo, KPIs, guardrails e kill-list — o ponto de entrada de qualquer pessoa nova. |
| 01 | **ROADMAP** | Plano faseado (Fase 0 fundação invisível → 1 identidade → 2 social → 3 arena) com o racional da ordem e a sequência de build. |
| 03 | **PESQUISA_RETENCAO_B2C** | Benchmarks de retenção (curva fitness D1~20-27%/D7~7%/D30~3% vs curva social ~2x) e as mecânicas que movem D1/D7/D30. |
| 04 | **PESQUISA_B2C_APROFUNDADA** | Estudo de caso dos vencedores (Hevy/Strong, Strava, Letterboxd, Beli) — prova que o log de baixíssima fricção é a fundação do hábito (eleva o Diário à Fase 1). |
| 05 | **PESQUISA_CULTURA_LUTADOR** | A cultura da tribo do BJJ: por que se gamifica processo e não a cor da faixa, e por que "genérico = AI slop" mata a credibilidade. |
| 06 | **IDEACAO_FEATURES_LUTADOR** | Catálogo de features candidatas (Passaporte, Diário, Cards, Streak, Mapa do Tatame, Mat Wars, Ligas) e sua big-bet inicial. |
| 07 | **UIUX_DESIGN_PORTAL_LUTADOR** | Direção visual "Linhagem" + nav fighter-first `[Lutador · Cena · (•)Treinei · Academia · Perfil]`, paleta anti-slop, motor de cards. |
| 08 | **ARQUITETURA_IDENTIDADE_LUTADOR** | Modelo de dados global vs academy-scoped, os 3 motores reusáveis (Cards/Placar/Temporadas), backfills e rules cost-safe. |
| 09 | **PREP_FASE_LUTADOR** | Preparação de fase: o que destravar primeiro (home solo, onboarding sem-academia) e os pré-requisitos técnicos de cada bloco. |
| 10 | **MULTIACADEMIA_STATUS** | Estado atual da arquitetura multi-academia (`userAcademyMapping`, `linkedUserId`) — a fundação pessoa↔ficha que já existe em produção. |

---

*Branch de produção: `firebase-production` (Firestore `arpjj-76350`). Esta pasta descreve a estratégia B2C do app do lutador, não o backend Tatami do branch `migration`.*
