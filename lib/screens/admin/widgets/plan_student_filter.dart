import '../../../models/student.dart';

/// Aba da folha "Gerenciar Alunos" de um plano (Financeiro → Planos).
enum PlanMembershipFilter { all, inPlan, notInPlan }

/// Projeção pura da lista da folha "Gerenciar Alunos".
///
/// [groupSnapshot] é a foto de quem estava no plano quando a aba atual foi
/// aberta — NÃO o estado ao vivo. De propósito: matricular/remover alguém
/// não pode tirar a linha do lugar na hora (um toque errado sumiria da tela e
/// não daria pra desfazer). O reagrupamento acontece ao trocar de aba.
///
/// "Todos" mantém o fluxo histórico da tela: quem FALTA matricular primeiro,
/// depois quem já está; alfabético dentro de cada grupo. As abas filtradas
/// são só alfabéticas.
List<Student> filterStudentsForPlan({
  required List<Student> students,
  required Set<String> groupSnapshot,
  required PlanMembershipFilter filter,
  required String searchQuery,
}) {
  final query = searchQuery.trim().toLowerCase();
  final result = students.where((s) {
    if (query.isNotEmpty &&
        !s.fullName.toLowerCase().contains(query) &&
        !(s.nickname?.toLowerCase().contains(query) ?? false)) {
      return false;
    }
    switch (filter) {
      case PlanMembershipFilter.all:
        return true;
      case PlanMembershipFilter.inPlan:
        return groupSnapshot.contains(s.id);
      case PlanMembershipFilter.notInPlan:
        return !groupSnapshot.contains(s.id);
    }
  }).toList();

  result.sort((a, b) {
    final aIn = groupSnapshot.contains(a.id);
    final bIn = groupSnapshot.contains(b.id);
    if (aIn != bIn) return aIn ? 1 : -1;
    return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
  });
  return result;
}

/// Quantos dos alunos LISTADOS estão em [enrolledIds]. `plan.studentIds` pode
/// guardar ids de alunos que já não aparecem na lista (inativos/removidos);
/// contar esses faria "No plano + Fora" não bater com "Todos".
int countStudentsInPlan(List<Student> students, Set<String> enrolledIds) =>
    students.where((s) => enrolledIds.contains(s.id)).length;
