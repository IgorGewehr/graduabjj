import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_service.dart';

/// Um contato de reengajamento registrado pelo staff para um aluno em risco.
///
/// Vive em `academies/{aid}/retentionContacts/{autoId}`. O outcome nasce
/// 'pending' e é fechado pelo job diário (Admin SDK): presença do aluno em
/// até 14 dias após o contato → 'recovered'; senão → 'lost'.
///
/// Invariante de privacidade: como o billingContactLog, NUNCA é visível ao
/// aluno — leitura/escrita são staff-only pelas rules (`isAcademyStaff`).
class RetentionContact {
  final String id;
  final String studentId;

  /// 'whatsapp' | 'push' | 'phone' | 'inperson'
  final String channel;

  /// UID do staff que registrou — a rule exige `byUid == request.auth.uid`
  /// no create (rastreabilidade não-forjável).
  final String byUid;

  /// Momento do contato (serverTimestamp). Null apenas em snapshots locais
  /// com latência de escrita pendente.
  final DateTime? at;

  /// Template usado no disparo (ex.: 'retention_7_14d'), quando aplicável.
  final String? templateId;
  final String? note;

  /// 'pending' | 'recovered' | 'lost' — fechado pelo job diário.
  final String outcome;
  final DateTime? outcomeAt;

  const RetentionContact({
    required this.id,
    required this.studentId,
    required this.channel,
    required this.byUid,
    required this.at,
    this.templateId,
    this.note,
    this.outcome = 'pending',
    this.outcomeAt,
  });

  factory RetentionContact.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? const {};
    return RetentionContact(
      id: doc.id,
      studentId: data['studentId'] as String? ?? '',
      channel: data['channel'] as String? ?? 'inperson',
      byUid: data['byUid'] as String? ?? '',
      at: (data['at'] as Timestamp?)?.toDate(),
      templateId: data['templateId'] as String?,
      note: data['note'] as String?,
      outcome: data['outcome'] as String? ?? 'pending',
      outcomeAt: (data['outcomeAt'] as Timestamp?)?.toDate(),
    );
  }

  bool get isPending => outcome == 'pending';
  bool get isRecovered => outcome == 'recovered';
  bool get isLost => outcome == 'lost';
}

/// Serviço de registro/consulta de contatos de reengajamento (Retenção 2.0).
///
/// Só ESCREVE o registro do contato — o disparo em si (wa.me, push callable)
/// acontece na camada de UI/serviços dedicados. O fechamento do outcome é
/// exclusivo do job diário server-side.
class RetentionContactService {
  final String academyId;
  final Collections _collections;

  RetentionContactService(this.academyId) : _collections = Collections(academyId);

  CollectionReference get _col => _collections.academy.collection('retentionContacts');

  /// Registra um contato feito com o aluno. `byUid` é SEMPRE o uid autenticado
  /// atual — obrigatório pela rule de create (não aceita byUid de terceiro).
  Future<void> registerContact({
    required String studentId,
    required String channel,
    String? templateId,
    String? note,
  }) async {
    final uid = FirebaseService.currentUserId;
    if (uid == null) {
      throw StateError('Sem usuário autenticado para registrar contato');
    }
    final trimmedNote = note?.trim();
    await _col.add(<String, dynamic>{
      'studentId': studentId,
      'channel': channel,
      'byUid': uid,
      'at': FieldValue.serverTimestamp(),
      if (templateId != null) 'templateId': templateId,
      if (trimmedNote != null && trimmedNote.isNotEmpty) 'note': trimmedNote,
      'outcome': 'pending',
    });
  }

  /// Últimos contatos de um aluno, mais recentes primeiro.
  ///
  /// A query composta (where + orderBy) pode exigir índice composto; no
  /// fallback lê sem orderBy e ordena client-side (volume por aluno é pequeno).
  Future<List<RetentionContact>> listForStudent(
    String studentId, {
    int limit = 20,
  }) async {
    QuerySnapshot snap;
    try {
      snap = await _col
          .where('studentId', isEqualTo: studentId)
          .orderBy('at', descending: true)
          .limit(limit)
          .get();
    } on FirebaseException {
      // Índice composto ausente → lê sem orderBy e ordena localmente.
      snap = await _col
          .where('studentId', isEqualTo: studentId)
          .limit(limit * 3)
          .get();
    }
    final contacts = snap.docs.map(RetentionContact.fromDoc).toList()
      ..sort((a, b) {
        final ta = a.at ?? DateTime.now();
        final tb = b.at ?? DateTime.now();
        return tb.compareTo(ta);
      });
    return contacts.take(limit).toList();
  }

  /// Todos os contatos registrados a partir de [since] (range single-field,
  /// sem índice composto). Alimenta a métrica "De N contatados, M voltaram".
  Future<List<RetentionContact>> listSince(DateTime since) async {
    final snap = await _col
        .where('at', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
        .get();
    return snap.docs.map(RetentionContact.fromDoc).toList();
  }

  /// StudentIds com contato ainda 'pending' (aguardando outcome do job).
  /// Usado pelo gate de "sugerir inativar" (não sugerir com contato em aberto).
  Future<Set<String>> pendingContactStudentIds() async {
    final snap = await _col.where('outcome', isEqualTo: 'pending').get();
    return snap.docs
        .map((d) => (d.data() as Map<String, dynamic>)['studentId'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }
}
