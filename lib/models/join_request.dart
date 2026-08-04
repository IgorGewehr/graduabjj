import 'package:cloud_firestore/cloud_firestore.dart';

/// Solicitação de entrada numa academia (self-onboarding). Vive em
/// `academies/{academyId}/joinRequests/{uid}` — doc id = uid do solicitante,
/// então há no máximo UMA solicitação por (academia, usuário). Escrita só por
/// Cloud Function (submitJoinRequest / decideJoinRequest / cancelJoinRequest).
class JoinRequest {
  /// uid do solicitante (== id do doc).
  final String uid;

  /// 'pending' | 'approved' | 'denied'.
  final String status;

  final String fullName;
  final String? email;
  final String? phone;
  final String? cpf;
  final DateTime? birthDate;

  /// 'kids' | 'adult' | null (o que o aluno informou no cadastro).
  final String? category;

  final DateTime? createdAt;
  final DateTime? decidedAt;
  final String? decidedBy;

  /// Ficha vinculada quando aprovado.
  final String? linkedStudentId;

  const JoinRequest({
    required this.uid,
    required this.status,
    required this.fullName,
    this.email,
    this.phone,
    this.cpf,
    this.birthDate,
    this.category,
    this.createdAt,
    this.decidedAt,
    this.decidedBy,
    this.linkedStudentId,
  });

  bool get isPending => status == 'pending';

  factory JoinRequest.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    return JoinRequest(
      uid: doc.id,
      status: (d['status'] ?? 'pending').toString(),
      fullName: (d['fullName'] ?? 'Aluno').toString(),
      email: d['email']?.toString(),
      phone: d['phone']?.toString(),
      cpf: d['cpf']?.toString(),
      birthDate: (d['birthDate'] as Timestamp?)?.toDate(),
      category: d['category']?.toString(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      decidedAt: (d['decidedAt'] as Timestamp?)?.toDate(),
      decidedBy: d['decidedBy']?.toString(),
      linkedStudentId: d['linkedStudentId']?.toString(),
    );
  }
}

/// Ponteiro leve em `users/{uid}.pendingJoinRequest` — o app do aluno usa isto
/// para renderizar a tela "aguardando aprovação" sem query de collectionGroup.
class PendingJoinRequest {
  final String academyId;
  final String academyName;
  final String requestId;
  final DateTime? createdAt;

  const PendingJoinRequest({
    required this.academyId,
    required this.academyName,
    required this.requestId,
    this.createdAt,
  });

  static PendingJoinRequest? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final academyId = m['academyId']?.toString();
    if (academyId == null || academyId.isEmpty) return null;
    return PendingJoinRequest(
      academyId: academyId,
      academyName: (m['academyName'] ?? 'Academia').toString(),
      requestId: (m['requestId'] ?? '').toString(),
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
