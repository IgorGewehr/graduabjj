import '../../../core/sports.dart';
import '../../../models/student.dart';
import '../../../services/belt_progression_service.dart';

/// Projeção pura da lista de alunos do admin.
///
/// Aplica todos os filtros em uma única passagem, evitando as listas
/// intermediárias que a tela criava para cada filtro ativo. O cache de faixa
/// também evita reconstruir a escada de graduação a cada comparação do sort.
List<Student> filterStudentsForAdminList({
  required List<Student> students,
  required String searchQuery,
  required StudentStatus? statusFilter,
  required StudentCategory? categoryFilter,
  required SportId? sportFilter,
  required String? beltFilter,
  required bool? accountFilter,
  required int? inactivityFilter,
  required String sortBy,
  required Map<String, EligibilitySnapshotEntry> eligibilityByStudent,
}) {
  final query = searchQuery.trim().toLowerCase();
  final filtered = students.where((student) {
    if (query.isNotEmpty &&
        !student.fullName.toLowerCase().contains(query) &&
        !(student.nickname?.toLowerCase().contains(query) ?? false) &&
        !(student.email?.toLowerCase().contains(query) ?? false)) {
      return false;
    }

    if (statusFilter != null) {
      if (student.status != statusFilter) return false;
    } else if (student.status == StudentStatus.transferred) {
      return false;
    }

    if (categoryFilter != null && student.category != categoryFilter) {
      return false;
    }
    if (sportFilter != null && !student.getSports().contains(sportFilter)) {
      return false;
    }
    if (beltFilter != null) {
      final sport = sportFilter ?? student.getPrimarySport();
      if (student.getGrade(sport)?.currentGrade != beltFilter) return false;
    }

    final hasAccount = student.linkedUserId?.isNotEmpty == true;
    if (accountFilter != null && hasAccount != accountFilter) return false;

    if (inactivityFilter != null) {
      if (student.status != StudentStatus.active) return false;
      final days = student.daysSinceLastAttendance;
      if (days == null ? inactivityFilter < 30 : days < inactivityFilter) {
        return false;
      }
    }
    return true;
  }).toList();

  switch (sortBy) {
    case 'attendance':
      filtered.sort(
        (a, b) => b.totalAttendanceCount.compareTo(a.totalAttendanceCount),
      );
      break;
    case 'belt':
      final ranks = <String, (int, int)>{};
      (int, int) rankOf(Student student) {
        return ranks.putIfAbsent(student.id, () {
          final sport = sportFilter ?? student.getPrimarySport();
          final grade = student.getGrade(sport)?.currentGrade ?? 'white';
          final grades = getGradesForSport(
            sport,
            category: student.category.value,
            muaythaiVariant: sport == SportId.muaythai
                ? resolveMuaythaiVariant(grade)
                : null,
          );
          return (
            grades.indexWhere((candidate) => candidate.id == grade),
            student.getGrade(sport)?.currentStripes ?? 0,
          );
        });
      }

      filtered.sort((a, b) {
        final aRank = rankOf(a);
        final bRank = rankOf(b);
        if (aRank.$1 != bRank.$1) return bRank.$1.compareTo(aRank.$1);
        return bRank.$2.compareTo(aRank.$2);
      });
      break;
    case 'eligible_first':
      filtered.sort((a, b) {
        final aEligibility = eligibilityByStudent[a.id];
        final bEligibility = eligibilityByStudent[b.id];
        final aEligible = aEligibility?.eligible == true ? 1 : 0;
        final bEligible = bEligibility?.eligible == true ? 1 : 0;
        if (aEligible != bEligible) return bEligible - aEligible;

        final aProgress = _eligibilityProgress(aEligibility);
        final bProgress = _eligibilityProgress(bEligibility);
        if (aProgress != bProgress) return bProgress.compareTo(aProgress);
        return a.fullName.compareTo(b.fullName);
      });
      break;
    case 'name':
    default:
      filtered.sort((a, b) => a.fullName.compareTo(b.fullName));
      break;
  }

  return filtered;
}

double _eligibilityProgress(EligibilitySnapshotEntry? entry) {
  if (entry == null || entry.requiredClasses <= 0) return 0;
  return entry.currentClasses / entry.requiredClasses;
}
