import 'package:cloud_firestore/cloud_firestore.dart';

// ════════════════════════════════════════════════════════════════════════════
// Feed post types
// ════════════════════════════════════════════════════════════════════════════

enum FeedPostType {
  graduacao,
  competicao,
  streakMilestone,
  sparringRecord,
  weeklyVolume,
  matMilestone;

  /// Wire value stored in Firestore `type` field.
  String get firestoreValue => switch (this) {
        FeedPostType.graduacao => 'graduacao',
        FeedPostType.competicao => 'competicao',
        FeedPostType.streakMilestone => 'streak_milestone',
        FeedPostType.sparringRecord => 'sparring_record',
        FeedPostType.weeklyVolume => 'weekly_volume',
        FeedPostType.matMilestone => 'mat_milestone',
      };

  static FeedPostType fromString(String s) => switch (s) {
        'graduacao' => FeedPostType.graduacao,
        'competicao' => FeedPostType.competicao,
        'streak_milestone' => FeedPostType.streakMilestone,
        'sparring_record' => FeedPostType.sparringRecord,
        'weekly_volume' => FeedPostType.weeklyVolume,
        'mat_milestone' => FeedPostType.matMilestone,
        _ => FeedPostType.weeklyVolume,
      };
}

// ════════════════════════════════════════════════════════════════════════════
// Typed payloads — one sealed subclass per FeedPostType
// ════════════════════════════════════════════════════════════════════════════

sealed class FeedPostPayload {
  const FeedPostPayload();

  Map<String, dynamic> toMap();

  /// Dispatch from Firestore `payload` map, keyed by [type].
  static FeedPostPayload fromMap(FeedPostType type, Map<String, dynamic> m) =>
      switch (type) {
        FeedPostType.graduacao => GraduacaoPayload.fromMap(m),
        FeedPostType.competicao => CompeticaoPayload.fromMap(m),
        FeedPostType.streakMilestone => StreakMilestonePayload.fromMap(m),
        FeedPostType.sparringRecord => SparringRecordPayload.fromMap(m),
        FeedPostType.weeklyVolume => WeeklyVolumePayload.fromMap(m),
        FeedPostType.matMilestone => MatMilestonePayload.fromMap(m),
      };
}

/// Payload for `graduacao` — "FAIXA ROXA · 187 AULAS · 14 MESES"
final class GraduacaoPayload extends FeedPostPayload {
  final String belt;
  final int stripes;
  final bool isBeltChange;
  final int trainingsToReach;
  final int monthsToReach;

  const GraduacaoPayload({
    required this.belt,
    required this.stripes,
    required this.isBeltChange,
    required this.trainingsToReach,
    required this.monthsToReach,
  });

  @override
  Map<String, dynamic> toMap() => {
        'belt': belt,
        'stripes': stripes,
        'isBeltChange': isBeltChange,
        'trainingsToReach': trainingsToReach,
        'monthsToReach': monthsToReach,
      };

  factory GraduacaoPayload.fromMap(Map<String, dynamic> m) => GraduacaoPayload(
        belt: (m['belt'] ?? 'white').toString(),
        stripes: (m['stripes'] as num?)?.toInt() ?? 0,
        isBeltChange: m['isBeltChange'] == true,
        trainingsToReach: (m['trainingsToReach'] as num?)?.toInt() ?? 0,
        monthsToReach: (m['monthsToReach'] as num?)?.toInt() ?? 0,
      );
}

/// Payload for `competicao` — "OURO NO OPEN SP"
final class CompeticaoPayload extends FeedPostPayload {
  final String name;

  /// 'gold' | 'silver' | 'bronze' | 'participant'
  final String position;

  const CompeticaoPayload({required this.name, required this.position});

  @override
  Map<String, dynamic> toMap() => {'name': name, 'position': position};

  factory CompeticaoPayload.fromMap(Map<String, dynamic> m) => CompeticaoPayload(
        name: (m['name'] ?? '').toString(),
        position: (m['position'] ?? 'participant').toString(),
      );
}

/// Payload for `streak_milestone` — "8 SEMANAS SEGUIDAS"
final class StreakMilestonePayload extends FeedPostPayload {
  final int weeks;

  const StreakMilestonePayload({required this.weeks});

  @override
  Map<String, dynamic> toMap() => {'weeks': weeks};

  factory StreakMilestonePayload.fromMap(Map<String, dynamic> m) =>
      StreakMilestonePayload(weeks: (m['weeks'] as num?)?.toInt() ?? 0);
}

/// Payload for `sparring_record` — "MELHOR NOITE: 9 ROLAS"
final class SparringRecordPayload extends FeedPostPayload {
  final int recorde;

  const SparringRecordPayload({required this.recorde});

  @override
  Map<String, dynamic> toMap() => {'recorde': recorde};

  factory SparringRecordPayload.fromMap(Map<String, dynamic> m) =>
      SparringRecordPayload(recorde: (m['recorde'] as num?)?.toInt() ?? 0);
}

/// Payload for `weekly_volume` — "3 TREINOS · 14 ROLAS ESSA SEMANA"
final class WeeklyVolumePayload extends FeedPostPayload {
  final int trainings;
  final int rolas;

  const WeeklyVolumePayload({required this.trainings, required this.rolas});

  @override
  Map<String, dynamic> toMap() => {'trainings': trainings, 'rolas': rolas};

  factory WeeklyVolumePayload.fromMap(Map<String, dynamic> m) =>
      WeeklyVolumePayload(
        trainings: (m['trainings'] as num?)?.toInt() ?? 0,
        rolas: (m['rolas'] as num?)?.toInt() ?? 0,
      );
}

/// Payload for `mat_milestone` — "250 AULAS" / "1 ANO DE TATAME"
/// [marco] = '100'|'250'|'500'|'1000'|'1yr'|'2yr'|'3yr'|'5yr'
final class MatMilestonePayload extends FeedPostPayload {
  final String marco;

  const MatMilestonePayload({required this.marco});

  @override
  Map<String, dynamic> toMap() => {'marco': marco};

  factory MatMilestonePayload.fromMap(Map<String, dynamic> m) =>
      MatMilestonePayload(marco: (m['marco'] ?? '').toString());
}

// ════════════════════════════════════════════════════════════════════════════
// Anti-spam constants (versioned — changing these creates new dedup keys)
// ════════════════════════════════════════════════════════════════════════════

/// Streak week-counts that trigger a `streak_milestone` post. A post fires only
/// when [currentWeeks] CROSSES one of these thresholds (never on maintain).
const streakMilestones = [4, 8, 12, 26, 52];

/// Attendance totals that trigger a `mat_milestone` post.
const matMilestones = [100, 250, 500, 1000];

/// Years of mat time that trigger a `mat_milestone` post.
const matAnniversaries = [1, 2, 3, 5];

// ════════════════════════════════════════════════════════════════════════════
// FeedPost — top-level materialised post in `feedPosts/{postId}`
// ════════════════════════════════════════════════════════════════════════════

class FeedPost {
  /// == doc-id (deterministic, see static id helpers below).
  final String postId;
  final String authorUid;
  final FeedPostType type;
  final FeedPostPayload payload;

  /// Real date of the event (graduation date, end-of-ISO-week, etc.).
  /// Orders the feed — a retroactive graduation does not disrupt chronology.
  final DateTime occurredAt;

  /// Server timestamp of the Firestore write. Null before first materialisation.
  final DateTime? createdAt;

  /// Academy of the author at emit time — used by the ACADEMIA feed query.
  final String? academyId;

  /// Author-controlled hide flag. Default false. ALWAYS written on create so
  /// server-side filter `hiddenByAuthor == false` is reliable on every doc.
  final bool hiddenByAuthor;
  final DateTime? hiddenAt;

  /// Staff moderation flag (admin/professor da academia do post). Default false.
  /// Diferente de [hiddenByAuthor]: o staff oculta para TODA a academia. O feed
  /// do aluno filtra `hiddenByStaff == true` client-side (poucos docs, mesmo
  /// custo de leitura); o feed de moderação do staff mostra TODOS (para reexibir).
  final bool hiddenByStaff;
  final DateTime? hiddenByStaffAt;

  /// Texto de exibição sobrescrito pelo staff (moderação de conteúdo). Quando
  /// presente, substitui a [headline] computada em TODAS as visões. null = usa a
  /// headline determinística do marco.
  final String? staffHeadline;

  /// Denorm like counter. Mantido pela CF `onFeedLikeWrite` (feed_like_counter.js).
  final int likeCount;

  // Denorm author identity — 0 reads on render (same pattern as kudos/trainingPairs).
  final String authorName;
  final String authorBelt;
  final int authorStripes;
  final String? authorPhotoUrl;

  /// Redundant copy of postId — self-documents idempotency contract.
  String get dedupeKey => postId;

  /// Headline efetiva exibida: a versão editada pelo staff, se houver; senão a
  /// [headline] determinística do marco. Usar SEMPRE nas visões de feed.
  String get displayHeadline =>
      (staffHeadline != null && staffHeadline!.trim().isNotEmpty)
          ? staffHeadline!
          : headline;

  /// Linha de headline UPPER-CASE para exibição fighter-style.
  String get headline {
    switch (type) {
      case FeedPostType.graduacao:
        final p = payload as GraduacaoPayload;
        final belt = p.belt.toUpperCase();
        final parts = <String>[];
        if (p.isBeltChange) {
          parts.add('FAIXA $belt');
        } else {
          parts.add('${p.stripes}º GRAU');
        }
        if (p.trainingsToReach > 0) parts.add('${p.trainingsToReach} AULAS');
        if (p.monthsToReach > 0) parts.add('${p.monthsToReach} MESES');
        return parts.join(' · ');

      case FeedPostType.competicao:
        final p = payload as CompeticaoPayload;
        final name = p.name.toUpperCase();
        final medal = switch (p.position) {
          'gold' => 'OURO',
          'silver' => 'PRATA',
          'bronze' => 'BRONZE',
          _ => null,
        };
        if (name.isEmpty) return 'COMPETIU';
        return medal == null ? name : '$medal · $name';

      case FeedPostType.streakMilestone:
        final p = payload as StreakMilestonePayload;
        return '${p.weeks} SEMANAS SEGUIDAS';

      case FeedPostType.sparringRecord:
        final p = payload as SparringRecordPayload;
        return 'MELHOR NOITE: ${p.recorde} ROLAS';

      case FeedPostType.weeklyVolume:
        final p = payload as WeeklyVolumePayload;
        final parts = <String>[];
        if (p.trainings > 0) {
          parts.add('${p.trainings} TREINO${p.trainings == 1 ? '' : 'S'} ESSA SEMANA');
        }
        if (p.rolas > 0) parts.add('${p.rolas} ROLA${p.rolas == 1 ? '' : 'S'}');
        return parts.isEmpty ? 'TREINOU ESSA SEMANA' : parts.join(' · ');

      case FeedPostType.matMilestone:
        final p = payload as MatMilestonePayload;
        final marco = p.marco;
        if (marco.endsWith('yr')) {
          final yr = marco.replaceFirst('yr', '');
          return '$yr ANO${yr == '1' ? '' : 'S'} DE TATAME';
        }
        return '$marco AULAS';
    }
  }

  const FeedPost({
    required this.postId,
    required this.authorUid,
    required this.type,
    required this.payload,
    required this.occurredAt,
    this.createdAt,
    this.academyId,
    this.hiddenByAuthor = false,
    this.hiddenAt,
    this.hiddenByStaff = false,
    this.hiddenByStaffAt,
    this.staffHeadline,
    this.likeCount = 0,
    required this.authorName,
    required this.authorBelt,
    required this.authorStripes,
    this.authorPhotoUrl,
  });

  // ── Deterministic post-ID helpers ─────────────────────────────────────────

  static String _dateStr(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  /// `grad_{uid}_{yyyymmdd}_{belt}{stripes}` — 1 post per graduation event.
  /// Mirrors the `sport|belt|stripes` key of showcase_builder.dart:181.
  static String gradId(String uid, DateTime date, String belt, int stripes) =>
      'grad_${uid}_${_dateStr(date)}_$belt$stripes';

  /// `comp_{uid}_{yyyymmdd}_{slug}` — slug reuses normalization of
  /// showcase_builder.dart:244 (trim + lower + non-alnum → underscore).
  static String compId(String uid, DateTime date, String name) {
    final slug =
        name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return 'comp_${uid}_${_dateStr(date)}_$slug';
  }

  /// `streak_{uid}_{weeks}` — weeks ∈ [streakMilestones]; fires once per value.
  static String streakId(String uid, int weeks) => 'streak_${uid}_$weeks';

  /// `spar_pr_{uid}_{recorde}` — fires only when the record is beaten.
  static String sparPrId(String uid, int recorde) => 'spar_pr_${uid}_$recorde';

  /// `vol_{uid}_{isoYear}W{ww}` — 1 post per author per CLOSED ISO week.
  /// [mondayUtc] must be the Monday 00:00 UTC of the closed week (use
  /// [mondayUtcOf] to derive it). ISO week-year used — handles Dec/Jan edge.
  static String volId(String uid, DateTime mondayUtc) {
    final thursday = mondayUtc.add(const Duration(days: 3));
    final jan1 = DateTime.utc(thursday.year, 1, 1);
    final ordinal = thursday.difference(jan1).inDays + 1;
    final weekNum = (ordinal + 6) ~/ 7;
    return 'vol_${uid}_${thursday.year}W${weekNum.toString().padLeft(2, '0')}';
  }

  /// `mat_{uid}_{marco}` — marco = '100'|'250'|'500'|'1000'|'1yr'|'2yr'|'3yr'|'5yr'.
  static String matId(String uid, String marco) => 'mat_${uid}_$marco';

  /// Monday (UTC 00:00) of the ISO week containing [d].
  /// Mirrors `_mondayUtc` in weekly_streak.dart — kept public here so
  /// callers computing [volId] don't depend on that private function.
  static DateTime mondayUtcOf(DateTime d) {
    final day = DateTime.utc(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  /// Converts to a Firestore-ready map.
  /// `createdAt` is always a server timestamp (resolved by Firestore on write).
  /// `hiddenByAuthor` is always explicit so the server-side filter is reliable.
  Map<String, dynamic> toMap() => {
        'postId': postId,
        'authorUid': authorUid,
        'type': type.firestoreValue,
        'payload': payload.toMap(),
        'occurredAt': Timestamp.fromDate(occurredAt),
        'createdAt': FieldValue.serverTimestamp(),
        'academyId': academyId, // explicit null is fine — excluded by != queries
        'hiddenByAuthor': hiddenByAuthor,
        if (hiddenAt != null) 'hiddenAt': Timestamp.fromDate(hiddenAt!),
        'hiddenByStaff': hiddenByStaff,
        if (hiddenByStaffAt != null)
          'hiddenByStaffAt': Timestamp.fromDate(hiddenByStaffAt!),
        if (staffHeadline != null) 'staffHeadline': staffHeadline,
        'likeCount': likeCount,
        'authorName': authorName,
        'authorBelt': authorBelt,
        'authorStripes': authorStripes,
        if (authorPhotoUrl != null) 'authorPhotoUrl': authorPhotoUrl,
        'dedupeKey': postId,
      };

  factory FeedPost.fromMap(Map<String, dynamic> d) {
    DateTime? parseTs(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    final type = FeedPostType.fromString((d['type'] ?? '').toString());
    final rawPayload = d['payload'];
    final payloadMap = rawPayload is Map
        ? Map<String, dynamic>.from(rawPayload)
        : const <String, dynamic>{};

    return FeedPost(
      postId: (d['postId'] ?? d['dedupeKey'] ?? '').toString(),
      authorUid: (d['authorUid'] ?? '').toString(),
      type: type,
      payload: FeedPostPayload.fromMap(type, payloadMap),
      occurredAt: parseTs(d['occurredAt']) ?? DateTime.now(),
      createdAt: parseTs(d['createdAt']),
      academyId: d['academyId'] as String?,
      hiddenByAuthor: d['hiddenByAuthor'] == true,
      hiddenAt: parseTs(d['hiddenAt']),
      hiddenByStaff: d['hiddenByStaff'] == true,
      hiddenByStaffAt: parseTs(d['hiddenByStaffAt']),
      staffHeadline: (d['staffHeadline'] as String?)?.trim().isNotEmpty == true
          ? (d['staffHeadline'] as String).trim()
          : null,
      likeCount: (d['likeCount'] as num?)?.toInt() ?? 0,
      authorName: (d['authorName'] ?? 'Lutador').toString(),
      authorBelt: (d['authorBelt'] ?? 'white').toString(),
      authorStripes: (d['authorStripes'] as num?)?.toInt() ?? 0,
      authorPhotoUrl: d['authorPhotoUrl'] as String?,
    );
  }
}
