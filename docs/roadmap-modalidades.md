# Roadmap — Evolução dos módulos por modalidade

> Checklist vivo para evoluir os módulos do app aos poucos. Baseado em análise
> do código atual + comparação com concorrentes (gestão de academia e de artes
> marciais) feita em 2026-06.
>
> **Princípio de priorização:** features **transversais** (alcançam várias/todas
> as modalidades) vêm antes das **específicas**, por terem o maior ROI.

## Taxonomia das modalidades (para ler o "quem beneficia")

- **🥋 Artes marciais com graduação:** BJJ · Muay Thai · Karatê · Judô · Kickboxing · Luta Livre
- **🥊 Combate de trocação (sem ou com graduação):** Muay Thai · Kickboxing · Boxe
- **⚖️ Esportes de categoria de peso:** BJJ · Judô · Muay Thai · Kickboxing · Boxe · Luta Livre
- **🏋️ Fitness sem graduação:** Musculação
- **(Boxe e Musculação:** `GradeSystem.none` — sem faixa)

## O que já existe (não recomeçar do zero)

| Já pronto | Onde |
|---|---|
| Multi-esporte (sports, sportData, primarySport) + graus corretos por arte | `lib/core/sports.dart`, `lib/models/student.dart` |
| Turmas/horários, chamada, check-in QR; check-in flexível da musculação | `class_service.dart`, `checkin_service.dart`, `musculacao_checkin_service.dart` |
| Biblioteca de conteúdo: vídeos (link/upload) + planilhas (montador + arquivo), audiência por aluno/modalidade/academia | `workout_plan_service.dart`, `training_video_service.dart` |
| Graduação: auto-promoção por contagem de presença + requisitos por faixa | `belt_progression_service.dart` |
| Avaliação técnica 1-5 por categoria (base p/ feedback de skill) | `assessment_service.dart` |
| Conquistas + linha do tempo (base de gamificação) | `achievement_service.dart`, `timeline_screen.dart` |
| Competições (inscrição, resultados, galeria) | `competition_service.dart` |
| Capacidade da turma (`maxStudents`, hoje só informativa) | `class_service.dart` |

> **Mergeado em 2026-06 (sprint do amigo, ex-`cobranca-pix-whatsapp`):** features
> novas que não estavam no roadmap A–F, agora na nossa branch —
> **Cobrança PIX por WhatsApp** (S1–S7, cron 9h, inerte sem `WHATSAPP_API_KEY`),
> **Jornal da Academia** (ver Z1), **Ranking de frequência** (ver A4),
> **Perfil público do aluno** (coleção `publicProfiles` + Cloud Function
> `mirrorStudentPublicProfile` — *precisa deploy de Functions p/ funcionar*),
> **SportTabBar + "Minhas Modalidades"** (UI multi-esporte; infra útil p/ B1),
> e **rework do BackButtonHandler** (com testes). Pendências da síntese em
> `docs/plano-graduacao-pedagogica.md` não afetadas.

---

## A. Transversais — beneficiam TODAS as modalidades (maior ROI)

- [ ] **A1. Reserva/agendamento de aula com vaga + lista de espera** — `maxStudents`
      hoje é só informativo; falta booking pelo aluno, limite de vaga, cancelamento
      e waitlist. Padrão em todo concorrente. _(beneficia: todas as modalidades com turma)_
- [ ] **A2. Push notifications reais** — hoje é stub (sem tokens/APNs). Habilita
      lembrete de aula/treino, "nova planilha/vídeo", "você faltou esta semana",
      lembrete de graduação. _(todas)_ — depende de **F2**.
- [x] **A3. Avaliação física / antropometria** ✅ **CONCLUÍDA (5 fases)** em
      `feat/evolucao-modulos` — peso/altura/IMC, % gordura (manual + Pollock 3 dobras),
      perimetria, dobras, bioimpedância manual, **fotos de evolução privadas**,
      portal "Minha Evolução" (gráficos fl_chart + comparação de fotos), meta numérica
      + progresso, notificação, lembrete de reavaliação e export PDF. Ver
      `docs/plano-avaliacao-fisica.md` e `docs/roteiro-teste-avaliacao-fisica.md`.
      _Pendente: teste manual + merge p/ produção._
- [~] **A4. Gamificação/engajamento** — **PARCIAL**: **Ranking de frequência**
      (leaderboard por turma, semanal/mensal) entregue na branch `cobranca-pix-whatsapp`
      (já mergeada na nossa). **Faltam**: streaks, metas de frequência mensal, badges.
      _(todas)_
- [ ] **A5. Biblioteca de exercícios com vídeo demonstrativo** — catálogo curado
      que o montador de planilha seleciona; cada exercício linka vídeo/GIF.
      Reaproveita a infra de vídeo. _(todas — alimenta condicionamento de qualquer arte
      e o treino de musculação)_
- [ ] **A6. Registro de execução de treino + progressão/PR** — aluno marca
      séries/carga feitas, histórico, recorde automático, gráficos. Hoje o app
      entrega o plano mas não registra execução. _(musculação + condicionamento de
      qualquer modalidade)_

---

## B. Artes marciais com graduação (BJJ · MT · Karatê · Judô · Kickboxing · Luta Livre)

> O recurso mais citado por TODO software de artes marciais. Hoje a graduação é
> **só contagem de presença**; isto adiciona a camada pedagógica.
>
> ✅ **B1–B4 CONCLUÍDOS (6 fases)** em `feat/evolucao-modulos` — ver
> `docs/plano-graduacao-pedagogica.md`. Pendente: teste manual + merge p/ produção.

- [x] **B1. Currículo/syllabus por nível** ✅ — montador admin (técnicas por
      modalidade/faixa, categoria, ordem, vídeo opcional), variante MT + toggle
      Adulto/Kids (BJJ), template BJJ básico opcional. Coleção `syllabus`.
- [x] **B2. Requisitos de graduação compostos** ✅ — elegibilidade soma presença
      **+ % de técnicas dominadas + tempo-em-faixa**, configurável por academia
      (`graduationSkillPolicy` informative|required + `minSkillPct`). Default
      informativo não altera a auto-promoção. Enforça no detalhe, listas e auto.
- [x] **B3. Elegibilidade automática + exame** ✅ — listas refletem requisitos
      compostos; lembrete "apto a graduar" (botão Avisar / Avisar todos, reusa
      `notifyGraduationEligible`); registro de exame/banca nas notas da promoção.
- [x] **B4. Feedback do instrutor por técnica + progresso visível** ✅ — aba
      "Currículo" no aluno (marcar Aprendendo/Praticando/Dominado + nota por
      técnica, % dominado) e portal "Minha Graduação" (read-only, gateado).
      Coleção `skillProgress`.

---

## C. Combate de trocação (Muay Thai · Kickboxing · Boxe)

- [ ] **C1. Registro de sparring/rounds + timer de rounds** — log de sessões
      (sacos, manoplas, sparring) e timer configurável (rounds/descanso).
- [ ] **C2. Biblioteca de combinações/golpes** — sequências (jab-cross-hook…) por
      nível, com vídeo. _(parente de A5/B1, mas voltada a trocação)_
- [ ] **C3. Cartel/ficha de luta** — registro de lutas (V/D/KO, evento, data) além
      do módulo de competições genérico.

---

## D. Controle de peso / categoria

- [x] **D1. Registro de peso + meta + histórico/gráfico** ✅ **coberto por A3**
      (peso no tempo + meta de peso-alvo + gráfico). Falta específico de corte de peso
      (ex.: alerta de categoria/janela de pesagem) se quiser aprofundar depois.

---

## E. Específicas de uma modalidade

**🏋️ Musculação**
- [ ] **E1. Periodização / mesociclos** — progressão planejada por semanas.
- [ ] **E2. Calculadora de 1RM e metas de carga.**
- [x] **E3. Metas de objetivo** ✅ **coberto por A3** — meta numérica (peso-alvo /
      %gordura-alvo) no aluno + barra de progresso no portal, e objetivo categórico
      (hipertrofia/emagrecimento/condicionamento/manutenção) na avaliação.

**🥋 Karatê**
- [ ] **E4. Biblioteca de katas** — recorte do currículo B1, com vídeo por kata e
      exigência por faixa.

**🥋 Judô**
- [ ] **E5. Checklist nage-waza / katame-waza / kata** — recorte do currículo B1
      no vocabulário do judô.

---

## F. Habilitadores técnicos (infra)

- [x] **F1. `storage.rules`** ✅ — criado e endurecido na A3 (fotos de avaliação
      **privadas**: staff + próprio aluno; fallback sem `read` público). Base pronta
      para uploads futuros (vídeos de técnica B1/A5).
- [ ] **F2. Push/FCM real** — cliente + tokens + APNs (iOS). Habilita **A2**.
- [~] **F3. Índices Firestore** — adicionado o índice `physicalAssessments`
      (studentId ASC + date DESC) na A3. Novos conforme cada feature futura
      (conteúdo por sport, reservas por turma/data).

---

## Sequenciamento sugerido (por ROI e dependência)

1. ~~**A3 — Avaliação física/antropometria** (+ F1 storage.rules)~~ ✅ **FEITO**
   (5 fases; falta teste manual + merge). Também fechou D1 e E3.
2. **A6 + A5 — Registro de treino + biblioteca de exercícios** → engajamento diário
   (musculação e condicionamento). **← PRÓXIMO sugerido.**
3. **B1→B4 — Currículo + requisitos de graduação** → transforma a graduação de
   "só presença" em pedagógica; beneficia 6 modalidades de uma vez.
4. **A1 — Reserva de aula com vaga/waitlist** → operação (turmas lotando).
5. **A2 + F2 — Push real** → retenção (lembretes).
6. **C1→C3 — Sparring/rounds/cartel** → diferenciador para trocação.
7. **A4 — Gamificação** → camada de engajamento sobre o resto.
8. **E* / D1 — Específicas** (periodização, 1RM, kata, weight cut) → refinamento.

> Cada item acima merece seu próprio mini-plano (modelo de dados + telas + fases +
> regras Firestore), no formato de `docs/plano-musculacao.md`, na hora de executar.

---

## Z. Backlog — engajamento (NÃO priorizado)

> Ideias capturadas pra não perder, **abaixo** dos módulos (A–F). São apostas de
> engajamento, não dor latente.

### Z1. Mural da Academia (feed enxuto) — **PARCIAL (Jornal da Academia)**
> ✅ Entregue pelo **Jornal da Academia** (sprint do amigo, branch
> `cobranca-pix-whatsapp`, já mergeada): feed cronológico (evento/notícia/seminário)
> com CRUD admin + **push ao publicar** (`sendAcademyNotification`) + o **canal de
> aviso livre do mestre** — que era "o único pedaço realmente novo" que esta nota pedia.

Decisão original (2026-06): **NÃO** fazer feed social estilo Facebook com **post de
aluno / curtidas / comentários** (risco de feed morto, compete com WhatsApp/Instagram,
imposto de UGC). Versão enxuta entregue:

- [x] Tela do **Jornal** no portal, cronológica, com avisos do mestre (texto + imagem,
      só instrutor). + headline na home.
- [ ] **Auto-posts** do que já existe (graduações/conquistas, eventos, competições) —
      **ainda falta** (hoje os posts são manuais do mestre).
- [x] Push quando sai post novo.
- [ ] Evolução só com tração: reações 1-toque (👏/🔥) → comentários → post de aluno.

### Z2. Atalho pra testar o apetite ANTES do mural — **DONE (parcial)**
- [x] "Enviar comunicado" pro mestre → CRUD de evento + notificação/push (dispatcher).
- [ ] Destacar conquistas/eventos recentes na home do portal — **ainda falta**.
- Entrega ~80% do valor com fração do esforço; só vira mural (Z1) se houver uso.

> Já cobre parte disso: **Eventos** (`academy_event`/`event_service`),
> **Conquistas + linha do tempo**, **Notificações/push**. O que falta é só o
> **canal de aviso livre** do mestre.
