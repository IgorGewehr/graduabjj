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

- [x] **A1. Reserva/agendamento de aula com vaga + lista de espera** ✅ **CONCLUÍDA
      (4 fases)** em `feat/evolucao-modulos` — ocorrência datada sobre as turmas
      recorrentes; capacidade real (`maxStudents`) + **fila de espera
      server-authoritative** (callables `reserveClassSlot`/`cancelClassReservation`,
      contador `classOccurrences` que o cliente não escreve); **auto-promoção** do 1º
      da espera com aviso; **corte de 1h**, **janela de 7 dias** e **limite/aluno**
      configuráveis; portal "Reservar aula" + admin "Reservas" (roster, add/remove,
      **no-show**). Reserva ≠ presença (check-in QR intacto). Ver
      `docs/plano-reserva-aula.md`. **Deploy de functions/rules/índices: FEITO**
      (additivo, não afeta a versão em produção).
      _Pendente: teste manual + merge p/ produção._
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
- [x] **A4. Gamificação/engajamento** ✅ — **streaks, badges/marcos e ranking** já
      vieram completos no sprint do amigo (cálculo + cron `scheduledGamificationMilestones`
      + timeline + hero na home). A4 "resto" fechou o gap real: **meta de frequência
      mensal** (padrão da academia em Ajustes + override por aluno no cadastro; barra
      de progresso "X/Y aulas" na home) + **surfacing na home** (posição no ranking do
      mês + 3 conquistas recentes). Helper puro `gamification.dart` +8 testes. Sem
      deploy (só campos em docs existentes + providers). Ver `docs/plano-gamificacao-a4.md`.
      _(todas)_ _Pendente: teste manual + merge p/ produção._
- [x] **A5. Biblioteca de exercícios com vídeo demonstrativo** ✅ — catálogo
      `exercises` por academia (grupo muscular/equipamento/vídeo) + seed; **picker
      no montador** (linka `exerciseId`, mantém texto livre); **"Ver demonstração"**
      no portal. Ver `docs/plano-treino-execucao.md`.
- [x] **A6. Registro de execução de treino + progressão/PR** ✅ — aluno registra
      **séries (reps + carga + RPE)** por exercício (`workoutExecutions`, upsert
      idempotente/dia); **progresso por exercício** com PR (carga + 1RM Epley),
      **gráfico fl_chart** e histórico; **celebração de novo PR**. _Pendente: teste
      manual + merge p/ produção._

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

> Módulo "Trocação" gateado por `FeatureId.striking` (AcademySettings.strikingEnabled).
> Ver `docs/plano-trocacao.md`. Ordem: C1 → C3 → C2.

- [x] **C1. Registro de sparring/rounds + timer de rounds** ✅ — timer cheio
      configurável (rounds/duração/descanso) com vibração+som; registro do aluno
      (tipo saco/manoplas/sparring/clinch/técnica + rounds + RPE + notas) com
      histórico. Coleção `strikingSessions`. Helper puro +11 testes. _Deploy feito._
- [x] **C2. Biblioteca de combinações/golpes** ✅ — catálogo `combos` por
      modalidade + nível (iniciante/intermediário/avançado), sequência de golpes +
      vídeo opcional; admin "Combinações" (CRUD + seed de modelos boxe/MT/kick) +
      portal read-only por modalidade. Helper de nível +4 testes.
- [x] **C3. Cartel/ficha de luta** ✅ — cartel oficial (só staff escreve, aluno vê):
      V/D/E + método (KO/TKO/Decisão/Finalização/DQ), evento, data, adversário,
      peso, rounds, vídeo, notas. Resumo "XV-YD-ZE (N nocautes)". Aba "Cartel" no
      aluno (admin) + portal "Meu cartel". Coleção `fightRecords`. Helper +7 testes.

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
2. ~~**A6 + A5 — Registro de treino + biblioteca de exercícios**~~ ✅ **FEITO**
   (6 fases; falta teste manual + merge). 1RM Epley cobre parte de E2.
3. ~~**B1→B4 — Currículo + requisitos de graduação**~~ ✅ **FEITO** (6 fases).
4. ~~**A1 — Reserva de aula com vaga/waitlist**~~ ✅ **FEITO** (4 fases; falta
   deploy + teste manual). Lembrete de aula fica p/ A2 (depende de push real).
5. **A2 + F2 — Push real** → retenção (lembretes). **← PRÓXIMO sugerido.**
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
