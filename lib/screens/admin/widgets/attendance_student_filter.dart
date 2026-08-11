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
    if (classStudentIds != null && !classStudentIds.contains(student.id)) {
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
