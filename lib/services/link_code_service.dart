import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_service.dart';

// Code configuration
const int _codeLength = 6;
const int _codeExpirationHours = 24;
const String _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Excludes 0, O, I, 1

/// Link Code Model
class LinkCode {
  final String id;
  final String code;
  final String studentId;
  final String studentName;
  final String academyId; // Multi-tenant: which academy this code belongs to
  final String createdBy;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? usedAt;
  final String? usedBy;

  LinkCode({
    required this.id,
    required this.code,
    required this.studentId,
    required this.studentName,
    required this.academyId,
    required this.createdBy,
    required this.createdAt,
    required this.expiresAt,
    this.usedAt,
    this.usedBy,
  });

  factory LinkCode.fromFirestore(DocumentSnapshot doc, {String? academyId}) {
    final data = doc.data() as Map<String, dynamic>;

    // Extract academyId from document path if not provided
    // Path format: academies/{academyId}/linkCodes/{docId}
    String resolvedAcademyId = academyId ?? '';
    if (resolvedAcademyId.isEmpty && doc.reference.path.contains('academies/')) {
      final pathSegments = doc.reference.path.split('/');
      if (pathSegments.length >= 2 && pathSegments[0] == 'academies') {
        resolvedAcademyId = pathSegments[1];
      }
    }

    return LinkCode(
      id: doc.id,
      code: data['code'] ?? '',
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? '',
      academyId: resolvedAcademyId,
      createdBy: data['createdBy'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      usedAt: data['usedAt'] != null
          ? (data['usedAt'] as Timestamp).toDate()
          : null,
      usedBy: data['usedBy'],
    );
  }

  // Computed properties
  bool get isUsed => usedAt != null;
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isValid => !isUsed && !isExpired;
}

/// Link Code Validation Result
class LinkCodeValidation {
  final bool valid;
  final LinkCode? linkCode;
  final String? error;

  LinkCodeValidation({
    required this.valid,
    this.linkCode,
    this.error,
  });
}

/// Link Code Service - Multi-tenant account linking
class LinkCodeService {
  final String academyId;
  late final Collections _collections;

  LinkCodeService(this.academyId) {
    _collections = Collections(academyId);
  }

  CollectionReference get _linkCodesRef => _collections.linkCodes;

  // ============================================
  // Get Code by Code String
  // ============================================
  Future<LinkCode?> getByCode(String code) async {
    final query = await _linkCodesRef
        .where('code', isEqualTo: code.toUpperCase())
        .get();

    if (query.docs.isEmpty) return null;
    return LinkCode.fromFirestore(query.docs.first);
  }

  // ============================================
  // Validate Code
  // ============================================
  Future<LinkCodeValidation> validate(String code) async {
    final linkCode = await getByCode(code);

    if (linkCode == null) {
      return LinkCodeValidation(
        valid: false,
        error: 'Código não encontrado',
      );
    }

    if (linkCode.isUsed) {
      return LinkCodeValidation(
        valid: false,
        error: 'Este código já foi utilizado',
      );
    }

    if (linkCode.isExpired) {
      return LinkCodeValidation(
        valid: false,
        error: 'Este código expirou',
      );
    }

    return LinkCodeValidation(
      valid: true,
      linkCode: linkCode,
    );
  }

  // ============================================
  // Get Active Code for Student
  // ============================================
  Future<LinkCode?> getActiveForStudent(String studentId) async {
    final query = await _linkCodesRef
        .where('studentId', isEqualTo: studentId)
        .get();

    final codes = query.docs
        .map((doc) => LinkCode.fromFirestore(doc))
        .toList();

    // Sort by createdAt desc
    codes.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Find first valid code
    for (final code in codes) {
      if (code.isValid) {
        return code;
      }
    }

    return null;
  }

  // ============================================
  // Get All Codes for Student
  // ============================================
  Future<List<LinkCode>> getForStudent(String studentId) async {
    final query = await _linkCodesRef
        .where('studentId', isEqualTo: studentId)
        .get();

    final codes = query.docs
        .map((doc) => LinkCode.fromFirestore(doc))
        .toList();

    codes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return codes;
  }

  // ============================================
  // Get Code by ID
  // ============================================
  Future<LinkCode?> getById(String id) async {
    final doc = await _collections.linkCode(id).get();
    if (!doc.exists) return null;
    return LinkCode.fromFirestore(doc);
  }

  // ============================================
  // Get Pending Codes (active, unused, not expired)
  // ============================================
  Future<List<LinkCode>> getPending() async {
    final snapshot = await _linkCodesRef.get();
    final codes = snapshot.docs
        .map((doc) => LinkCode.fromFirestore(doc))
        .where((c) => c.isValid)
        .toList();

    codes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return codes;
  }

  // ============================================
  // Get Recently Used Codes
  // ============================================
  Future<List<LinkCode>> getRecentlyUsed({int limit = 10}) async {
    final snapshot = await _linkCodesRef.get();
    var codes = snapshot.docs
        .map((doc) => LinkCode.fromFirestore(doc))
        .where((c) => c.isUsed)
        .toList();

    codes.sort((a, b) => (b.usedAt ?? b.createdAt).compareTo(a.usedAt ?? a.createdAt));

    if (codes.length > limit) {
      codes = codes.sublist(0, limit);
    }

    return codes;
  }

  // ============================================
  // WRITE OPERATIONS
  // ============================================

  // Helper: Generate random code
  String _generateCode() {
    final random = Random.secure();
    return List.generate(
      _codeLength,
      (index) => _codeChars[random.nextInt(_codeChars.length)],
    ).join();
  }

  // ============================================
  // Generate Code
  // ============================================
  Future<LinkCode> generate({
    required String studentId,
    required String studentName,
    required String createdBy,
  }) async {
    // Invalidate existing codes for this student
    await invalidate(studentId);

    // Generate unique code
    String code;
    LinkCode? existing;
    do {
      code = _generateCode();
      existing = await getByCode(code);
    } while (existing != null);

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: _codeExpirationHours));

    final docRef = await _linkCodesRef.add({
      'code': code,
      'studentId': studentId,
      'studentName': studentName,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    final doc = await docRef.get();
    return LinkCode.fromFirestore(doc);
  }

  // ============================================
  // Mark Code as Used
  // ============================================
  Future<LinkCode> markAsUsed(String code, String userId) async {
    final linkCode = await getByCode(code);
    if (linkCode == null) {
      throw Exception('Código não encontrado');
    }

    await _linkCodesRef.doc(linkCode.id).update({
      'usedAt': FieldValue.serverTimestamp(),
      'usedBy': userId,
    });

    // Link the student to the user
    await _collections.student(linkCode.studentId).update({
      'linkedUserId': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final doc = await _linkCodesRef.doc(linkCode.id).get();
    return LinkCode.fromFirestore(doc);
  }

  // ============================================
  // Delete Code
  // ============================================
  Future<void> delete(String id) async {
    await _linkCodesRef.doc(id).delete();
  }

  // ============================================
  // Cleanup Expired Codes
  // ============================================
  Future<int> cleanupExpired() async {
    final snapshot = await _linkCodesRef.get();
    final expiredCodes = snapshot.docs
        .map((doc) => LinkCode.fromFirestore(doc))
        .where((c) => c.isExpired && !c.isUsed)
        .toList();

    for (final code in expiredCodes) {
      await delete(code.id);
    }

    return expiredCodes.length;
  }

  // ============================================
  // Invalidate All Codes for Student
  // ============================================
  Future<void> invalidate(String studentId) async {
    final codes = await getForStudent(studentId);
    for (final code in codes) {
      if (!code.isUsed) {
        await delete(code.id);
      }
    }
  }
}

// ============================================
// Factory Function
// ============================================
LinkCodeService createLinkCodeService(String academyId) {
  return LinkCodeService(academyId);
}

// ============================================
// Default Instance (uses current academy)
// ============================================
LinkCodeService get linkCodeService => LinkCodeService(FirebaseService.academyId);

// ============================================
// GLOBAL VALIDATION (Multi-tenant)
// Used during registration when user doesn't have an academy yet
// ============================================

/// Validate code across ALL academies using collectionGroup
/// Returns the LinkCode with academyId extracted from the document path
Future<LinkCodeValidation> validateCodeGlobally(String code) async {
  final firestore = FirebaseFirestore.instance;

  try {
    // Search across ALL academies' linkCodes subcollections
    final query = await firestore
        .collectionGroup('linkCodes')
        .where('code', isEqualTo: code.toUpperCase())
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return LinkCodeValidation(
        valid: false,
        error: 'Código não encontrado',
      );
    }

    final doc = query.docs.first;
    final linkCode = LinkCode.fromFirestore(doc);

    // Validate academyId was extracted
    if (linkCode.academyId.isEmpty) {
      return LinkCodeValidation(
        valid: false,
        error: 'Erro ao identificar academia do código',
      );
    }

    // Check if already used
    if (linkCode.isUsed) {
      return LinkCodeValidation(
        valid: false,
        error: 'Este código já foi utilizado',
      );
    }

    // Check if expired
    if (linkCode.isExpired) {
      return LinkCodeValidation(
        valid: false,
        error: 'Este código expirou',
      );
    }

    return LinkCodeValidation(
      valid: true,
      linkCode: linkCode,
    );
  } catch (e) {
    return LinkCodeValidation(
      valid: false,
      error: 'Erro ao validar código: $e',
    );
  }
}
