# Plano de Implementação — Registro de Treino + Biblioteca de Exercícios (A6 + A5)

> **Status (2026-07): IMPLEMENTADO em produção** — `lib/models/exercise.dart`,
> `lib/services/exercise_service.dart`, `lib/models/workout_execution.dart`,
> `lib/services/workout_execution_service.dart`,
> `lib/screens/portal/exercise_progress_screen.dart`. Mantido como
> especificação de referência do que foi construído.
>
> Itens **A6** (registro de execução + progressão/PR) e **A5**
> (biblioteca de exercícios com vídeo) do `docs/roadmap-modalidades.md`. Branch:
> `feat/evolucao-modulos`.
>
> Objetivo: hoje o app **entrega** o plano de treino mas só registra um **checklist
> "feito/não"**. A6 adiciona o **registro do que foi feito** (séries: reps + carga) com
> **histórico, PR e gráfico**. A5 adiciona um **catálogo curado de exercícios com vídeo**
> que o montador seleciona. Engajamento diário — forte p/ musculação e condicionamento.

## ⚠️ Não confundir com o que já existe
- **`workoutLogs`** = checklist diário (set de "diaIdx:exIdx" marcados como feitos).
  Continua existindo; o **registro de execução** (A6) é OUTRA coisa (carga/reps por série)
  → **coleção nova** `workoutExecutions`. Não quebrar o checklist atual.
- **`TrainingVideo`** (coleção `content`) = biblioteca de vídeos solta. O **catálogo de
  exercícios** (A5) é uma entidade nova (`exercises`) que pode ter um vídeo.

---

## 1. Diagnóstico — o que já temos a favor

| Já pronto | Onde |
|---|---|
| Plano estruturado (dias → exercícios) + montador + audiência (academia/modalidade/alunos) | `workout_plan.dart`, `workout_plans_screen.dart` |
| `WorkoutExercise` (nome/sets/reps/load/rest/notes — texto livre, sem id) | `workout_plan.dart:27` |
| Checklist diário (`getTodayLog`/`saveTodayLog`, coleção `workoutLogs`) | `workout_plan_service.dart:91` |
| Biblioteca de vídeos (link/upload, audiência, multi-esporte) | `training_video.dart`, `training_video_service.dart` |
| Portal: detalhe do plano com checkbox por exercício | `workouts_screen.dart:158` |
| Regras `workoutLogs` (aluno escreve o seu), `content`/`workoutPlans` (staff escreve, aluno lê) | `firestore.rules:913-960` |
| Multi-esporte (`sport`/audiência) | em ambos os modelos |

**Falta (A6):** modelo+serviço de **execução** (séries reais), histórico por exercício,
**PR** automático, gráfico, e a UI de registro no portal.
**Falta (A5):** modelo+serviço de **Exercise** (catálogo) com categorização e vídeo,
tela admin de catálogo, **picker no montador**, e exibir o vídeo no portal.

---

## 2. Decisões (CONFIRMADAS 2026-06)

0. **Branch:** `feat/evolucao-modulos`.
1. **Catálogo (A5):** **por academia + seed** opcional de exercícios comuns de musculação.
2. **Registro (A6):** **por série** — reps + carga (RPE opcional).
3. **PR / progresso:** **ambos** — guardar séries cruas e derivar PR de **melhor carga** E
   **1RM estimado (Epley)**; gráfico de carga/1RM no tempo.
4. **Vídeo do exercício (A5):** **`videoUrl` direto** no Exercise (link/Storage).

**Padrão do montador (sem decisão — já assumo):** manter o **texto livre** atual
(retrocompatível) **e** adicionar um **picker do catálogo** opcional; ao escolher do
catálogo, grava `exerciseId` + snapshot do nome (+ vídeo). Planos antigos seguem válidos.

---

## 3. Modelo de dados (proposto)

### 3.1 Catálogo — `academies/{id}/exercises/{exerciseId}` (A5)
```jsonc
{
  "name": "Supino reto",
  "description": "...",            // opcional
  "videoUrl": "...",               // opcional (decisão #4)
  "muscleGroup": "peito",          // peito|costas|pernas|ombros|bracos|core|cardio|outro
  "equipment": "barra",            // barra|halter|maquina|peso-corporal|outro (opcional)
  "active": true,
  "createdBy": "...", "createdAt": ..., "updatedAt": ...
}
```

### 3.2 `WorkoutExercise` ganha (retrocompat) — em `workout_plan.dart`
```jsonc
"exerciseId": "<exercises doc id>"   // novo, opcional; null = exercício de texto livre (legado)
```

### 3.3 Registro de execução — `academies/{id}/workoutExecutions/{id}` (A6)
```jsonc
{
  "studentId": "...", "planId": "...",
  "dayIndex": 0, "exerciseIndex": 2,
  "exerciseId": "...",            // se veio do catálogo (p/ agregação)
  "exerciseName": "Supino reto",  // snapshot
  "date": Timestamp,
  "sets": [ { "reps": 10, "load": 60, "rpe": 8 }, ... ],   // RPE opcional
  "notes": "...",
  "createdAt": ..., "updatedAt": ...
}
```
> Indexado por `(studentId, exerciseName, date DESC)` para histórico/gráfico por exercício.

### 3.4 Derivados (no display / helper puro testável)
- **PR de carga** = maior `load` registrado no exercício.
- **1RM estimado** (Epley) por série = `load × (1 + reps/30)`; PR-1RM = maior estimado.
- **Volume** da sessão = Σ(reps × load). Série temporal por exercício p/ gráfico (fl_chart).

---

## 4. Telas

**Admin:**
- **Catálogo de exercícios** (nova tela): CRUD (nome, grupo muscular, equipamento, vídeo),
  busca/filtro. Seed opcional.
- **Montador**: ao adicionar exercício, **picker do catálogo** (busca) ou texto livre.

**Portal (aluno):**
- **Detalhe do plano**: além do checkbox, botão **"Registrar"** por exercício → folha de
  séries (reps + carga [+ RPE]); mostra o **PR** e **"Ver demonstração"** (vídeo) se houver.
- **Histórico/Progresso por exercício**: lista das sessões + **gráfico** de carga/1RM no tempo.

---

## 5. Plano por fases

### Fase 0 — Fundação
- Modelos `Exercise` + `WorkoutExecution` (+ `SetEntry`) + serviços (CRUD/queries).
- `WorkoutExercise.exerciseId` (opcional, retrocompat).
- Helper puro `lib/core/strength_math.dart` (1RM Epley, PR, volume) + testes.
- `firestore.rules`: `exercises` (staff escreve, membro lê) + `workoutExecutions`
  (aluno escreve/le o seu; staff lê) — espelha `content`/`workoutLogs`.
- Índices: `workoutExecutions (studentId, exerciseName, date DESC)`.

### Fase 1 — A5: Catálogo (admin) + seed
- Tela de catálogo (CRUD) + seed opcional de exercícios de musculação.

### Fase 2 — A5: Picker no montador + vídeo no portal
- Montador escolhe do catálogo (ou texto livre); portal mostra "Ver demonstração".

### Fase 3 — A6: Registro de execução (portal)
- Folha de séries (reps+carga[+RPE]) por exercício no detalhe do plano; grava execução.

### Fase 4 — A6: Histórico + PR + gráfico
- Tela/seção de progresso por exercício: sessões + PR (carga/1RM) + gráfico (fl_chart).

### Fase 5 — Polish
- Badge/realce de **novo PR** ao registrar; (opcional) notificação; resumo na home.

---

## 6. Regras e segurança
- **`exercises`**: leitura por membro da academia; escrita por staff. Não sensível.
- **`workoutExecutions`**: aluno cria/edita/le os seus (espelha `workoutLogs`); staff lê
  (acompanhar o aluno). Sem PII sensível (carga/reps).

## 7. Dependências
- `fl_chart` (já temos, da avaliação física) p/ os gráficos de progresso. Nada novo previsto.

## 8. Sequenciamento
**0 → 1 (catálogo) → 2 (picker+vídeo) → 3 (registro) → 4 (histórico/PR/gráfico) → 5 (polish).**
A Fase 3 já entrega "registrar o treino"; a Fase 4 dá o "uau" de progressão/PR.
