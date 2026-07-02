import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';
import '../models/user.dart';
import '../services/firebase_service.dart';
import '../services/global_user_service.dart';
import '../services/push_notification_service.dart';
import '../services/team_service.dart';
import 'selected_academy_provider.dart';

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
final userAcademyMappingProvider = FutureProvider<UserAcademyMapping?>((
  ref,
) async {
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

/// Current user provider with robust fallback logic.
///
/// Watches [selectedAcademyIdProvider] via `.select` so that switching the
/// active academy automatically rebuilds this provider — no manual
/// `ref.invalidate(currentUserProvider)` needed in the academy switcher.
final currentUserProvider = FutureProvider<AppUser?>((ref) async {
  final authState = ref.watch(authStateProvider);
  final firebaseUser = authState.valueOrNull;

  // Subscribe to id changes only — passing through `.select` so unrelated
  // changes to the SelectedAcademy state (cache writes, loading flag) do not
  // re-fetch the user document.
  final selectedAcademyId = ref.watch(
    selectedAcademyIdProvider.select((id) => id),
  );

  if (firebaseUser == null) {
    print('[AUTH] No firebase user');
    return null;
  }

  print('[AUTH] Loading user data for: ${firebaseUser.uid}');
  final firestore = ref.watch(firestoreProvider);

  // Step 1: Get or create global user
  GlobalUser? globalUser = await globalUserService.getGlobalUser(
    firebaseUser.uid,
  );

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
  final mapping = await globalUserService.getUserAcademyMapping(
    firebaseUser.uid,
  );
  String? academyId;

  if (mapping != null && mapping.academyIds.isNotEmpty) {
    // Prefer the explicit `selectedAcademyId` (set by selectAcademy) —
    // falls back to the user's primary academy on first boot when the
    // SelectedAcademyNotifier has not finished `_initialize()` yet.
    if (selectedAcademyId != null &&
        mapping.academyIds.contains(selectedAcademyId)) {
      academyId = selectedAcademyId;
    } else {
      academyId = mapping.primaryAcademyId ?? mapping.academyIds.first;
    }
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
  // RESILIÊNCIA (hotfix tela-branca pós-login): o read do doc academy-user pode
  // falhar (permissão transitória, índice ausente, parse de doc recém-criado
  // pelo CF joinAcademy). NÃO rebaixar o usuário a "grátis" por isso — a mapping
  // já carrega academyId + role + studentId + extraPermissions. Em erro, cai no
  // fallback abaixo (monta o AppUser a partir da mapping) em vez de mandar um
  // membro de academia para um portal vazio (que aparece como tela branca).
  DocumentSnapshot<Map<String, dynamic>>? userDoc;
  try {
    userDoc = await firestore
        .collection('academies')
        .doc(academyId)
        .collection('users')
        .doc(firebaseUser.uid)
        .get();
  } catch (e) {
    print('[AUTH] academy-user read failed; using mapping fallback: $e');
    userDoc = null;
  }

  if (userDoc != null && userDoc.exists) {
    final userData = userDoc.data()!;
    print(
      '[AUTH] Found user in academy subcollection: role=${userData['role']}',
    );

    // Combine global user data with academy-specific data
    return AppUser.fromGlobalAndAcademy(
      globalUser: globalUser,
      academyId: academyId,
      role:
          academyDetails?.role ??
          UserRoleExtension.fromString(userData['role'] ?? 'student'),
      studentId: academyDetails?.studentId ?? userData['studentId'],
      linkedStudentIds: userData['linkedStudentIds'] != null
          ? List<String>.from(userData['linkedStudentIds'])
          : null,
      instructorId: userData['instructorId'],
      pendingStudentLink: userData['pendingStudentLink'],
      approvedAt: userData['approvedAt'] != null
          ? (userData['approvedAt'] as Timestamp).toDate()
          : null,
      extraPermissions: academyDetails?.extraPermissions ?? const [],
    );
  }

  // Fallback: doc ausente OU read falhou acima — monta a partir da mapping (que
  // já carrega role/studentId/extraPermissions), preservando o contexto de
  // academia em vez de cair como usuário "grátis" (home vazio = tela branca).
  print('[AUTH] academy-user doc unavailable; building user from mapping');
  return AppUser.fromGlobalAndAcademy(
    globalUser: globalUser,
    academyId: academyId,
    role: academyDetails?.role ?? UserRole.student,
    studentId: academyDetails?.studentId,
    extraPermissions: academyDetails?.extraPermissions ?? const [],
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
    // Remove FCM token before signing out. Best-effort: NENHUMA falha de
    // limpeza de push pode impedir/atrasar o logout do usuário.
    try {
      await pushNotificationService.onUserLogout();
    } catch (e) {
      debugPrint('[auth] push cleanup on signOut failed: $e');
    }
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

      // 3. Delete student records and academy user docs from each academy
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
          // Remove academy-scoped user document
          await _firestore
              .collection('academies/$academyId/users')
              .doc(uid)
              .delete();
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
        throw Exception(
          'Por seguranca, faca login novamente antes de excluir sua conta',
        );
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

  /// Link an already-authenticated user to an additional academy via a
  /// student link code. After the firestore.rules hardening this path runs
  /// through the joinAcademy Cloud Function — only the server can safely
  /// update a userAcademyMapping that already exists.
  ///
  /// `linkCode` is the 6-char code typed by the user; `academyId` is the
  /// academy resolved during validation (kept in the signature for callers
  /// that already have it, but the server resolves authoritatively from
  /// the code itself).
  Future<void> linkStudentAccount(String linkCode, String academyId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuario nao autenticado');

    final resolvedAcademyId = await teamService.joinAcademy(linkCode);

    // Best-effort post-write client side fixups. These are not security
    // sensitive — Cloud Function already wrote authoritative data.
    try {
      await globalUserService.syncHighestBelt(user.uid);
    } catch (_) {/* non-fatal */}

    await pushNotificationService
        .subscribeToTopic('academy_${resolvedAcademyId.isNotEmpty ? resolvedAcademyId : academyId}');
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
      'settings': {'allowStudentRegistration': true, 'requireApproval': false},
      'subscription': {
        'plan': 'free',
        'status': 'active',
        'trialEndsAt':
            DateTime.now().add(const Duration(days: AppConstants.trialDays)),
      },
      'storeEnabled': false,
      'storePublished': false,
      'abacatePayEnabled': false,
      'autoGraduationEnabled': false,
      'studentCheckinEnabled': true,
    };

    // Add document info if provided
    if (documentType != null) academyData['ownerDocumentType'] = documentType;
    if (documentNumber != null)
      academyData['ownerDocumentNumber'] = documentNumber;

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

  /// Create an account from a student link code and join the academy.
  ///
  /// The academy join runs entirely through the `joinAcademy` Cloud Function:
  /// the server resolves academyId + studentId from the [code], writes the
  /// userAcademyMapping + academy-user doc, marks the code used, and CLAIMS the
  /// orphan student record (stamping linkedUserId + the optional [cpf]/[phone])
  /// — all atomically with the Admin SDK and its orphan-claim guard.
  ///
  /// This replaces the previous client-side writes (mapping/academyUser/student)
  /// that bypassed the server guard and allowed an attacker to hijack another
  /// student's record (account-takeover hardening). The UI/flow is unchanged.
  Future<UserCredential> createAccountWithLinkCode(
    String email,
    String password,
    String displayName,
    String code, { // 6-char link code; server derives academyId + studentId
    String? cpf, // Optional CPF to stamp on the claimed student record
    String? phone, // Optional WhatsApp phone to stamp on the claimed record
  }) async {
    // Create Firebase Auth account
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Update display name in Firebase Auth
    await credential.user?.updateDisplayName(displayName);

    // Create global user document (also pre-creates the empty academy mapping
    // that the Cloud Function populates).
    await globalUserService.createGlobalUser(
      userId: credential.user!.uid,
      email: email,
      displayName: displayName,
      accountType: AccountType.linked,
    );

    // Secure server-side join: mapping + academy-user doc + orphan student claim
    // (incl. cpf/phone) + mark-code-used, all atomic. Returns the academyId.
    final academyId = await teamService.joinAcademy(code, cpf: cpf, phone: phone);

    // Register FCM token + subscribe to the academy topic for push.
    await pushNotificationService.onUserLogin();
    if (academyId.isNotEmpty) {
      await pushNotificationService.subscribeToTopic('academy_$academyId');
    }

    return credential;
  }
}
