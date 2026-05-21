import 'package:flutter/foundation.dart';

import '../api/dto/academy_dto.dart' show ApiLinkCode;
import '../api/link_code_repo.dart';
import '../api/tatami_client.dart';
import 'firebase_service.dart';

// Mirrors the compile-time constant from api_provider.dart.
const _tatamiBaseUrl = String.fromEnvironment(
  'TATAMI_BASE_URL',
  defaultValue: 'https://tatami.tensorroot.com',
);

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

  /// Sprint 3 wiring — constrói a partir do DTO Tatami `ApiLinkCode`.
  ///
  /// `studentName` não vem na resposta REST (poderia, mas a API canônica
  /// é só do code + student_id) — call-sites que precisam mostrar o nome
  /// devem buscar o student separadamente via student_repo.getById.
  factory LinkCode.fromApi(ApiLinkCode src, {String? studentName}) {
    return LinkCode(
      id: src.id,
      code: src.code,
      studentId: src.studentId ?? '',
      studentName: studentName ?? '',
      academyId: src.academyId,
      createdBy: src.createdByUid ?? '',
      createdAt: src.createdAt ?? DateTime.now(),
      expiresAt: src.expiresAt,
      usedAt: src.usedAt,
      usedBy: src.usedByUid,
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
///
/// All Firestore operations have been replaced with HTTP calls via
/// [LinkCodeRemoteRepo]. Methods that have no matching backend endpoint
/// are marked as no-ops with TODO comments.
class LinkCodeService {
  final String academyId;
  final LinkCodeRemoteRepo _repo;

  LinkCodeService(this.academyId, this._repo);

  // ============================================
  // Get Code by Code String
  // Returns null if not found or backend error.
  // Uses the preview endpoint GET /v1/link-codes/{code}.
  // Note: preview returns academy info, not full LinkCode — we synthesize
  // a minimal LinkCode from the preview.
  // ============================================
  Future<LinkCode?> getByCode(String code) async {
    try {
      final preview = await _repo.getPreview(code.toUpperCase());
      return LinkCode(
        id: '',
        code: code.toUpperCase(),
        studentId: preview.studentId ?? '',
        studentName: preview.studentName ?? '',
        academyId: preview.academyId,
        createdBy: '',
        createdAt: DateTime.now(),
        expiresAt: preview.expiresAt,
      );
    } catch (_) {
      return null;
    }
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
  // TODO(tatami): sem endpoint GET /v1/academies/{id}/link-codes com filtro
  // por student_id. Retorna null enquanto não houver.
  // ============================================
  Future<LinkCode?> getActiveForStudent(String studentId) async {
    // TODO(tatami): implement when GET /v1/academies/{id}/link-codes?student_id= is available
    debugPrint('[LinkCodeService] getActiveForStudent: no-op — endpoint not available yet');
    return null;
  }

  // ============================================
  // Get All Codes for Student
  // TODO(tatami): sem endpoint de listagem por student_id.
  // ============================================
  Future<List<LinkCode>> getForStudent(String studentId) async {
    // TODO(tatami): implement when GET /v1/academies/{id}/link-codes?student_id= is available
    debugPrint('[LinkCodeService] getForStudent: no-op — endpoint not available yet');
    return [];
  }

  // ============================================
  // Get Code by ID
  // TODO(tatami): sem endpoint GET /v1/academies/{id}/link-codes/{id}.
  // ============================================
  Future<LinkCode?> getById(String id) async {
    // TODO(tatami): implement when GET /v1/academies/{id}/link-codes/{id} is available
    debugPrint('[LinkCodeService] getById: no-op — endpoint not available yet');
    return null;
  }

  // ============================================
  // Get Pending Codes (active, unused, not expired)
  // TODO(tatami): sem endpoint de listagem geral.
  // ============================================
  Future<List<LinkCode>> getPending() async {
    // TODO(tatami): implement when GET /v1/academies/{id}/link-codes is available
    debugPrint('[LinkCodeService] getPending: no-op — endpoint not available yet');
    return [];
  }

  // ============================================
  // Get Recently Used Codes
  // TODO(tatami): sem endpoint de listagem geral.
  // ============================================
  Future<List<LinkCode>> getRecentlyUsed({int limit = 10}) async {
    // TODO(tatami): implement when GET /v1/academies/{id}/link-codes is available
    debugPrint('[LinkCodeService] getRecentlyUsed: no-op — endpoint not available yet');
    return [];
  }

  // ============================================
  // Generate Code
  // POST /v1/academies/{academyId}/link-codes
  // ============================================
  Future<LinkCode> generate({
    required String studentId,
    required String studentName,
    required String createdBy,
    int? ttlSeconds,
  }) async {
    final src = await _repo.createForStudent(
      academyId,
      studentId: studentId,
      ttlSeconds: ttlSeconds,
    );
    return LinkCode.fromApi(src, studentName: studentName);
  }

  // ============================================
  // Mark Code as Used
  // No-op: the backend handles this atomically in POST /link-codes/{code}/redeem.
  // Manual marking is not needed and has no matching endpoint.
  // ============================================
  Future<LinkCode> markAsUsed(String code, String userId) async {
    // No-op: redeem is handled server-side.
    debugPrint('[LinkCodeService] markAsUsed: no-op — server handles on redeem');
    final existing = await getByCode(code);
    if (existing == null) throw Exception('Código não encontrado');
    return existing;
  }

  // ============================================
  // Delete Code
  // No-op: no DELETE endpoint for link codes.
  // TODO(tatami): implement when DELETE /v1/academies/{id}/link-codes/{id} is available.
  // ============================================
  Future<void> delete(String id) async {
    // TODO(tatami): implement when DELETE /v1/academies/{id}/link-codes/{id} is available
    debugPrint('[LinkCodeService] delete($id): no-op — endpoint not available yet');
  }

  // ============================================
  // Cleanup Expired Codes
  // No-op: backend manages TTL expiration automatically.
  // ============================================
  Future<int> cleanupExpired() async {
    // Backend manages TTL — no client-side cleanup needed.
    return 0;
  }

  // ============================================
  // Invalidate All Codes for Student
  // No-op: delete is a no-op; invalidation is server-managed.
  // ============================================
  Future<void> invalidate(String studentId) async {
    // No-op: backend manages code lifecycle.
    debugPrint('[LinkCodeService] invalidate: no-op — server manages code lifecycle');
  }
}

// ============================================
// Factory Function
// ============================================
LinkCodeService createLinkCodeService(String academyId) {
  return LinkCodeService(
    academyId,
    LinkCodeRemoteRepo(TatamiClient(baseUrl: _tatamiBaseUrl)),
  );
}

// ============================================
// Default Instance (uses current academy)
// ============================================
LinkCodeService get linkCodeService => LinkCodeService(
      FirebaseService.academyId,
      LinkCodeRemoteRepo(TatamiClient(baseUrl: _tatamiBaseUrl)),
    );

// ============================================
// GLOBAL VALIDATION (Multi-tenant)
// Used during registration when user doesn't have an academy yet.
//
// Migrated from Firestore collectionGroup to GET /v1/link-codes/{code}
// which returns academy_id directly in the preview response.
// ============================================

/// Validate code across ALL academies using the Tatami REST API.
///
/// GET /v1/link-codes/{code} returns academy_id in the preview — no
/// Firestore collectionGroup needed. This endpoint is unauthenticated
/// (preview only) so it works during registration before the user has
/// an academy context.
Future<LinkCodeValidation> validateCodeGlobally(String code) async {
  final repo = LinkCodeRemoteRepo(TatamiClient(baseUrl: _tatamiBaseUrl));

  try {
    final preview = await repo.getPreview(code.toUpperCase());

    if (preview.academyId.isEmpty) {
      return LinkCodeValidation(
        valid: false,
        error: 'Erro ao identificar academia do código',
      );
    }

    final expiresAt = preview.expiresAt;
    if (DateTime.now().isAfter(expiresAt)) {
      return LinkCodeValidation(
        valid: false,
        error: 'Este código expirou',
      );
    }

    final linkCode = LinkCode(
      id: '',
      code: code.toUpperCase(),
      studentId: preview.studentId ?? '',
      studentName: preview.studentName ?? '',
      academyId: preview.academyId,
      createdBy: '',
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
    );

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
