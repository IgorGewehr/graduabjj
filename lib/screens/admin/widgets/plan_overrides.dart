import '../../../services/plan_service.dart';

/// Qual personalização do aluno no plano: valor ou dia de vencimento.
enum PlanOverrideKind { value, dueDay }

/// Alunos com valor/vencimento personalizado em um plano.
class PlanOverrideIds {
  final List<String> value;
  final List<String> dueDay;

  const PlanOverrideIds({required this.value, required this.dueDay});

  List<String> of(PlanOverrideKind kind) =>
      kind == PlanOverrideKind.value ? value : dueDay;
}

/// Quem tem valor/vencimento personalizado em [plan].
///
/// Usa EXATAMENTE a mesma população que o card do plano usa para a receita
/// esperada: alunos ativos e cobráveis no plano, SEM os que estão em conflito
/// (cobrados em mais de um plano — ficam fora do cálculo). É de propósito: o
/// número do selo no card tem que bater com o tamanho da lista que ele abre,
/// senão o "2 personalizados" abre uma lista de 3.
PlanOverrideIds planOverrideIds(
  Plan plan, {
  required Set<String> activeStudentIds,
  required Set<String> conflictStudentIds,
}) {
  final included = plan
      .activeStudentIds(activeStudentIds)
      .where((id) => !conflictStudentIds.contains(id))
      .toList();
  return PlanOverrideIds(
    value: included.where(plan.customValues.containsKey).toList(),
    dueDay: included.where(plan.customDueDays.containsKey).toList(),
  );
}
