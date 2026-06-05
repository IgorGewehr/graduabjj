/// Pure, dependency-free helpers for the monthly attendance goal (A4).
///
/// No Flutter/Firestore imports so the goal math stays unit-testable (mirrors
/// `striking_timer.dart`, `cartel.dart`).
library;

/// Effective monthly goal for a student: their per-student override when set
/// (> 0), otherwise the academy default. Returns 0 when neither is set (>0),
/// meaning "no goal — don't show progress".
int effectiveMonthlyGoal(int? studentOverride, int academyDefault) {
  if (studentOverride != null && studentOverride > 0) return studentOverride;
  return academyDefault > 0 ? academyDefault : 0;
}

/// Progress toward a monthly attendance goal. [pct] is clamped to 0..1;
/// [reached] is true once [count] meets or beats a positive [goal].
({double pct, bool reached, int remaining}) monthlyGoalProgress(
    int count, int goal) {
  if (goal <= 0) return (pct: 0, reached: false, remaining: 0);
  final c = count < 0 ? 0 : count;
  final pct = (c / goal).clamp(0.0, 1.0);
  return (
    pct: pct,
    reached: c >= goal,
    remaining: c >= goal ? 0 : goal - c,
  );
}
