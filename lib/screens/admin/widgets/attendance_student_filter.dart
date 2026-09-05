import '../../../models/student.dart';

/// Filtra o roster da chamada sem mutar a lista carregada pela tela.
List<Student> filterAttendanceStudents({
  required List<Student> students,
  required String searchQuery,
  required Set<String>? classStudentIds,
  required Set<String> presentStudentIds,
  required String filterMode,
}) {
  final query = searchQuery.trim().toLowerCase();
  final filtered = students.where((student) {
    if (query.isNotEmpty &&
        !student.fullName.toLowerCase().contains(query) &&
        !(student.nickname?.toLowerCase().contains(query) ?? false)) {
      return false;
    }
    // Roster vazio = turma aberta (mesma regra legada de
    // BJJClass.acceptsCheckinFrom: studentIds.isEmpty || contains(...)).
    // Sem esse `isNotEmpty`, uma turma "sem alunos fixos" (o jeito hoje de
    // fazer chamada sem horário/turma real — ex.: musculação livre) escondia
    // TODOS os alunos da lista de chamada, em vez de mostrar todos.
    if (classStudentIds != null &&
        classStudentIds.isNotEmpty &&
        !classStudentIds.contains(student.id)) {
      return false;
    }
    final isPresent = presentStudentIds.contains(student.id);
    if (filterMode == 'present' && !isPresent) return false;
    if (filterMode == 'absent' && isPresent) return false;
    return true;
  }).toList();

  filtered.sort((a, b) => a.fullName.compareTo(b.fullName));
  return filtered;
}
