import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/join_request.dart';
import '../services/firebase_service.dart';
import 'auth_provider.dart';

/// STUDENT SIDE — ponteiro `users/{uid}.pendingJoinRequest`. Emite a solicitação
/// pendente do usuário logado (ou null). Usado pela tela "aguardando aprovação"
/// na aba Academia. Reage em tempo real (aprovar/negar limpa o ponteiro).
final pendingJoinRequestProvider =
    StreamProvider<PendingJoinRequest?>((ref) {
  final authUser = ref.watch(authStateProvider).valueOrNull;
  final uid = authUser?.uid ?? ref.watch(currentUserProvider).valueOrNull?.id;
  if (uid == null) return Stream.value(null);
  return FirebaseService.firestore
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((snap) {
    if (!snap.exists) return null;
    final data = snap.data();
    final raw = data?['pendingJoinRequest'];
    return PendingJoinRequest.fromMap(
        raw is Map ? Map<String, dynamic>.from(raw) : null);
  });
});

/// ADMIN SIDE — solicitações PENDENTES da academia atual, mais recentes primeiro.
/// Stream em tempo real (o badge "Solicitações (N)" e a lista acompanham).
final academyJoinRequestsProvider =
    StreamProvider.autoDispose<List<JoinRequest>>((ref) {
  final academyId = FirebaseService.academyId;
  if (academyId.isEmpty) return Stream.value(const <JoinRequest>[]);
  return FirebaseService.firestore
      .collection('academies')
      .doc(academyId)
      .collection('joinRequests')
      .where('status', isEqualTo: 'pending')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) => snap.docs.map(JoinRequest.fromDoc).toList());
});

/// Contagem de solicitações pendentes (para o badge). 0 enquanto carrega/erro.
final pendingJoinRequestsCountProvider = Provider.autoDispose<int>((ref) {
  return ref.watch(academyJoinRequestsProvider).maybeWhen(
        data: (list) => list.length,
        orElse: () => 0,
      );
});

/// Código ÚNICO da academia atual (o que vai no grupo do WhatsApp). null quando
/// ainda não foi gerado — a UI oferece "gerar" (rotateAcademyJoinCode).
final academyJoinCodeProvider = StreamProvider.autoDispose<String?>((ref) {
  final academyId = FirebaseService.academyId;
  if (academyId.isEmpty) return Stream.value(null);
  return FirebaseService.firestore
      .collection('academies')
      .doc(academyId)
      .snapshots()
      .map((s) => (s.data()?['joinCode'])?.toString());
});
