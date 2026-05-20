import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../api/repositories.dart';
import '../api/identity_repo.dart';
import '../api/tatami_client.dart';
import 'api_provider.dart';
import '../models/user.dart';
import '../services/global_user_service.dart';
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
// TODO(tatami): substituir por identityRepoProvider.getMe() que retorna
//   CurrentUserResponse com GlobalUser + memberships em uma única round-trip.
//   Bloqueado por: GlobalUser.fromApi adapter + testes de regressão no login flow.
final globalUserProvider = FutureProvider<GlobalUser?>((ref) async {
  final authState = ref.watch(authStateProvider);
  final firebaseUser = authState.valueOrNull;

  if (firebaseUser == null) return null;

  return await globalUserService.getGlobalUser(firebaseUser.uid);
});

/// User academy mapping provider - fetches from userAcademyMapping collection
// TODO(tatami): substituir por identityRepoProvider.listMemberships() quando
//   UserAcademyMapping.fromApiMemberships adapter for implementado. Tatami
//   retorna memberships paginadas em vez de doc único.
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
    return null;
  }

  // Pós-Fase 1: Tatami é o único path. Se /v1/me falhar com um erro de
  // rede/conexão, cai no Firestore como fallback. Erros HTTP (4xx/5xx)
  // são propagados — não queremos exibir dados obsoletos do Firestore
  // quando o backend respondeu com um erro estruturado.
  try {
    final app = await loadCurrentUserFromTatami(
      repo: ref.read(identityRepoProvider),
      selectedAcademyId: selectedAcademyId,
    );
    // Ensure selectedAcademyIdProvider is populated before screens read it.
    // The SelectedAcademyNotifier._initialize() is async and may not have
    // completed yet — this guarantees the id is available on the first frame.
    if (app.academyId != null &&
        ref.read(selectedAcademyIdProvider) == null) {
      ref.read(selectedAcademyIdProvider.notifier).state = app.academyId;
    }
    return app;
  } on DioException catch (e) {
    // Only fall back to Firestore on network-level failures. HTTP errors
    // (4xx/5xx) from the backend are real errors — rethrow so the UI
    // shows an error state instead of serving stale Firestore data.
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      // Fall through to Firestore fallback below.
    } else {
      rethrow;
    }
  } catch (e) {
    // Non-Dio exceptions (e.g. SocketException wrapped outside Dio,
    // FormatException on an unexpected response) — fall through to the
    // Firestore path which covers the "new user not yet in Tatami" edge case.
    // Caminho Firestore mantido aqui temporariamente porque cobre o
    // edge-case "usuário recém-criado sem global_user no Tatami". Esse
    // fluxo deve ser eliminado na Fase 3 (BE precisa auto-provisionar
    // ApiGlobalUser no primeiro /v1/me com Bearer Firebase).
  }

  final firestore = ref.watch(firestoreProvider);

  // Step 1: Get or create global user
  GlobalUser? globalUser = await globalUserService.getGlobalUser(
    firebaseUser.uid,
  );

  if (globalUser == null) {
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
  } else {
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
    );
  }

  // Fallback: user is linked to academy but doesn't have academy user document yet
  return AppUser.fromGlobalAndAcademy(
    globalUser: globalUser,
    academyId: academyId,
    role: academyDetails?.role ?? UserRole.student,
    studentId: academyDetails?.studentId,
  );
});

/// Helper isolado para a parte Tatami do [currentUserProvider]. Extraído
/// daquele FutureProvider para que dê pra testar em unidade sem precisar
/// montar Firestore / FirebaseAuth / Riverpod inteiro.
///
/// Retorna SEMPRE um AppUser não-nulo: quando a resposta de /v1/me não
/// tem membership ativa, constrói um AppUser `accountType=free` direto
/// do `ApiGlobalUser`.
Future<AppUser> loadCurrentUserFromTatami({
  required IdentityRemoteRepo repo,
  String? selectedAcademyId,
}) async {
  final cu = await repo.getMe();
  final app = AppUser.fromCurrentUserResponse(
    cu,
    activeAcademyId: selectedAcademyId,
  );
  if (app != null) return app;

  // Sem membership ativa = usuário free. Mapeia direto do ApiGlobalUser.
  return AppUser(
    id: cu.user.uid,
    email: cu.user.email,
    displayName: cu.user.displayName ?? '',
    photoUrl: cu.user.photoUrl,
    role: UserRole.student,
    phone: cu.user.phone,
    accountType: AccountType.free,
    jiujitsuStartDate: cu.user.jiujitsuStartDate,
    highestBelt: cu.user.highestBelt,
    highestStripes: cu.user.highestStripes,
    isProfilePublic: cu.user.isProfilePublic,
    createdAt: cu.user.createdAt ?? DateTime.now(),
    updatedAt: cu.user.updatedAt ?? DateTime.now(),
  );
}

/// Auth service provider
final authServiceProvider = Provider<AuthService>((ref) {
    final auth = ref.watch(firebaseAuthProvider);
  final firestore = ref.watch(firestoreProvider);
  final client = ref.watch(tatamiClientProvider);
  return AuthService(auth, firestore, client);
});

/// Auth Service Class
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final TatamiClient _tatami;

  AuthService(this._auth, this._firestore, this._tatami);

  User? get currentUser => _auth.currentUser;

  /// Sign in with email and password
  Future<UserCredential> signInWithEmail(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

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

  /// Delete user account and all associated data.
  /// Required by Google Play Store policy (LGPD compliance).
  ///
  /// Flow:
  ///   1. Fetch memberships from Go backend (/v1/me).
  ///   2. For each academy: soft-delete student row + remove membership.
  ///   3. Delete Firebase Auth user (must be last — invalidates the JWT
  ///      used by the Go API calls above).
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuario nao autenticado');

    try {
      // 1. Fetch current memberships from Go backend.
      final me = await _tatami.get<Map<String, dynamic>>('/v1/me');
      final memberships = (me['memberships'] as List? ?? [])
          .cast<Map<String, dynamic>>();

      // 2. For each academy: delete student row + remove membership.
      //    Both calls are best-effort — a 404 means the record doesn't
      //    exist anymore (already cleaned up), so we swallow it.
      for (final m in memberships) {
        final academyId = m['academy_id'] as String?;
        final studentId = m['student_id'] as String?;
        if (academyId == null) continue;

        if (studentId != null) {
          try {
            await _tatami.delete(
              '/v1/academies/$academyId/students/$studentId',
            );
          } catch (_) {}
        }

        try {
          await _tatami.delete(
            '/v1/academies/$academyId/memberships/${user.uid}',
          );
        } catch (_) {}
      }

      // 3. Delete Firebase Auth user last (invalidates JWT).
      await user.delete();
    } catch (e) {
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
  }

  /// Switch primary academy (for multi-academy users)
  Future<void> switchPrimaryAcademy(String newAcademyId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuario nao autenticado');

    await globalUserService.setPrimaryAcademy(
      userId: user.uid,
      academyId: newAcademyId,
    );
  }

  /// Get user's academy IDs
  Future<List<String>> getUserAcademyIds() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    return await globalUserService.getUserAcademyIds(user.uid);
  }

  /// Create academy account (registers professor and creates academy).
  /// Writes to Go backend — Firestore is NOT used for the academy document.
  /// The Go backend atomically creates: academy row, subscription trial,
  /// and the owner's user_academy_mapping with role=admin.
  Future<UserCredential> createAcademyAccount({
    required String email,
    required String password,
    required String displayName,
    required String academyName,
    String? documentType,
    String? documentNumber,
  }) async {
    // Step 1: Create Firebase Auth user (client-side — JWT needed for the
    // subsequent Go API call).
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user?.updateDisplayName(displayName);

    // Step 2: POST /v1/academies — Go backend handles everything atomically:
    // academy row, 7-day trial subscription, and owner membership (role=admin).
    // On slug conflict, append a 4-digit suffix and retry once.
    final baseSlug = _generateSlug(academyName);
    try {
      await _createAcademyOnBackend(
        slug: baseSlug,
        name: academyName,
        documentType: documentType,
        documentNumber: documentNumber,
      );
    } on Exception catch (e) {
      if (e.toString().contains('409') || e.toString().contains('conflict')) {
        final suffix = DateTime.now().millisecondsSinceEpoch % 10000;
        await _createAcademyOnBackend(
          slug: '${baseSlug}_$suffix',
          name: academyName,
          documentType: documentType,
          documentNumber: documentNumber,
        );
      } else {
        rethrow;
      }
    }

    return credential;
  }

  Future<void> _createAcademyOnBackend({
    required String slug,
    required String name,
    String? documentType,
    String? documentNumber,
  }) async {
    final body = <String, dynamic>{'name': name, 'slug': slug};
    if (documentNumber != null && documentNumber.isNotEmpty) {
      body['cnpj'] = documentNumber;
    }
    await _tatami.post<Map<String, dynamic>>('/v1/academies', data: body);
  }

  static String _generateSlug(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãä]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[ñ]'), 'n')
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
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
          throw Exception(
            'Falha ao vincular perfil do aluno. Tente novamente.',
          );
        }
      }
    }

    return credential;
  }
}
