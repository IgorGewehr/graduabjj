import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user.dart';
import 'firebase_service.dart';
import 'global_user_service.dart';

/// Cross-Academy Service
/// Fetches data across all academies a user is linked to.
/// Used by monitors/professors to see a student's complete history.
class CrossAcademyService {
  CrossAcademyService._();
  static final CrossAcademyService instance = CrossAcademyService._();

  // ============================================
  // Belt Labels Helper
  // ============================================
  static const Map<String, String> beltLabels = {
    'white': 'Branca',
    'blue': 'Azul',
    'purple': 'Roxa',
    'brown': 'Marrom',
    'black': 'Preta',
    'grey': 'Cinza',
    'grey-white': 'Cinza/Branca',
    'grey-black': 'Cinza/Preta',
    'yellow': 'Amarela',
    'yellow-white': 'Amarela/Branca',
    'yellow-black': 'Amarela/Preta',
    'orange': 'Laranja',
    'orange-white': 'Laranja/Branca',
    'orange-black': 'Laranja/Preta',
    'green': 'Verde',
    'green-white': 'Verde/Branca',
    'green-black': 'Verde/Preta',
  };

  // ============================================
  // Get Academy Name Helper
  // ============================================
  Future<String> _getAcademyName(String academyId) async {
    try {
      final academyRef =
          FirebaseService.firestore.collection('academies').doc(academyId);
      final academySnap = await academyRef.get();
      if (academySnap.exists) {
        final data = academySnap.data();
        return (data?['name'] as String?) ?? academyId;
      }
      return academyId;
    } catch (e) {
      return academyId;
    }
  }

  // ============================================
  // Check if Global User Profile is Public
  // ============================================
  Future<bool> isProfilePublic(String linkedUserId) async {
    try {
      final userRef = RootCollections.user(linkedUserId);
      final userSnap = await userRef.get();
      if (userSnap.exists) {
        final data = userSnap.data();
        return (data?['isProfilePublic'] as bool?) ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // ============================================
  // Get Belt Progressions Across Academies
  // ============================================
  Future<List<CrossAcademyBeltProgression>> getBeltProgressionsAcrossAcademies(
    String linkedUserId, {
    String? excludeAcademyId,
  }) async {
    final mapping = await globalUserService.getUserAcademyMapping(linkedUserId);
    if (mapping == null) return [];

    final allProgressions = <CrossAcademyBeltProgression>[];

    for (final academyId in mapping.academyIds) {
      // Optionally exclude current academy
      if (excludeAcademyId != null && academyId == excludeAcademyId) continue;

      final academyDetail = mapping.academyDetails?[academyId];
      if (academyDetail == null || academyDetail.studentId == null) continue;

      final studentId = academyDetail.studentId!;
      final academyName = await _getAcademyName(academyId);

      try {
        final progressionsRef = FirebaseService.firestore
            .collection('academies/$academyId/beltProgressions');
        final query =
            progressionsRef.where('studentId', isEqualTo: studentId);
        final snapshot = await query.get();

        for (final doc in snapshot.docs) {
          final data = doc.data();
          allProgressions.add(CrossAcademyBeltProgression(
            id: doc.id,
            studentId: studentId,
            previousBelt: data['previousBelt'] as String?,
            previousStripes: data['previousStripes'] as int?,
            newBelt: data['newBelt'] as String? ?? 'white',
            newStripes: data['newStripes'] as int? ?? 0,
            promotionDate: data['promotionDate'] != null
                ? (data['promotionDate'] as Timestamp).toDate()
                : DateTime.now(),
            totalClasses: data['totalClasses'] as int?,
            promotedByName: data['promotedByName'] as String?,
            notes: data['notes'] as String?,
            academyId: academyId,
            academyName: academyName,
          ));
        }
      } catch (e) {
        // Continue with other academies
      }
    }

    // Sort by promotion date descending
    allProgressions.sort((a, b) => b.promotionDate.compareTo(a.promotionDate));
    return allProgressions;
  }

  // ============================================
  // Get Competition Results Across Academies
  // ============================================
  Future<List<CrossAcademyCompetitionResult>>
      getCompetitionResultsAcrossAcademies(
    String linkedUserId, {
    String? excludeAcademyId,
  }) async {
    final mapping = await globalUserService.getUserAcademyMapping(linkedUserId);
    if (mapping == null) return [];

    final allResults = <CrossAcademyCompetitionResult>[];

    for (final academyId in mapping.academyIds) {
      // Optionally exclude current academy
      if (excludeAcademyId != null && academyId == excludeAcademyId) continue;

      final academyDetail = mapping.academyDetails?[academyId];
      if (academyDetail == null || academyDetail.studentId == null) continue;

      final studentId = academyDetail.studentId!;
      final academyName = await _getAcademyName(academyId);

      try {
        final resultsRef = FirebaseService.firestore
            .collection('academies/$academyId/competitionResults');
        final query = resultsRef.where('studentId', isEqualTo: studentId);
        final snapshot = await query.get();

        for (final doc in snapshot.docs) {
          final data = doc.data();
          allResults.add(CrossAcademyCompetitionResult(
            id: doc.id,
            competitionId: data['competitionId'] as String? ?? '',
            competitionName: data['competitionName'] as String? ?? 'Competicao',
            studentId: studentId,
            studentName: data['studentName'] as String?,
            position: data['position'] as String? ?? 'participant',
            beltCategory: data['beltCategory'] as String?,
            ageCategory: data['ageCategory'] as String?,
            weightCategory: data['weightCategory'] as String?,
            notes: data['notes'] as String?,
            date: data['date'] != null
                ? (data['date'] as Timestamp).toDate()
                : DateTime.now(),
            academyId: academyId,
            academyName: academyName,
          ));
        }
      } catch (e) {
        // Continue with other academies
      }
    }

    // Sort by date descending
    allResults.sort((a, b) => b.date.compareTo(a.date));
    return allResults;
  }

  // ============================================
  // Get Attendance Stats Across Academies
  // ============================================
  Future<List<AcademyAttendanceStats>> getAttendanceStatsAcrossAcademies(
    String linkedUserId,
  ) async {
    final mapping = await globalUserService.getUserAcademyMapping(linkedUserId);
    if (mapping == null) return [];

    final stats = <AcademyAttendanceStats>[];

    for (final academyId in mapping.academyIds) {
      final academyDetail = mapping.academyDetails?[academyId];
      if (academyDetail == null || academyDetail.studentId == null) continue;

      final studentId = academyDetail.studentId!;
      final academyName = await _getAcademyName(academyId);

      try {
        // Get student to check for initialAttendanceCount
        final studentRef = FirebaseService.firestore
            .collection('academies/$academyId/students')
            .doc(studentId);
        final studentSnap = await studentRef.get();
        int initialCount = 0;
        if (studentSnap.exists) {
          final studentData = studentSnap.data();
          initialCount = (studentData?['initialAttendanceCount'] as int?) ?? 0;
        }

        // Count attendance records
        final attendanceRef = FirebaseService.firestore
            .collection('academies/$academyId/attendance');
        final query = attendanceRef.where('studentId', isEqualTo: studentId);
        final snapshot = await query.count().get();
        final count = snapshot.count ?? 0;

        stats.add(AcademyAttendanceStats(
          academyId: academyId,
          academyName: academyName,
          count: count,
          initialCount: initialCount,
          totalCount: count + initialCount,
        ));
      } catch (e) {
        // Continue with other academies
      }
    }

    return stats;
  }

  // ============================================
  // Get Complete Student History Across Academies
  // ============================================
  Future<CrossAcademyStudentHistory?> getStudentGlobalHistory(
    String linkedUserId, {
    String? currentAcademyId,
  }) async {
    final mapping = await globalUserService.getUserAcademyMapping(linkedUserId);
    if (mapping == null) return null;

    final profilePublic = await isProfilePublic(linkedUserId);

    // Get academy info for all linked academies
    final academies = <CrossAcademyInfo>[];
    for (final academyId in mapping.academyIds) {
      final academyDetail = mapping.academyDetails?[academyId];
      if (academyDetail == null || academyDetail.studentId == null) continue;

      final academyName = await _getAcademyName(academyId);

      // Get student belt info
      final studentRef = FirebaseService.firestore
          .collection('academies/$academyId/students')
          .doc(academyDetail.studentId);
      final studentSnap = await studentRef.get();
      String currentBelt = 'white';
      int currentStripes = 0;

      if (studentSnap.exists) {
        final studentData = studentSnap.data();
        currentBelt = (studentData?['currentBelt'] as String?) ?? 'white';
        currentStripes = (studentData?['currentStripes'] as int?) ?? 0;
      }

      academies.add(CrossAcademyInfo(
        academyId: academyId,
        academyName: academyName,
        studentId: academyDetail.studentId!,
        currentBelt: currentBelt,
        currentStripes: currentStripes,
      ));
    }

    // Get belt progressions from other academies (exclude current)
    final beltProgressions = await getBeltProgressionsAcrossAcademies(
      linkedUserId,
      excludeAcademyId: currentAcademyId,
    );

    // Get competition results from other academies (exclude current)
    final competitionResults = await getCompetitionResultsAcrossAcademies(
      linkedUserId,
      excludeAcademyId: currentAcademyId,
    );

    // Get attendance stats from all academies
    final attendanceStats =
        await getAttendanceStatsAcrossAcademies(linkedUserId);

    // Calculate totals
    final totalAttendance =
        attendanceStats.fold<int>(0, (sum, stat) => sum + stat.totalCount);

    // Calculate medal count from all academies
    final allResults =
        await getCompetitionResultsAcrossAcademies(linkedUserId);
    int gold = 0, silver = 0, bronze = 0;
    for (final result in allResults) {
      if (result.position == 'gold') {
        gold++;
      } else if (result.position == 'silver') {
        silver++;
      } else if (result.position == 'bronze') {
        bronze++;
      }
    }

    return CrossAcademyStudentHistory(
      linkedUserId: linkedUserId,
      isProfilePublic: profilePublic,
      academies: academies,
      beltProgressions: beltProgressions,
      competitionResults: competitionResults,
      attendanceStats: attendanceStats,
      totalAttendance: totalAttendance,
      medalCount: MedalCount(
        gold: gold,
        silver: silver,
        bronze: bronze,
        total: allResults.length,
      ),
    );
  }
}

/// Singleton accessor
CrossAcademyService get crossAcademyService => CrossAcademyService.instance;

// ============================================
// Data Classes
// ============================================

class CrossAcademyBeltProgression {
  final String id;
  final String studentId;
  final String? previousBelt;
  final int? previousStripes;
  final String newBelt;
  final int newStripes;
  final DateTime promotionDate;
  final int? totalClasses;
  final String? promotedByName;
  final String? notes;
  final String academyId;
  final String academyName;

  CrossAcademyBeltProgression({
    required this.id,
    required this.studentId,
    this.previousBelt,
    this.previousStripes,
    required this.newBelt,
    required this.newStripes,
    required this.promotionDate,
    this.totalClasses,
    this.promotedByName,
    this.notes,
    required this.academyId,
    required this.academyName,
  });
}

class CrossAcademyCompetitionResult {
  final String id;
  final String competitionId;
  final String competitionName;
  final String studentId;
  final String? studentName;
  final String position;
  final String? beltCategory;
  final String? ageCategory;
  final String? weightCategory;
  final String? notes;
  final DateTime date;
  final String academyId;
  final String academyName;

  CrossAcademyCompetitionResult({
    required this.id,
    required this.competitionId,
    required this.competitionName,
    required this.studentId,
    this.studentName,
    required this.position,
    this.beltCategory,
    this.ageCategory,
    this.weightCategory,
    this.notes,
    required this.date,
    required this.academyId,
    required this.academyName,
  });
}

class AcademyAttendanceStats {
  final String academyId;
  final String academyName;
  final int count;
  final int initialCount;
  final int totalCount;

  AcademyAttendanceStats({
    required this.academyId,
    required this.academyName,
    required this.count,
    required this.initialCount,
    required this.totalCount,
  });
}

class CrossAcademyInfo {
  final String academyId;
  final String academyName;
  final String studentId;
  final String currentBelt;
  final int currentStripes;

  CrossAcademyInfo({
    required this.academyId,
    required this.academyName,
    required this.studentId,
    required this.currentBelt,
    required this.currentStripes,
  });
}

class MedalCount {
  final int gold;
  final int silver;
  final int bronze;
  final int total;

  MedalCount({
    required this.gold,
    required this.silver,
    required this.bronze,
    required this.total,
  });
}

class CrossAcademyStudentHistory {
  final String linkedUserId;
  final bool isProfilePublic;
  final List<CrossAcademyInfo> academies;
  final List<CrossAcademyBeltProgression> beltProgressions;
  final List<CrossAcademyCompetitionResult> competitionResults;
  final List<AcademyAttendanceStats> attendanceStats;
  final int totalAttendance;
  final MedalCount medalCount;

  CrossAcademyStudentHistory({
    required this.linkedUserId,
    required this.isProfilePublic,
    required this.academies,
    required this.beltProgressions,
    required this.competitionResults,
    required this.attendanceStats,
    required this.totalAttendance,
    required this.medalCount,
  });
}
