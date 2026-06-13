# Plano — E1 + E2: Musculação (periodização + 1RM/metas)

> Continua A5 (catálogo `exercises`) + A6 (`workoutExecutions` + `strength_math`
> Epley + tela de progresso por exercício). Código em inglês, UI pt-BR.
> Gateado por `FeatureId.workouts` (AcademySettings.workoutPlansEnabled) — já existe.

## Decisões do dono (2026-06)
- **E1**: mesociclo **simples** — programa de N semanas, cada semana com
  prescrição curta (sets×reps + intensidade) + foco; aluno vê "Semana X de N".
- **E2**: **calculadora de 1RM** avulsa (Epley + tabela de %) + **metas de carga
  por exercício definidas pelo ALUNO**, acompanhadas na tela de progresso.
- Ordem: **E2 → E1**.

## Reuso confirmado
- `lib/core/strength_math.dart`: `epley1RM(load, reps)`, `bestLoad`, `best1RM`.
- `workoutExecutions` (por `exerciseName`) + `exercise_progress_screen` (PR/gráfico).
- Padrões: Collections, barrel, rules (`isOwnStudentRecord`/`isAcademyStaff`),
  FeatureId/NavEntry, helper puro + teste.

---

## E2 — Calculadora de 1RM + metas de carga  ← **FASE 1**

### Helper puro — estender `strength_math.dart` (+ testes)
- `double loadForPercent(double oneRM, double pct)` → carga para % do 1RM.
- `List<({int pct, double load})> percentTable(double oneRM, {step})` → tabela
  100..50%.
- (Já tem `epley1RM`.)

### Calculadora (UI pura) — `lib/screens/portal/one_rep_max_screen.dart`
- Input carga + reps → **1RM estimado** (Epley). Tabela de %1RM (95/90/.../60%)
  com carga + faixa de reps sugerida. Sem backend.
- Acesso: botão na tela de treinos do portal + atalho na tela de progresso.

### Metas de carga (backend) — coleção `strengthGoals`
- Modelo `StrengthGoal`: id, studentId, exerciseName, targetLoadKg, createdAt.
  Doc determinístico `{studentId}__{exerciseName}` (upsert).
- Serviço `strength_goal_service.dart`: `setGoal`, `getForStudent`, `getOne`.
- **Aluno** define/edita a sua meta; staff lê. Regras espelham `workoutExecutions`.
- **Integração** em `exercise_progress_screen`: card "Meta" (definir/editar) +
  progresso atual (melhor carga) vs meta (% e "faltam Xkg").

---

## E1 — Mesociclo simples (fase seguinte)
- Modelo `Mesocycle`: name, sport?, audience (academy|sport|students) +
  assignedStudentIds, startDate?, weeks: List<`MesoWeek`{index, focus,
  prescription, deload:bool}>, active. Coleção `mesocycles` (espelha audiência de
  `workoutPlans`).
- Helper puro `meso.dart`: `currentMesoWeek(startDate, now, totalWeeks)` →
  índice 1-based (clamp ao fim) + testes.
- Admin `mesocycles_screen.dart`: CRUD + builder de semanas (foco + prescrição +
  marcar deload).
- Portal: "Periodização" na tela de treinos — semana atual destacada + lista das
  semanas. Read-only.

## Fora de escopo
- Cálculo automático de carga por %1RM no mesociclo (decidido: prescrição textual).
- Auto-progressão (regra +Xkg/semana).
- Integração do mesociclo com `workoutExecutions` (registro segue por exercício).

## Testes
- `strength_math` (loadForPercent, percentTable) + `meso` (currentMesoWeek).
