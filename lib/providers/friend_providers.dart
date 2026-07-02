import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sports.dart';
import '../models/feed_post.dart';
import '../models/fighter_profile.dart';
import '../models/ranking_entry.dart';
import '../services/achievement_service.dart';
import '../services/attendance_service.dart';
import '../services/belt_progression_service.dart';
import '../services/class_service.dart';
import '../services/feed_posts_service.dart';
import '../services/friend_service.dart';
import '../services/ranking_service.dart';
import '../services/self_records_service.dart';
import '../services/showcase_builder.dart';
import '../models/training_log.dart';
import '../services/training_log_service.dart';
import '../services/weekly_streak.dart';
import 'auth_provider.dart';
import 'portal_providers.dart';
import 'student_provider.dart';

/// Espelha o MEU perfil público (fighterProfiles/{uid}) e retorna meu código
/// curto de amigo (gerado na 1ª vez, estável depois). Watchar isto garante que
/// eu fico "descobrível por código" assim que abro a aba social.
final myFighterCodeProvider = FutureProvider<String?>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return null;
  final student = await ref.watch(currentStudentProvider.future);

  final sport = student?.getPrimarySport() ?? SportId.bjj;
  final grade = student?.getGrade(sport);
  final belt = grade?.currentGrade ?? student?.currentBelt ?? 'white';
  final stripes = grade?.currentStripes ?? student?.currentStripes ?? 0;
  final name = (student?.nickname != null && student!.nickname!.isNotEmpty)
      ? student.nickname!
      : (student?.fullName ?? 'Lutador');
  final total = student?.totalAttendanceCount ?? 0;
  final streak = student == null
      ? 0
      : (ref
              .watch(studentStreakInfoProvider(student.id))
              .valueOrNull
              ?.currentWeeks ??
          0);
  final academyName = ref.watch(academySettingsProvider).valueOrNull?.name;

  return friendService.mirror(
    uid: user.id,
    name: name,
    belt: belt,
    stripes: stripes,
    sport: sport.value,
    photoUrl: student?.photoUrl,
    totalTrainings: total,
    currentStreak: streak,
    academyName: academyName,
  );
});

/// Meus amigos (quem eu sigo), com o perfil público de cada um.
final myFriendsProvider = FutureProvider<List<FighterProfile>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return const [];
  return friendService.getFriends(user.id);
});

/// VITRINE DO DONO — computa a vitrine do PRÓPRIO usuário a partir dos dados da
/// sua academia (beltProgressions + attendance + achievements + streak),
/// MATERIALIZA em `fighterProfiles/{uid}` (write condicional por hash) e devolve
/// o [FighterProfile] já com a vitrine para o owner renderizar imediatamente —
/// sem precisar reler o espelho.
///
/// Custo: leituras que o Treinei já dispara (progressões + streak) + 1 leitura
/// de attendance (bound 2000) + 1 de competições + 1 write condicional do
/// mirror (só quando o hash muda). Tudo da PRÓPRIA academia do dono.
final myShowcaseProvider = FutureProvider<FighterProfile?>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return null;
  final academyId = user.academyId;
  final student = await ref.watch(currentStudentProvider.future);
  if (academyId == null || academyId.isEmpty || student == null) return null;

  final sport = student.getPrimarySport();
  final grade = student.getGrade(sport);
  final belt = grade?.currentGrade ?? student.currentBelt;
  final stripes = grade?.currentStripes ?? student.currentStripes;
  final name = (student.nickname != null && student.nickname!.isNotEmpty)
      ? student.nickname!
      : student.fullName;
  final academyName = ref.watch(academySettingsProvider).valueOrNull?.name;
  final useWeights =
      ref.watch(academySettingsProvider).valueOrNull?.useClassWeights ?? false;

  // Leituras da PRÓPRIA academia (owner-side). studentId == student.id.
  final progs = await BeltProgressionService(academyId).getByStudent(student.id);
  final att =
      await AttendanceService(academyId).getByStudent(student.id, limit: 2000);
  final comps = await AchievementService(academyId).getCompetitions(student.id);
  // Auto-declarados do aluno (Jornada multi-fonte): graduações/competições que
  // o próprio lutador registrou, em coleções separadas de beltProgressions.
  final selfRecords = SelfRecordsService(academyId);
  final selfGrads = await selfRecords.listGraduations(student.id);
  final selfComps = await selfRecords.listCompetitions(student.id);
  // Streak SEMANAL POR ESPORTE (esporte PRINCIPAL — a Jornada é primary-centric,
  // casa com graduações/competições já sport-tagged). FUNDE presença verificada
  // (reusa `att`, já lido) + self-logs do próprio uid, dedup por dia, e computa
  // via a mesma função pura do dashboard.
  final trainedDays = <DateTime>{};
  for (final a in att) {
    if ((a.sport ?? 'bjj') != sport.value) continue;
    trainedDays.add(DateTime(a.date.year, a.date.month, a.date.day));
  }
  final selfLogs = await TrainingLogService(user.id).recent(limit: 400);
  for (final l in selfLogs) {
    if (l.effectiveSport != sport.value) continue;
    trainedDays.add(DateTime(l.date.year, l.date.month, l.date.day));
  }
  final streak = computeWeeklyStreak(trainedDays: trainedDays, now: DateTime.now());

  final showcase = ShowcaseBuilder.build(
    progressions: progs,
    attendance: att,
    competitions: comps,
    selfGraduations: selfGrads,
    selfCompetitions: selfComps,
    streak: (currentWeeks: streak.currentWeeks, recordWeeks: streak.recordWeeks),
    startDate: student.startDate,
    totalTrainings: student.totalAttendanceCount,
    useWeights: useWeights,
  );

  // Materializa (write condicional por hash) e propaga o photoUrl/código.
  await friendService.mirror(
    uid: user.id,
    name: name,
    belt: belt,
    stripes: stripes,
    sport: sport.value,
    photoUrl: student.photoUrl,
    totalTrainings: showcase.totalTrainings,
    currentStreak: showcase.currentStreak,
    academyName: academyName,
    recordStreak: showcase.recordStreak,
    firstTrainingDate: showcase.firstTrainingDate,
    lastTrainingDate: showcase.lastTrainingDate,
    graduations: showcase.graduations,
    competitions: showcase.competitions,
    medals: showcase.medals,
    showcaseHash: showcase.hash,
  );

  // Emite posts do feed social (create-if-absent idempotente — never reescreve).
  try {
    await _emitFeedPosts(
      uid: user.id,
      name: name,
      belt: belt,
      stripes: stripes,
      photoUrl: student.photoUrl,
      academyId: academyId,
      showcase: showcase,
      att: att,
      selfLogs: selfLogs,
      streakCurrentWeeks: streak.currentWeeks,
    );
  } catch (_) {
    // Feed não é crítico: falha silenciosa para não bloquear a abertura do app.
  }

  // Devolve o perfil local já com a vitrine (consistente com o que o visitante
  // lerá) — sem custar uma releitura do espelho.
  return FighterProfile(
    uid: user.id,
    name: name,
    belt: belt,
    stripes: stripes,
    sport: sport.value,
    fighterCode: '',
    photoUrl: student.photoUrl,
    totalTrainings: showcase.totalTrainings,
    currentStreak: showcase.currentStreak,
    academyName: academyName,
    recordStreak: showcase.recordStreak,
    firstTrainingDate: showcase.firstTrainingDate,
    lastTrainingDate: showcase.lastTrainingDate,
    graduations: showcase.graduations,
    competitions: showcase.competitions,
    medals: showcase.medals,
    showcaseUpdatedAt: DateTime.now(),
  );
});

// =============================================================================
// Feed post emitter — chamado por myShowcaseProvider após mirror().
// Emite (create-if-absent) todos os marcos deriváveis da vitrine atual.
// =============================================================================
Future<void> _emitFeedPosts({
  required String uid,
  required String name,
  required String belt,
  required int stripes,
  required String? photoUrl,
  required String academyId,
  required ShowcaseData showcase,
  required List<Attendance> att,
  required List<TrainingLog> selfLogs,
  required int streakCurrentWeeks,
}) async {
  final now = DateTime.now();

  // ── 1. GRADUAÇÕES ──────────────────────────────────────────────────────────
  for (final g in showcase.graduations) {
    final postId = FeedPost.gradId(uid, g.date, g.belt, g.stripes);
    await feedPostsService.emitIfAbsent(FeedPost(
      postId: postId,
      authorUid: uid,
      type: FeedPostType.graduacao,
      payload: GraduacaoPayload(
        belt: g.belt,
        stripes: g.stripes,
        isBeltChange: g.isBeltChange,
        trainingsToReach: g.trainingsToReach,
        monthsToReach: g.monthsToReach,
      ),
      occurredAt: g.date,
      academyId: academyId,
      authorName: name,
      authorBelt: belt,
      authorStripes: stripes,
      authorPhotoUrl: photoUrl,
    ));
  }

  // ── 2. COMPETIÇÕES ─────────────────────────────────────────────────────────
  for (final c in showcase.competitions) {
    final postId = FeedPost.compId(uid, c.date, c.name);
    await feedPostsService.emitIfAbsent(FeedPost(
      postId: postId,
      authorUid: uid,
      type: FeedPostType.competicao,
      payload: CompeticaoPayload(name: c.name, position: c.position),
      occurredAt: c.date,
      academyId: academyId,
      authorName: name,
      authorBelt: belt,
      authorStripes: stripes,
      authorPhotoUrl: photoUrl,
    ));
  }

  // ── 3. STREAK MILESTONE — só quando cruzar um dos thresholds exatos ────────
  if (streakMilestones.contains(streakCurrentWeeks)) {
    final postId = FeedPost.streakId(uid, streakCurrentWeeks);
    await feedPostsService.emitIfAbsent(FeedPost(
      postId: postId,
      authorUid: uid,
      type: FeedPostType.streakMilestone,
      payload: StreakMilestonePayload(weeks: streakCurrentWeeks),
      occurredAt: now,
      academyId: academyId,
      authorName: name,
      authorBelt: belt,
      authorStripes: stripes,
      authorPhotoUrl: photoUrl,
    ));
  }

  // ── 4. SPARRING RECORD — melhor noite (max sparringCount > 0) ──────────────
  if (selfLogs.isNotEmpty) {
    final maxRolas = selfLogs.fold<int>(
        0,
        (int acc, TrainingLog l) =>
            l.sparringCount > acc ? l.sparringCount : acc);
    if (maxRolas > 0) {
      final bestLog = selfLogs.firstWhere(
          (TrainingLog l) => l.sparringCount == maxRolas);
      final postId = FeedPost.sparPrId(uid, maxRolas);
      await feedPostsService.emitIfAbsent(FeedPost(
        postId: postId,
        authorUid: uid,
        type: FeedPostType.sparringRecord,
        payload: SparringRecordPayload(recorde: maxRolas),
        occurredAt: bestLog.date,
        academyId: academyId,
        authorName: name,
        authorBelt: belt,
        authorStripes: stripes,
        authorPhotoUrl: photoUrl,
      ));
    }
  }

  // ── 5. WEEKLY VOLUME — última semana ISO FECHADA ───────────────────────────
  // Semana fechada = a semana que encerrou no domingo PASSADO (não a atual).
  final currentMonday = FeedPost.mondayUtcOf(now);
  final closedMonday = currentMonday.subtract(const Duration(days: 7));

  // Conta dias únicos treinados (att + selfLog) na semana fechada.
  final trainedDays = <DateTime>{};
  for (final a in att) {
    if (FeedPost.mondayUtcOf(a.date) == closedMonday) {
      trainedDays.add(DateTime(a.date.year, a.date.month, a.date.day));
    }
  }
  for (final l in selfLogs) {
    if (FeedPost.mondayUtcOf(l.date) == closedMonday) {
      trainedDays.add(DateTime(l.date.year, l.date.month, l.date.day));
    }
  }
  final weekRolas = selfLogs
      .where((TrainingLog l) => FeedPost.mondayUtcOf(l.date) == closedMonday)
      .fold<int>(0, (int s, TrainingLog l) => s + l.sparringCount);

  if (trainedDays.isNotEmpty) {
    final postId = FeedPost.volId(uid, closedMonday);
    await feedPostsService.emitIfAbsent(FeedPost(
      postId: postId,
      authorUid: uid,
      type: FeedPostType.weeklyVolume,
      payload: WeeklyVolumePayload(
          trainings: trainedDays.length, rolas: weekRolas),
      // occurredAt = domingo da semana fechada (mais intuitivo no feed).
      occurredAt: closedMonday.add(const Duration(days: 6)),
      academyId: academyId,
      authorName: name,
      authorBelt: belt,
      authorStripes: stripes,
      authorPhotoUrl: photoUrl,
    ));
  }

  // ── 6. MAT MILESTONES (opcional) — aulas acumuladas e anos de tatame ───────
  final total = showcase.totalTrainings;
  for (final milestone in matMilestones) {
    if (total >= milestone) {
      final postId = FeedPost.matId(uid, milestone.toString());
      await feedPostsService.emitIfAbsent(FeedPost(
        postId: postId,
        authorUid: uid,
        type: FeedPostType.matMilestone,
        payload: MatMilestonePayload(marco: milestone.toString()),
        occurredAt: now, // data aproximada (1ª emissão = quando cruzou)
        academyId: academyId,
        authorName: name,
        authorBelt: belt,
        authorStripes: stripes,
        authorPhotoUrl: photoUrl,
      ));
    }
  }
  for (final yr in matAnniversaries) {
    final anniversary =
        showcase.firstTrainingDate.add(Duration(days: yr * 365));
    if (!now.isBefore(anniversary)) {
      final postId = FeedPost.matId(uid, '${yr}yr');
      await feedPostsService.emitIfAbsent(FeedPost(
        postId: postId,
        authorUid: uid,
        type: FeedPostType.matMilestone,
        payload: MatMilestonePayload(marco: '${yr}yr'),
        occurredAt: anniversary,
        academyId: academyId,
        authorName: name,
        authorBelt: belt,
        authorStripes: stripes,
        authorPhotoUrl: photoUrl,
      ));
    }
  }
}

// =============================================================================
// Providers de audiência e feed.
// =============================================================================

/// UIDs dos PARCEIROS de treino do usuário atual:
///   Camada 1 — follows bidirecional (getFriends).
///   Camada 2 — colegas de turma (BJJClass.studentIds → publicProfiles.linkedUserId).
/// O próprio uid é excluído do resultado.
final myPartnersAudienceProvider = FutureProvider<List<String>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return const [];
  final student = await ref.watch(currentStudentProvider.future);

  final uids = <String>{};

  // Camada 1: amigos por código (follows bidirecionais).
  final friends = await ref.watch(myFriendsProvider.future);
  for (final f in friends) {
    uids.add(f.uid);
  }

  // Camada 2: colegas de turma (mesmo academyId).
  final aid = user.academyId;
  final myStudentId = student?.id;
  if (aid != null && myStudentId != null) {
    try {
      final allClasses = await ClassService(aid).list();
      final peerIds = <String>{};
      for (final c in allClasses) {
        if (c.studentIds.contains(myStudentId)) {
          for (final sid in c.studentIds) {
            if (sid != myStudentId) peerIds.add(sid);
          }
        }
      }
      if (peerIds.isNotEmpty) {
        // Lê publicProfiles (sem PII) para obter linkedUserId de cada colega.
        final pubRef = FirebaseFirestore.instance
            .collection('academies')
            .doc(aid)
            .collection('publicProfiles');
        final idList = peerIds.toList();
        for (var i = 0; i < idList.length; i += 10) {
          final end = (i + 10).clamp(0, idList.length);
          final q = await pubRef
              .where(FieldPath.documentId, whereIn: idList.sublist(i, end))
              .get();
          for (final d in q.docs) {
            final linkedUid = d.data()['linkedUserId'];
            if (linkedUid is String && linkedUid.isNotEmpty) {
              uids.add(linkedUid);
            }
          }
        }
      }
    } catch (_) {
      // Fallback seguro: usa só os amigos se leitura de turmas falhar.
    }
  }

  uids.remove(user.id);
  return uids.toList();
});

/// Feed de posts dos PARCEIROS do usuário atual (aba PARCEIROS).
/// Busca via [feedPostsService.feedForAudience] batchando a [myPartnersAudienceProvider].
final feedPostsProvider = FutureProvider<List<FeedPost>>((ref) async {
  final audienceUids = await ref.watch(myPartnersAudienceProvider.future);
  if (audienceUids.isEmpty) return const [];
  final posts = await feedPostsService.feedForAudience(audienceUids);
  // Posts ocultados pela moderação (staff) somem para o aluno em TODAS as abas.
  return posts.where((p) => !p.hiddenByStaff).toList();
});

/// Feed de posts da ACADEMIA do usuário atual (aba ACADEMIA).
final academyFeedPostsProvider = FutureProvider<List<FeedPost>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user?.academyId == null || user!.academyId!.isEmpty) return const [];
  final posts = await feedPostsService.feedForAcademy(user.academyId!);
  // Filtro de moderação client-side (barato: poucos docs ocultos, mesmo custo de
  // leitura). Evita índice composto extra + backfill de hiddenByStaff.
  return posts.where((p) => !p.hiddenByStaff).toList();
});

/// Feed de MODERAÇÃO da academia (visão do staff em SOCIAL): igual ao do aluno
/// PORÉM inclui os posts ocultados pelo staff (hiddenByStaff==true), para que o
/// admin/professor possa reexibi-los. Mantém o filtro do autor (hiddenByAuthor).
final staffAcademyFeedProvider = FutureProvider<List<FeedPost>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user?.academyId == null || user!.academyId!.isEmpty) return const [];
  return feedPostsService.feedForAcademy(user.academyId!);
});

/// Set de postIds que o usuário atual já curtiu — batch de 30 no máx.
/// Invalida automaticamente quando [feedPostsProvider] invalida.
final likedPostIdsProvider = FutureProvider<Set<String>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return const {};
  final posts = await ref.watch(feedPostsProvider.future);
  if (posts.isEmpty) return const {};
  return feedPostsService.didILike(
      user.id, posts.map((p) => p.postId).toList());
});

/// Set de postIds da aba ACADEMIA que o usuário atual já curtiu.
/// Invalida automaticamente quando [academyFeedPostsProvider] invalida.
final academyLikedPostIdsProvider = FutureProvider<Set<String>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return const {};
  final posts = await ref.watch(academyFeedPostsProvider.future);
  if (posts.isEmpty) return const {};
  return feedPostsService.didILike(
      user.id, posts.map((p) => p.postId).toList());
});

// =============================================================================

/// Um item do FEED DE ATIVIDADE dos amigos: a ação MAIS RECENTE de um amigo
/// (graduação, competição ou treino), com a data e um rótulo curto p/ exibição.
class FriendActivity {
  final FighterProfile friend;

  /// `'graduacao'` | `'competicao'` | `'treino'`.
  final String tipo;
  final DateTime date;
  final String label;

  const FriendActivity({
    required this.friend,
    required this.tipo,
    required this.date,
    required this.label,
  });
}

/// FEED DE ATIVIDADE dos amigos — deriva, por amigo, a ATIVIDADE MAIS RECENTE
/// entre {última graduação, última competição, último treino (lastTrainingDate)}
/// a partir da vitrine já materializada (sem leituras extras: usa o que o
/// [myFriendsProvider] hidratou). Retorna uma lista ORDENADA por data desc.
/// Amigos sem nenhum sinal datável são omitidos.
final friendsActivityProvider =
    FutureProvider<List<FriendActivity>>((ref) async {
  final friends = await ref.watch(myFriendsProvider.future);
  final out = <FriendActivity>[];
  for (final f in friends) {
    // As listas de vitrine vêm desc por data (mais recente primeiro), mas
    // computamos o max p/ robustez contra docs legados fora de ordem.
    DateTime? gradDate;
    for (final g in f.graduations) {
      if (gradDate == null || g.date.isAfter(gradDate)) gradDate = g.date;
    }
    DateTime? compDate;
    for (final c in f.competitions) {
      if (compDate == null || c.date.isAfter(compDate)) compDate = c.date;
    }
    final trainDate = f.lastTrainingDate;

    // Escolhe o sinal mais recente (treino desempata por último: empate raro).
    String? tipo;
    DateTime? best;
    String label = '';
    void consider(DateTime? d, String t, String l) {
      if (d == null) return;
      if (best == null || d.isAfter(best!)) {
        best = d;
        tipo = t;
        label = l;
      }
    }

    final lastComp = compDate == null
        ? null
        : f.competitions.firstWhere((c) => c.date == compDate,
            orElse: () => f.competitions.first);
    consider(gradDate, 'graduacao', 'GRADUOU');
    consider(
      compDate,
      'competicao',
      (lastComp?.name.trim().isNotEmpty ?? false)
          ? lastComp!.name.toUpperCase()
          : 'COMPETIU',
    );
    consider(trainDate, 'treino', 'TREINOU');

    if (best == null || tipo == null) continue;
    out.add(FriendActivity(
      friend: f,
      tipo: tipo!,
      date: best!,
      label: label,
    ));
  }
  out.sort((a, b) => b.date.compareTo(a.date));
  return out;
});

/// VISÃO DE VISITANTE — lê a vitrine materializada de [uid] em
/// `fighterProfiles/{uid}` (1 read). Nunca toca a attendance privada da outra
/// academia. Retorna null quando o lutador ainda não materializou a vitrine.
final fighterShowcaseProvider =
    FutureProvider.family<FighterProfile?, String>((ref, uid) async {
  if (uid.isEmpty) return null;
  return friendService.getProfile(uid);
});

// =============================================================================
// Parceiros: tipo comum + providers de exibição e ranking.
// =============================================================================

/// Representação LEVE de um parceiro para o strip da aba PARCEIROS.
/// Um lutador pode ser [isFriend] E [isClassmate] ao mesmo tempo.
class PartnerDisplay {
  /// Firebase Auth uid. Null para colegas sem conta vinculada (sem linkedUserId).
  final String? uid;

  /// Chave estável: linkedUserId quando disponível, senão o studentId da
  /// academia (id do doc em publicProfiles).
  final String studentId;

  final String name;
  final String belt;
  final int stripes;
  final String? photoUrl;
  final int totalTrainings;
  final bool isFriend;
  final bool isClassmate;

  const PartnerDisplay({
    this.uid,
    required this.studentId,
    required this.name,
    required this.belt,
    required this.stripes,
    this.photoUrl,
    required this.totalTrainings,
    required this.isFriend,
    required this.isClassmate,
  });
}

/// Strip de PARCEIROS: colegas de turma (publicProfiles das minhas turmas)
/// ∪ amigos por código (fighterProfiles via getFriends), dedup por uid,
/// ordenado por nome.
///
/// Colegas: lê `academies/{aid}/publicProfiles/{sid}` em batches de 10.
/// Amigos: usa [myFriendsProvider] (já hidratado).
/// Custo: ClassService.list() + batch de publicProfiles (já feito por
/// [myPartnersAudienceProvider] — se ambos ficarem vivos, o Riverpod pode
/// compartilhar ClassService.list() via cache).
final partnersDisplayProvider =
    FutureProvider<List<PartnerDisplay>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return const [];
  final student = await ref.watch(currentStudentProvider.future);
  final aid = user.academyId;
  final myStudentId = student?.id;
  final myUid = user.id;

  // Chave do map: uid quando disponível, senão studentId (garante dedup).
  final map = <String, PartnerDisplay>{};

  // ── 1. Amigos por código ─────────────────────────────────────────────────
  final friends = await ref.watch(myFriendsProvider.future);
  for (final f in friends) {
    if (f.uid == myUid) continue;
    map[f.uid] = PartnerDisplay(
      uid: f.uid,
      studentId: f.uid,
      name: f.name,
      belt: f.belt,
      stripes: f.stripes,
      photoUrl: f.photoUrl,
      totalTrainings: f.totalTrainings,
      isFriend: true,
      isClassmate: false,
    );
  }

  // ── 2. Colegas de turma ───────────────────────────────────────────────────
  if (aid != null && myStudentId != null) {
    try {
      final allClasses = await ClassService(aid).list();
      final peerIds = <String>{};
      for (final c in allClasses) {
        if (c.studentIds.contains(myStudentId)) {
          for (final sid in c.studentIds) {
            if (sid != myStudentId) peerIds.add(sid);
          }
        }
      }
      if (peerIds.isNotEmpty) {
        final pubRef = FirebaseFirestore.instance
            .collection('academies')
            .doc(aid)
            .collection('publicProfiles');
        final idList = peerIds.toList();
        for (var i = 0; i < idList.length; i += 10) {
          final end = (i + 10).clamp(0, idList.length);
          final q = await pubRef
              .where(FieldPath.documentId, whereIn: idList.sublist(i, end))
              .get();
          for (final d in q.docs) {
            final data = d.data();
            final linkedUid = data['linkedUserId'] as String?;
            if (linkedUid != null && linkedUid == myUid) continue;
            final sid = d.id;
            final nick = data['nickname'] as String?;
            final name = (nick != null && nick.trim().isNotEmpty)
                ? nick.trim()
                : ((data['fullName'] as String?)?.trim().isNotEmpty == true
                    ? (data['fullName'] as String).trim()
                    : 'Atleta');
            final belt = (data['currentBelt'] as String?) ?? 'white';
            final stripes =
                (data['currentStripes'] as num?)?.toInt() ?? 0;
            final photoUrl = data['photoUrl'] as String?;
            final total =
                ((data['initialAttendanceCount'] as num?)?.toInt() ?? 0) +
                    ((data['attendanceCount'] as num?)?.toInt() ?? 0);

            // Chave de dedup: uid vinculado quando disponível, senão studentId.
            final key = (linkedUid != null && linkedUid.isNotEmpty)
                ? linkedUid
                : sid;

            if (map.containsKey(key)) {
              // Já existe como amigo — promove isClassmate para true.
              final ex = map[key]!;
              map[key] = PartnerDisplay(
                uid: ex.uid,
                studentId: ex.studentId,
                name: ex.name,
                belt: ex.belt,
                stripes: ex.stripes,
                photoUrl: ex.photoUrl,
                totalTrainings: ex.totalTrainings,
                isFriend: ex.isFriend,
                isClassmate: true,
              );
            } else {
              map[key] = PartnerDisplay(
                uid: (linkedUid != null && linkedUid.isNotEmpty)
                    ? linkedUid
                    : null,
                studentId: sid,
                name: name,
                belt: belt,
                stripes: stripes,
                photoUrl: (photoUrl != null && photoUrl.isNotEmpty)
                    ? photoUrl
                    : null,
                totalTrainings: total,
                isFriend: false,
                isClassmate: true,
              );
            }
          }
        }
      }
    } catch (_) {
      // Fallback seguro: mantém só os amigos se a leitura de turmas falhar.
    }
  }

  final list = map.values.toList();
  list.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
});

// =============================================================================

/// Uma entrada no ranking de parceiros.
class PartnerRankEntry {
  final int rank;

  /// uid do lutador (null = colega sem conta vinculada).
  final String? uid;

  /// ID de navegação pro perfil: studentId real do colega (→ perfil intra-
  /// academia via publicProfiles) OU uid do amigo cross-academy (→ vitrine do
  /// espelho). Navegar por AQUI (não pelo uid) evita "Perfil não disponível".
  final String studentId;
  final String name;
  final String belt;
  final int stripes;
  final String? photoUrl;

  /// Total de treinos — métrica canônica disponível nos dois lados:
  ///   - amigo  → [FighterProfile.totalTrainings] (espelho em fighterProfiles)
  ///   - colega → publicProfiles.initialAttendanceCount + .attendanceCount
  ///   - eu     → student.totalAttendanceCount
  final int totalTrainings;

  /// true para a entrada do próprio usuário.
  final bool isMe;

  const PartnerRankEntry({
    required this.rank,
    this.uid,
    required this.studentId,
    required this.name,
    required this.belt,
    required this.stripes,
    this.photoUrl,
    required this.totalTrainings,
    required this.isMe,
  });
}

class _RawRankEntry {
  final String? uid;
  final String studentId;
  final String name;
  final String belt;
  final int stripes;
  final String? photoUrl;
  final int totalTrainings;
  final bool isMe;
  const _RawRankEntry({
    this.uid,
    required this.studentId,
    required this.name,
    required this.belt,
    required this.stripes,
    this.photoUrl,
    required this.totalTrainings,
    required this.isMe,
  });
}

/// RANKING DOS PARCEIROS, ciente de período.
///
/// - [period] = `null`  → **GERAL**: comportamento original — ordena por
///   `totalTrainings` histórico de todos os parceiros + eu. Inclui amigos
///   cross-academy.
/// - [period] = [RankingPeriod.month] / [RankingPeriod.week] → **MENSAL /
///   SEMANAL**: conta presenças no período via CF `getAttendanceRanking`,
///   filtrado aos colegas de turma da MINHA academia + eu. Amigos cross-
///   academy são excluídos neste modo (não têm studentId na minha academia).
///
/// `totalTrainings` em [PartnerRankEntry] é reutilizado semanticamente como
/// "presenças no período" quando [period] não é nulo.
///
/// API para a UI:
///   ```dart
///   final rankAsync = ref.watch(partnersRankingProvider(null));           // GERAL
///   final rankAsync = ref.watch(partnersRankingProvider(RankingPeriod.month)); // MÊS
///   final rankAsync = ref.watch(partnersRankingProvider(RankingPeriod.week));  // SEMANA
///   rankAsync.when(
///     data: (entries) { /* entries[i].rank, .name, .belt, .totalTrainings, .isMe */ },
///     ...
///   );
///   ```
final partnersRankingProvider =
    FutureProvider.family<List<PartnerRankEntry>, RankingPeriod?>(
        (ref, period) async {
  final user = await ref.watch(currentUserProvider.future);
  if (user == null) return const [];
  final student = await ref.watch(currentStudentProvider.future);
  final partners = await ref.watch(partnersDisplayProvider.future);

  // ── GERAL: comportamento original (sem chamada à CF de ranking) ────────────
  if (period == null) {
    final raw = <_RawRankEntry>[];
    if (student != null) {
      final myName = (student.nickname != null && student.nickname!.isNotEmpty)
          ? student.nickname!
          : student.fullName;
      raw.add(_RawRankEntry(
        uid: user.id,
        studentId: student.id,
        name: myName,
        belt: student.currentBelt,
        stripes: student.currentStripes,
        photoUrl: student.photoUrl,
        totalTrainings: student.totalAttendanceCount,
        isMe: true,
      ));
    }
    for (final p in partners) {
      raw.add(_RawRankEntry(
        uid: p.uid,
        studentId: p.studentId,
        name: p.name,
        belt: p.belt,
        stripes: p.stripes,
        photoUrl: p.photoUrl,
        totalTrainings: p.totalTrainings,
        isMe: false,
      ));
    }
    raw.sort((a, b) {
      final c = b.totalTrainings.compareTo(a.totalTrainings);
      return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return [
      for (var i = 0; i < raw.length; i++)
        PartnerRankEntry(
          rank: i + 1,
          uid: raw[i].uid,
          studentId: raw[i].studentId,
          name: raw[i].name,
          belt: raw[i].belt,
          stripes: raw[i].stripes,
          photoUrl: raw[i].photoUrl,
          totalTrainings: raw[i].totalTrainings,
          isMe: raw[i].isMe,
        ),
    ];
  }

  // ── MENSAL / SEMANAL: presença no período via CF ───────────────────────────
  final aid = user.academyId;
  if (aid == null || aid.isEmpty || student == null) return const [];

  // Lookup de belt/stripes/photo por studentId — somente colegas de turma.
  // Amigos cross-academy (studentId == uid, fora do ranking da academia) ficam
  // de fora: degradação aceitável documentada no contrato do provider.
  final classmateMap = <String, PartnerDisplay>{};
  for (final p in partners) {
    if (p.isClassmate) classmateMap[p.studentId] = p;
  }
  final targetIds = {...classmateMap.keys, student.id};

  // Ranking completo da academia no período (CF getAttendanceRanking).
  // Sem filtro de turma (classIds: null) = toda a academia.
  final academyRanking = await RankingService(aid).getRanking(
    period: period,
    classIds: null,
    limit: 1000,
  );

  // Filtra às entradas de interesse (parceiros + eu).
  final filtered =
      academyRanking.where((e) => targetIds.contains(e.studentId)).toList();

  final myName = (student.nickname != null && student.nickname!.isNotEmpty)
      ? student.nickname!
      : student.fullName;

  final raw = <_RawRankEntry>[];
  var myInRanking = false;

  for (final e in filtered) {
    final isMe = e.studentId == student.id;
    if (isMe) {
      myInRanking = true;
      raw.add(_RawRankEntry(
        uid: user.id,
        studentId: student.id,
        name: myName,
        belt: student.currentBelt,
        stripes: student.currentStripes,
        photoUrl: student.photoUrl,
        totalTrainings: e.attendanceCount,
        isMe: true,
      ));
    } else {
      final p = classmateMap[e.studentId];
      if (p == null) continue;
      raw.add(_RawRankEntry(
        uid: p.uid,
        studentId: e.studentId,
        name: p.name,
        belt: p.belt,
        stripes: p.stripes,
        photoUrl: p.photoUrl ?? e.photoUrl,
        totalTrainings: e.attendanceCount,
        isMe: false,
      ));
    }
  }

  // Inclui "eu" com 0 presenças se ausente do ranking do período.
  if (!myInRanking) {
    raw.add(_RawRankEntry(
      uid: user.id,
      studentId: student.id,
      name: myName,
      belt: student.currentBelt,
      stripes: student.currentStripes,
      photoUrl: student.photoUrl,
      totalTrainings: 0,
      isMe: true,
    ));
  }

  raw.sort((a, b) {
    final c = b.totalTrainings.compareTo(a.totalTrainings);
    return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return [
    for (var i = 0; i < raw.length; i++)
      PartnerRankEntry(
        rank: i + 1,
        uid: raw[i].uid,
        studentId: raw[i].studentId,
        name: raw[i].name,
        belt: raw[i].belt,
        stripes: raw[i].stripes,
        photoUrl: raw[i].photoUrl,
        totalTrainings: raw[i].totalTrainings,
        isMe: raw[i].isMe,
      ),
  ];
});
