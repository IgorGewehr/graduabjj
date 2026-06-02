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

---

## A. Transversais — beneficiam TODAS as modalidades (maior ROI)

- [ ] **A1. Reserva/agendamento de aula com vaga + lista de espera** — `maxStudents`
      hoje é só informativo; falta booking pelo aluno, limite de vaga, cancelamento
      e waitlist. Padrão em todo concorrente. _(beneficia: todas as modalidades com turma)_
- [ ] **A2. Push notifications reais** — hoje é stub (sem tokens/APNs). Habilita
      lembrete de aula/treino, "nova planilha/vídeo", "você faltou esta semana",
      lembrete de graduação. _(todas)_ — depende de **F2**.
- [ ] **A3. Avaliação física / antropometria** — peso, altura, IMC, % gordura,
      perimetria, dobras, bioimpedância, **fotos de evolução** + gráficos no tempo.
      Hoje só há avaliação 1-5 subjetiva. _(todas; essencial p/ musculação, útil p/
      controle de peso de combate — ver D1)_
- [ ] **A4. Gamificação/engajamento** — streaks, metas de frequência mensal,
      badges. Já há base em conquistas/timeline. _(todas)_
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

- [ ] **B1. Currículo/syllabus por nível** — checklist de técnicas exigidas por
      faixa/grau (posições no BJJ/LL, golpes no MT/KB, **kata** no Karatê,
      **nage-waza/katame-waza/kata** no Judô), com vídeo opcional por técnica.
- [ ] **B2. Requisitos de graduação compostos** — presença mínima **+ tempo-em-faixa
      + skills marcadas como dominadas** (não só presença). Evolui `belt_progression_service`.
- [ ] **B3. Elegibilidade automática + exame** — identificar quem está apto,
      lembrete de graduação, agendar/registrar eventos de grading.
- [ ] **B4. Feedback do instrutor por técnica + progresso visível** — aluno/responsável
      vê o quanto falta pro próximo grau. Evolui a avaliação 1-5 atual.

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

- [ ] **D1. Registro de peso + meta de categoria + histórico/gráfico** — útil em
      corte de peso e acompanhamento. _(esportes de categoria de peso)_ — pode ser
      um recorte de **A3** (antropometria).

---

## E. Específicas de uma modalidade

**🏋️ Musculação**
- [ ] **E1. Periodização / mesociclos** — progressão planejada por semanas.
- [ ] **E2. Calculadora de 1RM e metas de carga.**
- [ ] **E3. Metas de objetivo** (hipertrofia/emagrecimento/condicionamento) +
      acompanhamento contra a avaliação física (A3).

**🥋 Karatê**
- [ ] **E4. Biblioteca de katas** — recorte do currículo B1, com vídeo por kata e
      exigência por faixa.

**🥋 Judô**
- [ ] **E5. Checklist nage-waza / katame-waza / kata** — recorte do currículo B1
      no vocabulário do judô.

---

## F. Habilitadores técnicos (infra)

- [ ] **F1. `storage.rules`** — não existe hoje (gap de segurança). Necessário
      antes de qualquer upload novo (fotos de evolução A3, vídeos de técnica B1/A5).
- [ ] **F2. Push/FCM real** — cliente + tokens + APNs (iOS). Habilita **A2**.
- [ ] **F3. Índices Firestore** novos conforme cada feature (conteúdo por sport,
      reservas por turma/data, medidas por aluno/data).

---

## Sequenciamento sugerido (por ROI e dependência)

1. **A3 — Avaliação física/antropometria** (+ F1 storage.rules) → maior expectativa
   não atendida; encaixa na infra atual; serve todas as modalidades.
2. **A6 + A5 — Registro de treino + biblioteca de exercícios** → engajamento diário
   (musculação e condicionamento).
3. **B1→B4 — Currículo + requisitos de graduação** → transforma a graduação de
   "só presença" em pedagógica; beneficia 6 modalidades de uma vez.
4. **A1 — Reserva de aula com vaga/waitlist** → operação (turmas lotando).
5. **A2 + F2 — Push real** → retenção (lembretes).
6. **C1→C3 — Sparring/rounds/cartel** → diferenciador para trocação.
7. **A4 — Gamificação** → camada de engajamento sobre o resto.
8. **E* / D1 — Específicas** (periodização, 1RM, kata, weight cut) → refinamento.

> Cada item acima merece seu próprio mini-plano (modelo de dados + telas + fases +
> regras Firestore), no formato de `docs/plano-musculacao.md`, na hora de executar.
