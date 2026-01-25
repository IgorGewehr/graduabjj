import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user.dart';
import '../services/firebase_service.dart';

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

/// User academy mapping provider - fetches from userAcademyMapping collection
final userAcademyMappingProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final authState = ref.watch(authStateProvider);
  final firebaseUser = authState.valueOrNull;

  if (firebaseUser == null) return null;

  final firestore = ref.watch(firestoreProvider);
  final mappingDoc = await firestore.collection('userAcademyMapping').doc(firebaseUser.uid).get();

  if (!mappingDoc.exists) return null;

  return mappingDoc.data();
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

  // Step 1: Try to get academy mapping
  final mappingDoc = await firestore.collection('userAcademyMapping').doc(firebaseUser.uid).get();
  String? academyId;

  if (mappingDoc.exists) {
    final mappingData = mappingDoc.data()!;
    print('[AUTH] Found userAcademyMapping: $mappingData');

    // Support both old format (academyId) and new format (academyIds/primaryAcademyId)
    if (mappingData['primaryAcademyId'] != null) {
      academyId = mappingData['primaryAcademyId'] as String;
    } else if (mappingData['academyIds'] != null && (mappingData['academyIds'] as List).isNotEmpty) {
      academyId = (mappingData['academyIds'] as List).first as String;
    } else if (mappingData['academyId'] != null) {
      academyId = mappingData['academyId'] as String;
    }
  } else {
    print('[AUTH] No userAcademyMapping found, checking root users collection...');

    // Fallback: Check root users collection for backwards compatibility
    final rootUserDoc = await firestore.collection('users').doc(firebaseUser.uid).get();
    if (rootUserDoc.exists) {
      final userData = rootUserDoc.data()!;
      print('[AUTH] Found user in root collection: role=${userData['role']}');

      // If user exists in root and has academyId, use it
      if (userData['academyId'] != null) {
        academyId = userData['academyId'] as String;
      } else {
        // Default to first academy (for backwards compatibility with single-tenant)
        academyId = 'academia-principal';
        print('[AUTH] Using default academyId: $academyId');
      }
    }
  }

  if (academyId == null) {
    print('[AUTH] Could not determine academyId');
    return null;
  }

  print('[AUTH] Using academyId: $academyId');

  // Set the academy context for FirebaseService
  FirebaseService.setAcademyId(academyId);

  // Step 2: Try to get user from academy's users subcollection
  final userDoc = await firestore
      .collection('academies')
      .doc(academyId)
      .collection('users')
      .doc(firebaseUser.uid)
      .get();

  if (userDoc.exists) {
    final userData = userDoc.data()!;
    print('[AUTH] Found user in academy subcollection: role=${userData['role']}');
    userData['academyId'] = academyId;
    return AppUser.fromMap(userDoc.id, userData);
  }

  // Step 3: Fallback to root users collection
  print('[AUTH] User not in academy subcollection, checking root...');
  final rootUserDoc = await firestore.collection('users').doc(firebaseUser.uid).get();

  if (rootUserDoc.exists) {
    final userData = rootUserDoc.data()!;
    print('[AUTH] Found user in root: role=${userData['role']}');
    userData['academyId'] = academyId;
    return AppUser.fromMap(rootUserDoc.id, userData);
  }

  print('[AUTH] User not found anywhere');
  return null;
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
    return await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Create account with email and password
  Future<UserCredential> createAccount(
    String email,
    String password,
    String displayName,
  ) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Update display name
    await credential.user?.updateDisplayName(displayName);

    // Create user document
    await _firestore.collection('users').doc(credential.user!.uid).set({
      'email': email,
      'displayName': displayName,
      'role': 'student',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return credential;
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// Get user document
  Future<AppUser?> getUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromFirestore(doc);
  }

  /// Update user profile
  Future<void> updateProfile({
    String? displayName,
    String? photoUrl,
    String? phone,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (displayName != null) {
      updates['displayName'] = displayName;
      await user.updateDisplayName(displayName);
    }

    if (photoUrl != null) {
      updates['photoUrl'] = photoUrl;
      await user.updatePhotoURL(photoUrl);
    }

    if (phone != null) {
      updates['phone'] = phone;
    }

    await _firestore.collection('users').doc(user.uid).update(updates);
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

    // Update user document in academy's users subcollection
    await academyRef.collection('users').doc(user.uid).set({
      'studentId': studentId,
      'role': 'student',
      'email': user.email,
      'displayName': user.displayName,
      'approvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

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

    // Create/update userAcademyMapping
    await _firestore.collection('userAcademyMapping').doc(user.uid).set({
      'academyIds': FieldValue.arrayUnion([academyId]),
      'primaryAcademyId': academyId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
