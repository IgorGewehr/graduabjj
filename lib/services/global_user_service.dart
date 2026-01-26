import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user.dart';
import 'firebase_service.dart';

/// Global User Service
/// Manages users at ROOT /users/{uid} (independent of academies)
class GlobalUserService {
  GlobalUserService._();
  static final GlobalUserService instance = GlobalUserService._();

  // ============================================
  // Belt Comparison Helper
  // ============================================
  static const List<String> _beltOrder = [
    // Kids belts
    'white',
    'grey',
    'grey-white',
    'grey-black',
    'yellow',
    'yellow-white',
    'yellow-black',
    'orange',
    'orange-white',
    'orange-black',
    'green',
    'green-white',
    'green-black',
    // Adult belts
    'blue',
    'purple',
    'brown',
    'black',
  ];

  int _compareBelts(String belt1, String belt2) {
    final index1 = _beltOrder.indexOf(belt1);
    final index2 = _beltOrder.indexOf(belt2);
    return index1 - index2;
  }

  // ============================================
  // Global User CRUD
  // ============================================

  /// Get global user by ID
  Future<GlobalUser?> getGlobalUser(String userId) async {
    final userRef = RootCollections.user(userId);
    final userSnap = await userRef.get();

    if (!userSnap.exists) {
      return null;
    }

    return GlobalUser.fromFirestore(userSnap);
  }

  /// Create a new global user (for free accounts or first-time signup)
  Future<GlobalUser> createGlobalUser({
    required String userId,
    required String email,
    required String displayName,
    String? photoUrl,
    String? phone,
    AccountType accountType = AccountType.free,
  }) async {
    final userRef = RootCollections.user(userId);

    final userData = {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'phone': phone,
      'accountType': accountType.value,
      'isProfilePublic': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await userRef.set(userData);

    // Also create empty userAcademyMapping
    final mappingRef = RootCollections.userAcademyMappingDoc(userId);
    await mappingRef.set({
      'academyIds': <String>[],
      'primaryAcademyId': null,
      'academyDetails': <String, dynamic>{},
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return GlobalUser(
      id: userId,
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
      phone: phone,
      accountType: accountType,
      isProfilePublic: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Update global user profile
  Future<void> updateGlobalUser(
    String userId,
    Map<String, dynamic> data,
  ) async {
    final userRef = RootCollections.user(userId);

    final updateData = <String, dynamic>{
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Convert dates to Timestamps
    if (data['birthDate'] != null && data['birthDate'] is DateTime) {
      updateData['birthDate'] = Timestamp.fromDate(data['birthDate']);
    }
    if (data['jiujitsuStartDate'] != null &&
        data['jiujitsuStartDate'] is DateTime) {
      updateData['jiujitsuStartDate'] =
          Timestamp.fromDate(data['jiujitsuStartDate']);
    }

    await userRef.update(updateData);
  }

  /// Check if global user exists
  Future<bool> globalUserExists(String userId) async {
    final userRef = RootCollections.user(userId);
    final userSnap = await userRef.get();
    return userSnap.exists;
  }

  /// Get or create global user
  Future<GlobalUser> getOrCreateGlobalUser({
    required String userId,
    required String email,
    required String displayName,
    String? photoUrl,
    String? phone,
  }) async {
    final existing = await getGlobalUser(userId);
    if (existing != null) {
      return existing;
    }

    return createGlobalUser(
      userId: userId,
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
      phone: phone,
    );
  }

  // ============================================
  // User-Academy Mapping
  // ============================================

  /// Get user's academy mapping
  Future<UserAcademyMapping?> getUserAcademyMapping(String userId) async {
    final mappingRef = RootCollections.userAcademyMappingDoc(userId);
    final mappingSnap = await mappingRef.get();

    if (!mappingSnap.exists) {
      return null;
    }

    return UserAcademyMapping.fromFirestore(mappingSnap);
  }

  /// Link user to an academy
  Future<void> linkUserToAcademy({
    required String userId,
    required String academyId,
    String? studentId,
    required UserRole role,
  }) async {
    final mappingRef = RootCollections.userAcademyMappingDoc(userId);
    final userRef = RootCollections.user(userId);

    // Get current mapping
    final mappingSnap = await mappingRef.get();
    final currentMapping =
        mappingSnap.exists ? mappingSnap.data() as Map<String, dynamic>? : null;

    final academyDetail = {
      'studentId': studentId,
      'role': role.value,
      'joinedAt': FieldValue.serverTimestamp(),
      'status': 'active',
    };

    if (currentMapping != null) {
      // Update existing mapping
      await mappingRef.update({
        'academyIds': FieldValue.arrayUnion([academyId]),
        'primaryAcademyId': currentMapping['primaryAcademyId'] ?? academyId,
        'academyDetails.$academyId': academyDetail,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Create new mapping
      await mappingRef.set({
        'academyIds': [academyId],
        'primaryAcademyId': academyId,
        'academyDetails': {
          academyId: academyDetail,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Update global user accountType to 'linked'
    await userRef.update({
      'accountType': 'linked',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Unlink user from an academy
  Future<void> unlinkUserFromAcademy({
    required String userId,
    required String academyId,
  }) async {
    final mappingRef = RootCollections.userAcademyMappingDoc(userId);
    final userRef = RootCollections.user(userId);

    // Get current mapping
    final mappingSnap = await mappingRef.get();
    if (!mappingSnap.exists) {
      return;
    }

    final currentMapping = mappingSnap.data() as Map<String, dynamic>;
    final currentAcademyIds =
        List<String>.from(currentMapping['academyIds'] ?? []);
    final currentDetails =
        Map<String, dynamic>.from(currentMapping['academyDetails'] ?? {});

    // Remove academy from list
    final newAcademyIds = currentAcademyIds.where((id) => id != academyId).toList();

    // Remove academy details
    currentDetails.remove(academyId);

    // Determine new primary academy
    final newPrimaryAcademyId = currentMapping['primaryAcademyId'] == academyId
        ? (newAcademyIds.isNotEmpty ? newAcademyIds.first : null)
        : currentMapping['primaryAcademyId'];

    // Update mapping
    await mappingRef.update({
      'academyIds': newAcademyIds,
      'primaryAcademyId': newPrimaryAcademyId,
      'academyDetails': currentDetails,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // If no more academies, set user back to 'free'
    if (newAcademyIds.isEmpty) {
      await userRef.update({
        'accountType': 'free',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Set primary academy for user
  Future<void> setPrimaryAcademy({
    required String userId,
    required String academyId,
  }) async {
    final mappingRef = RootCollections.userAcademyMappingDoc(userId);

    await mappingRef.update({
      'primaryAcademyId': academyId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get user's primary academy ID
  Future<String?> getPrimaryAcademyId(String userId) async {
    final mapping = await getUserAcademyMapping(userId);
    return mapping?.primaryAcademyId;
  }

  /// Get all academy IDs for a user
  Future<List<String>> getUserAcademyIds(String userId) async {
    final mapping = await getUserAcademyMapping(userId);
    return mapping?.academyIds ?? [];
  }

  // ============================================
  // Belt Synchronization
  // ============================================

  /// Sync highest belt from all linked academies
  /// Call this after any belt change in any academy
  Future<void> syncHighestBelt(String userId) async {
    final userRef = RootCollections.user(userId);
    final mappingRef = RootCollections.userAcademyMappingDoc(userId);

    // Get mapping
    final mappingSnap = await mappingRef.get();
    if (!mappingSnap.exists) {
      return;
    }

    final mapping = mappingSnap.data() as Map<String, dynamic>;
    final academyIds = List<String>.from(mapping['academyIds'] ?? []);

    if (academyIds.isEmpty) {
      return;
    }

    String highestBelt = 'white';
    int highestStripes = 0;
    DateTime? earliestJiujitsuStart;

    // Check each academy
    for (final academyId in academyIds) {
      final academyDetails =
          (mapping['academyDetails'] as Map<String, dynamic>?)?[academyId]
              as Map<String, dynamic>?;
      if (academyDetails == null || academyDetails['studentId'] == null) {
        continue;
      }

      final studentRef = FirebaseService.firestore
          .collection('academies/$academyId/students')
          .doc(academyDetails['studentId'] as String);
      final studentSnap = await studentRef.get();

      if (!studentSnap.exists) continue;

      final studentData = studentSnap.data() as Map<String, dynamic>;
      final belt = studentData['currentBelt'] as String? ?? 'white';
      final stripes = studentData['currentStripes'] as int? ?? 0;
      final jiujitsuStart = studentData['jiujitsuStartDate'] != null
          ? (studentData['jiujitsuStartDate'] as Timestamp).toDate()
          : null;

      // Compare belts
      if (_compareBelts(belt, highestBelt) > 0) {
        highestBelt = belt;
        highestStripes = stripes;
      } else if (belt == highestBelt && stripes > highestStripes) {
        highestStripes = stripes;
      }

      // Track earliest jiu-jitsu start date
      if (jiujitsuStart != null) {
        if (earliestJiujitsuStart == null ||
            jiujitsuStart.isBefore(earliestJiujitsuStart)) {
          earliestJiujitsuStart = jiujitsuStart;
        }
      }
    }

    // Update global user
    final updateData = <String, dynamic>{
      'highestBelt': highestBelt,
      'highestStripes': highestStripes,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (earliestJiujitsuStart != null) {
      updateData['jiujitsuStartDate'] =
          Timestamp.fromDate(earliestJiujitsuStart);
    }

    await userRef.update(updateData);
  }

  // ============================================
  // Academy User Management
  // ============================================

  /// Get academy user (user within academy context)
  Future<AppUser?> getAcademyUser({
    required String academyId,
    required String userId,
  }) async {
    final userRef = FirebaseService.firestore
        .collection('academies/$academyId/users')
        .doc(userId);
    final userSnap = await userRef.get();

    if (!userSnap.exists) {
      return null;
    }

    return AppUser.fromFirestore(userSnap);
  }

  /// Create or update academy user
  Future<void> upsertAcademyUser({
    required String academyId,
    required String userId,
    required Map<String, dynamic> data,
  }) async {
    final userRef = FirebaseService.firestore
        .collection('academies/$academyId/users')
        .doc(userId);

    final userData = {
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Convert dates
    if (data['approvedAt'] != null && data['approvedAt'] is DateTime) {
      userData['approvedAt'] = Timestamp.fromDate(data['approvedAt']);
    }
    if (data['joinedAt'] != null && data['joinedAt'] is DateTime) {
      userData['joinedAt'] = Timestamp.fromDate(data['joinedAt']);
    }

    await userRef.set(userData, SetOptions(merge: true));
  }

  /// Delete academy user (when leaving academy)
  Future<void> deleteAcademyUser({
    required String academyId,
    required String userId,
  }) async {
    final userRef = FirebaseService.firestore
        .collection('academies/$academyId/users')
        .doc(userId);
    await userRef.delete();
  }

  // ============================================
  // Combined Operations
  // ============================================

  /// Get full user context (global + academy-specific)
  Future<AppUser?> getFullUserContext({
    required String userId,
    required String academyId,
  }) async {
    final globalUser = await getGlobalUser(userId);
    if (globalUser == null) {
      return null;
    }

    final mapping = await getUserAcademyMapping(userId);
    final academyDetails = mapping?.academyDetails?[academyId];

    if (academyDetails == null) {
      // User exists but not linked to this academy
      // Return as free user
      return AppUser(
        id: globalUser.id,
        email: globalUser.email,
        displayName: globalUser.displayName,
        photoUrl: globalUser.photoUrl,
        role: UserRole.student,
        phone: globalUser.phone,
        accountType: globalUser.accountType,
        jiujitsuStartDate: globalUser.jiujitsuStartDate,
        highestBelt: globalUser.highestBelt,
        highestStripes: globalUser.highestStripes,
        isProfilePublic: globalUser.isProfilePublic,
        createdAt: globalUser.createdAt,
        updatedAt: globalUser.updatedAt,
      );
    }

    // Get academy-specific user data
    final academyUser = await getAcademyUser(
      academyId: academyId,
      userId: userId,
    );

    return AppUser.fromGlobalAndAcademy(
      globalUser: globalUser,
      academyId: academyId,
      role: academyDetails.role,
      studentId: academyDetails.studentId,
      linkedStudentIds: academyUser?.linkedStudentIds,
      instructorId: academyUser?.instructorId,
      pendingStudentLink: academyUser?.pendingStudentLink,
      approvedAt: academyUser?.approvedAt,
    );
  }
}

/// Singleton accessor
GlobalUserService get globalUserService => GlobalUserService.instance;
