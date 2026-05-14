import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user.dart';
import '../services/firebase_service.dart';
import '../services/global_user_service.dart';
import '../services/push_notification_service.dart';

/// Firebase Auth instance provider
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

/// Firebase Firestore instance provider
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

/// Auth state stream provider
final authStateProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return auth.authStateChanges();
});

/// Flag to prevent router redirects during account creation
/// When true, the router will not redirect away from auth pages
final isCreatingAccountProvider = StateProvider<bool>((ref) => false);

/// Student name displayed in the account creation overlay
final creatingAccountStudentNameProvider = StateProvider<String>((ref) => '');

/// Global user provider - fetches from ROOT /users collection
final globalUserProvider = FutureProvider<GlobalUser?>((ref) async {
  final authState = ref.watch(authStateProvider);
  final firebaseUser = authState.valueOrNull;

  if (firebaseUser == null) return null;

  return await globalUserService.getGlobalUser(firebaseUser.uid);
});

/// User academy mapping provider - fetches from userAcademyMapping collection
final userAcademyMappingProvider = FutureProvider<UserAcademyMapping?>((ref) async {
  final authState = ref.watch(authStateProvider);
  final firebaseUser = authState.valueOrNull;

  if (firebaseUser == null) return null;

  return await globalUserService.getUserAcademyMapping(firebaseUser.uid);
});

/// Whether the current user is a free user (not linked to any academy)
final isFreeUserProvider = Provider<bool>((ref) {
  final globalUser = ref.watch(globalUserProvider).valueOrNull;
  return globalUser?.accountType == AccountType.free;
});

/// Current user provider with robust fallback logic
final currentUserProvider = FutureProvider<AppUser?>((ref) async {
  final authState = ref.watch(authStateProvider);
  final firebaseUser = authState.valueOrNull;

  if (firebaseUser == null) {
    print('[AUTH] No firebase user');
    return null;
  }

  print('[AUTH] Loading user data for: ${firebaseUser.uid}');
  final firestore = ref.watch(firestoreProvider);

  // Step 1: Get or create global user
  GlobalUser? globalUser = await globalUserService.getGlobalUser(firebaseUser.uid);

  if (globalUser == null) {
    print('[AUTH] Creating new global user...');
    // Create new global user (free account)
    globalUser = await globalUserService.createGlobalUser(
      userId: firebaseUser.uid,
      email: firebaseUser.email ?? '',
      displayName: firebaseUser.displayName ?? '',
      photoUrl: firebaseUser.photoURL,
    );
  }

  // Step 2: Get academy mapping
  final mapping = await globalUserService.getUserAcademyMapping(firebaseUser.uid);
  String? academyId;

  if (mapping != null && mapping.academyIds.isNotEmpty) {
    // User is linked to academy(ies)
    academyId = mapping.primaryAcademyId ?? mapping.academyIds.first;
    print('[AUTH] User is linked to academy: $academyId');
  } else {
    print('[AUTH] User is a free user (not linked to any academy)');
    // Return as free user without academy context
    return AppUser(
      id: globalUser.id,
      email: globalUser.email,
      displayName: globalUser.displayName,
      photoUrl: globalUser.photoUrl,
      role: UserRole.student,
      phone: globalUser.phone,
      accountType: AccountType.free,
      jiujitsuStartDate: globalUser.jiujitsuStartDate,
      highestBelt: globalUser.highestBelt,
      highestStripes: globalUser.highestStripes,
      isProfilePublic: globalUser.isProfilePublic,
      createdAt: globalUser.createdAt,
      updatedAt: globalUser.updatedAt,
    );
  }

  // Set the academy context for FirebaseService
  FirebaseService.setAcademyId(academyId);

  // Step 3: Get academy-specific user data
  final academyDetails = mapping.academyDetails?[academyId];
  final userDoc = await firestore
      .collection('academies')
      .doc(academyId)
      .collection('users')
      .doc(firebaseUser.uid)
      .get();

  if (userDoc.exists) {
    final userData = userDoc.data()!;
    print('[AUTH] Found user in academy subcollection: role=${userData['role']}');

    // Combine global user data with academy-specific data
    return AppUser.fromGlobalAndAcademy(
      globalUser: globalUser,
      academyId: academyId,
      role: academyDetails?.role ?? UserRoleExtension.fromString(userData['role'] ?? 'student'),
      studentId: academyDetails?.studentId ?? userData['studentId'],
      linkedStudentIds: userData['linkedStudentIds'] != null
          ? List<String>.from(userData['linkedStudentIds'])
          : null,
      instructorId: userData['instructorId'],
      pendingStudentLink: userData['pendingStudentLink'],
      approvedAt: userData['approvedAt'] != null
          ? (userData['approvedAt'] as Timestamp).toDate()
          : null,
    );
  }

  // Fallback: user is linked to academy but doesn't have academy user document yet
  print('[AUTH] Creating academy user document...');
  return AppUser.fromGlobalAndAcademy(
    globalUser: globalUser,
    academyId: academyId,
    role: academyDetails?.role ?? UserRole.student,
    studentId: academyDetails?.studentId,
  );
});

/// Auth service provider
final authServiceProvider = Provider<AuthService>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final firestore = ref.watch(firestoreProvider);
  return AuthService(auth, firestore);
});

/// Auth Service Class
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthService(this._auth, this._firestore);

  User? get currentUser => _auth.currentUser;

  /// Sign in with email and password
  Future<UserCredential> signInWithEmail(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Update FCM token for push notifications
    await pushNotificationService.onUserLogin();

    return credential;
  }

  /// Create account with email and password (creates free user)
  Future<UserCredential> createAccount(
    String email,
    String password,
    String displayName,
  ) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Update display name in Firebase Auth
    await credential.user?.updateDisplayName(displayName);

    // Create global user document using globalUserService
    // This also creates the empty userAcademyMapping
    await globalUserService.createGlobalUser(
      userId: credential.user!.uid,
      email: email,
      displayName: displayName,
      accountType: AccountType.free, // New users start as free
    );

    // Register FCM token for push notifications
    await pushNotificationService.onUserLogin();

    return credential;
  }

  /// Sign out
  Future<void> signOut() async {
    // Remove FCM token before signing out
    await pushNotificationService.onUserLogout();
    await _auth.signOut();
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// Change the current user's password.
  ///
  /// Firebase requires a recent re-authentication for sensitive operations
  /// like updating the password; if the cached credential is too old the call
  /// throws `requires-recent-login`. We reauthenticate explicitly with the
  /// user's current password first so the caller always gets a deterministic
  /// success/fail without surprise prompts.
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('Usuario nao autenticado');
    }

    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  /// Delete user account and all associated data
  /// This is required by Google Play Store policy
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuario nao autenticado');

    final uid = user.uid;

    try {
      // 1. Remove FCM token
      await pushNotificationService.onUserLogout();

      // 2. Get user's academy mappings to delete related data
      final mapping = await globalUserService.getUserAcademyMapping(uid);

      // 3. Delete student records from each academy
      if (mapping != null) {
        for (final academyId in mapping.academyIds) {
          final academyDetail = mapping.academyDetails?[academyId];
          if (academyDetail?.studentId != null) {
            // Mark student as deleted (soft delete for academy records)
            await _firestore
                .collection('academies/$academyId/students')
                .doc(academyDetail!.studentId)
                .update({
              'status': 'deleted',
              'deletedAt': FieldValue.serverTimestamp(),
              'deletedByUser': true,
            });
          }
        }
      }

      // 4. Delete userAcademyMapping
      await _firestore.collection('userAcademyMapping').doc(uid).delete();

      // 5. Delete global user document
      await _firestore.collection('users').doc(uid).delete();

      // 6. Delete Firebase Auth user (must be last)
      await user.delete();
    } catch (e) {
      // If requires recent login, throw specific error
      if (e.toString().contains('requires-recent-login')) {
        throw Exception('Por seguranca, faca login novamente antes de excluir sua conta');
      }
      rethrow;
    }
  }

  /// Get global user document
  Future<GlobalUser?> getGlobalUser(String uid) async {
    return await globalUserService.getGlobalUser(uid);
  }

  /// Update global user profile
  Future<void> updateGlobalProfile({
    String? displayName,
    String? photoUrl,
    String? phone,
    DateTime? birthDate,
    String? cpf,
    double? weight,
    bool? isProfilePublic,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final updates = <String, dynamic>{};

    if (displayName != null) {
      updates['displayName'] = displayName;
      await user.updateDisplayName(displayName);
    }

    if (photoUrl != null) {
      updates['photoUrl'] = photoUrl;
      await user.updatePhotoURL(photoUrl);
    }

    if (phone != null) updates['phone'] = phone;
    if (birthDate != null) updates['birthDate'] = birthDate;
    if (cpf != null) updates['cpf'] = cpf;
    if (weight != null) updates['weight'] = weight;
    if (isProfilePublic != null) updates['isProfilePublic'] = isProfilePublic;

    if (updates.isNotEmpty) {
      await globalUserService.updateGlobalUser(user.uid, updates);
    }
  }

  /// Link student account with code (multi-tenant)
  Future<void> linkStudentAccount(String linkCode, String academyId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuario nao autenticado');

    final academyRef = _firestore.collection('academies').doc(academyId);

    // Find link code document in academy's linkCodes subcollection
    final codeQuery = await academyRef
        .collection('linkCodes')
        .where('code', isEqualTo: linkCode.toUpperCase())
        .where('usedAt', isNull: true)
        .limit(1)
        .get();

    if (codeQuery.docs.isEmpty) {
      throw Exception('Codigo invalido ou ja utilizado');
    }

    final codeDoc = codeQuery.docs.first;
    final codeData = codeDoc.data();

    // Check if code is expired
    final expiresAt = (codeData['expiresAt'] as Timestamp).toDate();
    if (DateTime.now().isAfter(expiresAt)) {
      throw Exception('Codigo expirado');
    }

    final studentId = codeData['studentId'] as String;

    // Link user to academy using globalUserService
    await globalUserService.linkUserToAcademy(
      userId: user.uid,
      academyId: academyId,
      studentId: studentId,
      role: UserRole.student,
    );

    // Update/create academy user document
    await globalUserService.upsertAcademyUser(
      academyId: academyId,
      userId: user.uid,
      data: {
        'studentId': studentId,
        'role': 'student',
        'email': user.email,
        'displayName': user.displayName,
        'approvedAt': DateTime.now(),
        'status': 'active',
      },
    );

    // Update student document in academy's students subcollection
    await academyRef.collection('students').doc(studentId).update({
      'linkedUserId': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Mark code as used
    await codeDoc.reference.update({
      'usedAt': FieldValue.serverTimestamp(),
      'usedBy': user.uid,
    });

    // Sync highest belt from all linked academies
    await globalUserService.syncHighestBelt(user.uid);

    // Subscribe to academy push notifications topic
    await pushNotificationService.subscribeToTopic('academy_$academyId');
  }

  /// Unlink from academy
  Future<void> unlinkFromAcademy(String academyId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuario nao autenticado');

    // Get the mapping to find studentId
    final mapping = await globalUserService.getUserAcademyMapping(user.uid);
    final academyDetail = mapping?.academyDetails?[academyId];
    final studentId = academyDetail?.studentId;

    // Unlink student from user
    if (studentId != null) {
      await _firestore
          .collection('academies')
          .doc(academyId)
          .collection('students')
          .doc(studentId)
          .update({
        'linkedUserId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Remove academy user document
    await globalUserService.deleteAcademyUser(
      academyId: academyId,
      userId: user.uid,
    );

    // Unlink user from academy
    await globalUserService.unlinkUserFromAcademy(
      userId: user.uid,
      academyId: academyId,
    );

    // Unsubscribe from academy push notifications topic
    await pushNotificationService.unsubscribeFromTopic('academy_$academyId');
  }

  /// Switch primary academy (for multi-academy users)
  Future<void> switchPrimaryAcademy(String newAcademyId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuario nao autenticado');

    await globalUserService.setPrimaryAcademy(
      userId: user.uid,
      academyId: newAcademyId,
    );

    // Update FirebaseService context
    FirebaseService.setAcademyId(newAcademyId);
  }

  /// Get user's academy IDs
  Future<List<String>> getUserAcademyIds() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    return await globalUserService.getUserAcademyIds(user.uid);
  }

  /// Create academy account (registers professor and creates academy)
  /// Uses a Firestore auto-generated ID for the academy document.
  Future<UserCredential> createAcademyAccount({
    required String email,
    required String password,
    required String displayName,
    required String academyName,
    String? documentType,
    String? documentNumber,
  }) async {
    // Step 1: Create Firebase Auth user
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Step 2: Update display name in Firebase Auth
    await credential.user?.updateDisplayName(displayName);

    // Step 3: Create global user document with accountType: linked
    await globalUserService.createGlobalUser(
      userId: credential.user!.uid,
      email: email,
      displayName: displayName,
      accountType: AccountType.linked,
    );

    // Step 4: Create academy document with auto-generated ID
    final academyRef = _firestore.collection('academies').doc();
    final academyId = academyRef.id;

    final academyData = <String, dynamic>{
      'name': academyName,
      'ownerId': credential.user!.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'settings': {
        'allowStudentRegistration': true,
        'requireApproval': false,
      },
      'subscription': {
        'plan': 'free',
        'status': 'active',
        'trialEndsAt': DateTime.now().add(const Duration(days: 30)),
      },
      'storeEnabled': false,
      'storePublished': false,
      'abacatePayEnabled': false,
      'autoGraduationEnabled': false,
      'studentCheckinEnabled': true,
    };

    // Add document info if provided
    if (documentType != null) academyData['ownerDocumentType'] = documentType;
    if (documentNumber != null) academyData['ownerDocumentNumber'] = documentNumber;

    await academyRef.set(academyData);

    // Step 5: Create academy user document (role: admin)
    await globalUserService.upsertAcademyUser(
      academyId: academyId,
      userId: credential.user!.uid,
      data: {
        'email': email,
        'displayName': displayName,
        'role': 'admin',
        'isActive': true,
        'status': 'active',
      },
    );

    // Step 6: Link user to academy via globalUserService
    await globalUserService.linkUserToAcademy(
      userId: credential.user!.uid,
      academyId: academyId,
      role: UserRole.admin,
    );

    // Step 7: Register FCM token for push notifications
    await pushNotificationService.onUserLogin();

    // Step 8: Subscribe to academy push notifications topic
    await pushNotificationService.subscribeToTopic('academy_$academyId');

    return credential;
  }

  /// Create account with link code (registers and links to student in one step)
  /// CRITICAL: academyId must be passed explicitly (from link code validation)
  /// to ensure multi-tenant correctness during registration
  Future<UserCredential> createAccountWithLinkCode(
    String email,
    String password,
    String displayName,
    String studentId,
    String academyId, // Must be passed from validated link code
    String? cpf, { // Optional CPF to save with student
    String? phone, // Optional WhatsApp phone to save with student
  }) async {
    // Create Firebase Auth account
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Update display name in Firebase Auth
    await credential.user?.updateDisplayName(displayName);

    // Create global user document
    await globalUserService.createGlobalUser(
      userId: credential.user!.uid,
      email: email,
      displayName: displayName,
      accountType: AccountType.linked, // Already linked to academy
    );

    // Link user to academy
    await globalUserService.linkUserToAcademy(
      userId: credential.user!.uid,
      academyId: academyId,
      studentId: studentId,
      role: UserRole.student,
    );

    // Create academy user document
    await globalUserService.upsertAcademyUser(
      academyId: academyId,
      userId: credential.user!.uid,
      data: {
        'studentId': studentId,
        'role': 'student',
        'email': email,
        'displayName': displayName,
        'approvedAt': DateTime.now(),
        'status': 'active',
      },
    );

    // Register FCM token for push notifications
    await pushNotificationService.onUserLogin();

    // Subscribe to academy push notifications topic
    await pushNotificationService.subscribeToTopic('academy_$academyId');

    // Update student document with linkedUserId and CPF (with retry logic)
    // This MUST complete before returning to avoid race conditions on first login
    bool studentUpdated = false;
    for (int attempt = 0; attempt < 3 && !studentUpdated; attempt++) {
      try {
        final updateData = <String, dynamic>{
          'linkedUserId': credential.user!.uid,
          'email': email,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Only add CPF if provided
        if (cpf != null && cpf.isNotEmpty) {
          updateData['cpf'] = cpf;
        }

        // Only add phone if provided
        if (phone != null && phone.isNotEmpty) {
          updateData['phone'] = phone;
        }

        await _firestore
            .collection('academies')
            .doc(academyId)
            .collection('students')
            .doc(studentId)
            .update(updateData);

        studentUpdated = true;
      } catch (e) {
        debugPrint('Student update attempt ${attempt + 1} failed: $e');
        if (attempt < 2) {
          await Future.delayed(Duration(milliseconds: 500));
        } else {
          // On final attempt failure, log error but continue
          // User can still login, but profile linking might fail
          debugPrint('CRITICAL: Failed to update student after 3 attempts');
          throw Exception('Falha ao vincular perfil do aluno. Tente novamente.');
        }
      }
    }

    return credential;
  }
}
