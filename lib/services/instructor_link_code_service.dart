import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_service.dart';
import 'team_service.dart';

/// Permissions the academy owner is allowed to grant on top of the
/// instructor role's defaults. Mirrors GRANTABLE_EXTRA_PERMISSIONS on the
/// web side — keep these two lists in sync.
class GrantablePermission {
  final String permission;
  final String label;
  final String description;
  const GrantablePermission(this.permission, this.label, this.description);
}

const List<GrantablePermission> kGrantableExtraPermissions = [
  GrantablePermission('attendance:take', 'Fazer chamada',
      'Registrar presença dos alunos nas aulas'),
  GrantablePermission('financial:view', 'Ver financeiro',
      'Mensalidades, quem pagou, recibos'),
  GrantablePermission('financial:create', 'Lançar cobranças',
      'Criar novas cobranças (não inclui edição/exclusão)'),
  GrantablePermission('students:create', 'Cadastrar alunos',
      'Criar novos alunos na academia'),
  GrantablePermission('students:delete', 'Excluir alunos',
      'Remover alunos da academia (cuidado!)'),
  GrantablePermission('reports:view', 'Ver relatórios',
      'Acessar dashboards e métricas'),
  GrantablePermission('competitions:create', 'Criar competições',
      'Cadastrar torneios e abrir inscrições'),
  GrantablePermission('graduation:manage', 'Graduar alunos',
      'Promover faixas e registrar graduações'),
];

/// One-shot 8-char code that, when redeemed, links a user to an academy as
/// `instructor` and grants the snapshot of `extraPermissions` it carries.
class InstructorLinkCode {
  final String id;
  final String code;
  final String createdBy;
  final String createdByName;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<String> extraPermissions;
  final DateTime? usedAt;
  final String? usedBy;
  final String? usedByName;

  const InstructorLinkCode({
    required this.id,
    required this.code,
    required this.createdBy,
    required this.createdByName,
    required this.createdAt,
    required this.expiresAt,
    required this.extraPermissions,
    this.usedAt,
    this.usedBy,
    this.usedByName,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isUsed => usedAt != null;

  factory InstructorLinkCode.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return InstructorLinkCode(
      id: doc.id,
      code: data['code'] ?? doc.id,
      createdBy: data['createdBy'] ?? '',
      createdByName: data['createdByName'] ?? '',
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt:
          (data['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      extraPermissions: data['extraPermissions'] is List
          ? List<String>.from(data['extraPermissions'])
          : const [],
      usedAt: (data['usedAt'] as Timestamp?)?.toDate(),
      usedBy: data['usedBy'],
      usedByName: data['usedByName'],
    );
  }
}

class InstructorLinkCodeService {
  static const _ttlMinutes = 30;
  static const _codeLen = 8;
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  final String academyId;
  InstructorLinkCodeService(this.academyId);

  CollectionReference get _codesRef => FirebaseService.firestore
      .collection('academies/$academyId/instructorLinkCodes');

  String _generateCode() {
    final rng = Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < _codeLen; i++) {
      buf.write(_alphabet[rng.nextInt(_alphabet.length)]);
    }
    return buf.toString();
  }

  /// Generate a fresh code valid for 30 minutes.
  Future<InstructorLinkCode> generate({
    required String createdBy,
    required String createdByName,
    required List<String> extraPermissions,
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: _ttlMinutes));

    for (var attempt = 0; attempt < 5; attempt++) {
      final code = _generateCode();
      final ref = _codesRef.doc(code);
      final existing = await ref.get();
      if (existing.exists) continue;
      final payload = {
        'code': code,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'createdAt': Timestamp.fromDate(now),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'extraPermissions': extraPermissions,
      };
      await ref.set(payload);
      return InstructorLinkCode(
        id: code,
        code: code,
        createdBy: createdBy,
        createdByName: createdByName,
        createdAt: now,
        expiresAt: expiresAt,
        extraPermissions: extraPermissions,
      );
    }
    throw Exception('Não foi possível gerar um código único. Tente novamente.');
  }

  /// List unused, unexpired codes for the academy.
  Future<List<InstructorLinkCode>> listActive() async {
    final snap = await _codesRef.get();
    final now = DateTime.now();
    final list = snap.docs
        .map(InstructorLinkCode.fromFirestore)
        .where((c) => c.usedAt == null && c.expiresAt.isAfter(now))
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> delete(String codeId) async {
    await _codesRef.doc(codeId).delete();
  }
}

/// Cross-academy lookup used during redeem flow (no academy context yet).
/// Returns the matching code plus the academyId extracted from the doc path.
Future<({InstructorLinkCode code, String academyId})?>
    validateInstructorCodeGlobally(String rawCode) async {
  final code = rawCode.trim().toUpperCase();
  if (code.isEmpty) return null;
  final q = await FirebaseService.firestore
      .collectionGroup('instructorLinkCodes')
      .where('code', isEqualTo: code)
      .get();

  for (final d in q.docs) {
    final parsed = InstructorLinkCode.fromFirestore(d);
    if (parsed.isUsed || parsed.isExpired) continue;
    // Path: academies/{academyId}/instructorLinkCodes/{codeId}
    final parts = d.reference.path.split('/');
    if (parts.length < 2) continue;
    return (code: parsed, academyId: parts[1]);
  }
  return null;
}

/// Promote an existing user (already linked to the academy) to instructor.
/// Delegates to the `promoteToInstructor` Cloud Function, which validates
/// that the caller is the academy admin before mutating the mapping.
Future<void> promoteUserToInstructor({
  required String userId,
  required String academyId,
  required List<String> extraPermissions,
  String? email,
  String? displayName,
}) async {
  await teamService.promoteToInstructor(
    userId: userId,
    academyId: academyId,
    extraPermissions: extraPermissions,
  );
}

/// Redeem an instructor invite code for the currently-authenticated user.
/// Delegates to the `redeemInstructorCode` Cloud Function — the function
/// resolves the academy from the code itself and stamps the stored
/// extraPermissions atomically with the code-used mark.
Future<void> redeemInstructorCode({
  required InstructorLinkCode code,
  required String academyId,
  required String userId,
  required String userEmail,
  required String userDisplayName,
}) async {
  await teamService.redeemInstructorCode(code.code);
}
