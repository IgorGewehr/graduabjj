# Plano — A4: Gamificação (resto)

> O sprint do amigo já entregou **streaks** (cálculo + milestones + hero na home),
> **badges/marcos** (Achievement completo + cron `scheduledGamificationMilestones`
> + timeline + perfil) e **ranking** (semanal/mensal + tela + milestones top-3).
> A4 "resto" = preencher o **único gap real (meta mensal)** + **dar visibilidade**
> na home ao que já existe (ranking do aluno + conquistas recentes).

## Decisões do dono (2026-06)
- Escopo: **meta mensal + surfacing na home**.
- Meta: **padrão da academia + override por aluno**.
- Contagem: **total de presenças no mês** (qualquer modalidade).

## Reuso (já existe — NÃO refazer)
- `studentMonthlyAttendanceProvider(studentId)` → presenças do mês (X).
- `studentAchievementsProvider(studentId)` → conquistas (p/ "recentes").
- `RankingService.getStudentRank({studentId, period: month, scope})` → posição.
- `studentStreakProvider`, `HomeHeroCard` (streak já na home).

## Fase 1 — Meta de frequência mensal
- **AcademySettings**: `monthlyAttendanceGoal: int` (default 0 = desligado) +
  `updateMonthlyAttendanceGoal`. Card "Gamificação" nos ajustes (stepper).
- **Student**: `monthlyAttendanceGoal: int?` (override). Model (fromFirestore/
  toFirestore/copyWith) + setter no `student_form_screen` (seção de plano/frequência).
- **Meta efetiva** = `student.monthlyAttendanceGoal ?? settings.monthlyAttendanceGoal`
  (se ≤ 0 → não mostra).
- **Home**: card "Meta do mês: X/Y aulas" com barra de progresso, quando meta > 0.
  Lê `studentMonthlyAttendanceProvider` + meta efetiva.

## Fase 2 — Surfacing na home (dados já existem)
- Novo provider `studentMonthlyRankProvider(studentId)` → `int?` (period month,
  scope derivado da categoria: kids→'kids', senão 'geral').
- Widget `GamificationSection(student)` na home (após o card de graduação):
  - **Meta do mês** (Fase 1).
  - **Ranking**: "Você está em Nº este mês" (oculto se sem posição).
  - **Conquistas recentes**: últimos 3 achievements (chips/linha), link p/ timeline.
  - Renderiza `SizedBox.shrink()` se não há nada a mostrar (sem meta, sem rank,
    sem conquista) — não polui a home.

## Fora de escopo
- Push automático ao desbloquear badge (infra existe; fica p/ A2/F2).
- Meta por modalidade (decidido: total do mês).
- Animação de unlock de badge.

## Testes
- Helper puro `monthlyGoalProgress(count, goal)` → `(pct, reached)` + testes
  (clamp, goal 0, count>goal).
