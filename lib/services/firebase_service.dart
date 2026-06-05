import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firebase Service - Base configuration and collection references
/// Multi-tenant architecture for BJJ academies
class FirebaseService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  FirebaseService._();

  static FirebaseFirestore get firestore => _firestore;
  static FirebaseAuth get auth => _auth;

  // Current user
  static User? get currentUser => _auth.currentUser;
  static String? get currentUserId => _auth.currentUser?.uid;

  // Default academy ID (should be set from user profile or environment)
  static String _academyId = 'default';

  static String get academyId => _academyId;

  static void setAcademyId(String id) {
    _academyId = id;
  }
}

/// Collection References - Multi-tenant structure
class Collections {
  final String academyId;

  Collections(this.academyId);

  // Base academy document
  DocumentReference get academy =>
      FirebaseService.firestore.collection('academies').doc(academyId);

  // Subcollections under academy
  CollectionReference get students => academy.collection('students');
  CollectionReference get attendance => academy.collection('attendance');
  CollectionReference get achievements => academy.collection('achievements');
  CollectionReference get classes => academy.collection('classes');
  CollectionReference get teams => academy.collection('teams');
  CollectionReference get plans => academy.collection('plans');
  CollectionReference get payments => academy.collection('financials');
  CollectionReference get competitions => academy.collection('competitions');
  CollectionReference get competitionEnrollments => academy.collection('competitionEnrollments');
  CollectionReference get assessments => academy.collection('assessments');
  CollectionReference get linkCodes => academy.collection('linkCodes');
  CollectionReference get settings => academy.collection('settings');
  CollectionReference get storeProducts => academy.collection('storeProducts');
  CollectionReference get storeOrders => academy.collection('storeOrders');
  CollectionReference get beltProgressions => academy.collection('beltProgressions');
  CollectionReference get notifications => academy.collection('notifications');
  CollectionReference get checkins => academy.collection('checkins');
  CollectionReference get billingContactLog => academy.collection('billingContactLog');
  CollectionReference get workoutPlans => academy.collection('workoutPlans');
  CollectionReference get content => academy.collection('content');
  CollectionReference get workoutLogs => academy.collection('workoutLogs');
  CollectionReference get physicalAssessments => academy.collection('physicalAssessments');
  CollectionReference get syllabus => academy.collection('syllabus');
  CollectionReference get skillProgress => academy.collection('skillProgress');
  CollectionReference get exercises => academy.collection('exercises');
  CollectionReference get workoutExecutions => academy.collection('workoutExecutions');
  CollectionReference get classBookings => academy.collection('classBookings');
  CollectionReference get classOccurrences => academy.collection('classOccurrences');
  CollectionReference get strikingSessions => academy.collection('strikingSessions');
  CollectionReference get fightRecords => academy.collection('fightRecords');
  CollectionReference get combos => academy.collection('combos');
  CollectionReference get strengthGoals => academy.collection('strengthGoals');

  // Individual document references
  DocumentReference student(String id) => students.doc(id);
  DocumentReference attendanceDoc(String id) => attendance.doc(id);
  DocumentReference achievement(String id) => achievements.doc(id);
  DocumentReference classDoc(String id) => classes.doc(id);
  DocumentReference team(String id) => teams.doc(id);
  DocumentReference plan(String id) => plans.doc(id);
  DocumentReference payment(String id) => payments.doc(id);
  DocumentReference competition(String id) => competitions.doc(id);
  DocumentReference competitionEnrollment(String id) => competitionEnrollments.doc(id);
  DocumentReference assessment(String id) => assessments.doc(id);
  DocumentReference physicalAssessment(String id) => physicalAssessments.doc(id);
  DocumentReference syllabusTechnique(String id) => syllabus.doc(id);
  DocumentReference skillProgressDoc(String id) => skillProgress.doc(id);
  DocumentReference exercise(String id) => exercises.doc(id);
  DocumentReference workoutExecution(String id) => workoutExecutions.doc(id);
  DocumentReference classBooking(String id) => classBookings.doc(id);
  DocumentReference classOccurrence(String id) => classOccurrences.doc(id);
  DocumentReference linkCode(String code) => linkCodes.doc(code);
  DocumentReference checkin(String id) => checkins.doc(id);

  // Factory method for convenience
  static Collections forAcademy(String academyId) => Collections(academyId);

  // Default instance using current academy
  static Collections get current => Collections(FirebaseService.academyId);
}

/// Root Collections (global, not per-academy)
class RootCollections {
  static CollectionReference get academies =>
      FirebaseService.firestore.collection('academies');

  /// Global users (identity independent of academies)
  static CollectionReference get users =>
      FirebaseService.firestore.collection('users');

  static DocumentReference user(String uid) => users.doc(uid);

  /// User-to-Academy mapping
  static CollectionReference get userAcademyMapping =>
      FirebaseService.firestore.collection('userAcademyMapping');

  static DocumentReference userAcademyMappingDoc(String uid) =>
      userAcademyMapping.doc(uid);
}

/// Academy-scoped users (user context within a specific academy)
class AcademyUserCollections {
  final String academyId;

  AcademyUserCollections(this.academyId);

  CollectionReference get users =>
      FirebaseService.firestore.collection('academies/$academyId/users');

  DocumentReference user(String uid) => users.doc(uid);
}
