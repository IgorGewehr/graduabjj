import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/sports.dart';
import '../../models/fighter_profile.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friend_providers.dart';
import '../../providers/portal_providers.dart';
import '../../providers/sparring_providers.dart';
import '../../providers/student_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/sparring_engine.dart';
import '../../services/self_records_service.dart';
import '../../services/training_log_service.dart';
import '../../widgets/polish/polish.dart';

/// TREINEI — A JORNADA DA EVOLUÇÃO DO LUTADOR (= o perfil público dele).
///
/// Modelo (decidido com o dono): o "Treinei" deixa de ser um diário dia-a-dia e
/// vira a JORNADA da caminhada — a mesma coisa que o visitante vê quando abre o
/// meu perfil. Três unidades de BJJ (não corrida):
///   1. STREAK   — consistência (herói: dias seguidos + recorde).
///   2. GRADUAÇÕES — cada faixa/grau, QUANDO, e o esforço por trás
///      ("NN TREINOS · MM MESES ATÉ AQUI"). Verificadas (academia, = TETO) são
///      read-only; auto-declaradas (`selfGraduations`) o lutador add/edita/exclui.
///   3. COMPETIÇÕES — cartel + a "estrada" entre uma comp e a próxima.
///      Da academia (verificadas) + externas auto-declaradas (`selfCompetitions`).
///
/// A jornada é computada e MATERIALIZADA pelo dono em `fighterProfiles/{uid}`
/// (provider [myShowcaseProvider], write condicional por hash). O visitante lê
/// o mesmo blob em 1 read — nunca a attendance privada da academia. O auto-
/// declarado NUNCA toca `beltProgressions` (= TETO) — vive em coleções `self*`.
///
/// O SELF-LOG ("TREINEI HOJE") — treino sem professor (open mat, drill em casa)
/// — continua existindo, mas REBAIXADO para a aba HISTÓRICO. Ele NÃO alimenta os
/// números da jornada (jornada = só `attendance` verificada). Anti-fraude já
/// garantido no backend: graduação-por-presença lê `academies/{id}/attendance`,
/// nunca `training_logs`. A UI só sinaliza isso (selo AUTO + microcopy seca).
///
/// Fontes do HISTÓRICO:
///  - VERIFICADO: `AttendanceService(academyId).getByStudentPaginated(uid,30)`
///    (fallback `getByStudent`) — date-desc, bounded.
///  - AUTO (self): `users/{uid}/training_logs` orderBy(date desc).limit(60).
/// Snapshot dos auto-declarados do dono (graduações + competições) COM os ids,
/// para a Jornada própria poder editar/excluir o registro certo. O
/// [myShowcaseProvider] mescla verified+auto mas perde o id; este provider
/// carrega os docs `self*` crus (mesmas leituras já feitas no showcase) só para
/// resolver a edição. Invalidado após qualquer mutação.
class _SelfRecords {
  final String academyId;
  final String studentId;
  final List<SelfGraduation> grads;
  final List<SelfCompetition> comps;
  const _SelfRecords({
    required this.academyId,
    required this.studentId,
    required this.grads,
    required this.comps,
  });
}

final _selfRecordsProvider = FutureProvider.autoDispose<_SelfRecords?>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  final student = await ref.watch(currentStudentProvider.future);
  final academyId = user?.academyId;
  if (academyId == null || academyId.isEmpty || student == null) return null;
  final svc = SelfRecordsService(academyId);
  final grads = await svc.listGraduations(student.id);
  final comps = await svc.listCompetitions(student.id);
  return _SelfRecords(
    academyId: academyId,
    studentId: student.id,
    grads: grads,
    comps: comps,
  );
});

class DiarioScreen extends ConsumerStatefulWidget {
  const DiarioScreen({super.key});

  @override
  ConsumerState<DiarioScreen> createState() => _DiarioScreenState();
}

/// Procedência de uma linha do histórico.
enum TrainSource { verified, self }

/// Linha normalizada do histórico unificado (uma fonte por linha — NÃO
/// deduplicar: o lutador pode ter aula de manhã + open mat à noite).
class TrainEntry {
  final TrainSource source;
  final DateTime date; // dateOnly p/ ordenar/agrupar
  final String title; // className (verified) ou modalidade/"ROLA" (self)
  final String? sport; // 'bjj','muaythai'...
  final String? subtitle; // verified: verifiedByName
  final DocumentReference<Map<String, dynamic>>? selfRef; // só self → editar
  final int sparringCount; // só self — nº de rolas/rounds do dia (coração)
  final String? intensity; // só self — 'leve'|'media'|'dura'
  final List<String> techniques; // só self
  final List<String> partners; // só self
  final String? feeling; // só self
  final String? verifiedId; // só verified — attendance id (p/ anexar rolas)
  final String? note; // só self — texto livre "FOCO DO DIA" (≤140 chars)

  const TrainEntry({
    required this.source,
    required this.date,
    required this.title,
    this.sport,
    this.subtitle,
    this.selfRef,
    this.sparringCount = 0,
    this.intensity,
    this.techniques = const [],
    this.partners = const [],
    this.feeling,
    this.verifiedId,
    this.note,
  });

  bool get isSelf => source == TrainSource.self;
}

/// Fases da tela: principal (idle), logger count-first (count) e detalhe/edição
/// pós-save (reward).
enum _Phase { idle, count, reward }

/// Ação escolhida na folha de um marco AUTO-declarado (graduação/competição).
enum _RecordAction { editDate, delete }

class _DiarioScreenState extends ConsumerState<DiarioScreen> {
  // ── Anti-slop design tokens (paleta da tribo, escopo local) ───────────────
  // Bone canvas + tinta + UM acento sangue. As cores de FAIXA só aparecem no
  // marco real (faixa/grau) — isto é fightwear, não dashboard fitness.
  static const Color _ink = Color(0xFF0A0A0A); // preto industrial
  static const Color _bone = Color(0xFFFAFAF7); // osso (canvas claro)
  static const Color _blood = Color(0xFFB91C1C); // vermelho-sangue (único acento)
  static const Color _smoke = Color(0xFF6B6B66); // texto secundário sobre osso
  static const Color _ash = Color(0xFF9A9A93); // texto secundário sobre tinta
  static const Color _hair = Color(0x14000000); // hairline sobre osso

  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  /// Default do stepper — "a galera faz ~5 sparrings/treino" (decisão do dono).
  static const int _kDefaultSparring = 5;
  static const int _kMaxSparring = 50;

  /// Atalhos rápidos de contagem (1 toque = seta o número).
  static const List<int> _kQuickCounts = [3, 5, 8, 10, 15];

  /// Visão ativa: 0 = JORNADA (a estrela), 1 = HISTÓRICO (feed + self-log).
  int _view = 0;

  // ── Estado de carregamento do feed do HISTÓRICO ───────────────────────────
  bool _loadingFeed = true;
  Object? _feedError;

  /// Academia resolvida no load (para microcopy do HISTÓRICO).
  String? _academyId;

  /// Histórico unificado (verificado + self), date-desc.
  List<TrainEntry> _feed = const [];

  /// true quando a fase reward está EDITANDO um self-log existente.
  bool _editing = false;

  // ── Estado de gravação ────────────────────────────────────────────────────
  _Phase _phase = _Phase.idle;
  bool _saving = false;

  // ── Estado do logger count-first + detalhes opcionais do self-log ─────────
  DocumentReference<Map<String, dynamic>>? _logRef;
  int _sparringCount = _kDefaultSparring; // coração — nº de rolas/rounds do dia
  int _rewardCount = 0; // nº que acabou de entrar (mostrado na recompensa)
  int? _rewardDelta; // +N vs. último treino do mesmo esporte (SÓ se positivo)
  DateTime _logDate = DateUtils.dateOnly(DateTime.now()); // dia em edição
  String? _linkedAttendanceId; // aula verificada à qual o count foi anexado
  SportId? _sport;
  String? _intensity; // 'leve'|'media'|'dura'
  String? _feeling;
  final List<String> _techniques = [];
  final List<String> _partners = [];

  final TextEditingController _techCtrl = TextEditingController();
  final TextEditingController _partnerCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  /// Nota livre "FOCO DO DIA" digitada na fase reward (≤140 chars).
  String? _note;

  // Sensações — tom da tribo, sem exclamação fitness.
  static const Map<String, String> _feelings = {
    'leve': 'LEVE',
    'na_medida': 'NA MEDIDA',
    'pesado': 'PESADO',
    'quebrado': 'QUEBRADO',
  };

  // Intensidade — metadado leve opcional (nunca bloqueia o save).
  static const Map<String, String> _intensities = {
    'leve': 'LEVE',
    'media': 'NA MEDIDA',
    'dura': 'DURA',
  };

  @override
  void initState() {
    super.initState();
    _loadFeed();
  }

  @override
  void dispose() {
    _techCtrl.dispose();
    _partnerCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String? get _uid => ref.read(currentUserProvider).valueOrNull?.id;

  CollectionReference<Map<String, dynamic>>? _logsCol(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('training_logs');

  // ── Carrega o feed unificado do HISTÓRICO (2 leituras bounded) ────────────
  Future<void> _loadFeed() async {
    final user = ref.read(currentUserProvider).valueOrNull;
    final uid = user?.id;
    if (uid == null) {
      setState(() {
        _loadingFeed = false;
        _feedError = 'no-user';
      });
      return;
    }
    final academyId = user?.academyId;
    // A attendance é indexada pelo ID da FICHA do aluno (student.id), NÃO pelo
    // uid. Passar o uid devolvia query vazia + permission-denied (uid != o
    // studentId que a rule isOwnStudentRecord espera).
    final student = await ref.read(currentStudentProvider.future);
    final studentId = student?.id;
    setState(() {
      _loadingFeed = true;
      _feedError = null;
      _academyId = academyId;
    });

    try {
      // Dispara as duas leituras ANTES de aguardar → executam em paralelo.
      final selfFut =
          _logsCol(uid)!.orderBy('date', descending: true).limit(60).get();

      Future<List<Attendance>> verifiedFut;
      if (academyId != null && academyId.isNotEmpty && studentId != null) {
        final svc = AttendanceService(academyId);
        verifiedFut = _loadVerified(svc, studentId);
      } else {
        verifiedFut = Future.value(const <Attendance>[]);
      }

      final selfSnap = await selfFut;
      final verified = await verifiedFut;

      final entries = <TrainEntry>[];

      // Presenças verificadas — entram sozinhas, sem input do lutador.
      for (final a in verified) {
        // Nunca mostrar o placeholder genérico "Administrador" — só nome real
        // do professor/admin; senão, sem nome.
        final vName = a.verifiedByName.trim();
        final showName =
            vName.isNotEmpty && vName.toLowerCase() != 'administrador';
        entries.add(TrainEntry(
          source: TrainSource.verified,
          date: DateUtils.dateOnly(a.date),
          title: a.className.trim().isNotEmpty ? a.className : 'AULA',
          sport: a.sport,
          subtitle: showName ? vName : null,
          verifiedId: a.id,
        ));
      }

      // Self-logs — treino sem professor.
      for (final d in selfSnap.docs) {
        final data = d.data();
        final ts = data['date'];
        final date = ts is Timestamp ? ts.toDate() : DateTime.now();
        entries.add(_selfEntry(
          ref: d.reference,
          date: DateUtils.dateOnly(date),
          sport: data['sport'] as String?,
          sparringCount: (data['sparringCount'] as num?)?.toInt() ?? 0,
          intensity: data['intensity'] as String?,
          feeling: data['feeling'] as String?,
          techniques: List<String>.from(data['techniques'] ?? const []),
          partners: List<String>.from(data['partners'] ?? const []),
          note: data['note'] as String?,
        ));
      }

      _sortFeed(entries);

      if (!mounted) return;
      setState(() {
        _feed = entries;
        _loadingFeed = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _feedError = e;
        _loadingFeed = false;
      });
    }
  }

  /// Versão paginada (bounded) com fallback p/ índice ausente — mesmo padrão
  /// de `studentAttendanceProvider`. NUNCA usar `getByStudent` direto sem
  /// fallback (scan da coleção inteira).
  Future<List<Attendance>> _loadVerified(
      AttendanceService svc, String studentId) async {
    try {
      final page = await svc.getByStudentPaginated(studentId, limit: 30);
      return page.items;
    } catch (_) {
      // Índice composto ausente? Cai pro read não paginado (sort client-side).
      return svc.getByStudent(studentId, limit: 30);
    }
  }

  /// Constrói um TrainEntry de self-log (título = modalidade ou "TREINO").
  TrainEntry _selfEntry({
    required DocumentReference<Map<String, dynamic>> ref,
    required DateTime date,
    required String? sport,
    int sparringCount = 0,
    String? intensity,
    required String? feeling,
    required List<String> techniques,
    required List<String> partners,
    String? note,
  }) {
    final title = sport != null
        ? getSport(SportId.fromString(sport)).labelShort.toUpperCase()
        : 'TREINO';
    return TrainEntry(
      source: TrainSource.self,
      date: date,
      title: title,
      sport: sport,
      selfRef: ref,
      sparringCount: sparringCount,
      intensity: intensity,
      feeling: feeling,
      techniques: techniques,
      partners: partners,
      note: note,
    );
  }

  /// Ordena desc por data; em empate de dia, VERIFICADO vem antes de SELF.
  void _sortFeed(List<TrainEntry> list) {
    list.sort((x, y) {
      final c = y.date.compareTo(x.date);
      if (c != 0) return c;
      if (x.source == y.source) return 0;
      return x.source == TrainSource.verified ? -1 : 1;
    });
  }

  // ── Abre o logger COUNT-FIRST (toque 1: escolher número) ──────────────────
  /// [date]/[sport]/[linkedAttendanceId] preenchidos quando o count é anexado a
  /// uma linha VERIFICADA do histórico; senão default = hoje + esporte primário.
  void _openCount({
    DateTime? date,
    SportId? sport,
    String? linkedAttendanceId,
  }) {
    if (_uid == null) return;
    final student = ref.read(currentStudentProvider).valueOrNull;
    final primary = sport ?? student?.getPrimarySport();
    setState(() {
      _editing = false;
      _logRef = null;
      _logDate = DateUtils.dateOnly(date ?? DateTime.now());
      _sport = primary;
      _sparringCount = _kDefaultSparring;
      _intensity = null;
      _feeling = null;
      _note = null;
      _noteCtrl.clear();
      _linkedAttendanceId = linkedAttendanceId;
      _techniques.clear();
      _partners.clear();
      _phase = _Phase.count;
    });
  }

  /// Esporte tem sparring? (musculação = check-in simples, sem número.)
  bool get _sportHasSparring =>
      sparringUnit(_sport ?? SportId.bjj) != null;

  /// Último count do MESMO esporte antes de [_logDate] — base do "+N" positivo.
  int? _previousSelfCount() {
    final target = _sport?.value;
    final prior = _feed
        .where((e) =>
            e.isSelf &&
            e.sparringCount > 0 &&
            (e.sport ?? 'bjj') == (target ?? 'bjj') &&
            e.date.isBefore(_logDate))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return prior.isEmpty ? null : prior.first.sparringCount;
  }

  // ── Toque 2: grava o count do dia (upsert-by-day) ─────────────────────────
  Future<void> _saveCount() async {
    final uid = _uid;
    if (uid == null || _saving) return;
    setState(() => _saving = true);
    final hasSparring = _sportHasSparring;
    final count = hasSparring ? _sparringCount : 0;
    // Delta positivo ANTES do optimistic insert (senão compara consigo mesmo).
    final prev = _previousSelfCount();
    try {
      final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
      final id = await TrainingLogService(uid).upsertForDay(
        date: _logDate,
        sparringCount: count,
        sport: _sport?.value,
        intensity: _intensity,
        feeling: _feeling,
        linkedAttendanceId: _linkedAttendanceId,
        academyId: academyId,
      );
      final ref0 = _logsCol(uid)!.doc(id);

      // Upsert-by-day no feed local: substitui o self-log do mesmo dia (se
      // houver) e reinsere. O self-log NÃO mexe nas métricas verificadas, então
      // não invalidamos o showcase — a jornada só lê attendance verificada.
      final next = _feed
          .where((e) => !(e.isSelf && DateUtils.isSameDay(e.date, _logDate)))
          .toList();
      next.insert(
        0,
        _selfEntry(
          ref: ref0,
          date: _logDate,
          sport: _sport?.value,
          sparringCount: count,
          intensity: _intensity,
          feeling: _feeling,
          techniques: const [],
          partners: const [],
        ),
      );
      _sortFeed(next);

      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _logRef = ref0;
        _editing = false;
        _feed = next;
        _rewardCount = count;
        _rewardDelta =
            (hasSparring && prev != null && count > prev) ? count - prev : null;
        _saving = false;
        _phase = _Phase.reward;
      });
      // Recalcula os insights de sparring (total/recorde/esforço/tendência).
      // NÃO invalida o showcase — a jornada verificada só lê attendance.
      ref.invalidate(sparringInsightsProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Não rolou de salvar. Tenta de novo.');
    }
  }

  void _bumpCount(int delta) {
    final next = (_sparringCount + delta).clamp(0, _kMaxSparring);
    if (next == _sparringCount) return;
    HapticFeedback.selectionClick();
    setState(() => _sparringCount = next);
  }

  void _setCount(int value) {
    final next = value.clamp(0, _kMaxSparring);
    HapticFeedback.selectionClick();
    setState(() => _sparringCount = next);
  }

  void _selectIntensity(String key) {
    final next = _intensity == key ? null : key;
    setState(() => _intensity = next);
  }

  // ── Atualiza o doc recém-criado com os detalhes opcionais ─────────────────
  Future<void> _patchLog(Map<String, dynamic> patch) async {
    final ref0 = _logRef;
    if (ref0 == null) return;
    try {
      await ref0.update({...patch, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (_) {
      _snack('Não consegui guardar isso agora.');
    }
  }

  void _selectSport(SportId id) {
    final next = _sport == id ? null : id;
    setState(() => _sport = next);
    _patchLog({'sport': next?.value ?? FieldValue.delete()});
  }

  void _selectFeeling(String key) {
    final next = _feeling == key ? null : key;
    setState(() => _feeling = next);
    _patchLog({'feeling': next ?? FieldValue.delete()});
  }

  void _addTech() {
    final v = _techCtrl.text.trim();
    if (v.isEmpty) return;
    setState(() {
      _techniques.add(v);
      _techCtrl.clear();
    });
    _patchLog({'techniques': _techniques});
  }

  void _removeTech(String v) {
    setState(() => _techniques.remove(v));
    _patchLog({'techniques': _techniques});
  }

  void _addPartner() {
    final v = _partnerCtrl.text.trim();
    if (v.isEmpty) return;
    setState(() {
      _partners.add(v);
      _partnerCtrl.clear();
    });
    _patchLog({'partners': _partners});
  }

  void _removePartner(String v) {
    setState(() => _partners.remove(v));
    _patchLog({'partners': _partners});
  }

  /// Ao sair da edição/reward, reflete os detalhes editados de volta no feed
  /// local (sem refetch) — mantém o subtítulo e nota da linha self coerentes.
  void _done() {
    final ref0 = _logRef;

    // Salva a nota se foi digitada e ainda não persistida via onSubmitted.
    final noteText = _noteCtrl.text.trim();
    final noteToSave = noteText.isEmpty ? null : noteText;
    if (ref0 != null && noteToSave != _note) {
      _note = noteToSave;
      _patchLog({'note': noteToSave ?? FieldValue.delete()});
    }

    // Atualiza o feed local (edição OU novo save com detalhes pós-reward).
    if (ref0 != null) {
      final updated = _feed.map((e) {
        if (e.selfRef?.path != ref0.path) return e;
        return _selfEntry(
          ref: ref0,
          date: e.date,
          sport: _sport?.value,
          sparringCount: _sparringCount,
          intensity: _intensity,
          feeling: _feeling,
          techniques: List<String>.from(_techniques),
          partners: List<String>.from(_partners),
          note: noteToSave,
        );
      }).toList();
      _feed = updated;
    }

    setState(() {
      _phase = _Phase.idle;
      _editing = false;
      _logRef = null;
    });
  }

  /// Abre um self-log existente para EDITAR — direto no logger COUNT (ajusta o
  /// número + excluir). Verified NUNCA entra aqui (registro da casa, imutável).
  void _openEdit(TrainEntry e) {
    if (!e.isSelf || e.selfRef == null) return;
    setState(() {
      _logRef = e.selfRef;
      _editing = true;
      _logDate = e.date;
      _linkedAttendanceId = null;
      _sport = e.sport != null ? SportId.fromString(e.sport!) : null;
      _sparringCount = e.sparringCount > 0 ? e.sparringCount : _kDefaultSparring;
      _intensity = e.intensity;
      _feeling = e.feeling;
      _note = e.note;
      _noteCtrl.text = e.note ?? '';
      _techniques
        ..clear()
        ..addAll(e.techniques);
      _partners
        ..clear()
        ..addAll(e.partners);
      _phase = _Phase.count;
    });
  }

  /// Exclui o self-log em edição (com confirmação).
  Future<void> _deleteLog() async {
    final ref0 = _logRef;
    if (ref0 == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: _bone,
        title: const Text('EXCLUIR ESTE TREINO?',
            style: TextStyle(fontWeight: FontWeight.w900, color: _ink)),
        content: const Text(
            'O registro some do seu diário. Não dá pra desfazer.',
            style: TextStyle(color: _smoke, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('CANCELAR',
                style: TextStyle(color: _smoke, fontWeight: FontWeight.w800)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('EXCLUIR',
                style: TextStyle(color: _blood, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref0.delete();
    } catch (_) {
      _snack('Não consegui excluir agora.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _feed = _feed.where((x) => x.selfRef?.path != ref0.path).toList();
      _phase = _Phase.idle;
      _editing = false;
      _logRef = null;
    });
    ref.invalidate(sparringInsightsProvider);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: _bone,
          ),
        ),
        backgroundColor: _ink,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Mantém a tela viva quando o usuário loga (resume de no-user).
    ref.listen(currentUserProvider, (prev, next) {
      if (next.valueOrNull?.id != null && _feedError == 'no-user') {
        _loadFeed();
      }
    });

    return Scaffold(
      backgroundColor: _bone,
      body: SafeArea(
        child: switch (_phase) {
          _Phase.count => _buildCount(),
          _Phase.reward => _buildReward(),
          _Phase.idle => _buildMain(),
        },
      ),
    );
  }

  // ── FASE IDLE: TREINEI = [ JORNADA | HISTÓRICO ] ──────────────────────────
  Widget _buildMain() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Kicker('TREINEI'),
          const SizedBox(height: 14),
          _segmented(),
          const SizedBox(height: 16),
          Expanded(
            child: IndexedStack(
              index: _view,
              children: [
                _buildVitrine(),
                _buildHistorico(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Segmented control [ JORNADA | HISTÓRICO ] ─────────────────────────────
  Widget _segmented() {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _ink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _hair),
      ),
      child: Row(
        children: [
          _segItem('JORNADA', 0),
          _segItem('HISTÓRICO', 1),
        ],
      ),
    );
  }

  Widget _segItem(String label, int i) {
    final sel = _view == i;
    return Expanded(
      child: Pressable(
        onTap: () => setState(() => _view = i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? _ink : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: sel ? _bone : _smoke,
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // JORNADA — herói (foto+faixa+streak) + PRÓXIMA GRADUAÇÃO + GRADUAÇÕES +
  // COMPETIÇÕES. A visão PRÓPRIA é editável: os marcos AUTO (auto-declarados)
  // ganham add/editar-data/excluir; os VERIFICADOS (= TETO) são read-only.
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildVitrine() {
    final showcaseAsync = ref.watch(myShowcaseProvider);

    return showcaseAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: _ink, strokeWidth: 2),
      ),
      error: (e, _) => _centerNote(
        'DEU RUIM',
        'Não consegui montar sua jornada agora.',
        icon: LucideIcons.alertTriangle,
      ),
      data: (p) {
        if (p == null) {
          // Sem academia / sem aluno resolvido → solo. A caminhada verificada
          // ainda não existe; mas os INSIGHTS de sparring dependem só dos logs
          // pessoais, então a seção "SEU SPARRING" ainda aparece se houver rolas.
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              const SizedBox(height: 20),
              _centerNote(
                'SUA JORNADA\nCOMEÇA NO TATAME',
                'Quando sua academia marcar presença e graduação, sua evolução '
                    'aparece aqui — graduações, streak e competições.',
                icon: LucideIcons.dumbbell,
              ),
              const SizedBox(height: 26),
              _sparringSection(),
            ],
          );
        }

        final grads = p.graduations;
        final comps = p.competitions;
        final medals = p.medals;
        final multiSport = grads.map((g) => g.sport).toSet().length > 1;
        // Auto-declarados crus (com ids) para resolver editar/excluir o marco.
        final self = ref.watch(_selfRecordsProvider).valueOrNull;

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            _vitrineHero(p),
            const SizedBox(height: 18),
            _nextPromotionCard(),
            _sparringSection(),
            _graduationsSection(grads, multiSport, self),
            const SizedBox(height: 22),
            _competitionsSection(comps, medals, self),
          ],
        );
      },
    );
  }

  // ── Cartel de treino: streak · recorde · aulas verificadas. SEM foto/nome/
  // faixa — identidade fica no PERFIL; a Jornada foca no TREINO.
  // AULAS VERIFICADAS = totalTrainings (só presenças da academia + baseline).
  // SESSÕES DE TATAME = união de dias com presença verificada OU self-log no
  // feed carregado — mostrado como nota discreta abaixo do card.
  Widget _vitrineHero(FighterProfile p) {
    // União de dias únicos do feed (verificados ∪ self). Boundado pelos ~30+60
    // docs carregados; suficiente para o contexto de "Jornada".
    final sessoesTatame = _feed.map((e) => e.date).toSet().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hair),
          ),
          child: Row(
            children: [
              Expanded(
                child: _heroStat(p.currentStreak, 'SEMANAS', accent: true),
              ),
              _heroDivider(),
              Expanded(child: _heroStat(p.recordStreak, 'RECORDE')),
              _heroDivider(),
              Expanded(
                child: _heroStatVerificado(p.totalTrainings, 'AULAS VERIFICADAS'),
              ),
            ],
          ),
        ),
        if (sessoesTatame > 0) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '$sessoesTatame SESSÕES DE TATAME',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  fontFeatures: _tabular,
                  color: _smoke,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '· inclui avulsos · não conta pra faixa',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: _smoke.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _heroDivider() =>
      Container(width: 1, height: 42, color: _hair);

  Widget _heroStat(int value, String label, {bool accent = false}) {
    return Column(
      children: [
        AnimatedCountUp(
          value: value,
          style: TextStyle(
            fontSize: 34,
            height: 1.0,
            fontWeight: FontWeight.w900,
            fontFeatures: _tabular,
            letterSpacing: -1.0,
            color: accent ? _blood : _ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: _eyebrow(_smoke, 10)),
      ],
    );
  }

  /// Variante de _heroStat para "AULAS VERIFICADAS" — exibe um ícone de check
  /// discreto ao lado do rótulo para indicar que são presenças da academia.
  Widget _heroStatVerificado(int value, String label) {
    return Column(
      children: [
        AnimatedCountUp(
          value: value,
          style: const TextStyle(
            fontSize: 34,
            height: 1.0,
            fontWeight: FontWeight.w900,
            fontFeatures: _tabular,
            letterSpacing: -1.0,
            color: _ink,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_outlined, size: 10, color: _smoke),
            const SizedBox(width: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: _eyebrow(_smoke, 9.5),
            ),
          ],
        ),
      ],
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // SEU SPARRING — insights dos self-logs (total · recorde · esforço até cada
  // faixa · tendência positiva). Multi-modal (unidade por esporte). NÃO conta
  // pra graduação — é o esforço do lutador virando narrativa de progresso.
  // ════════════════════════════════════════════════════════════════════════
  Widget _sparringSection() {
    final ins = ref.watch(sparringInsightsProvider).valueOrNull;
    if (ins == null || ins.totalAll == 0) return const SizedBox.shrink();
    final multiSport = ins.sportsWithCount.length > 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('SEU SPARRING'),
          _sparringStatsCard(ins),
          // Tendência — o ÚNICO juízo de valor, e sempre positivo (por design).
          if (ins.trend != null) ...[
            const SizedBox(height: 14),
            _trendLine(ins.trend!),
          ],
          // "N rolas até a faixa X" — esforço acumulado entre graduações.
          if (ins.gradEfforts.isNotEmpty) ...[
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 2),
              child:
                  Text('ESFORÇO ATÉ CADA FAIXA', style: _eyebrow(_smoke, 10.5)),
            ),
            ...ins.gradEfforts.map((e) => _gradEffortRow(e, multiSport)),
          ],
        ],
      ),
    );
  }

  // 3 stats tabulares (total · melhor noite · sessões) — todos MONOTÔNICOS
  // (só sobem), então nunca desmotivam mesmo quem estagnou.
  Widget _sparringStatsCard(SparringInsights ins) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hair),
      ),
      child: Row(
        children: [
          Expanded(
            child: _heroStat(ins.totalAll, _sparringUnitLabel(ins),
                accent: true),
          ),
          _heroDivider(),
          Expanded(child: _heroStat(ins.bestNight, 'MELHOR NOITE')),
          _heroDivider(),
          Expanded(child: _heroStat(ins.totalSessions, 'SESSÕES')),
        ],
      ),
    );
  }

  Widget _trendLine(TrendSignal t) {
    final unit = getSparringTerm(SportId.fromString(t.sport))?.toUpperCase() ??
        'SPARRINGS';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _blood.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _blood.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.trendingUp, size: 20, color: _blood),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SUA MÉDIA DE $unit POR TREINO VEM SUBINDO',
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: _blood,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '+${t.deltaPerc}% NOS ÚLTIMOS TREINOS',
                  style: const TextStyle(
                    color: _smoke,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    fontFeatures: _tabular,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradEffortRow(GraduationEffort e, bool multiSport) {
    final sportId = SportId.fromString(e.sport);
    final beltColor = _beltColor(sportId, e.belt);
    final label = _effortLabel(sportId, e);
    final unit =
        getSparringTerm(sportId, count: e.sparringsInBlock)?.toUpperCase() ??
            'SPARRINGS';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: beltColor,
              shape: BoxShape.circle,
              border: Border.all(color: _hair),
            ),
          ),
          const SizedBox(width: 10),
          if (multiSport) ...[
            _miniSportChip(sportId),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: _ink,
              ),
            ),
          ),
          Text(
            '${e.sparringsInBlock} $unit',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              fontFeatures: _tabular,
              letterSpacing: 0.3,
              color: _blood,
            ),
          ),
        ],
      ),
    );
  }

  /// Rótulo do marco de esforço ("FAIXA AZUL" / "2º GRAU BRANCA").
  String _effortLabel(SportId sport, GraduationEffort e) {
    final label = getGradeLabel(sport, e.belt).toUpperCase();
    return e.isBeltChange ? 'FAIXA $label' : '${e.stripes}º GRAU $label';
  }

  /// Unidade do card de totais: plural do esporte quando só há 1; senão o termo
  /// neutro "SPARRINGS" (multi-modal, sem misturar rolas+rounds num só número).
  String _sparringUnitLabel(SparringInsights ins, {int count = 2}) {
    final s = ins.sportsWithCount;
    if (s.length == 1) {
      final term = getSparringTerm(SportId.fromString(s.first), count: count);
      if (term != null) return term.toUpperCase();
    }
    return 'SPARRINGS';
  }

  // ── GRADUAÇÕES — timeline com o esforço por trás de cada marco ────────────
  Widget _graduationsSection(
      List<FighterGraduation> grads, bool multiSport, _SelfRecords? self) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('GRADUAÇÕES', onAdd: self == null ? null : _addGraduation),
        if (grads.isEmpty)
          _emptyLine('Nenhuma graduação ainda. Adicione faixas/graus antigos.')
        else
          ...grads.map((g) => _gradTile(g, multiSport, self)),
      ],
    );
  }

  Widget _gradTile(
      FighterGraduation g, bool multiSport, _SelfRecords? self) {
    final sportId = SportId.fromString(g.sport);
    final beltColor = _beltColor(sportId, g.belt);
    final unit = g.weighted ? 'PONTOS' : 'TREINOS';
    final isAuto = g.source == 'auto';
    final effort = g.trainingsToReach > 0
        ? '${g.trainingsToReach} $unit · ${_monthsLabel(g.monthsToReach)} ATÉ AQUI'
        : '${_monthsLabel(g.monthsToReach)} ATÉ AQUI';
    // Casa o marco AUTO ao doc cru (mesmo esporte/grau/grau-stripes/data) para
    // editar/excluir o registro certo. Verificado nunca tem ação.
    final SelfGraduation? rec = (isAuto && self != null)
        ? self.grads
            .where((s) =>
                s.sport == g.sport &&
                s.grade == g.belt &&
                s.stripes == g.stripes &&
                DateUtils.isSameDay(s.date, g.date))
            .firstOrNull
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hair),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Marco — a única cor de faixa real na tela.
          Container(
            width: 10,
            height: 38,
            decoration: BoxDecoration(
              color: beltColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _gradLabel(sportId, g),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                          color: _ink,
                        ),
                      ),
                    ),
                    if (multiSport) ...[
                      _miniSportChip(sportId),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _dmy(g.date),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _smoke,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        effort,
                        style: const TextStyle(
                          color: _smoke,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          fontFeatures: _tabular,
                        ),
                      ),
                    ),
                    if (isAuto) _autoTag(),
                  ],
                ),
              ],
            ),
          ),
          // Verificado = read-only; AUTO casado → menu editar/excluir.
          if (rec != null) ...[
            const SizedBox(width: 6),
            _editDot(() => _gradActions(rec, self!)),
          ],
        ],
      ),
    );
  }

  // ── COMPETIÇÕES — cartel + a "estrada" entre cada marco ───────────────────
  Widget _competitionsSection(
      List<FighterCompetitionMark> comps, MedalCount medals, _SelfRecords? self) {
    final tiles = <Widget>[];
    for (var i = 0; i < comps.length; i++) {
      // Lista é desc (mais recente primeiro): o mais antigo (índice final) é a
      // ESTREIA — a primeira vez na estrada.
      tiles.add(_compTile(comps[i], isFirst: i == comps.length - 1, self: self));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader('COMPETIÇÕES',
            onAdd: self == null ? null : _addCompetition),
        if (medals.total > 0) ...[
          _cartel(medals),
          const SizedBox(height: 12),
        ],
        if (comps.isEmpty)
          _emptyLine('Lutou por outra academia? Adicione sua competição externa.')
        else
          ...tiles,
      ],
    );
  }

  Widget _cartel(MedalCount m) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hair),
      ),
      child: Row(
        children: [
          Expanded(child: _medalCol('OURO', m.gold)),
          _heroDivider(),
          Expanded(child: _medalCol('PRATA', m.silver)),
          _heroDivider(),
          Expanded(child: _medalCol('BRONZE', m.bronze)),
        ],
      ),
    );
  }

  Widget _medalCol(String label, int n) {
    return Column(
      children: [
        const Icon(LucideIcons.medal, size: 18, color: _blood),
        const SizedBox(height: 6),
        AnimatedCountUp(
          value: n,
          style: const TextStyle(
            fontSize: 26,
            height: 1.0,
            fontWeight: FontWeight.w900,
            fontFeatures: _tabular,
            letterSpacing: -0.5,
            color: _ink,
          ),
        ),
        const SizedBox(height: 5),
        Text(label, style: _eyebrow(_smoke, 10)),
      ],
    );
  }

  Widget _compTile(FighterCompetitionMark c,
      {required bool isFirst, _SelfRecords? self}) {
    final isPodium =
        c.position == 'gold' || c.position == 'silver' || c.position == 'bronze';
    final col = isPodium ? _blood : _ink;
    final posLabel = _positionLabel(c.position);
    final isAuto = c.source == 'auto';
    final category = [c.beltCategory, c.weightCategory, c.modality]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');
    // Casa o marco AUTO ao doc cru (mesmo esporte/nome/data).
    final SelfCompetition? rec = (isAuto && self != null)
        ? self.comps
            .where((s) =>
                s.sport == c.sport &&
                s.name == c.name &&
                DateUtils.isSameDay(s.date, c.date))
            .firstOrNull
        : null;

    // A "estrada": o esforço entre a competição anterior e esta.
    final road = isFirst
        ? 'ESTREIA · ${c.cumulativeTrainings} TREINOS · ${_monthsLabel(c.monthsSincePrev)} DE CAMINHADA'
        : 'DESDE A ÚLTIMA · ${c.trainingsSincePrev} TREINOS · ${_monthsLabel(c.monthsSincePrev)}'
            '${c.gradesSincePrev > 0 ? ' · ${_gradesLabel(c.gradesSincePrev)}' : ''}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hair),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: col.withValues(alpha: 0.25)),
            ),
            child: Icon(
              isPodium ? LucideIcons.medal : LucideIcons.award,
              size: 22,
              color: col,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(posLabel, style: _eyebrow(col, 10)),
                    if (isAuto) ...[
                      const SizedBox(width: 8),
                      _autoTag(),
                    ],
                    const Spacer(),
                    Text(
                      _dmy(c.date),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _ash,
                        fontFeatures: _tabular,
                      ),
                    ),
                    if (rec != null) ...[
                      const SizedBox(width: 4),
                      _editDot(() => _compActions(rec, self!)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  c.name.isNotEmpty ? c.name : 'COMPETIÇÃO',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (category.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    category,
                    style: const TextStyle(
                      color: _smoke,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 9),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 8,
                      height: 2,
                      margin: const EdgeInsets.only(top: 5),
                      color: _blood,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        road,
                        style: const TextStyle(
                          color: _blood,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          fontFeatures: _tabular,
                          letterSpacing: 0.4,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Hint compacto quando uma seção está vazia (mas com CTA de adicionar) ──
  Widget _emptyLine(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hair),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.4,
          fontWeight: FontWeight.w600,
          color: _smoke,
        ),
      ),
    );
  }

  // ── Selo "AUTO" (auto-declarado) — espelha o badge do HISTÓRICO em miniatura.
  Widget _autoTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _ink.withValues(alpha: 0.18)),
      ),
      child: Text('AUTO', style: _eyebrow(_ink, 9)),
    );
  }

  // ── Affordance de edição de um marco AUTO (só auto-declarado tem ação). ────
  Widget _editDot(VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        child: const Icon(Icons.more_horiz, size: 20, color: _smoke),
      ),
    );
  }

  // ── GRADUAÇÃO-POR-PRESENÇA — destaque da próxima graduação da academia ─────
  /// Mostra, para o esporte PRINCIPAL, o progresso de presenças → próxima faixa
  /// quando a academia tem graduação-por-presença. Esportes sem grade (boxe/
  /// musculação) e quem já está no topo não renderizam nada.
  Widget _nextPromotionCard() {
    // GATE OBRIGATÓRIO: só mostra a graduação-POR-PRESENÇA quando a academia
    // REALMENTE habilitou (autoGraduationEnabled). Sem isso, a barra aparecia
    // pra academias que NÃO usam graduação por presença (ex.: T23) — errado.
    final settings = ref.watch(academySettingsProvider).valueOrNull;
    if (settings == null || !settings.autoGraduationEnabled) {
      return const SizedBox.shrink();
    }
    final student = ref.watch(currentStudentProvider).valueOrNull;
    if (student == null) return const SizedBox.shrink();
    final sport = student.getPrimarySport();
    if (getSport(sport).gradeSystem == GradeSystem.none) {
      return const SizedBox.shrink();
    }
    final elig = ref
        .watch(studentSportEligibilityProvider(
            (studentId: student.id, sport: sport)))
        .valueOrNull;
    if (elig == null || elig.nextBelt == null) return const SizedBox.shrink();

    final beltLabel = getGradeLabel(sport, elig.nextBelt!).toUpperCase();
    final target = (elig.nextStripes ?? 0) > 0
        ? '${elig.nextStripes}º GRAU $beltLabel'
        : 'FAIXA $beltLabel';
    final unit = elig.weighted ? 'PONTOS' : 'TREINOS';
    final req = elig.requiredClasses;
    final frac =
        req > 0 ? (elig.currentClasses / req).clamp(0.0, 1.0) : (elig.eligible ? 1.0 : 0.0);
    final status = elig.eligible
        ? 'PRONTO PRA GRADUAR'
        : '${elig.currentClasses} / $req $unit · FALTAM ${elig.missingClasses}';

    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 14, height: 2, color: _blood),
              const SizedBox(width: 8),
              Text('PRÓXIMA GRADUAÇÃO · POR PRESENÇA',
                  style: _eyebrow(_ink, 11)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            target,
            style: const TextStyle(
              fontSize: 20,
              height: 1.0,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              color: _ink,
            ),
          ),
          const SizedBox(height: 12),
          // Barra de progresso — o único acento sangue.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 7,
              backgroundColor: _ink.withValues(alpha: 0.06),
              valueColor: const AlwaysStoppedAnimation(_blood),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            status,
            style: TextStyle(
              color: elig.eligible ? _blood : _smoke,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontFeatures: _tabular,
            ),
          ),
        ],
      ),
    );
  }

  // ── Invalidação pós-mutação: recarrega o merge (showcase) + os docs crus. ──
  void _refreshJornada() {
    ref.invalidate(_selfRecordsProvider);
    ref.invalidate(myShowcaseProvider);
  }

  Future<DateTime?> _pickDate(DateTime initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(1990),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _blood,
            onPrimary: _bone,
            onSurface: _ink,
          ),
        ),
        child: child!,
      ),
    );
  }

  // ── Ações de uma GRADUAÇÃO auto-declarada: editar data / excluir ───────────
  Future<void> _gradActions(SelfGraduation rec, _SelfRecords self) async {
    final action = await _actionSheet();
    if (action == _RecordAction.editDate) {
      final picked = await _pickDate(rec.date);
      if (picked == null) return;
      try {
        await SelfRecordsService(self.academyId).updateGraduation(
            self.studentId, rec.id, {'date': Timestamp.fromDate(picked)});
        _refreshJornada();
      } catch (_) {
        _snack('Não consegui salvar a data.');
      }
    } else if (action == _RecordAction.delete) {
      final ok = await _confirmDelete('EXCLUIR ESTA GRADUAÇÃO?',
          'O marco auto-declarado some da sua jornada. Não dá pra desfazer.');
      if (!ok) return;
      try {
        await SelfRecordsService(self.academyId)
            .deleteGraduation(self.studentId, rec.id);
        _refreshJornada();
      } catch (_) {
        _snack('Não consegui excluir agora.');
      }
    }
  }

  // ── Ações de uma COMPETIÇÃO auto-declarada: editar data / excluir ──────────
  Future<void> _compActions(SelfCompetition rec, _SelfRecords self) async {
    final action = await _actionSheet();
    if (action == _RecordAction.editDate) {
      final picked = await _pickDate(rec.date);
      if (picked == null) return;
      try {
        await SelfRecordsService(self.academyId).updateCompetition(
            self.studentId, rec.id, {'date': Timestamp.fromDate(picked)});
        _refreshJornada();
      } catch (_) {
        _snack('Não consegui salvar a data.');
      }
    } else if (action == _RecordAction.delete) {
      final ok = await _confirmDelete('EXCLUIR ESTA COMPETIÇÃO?',
          'O marco auto-declarado some da sua jornada. Não dá pra desfazer.');
      if (!ok) return;
      try {
        await SelfRecordsService(self.academyId)
            .deleteCompetition(self.studentId, rec.id);
        _refreshJornada();
      } catch (_) {
        _snack('Não consegui excluir agora.');
      }
    }
  }

  /// Folha de ações reutilizada por graduação/competição auto-declaradas.
  Future<_RecordAction?> _actionSheet() {
    return showModalBottomSheet<_RecordAction>(
      context: context,
      backgroundColor: _bone,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _sheetGrabber(),
            const SizedBox(height: 8),
            _sheetAction(
              icon: Icons.event,
              label: 'EDITAR DATA',
              color: _ink,
              onTap: () => Navigator.pop(c, _RecordAction.editDate),
            ),
            _sheetAction(
              icon: Icons.delete_outline,
              label: 'EXCLUIR',
              color: _blood,
              onTap: () => Navigator.pop(c, _RecordAction.delete),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sheetGrabber() => Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: _ink.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _sheetAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: _bone,
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w900, color: _ink)),
        content: Text(body,
            style: const TextStyle(color: _smoke, fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('CANCELAR',
                style: TextStyle(color: _smoke, fontWeight: FontWeight.w800)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('EXCLUIR',
                style: TextStyle(color: _blood, fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // ── Adicionar GRADUAÇÃO passada (com TETO verificado) ──────────────────────
  Future<void> _addGraduation() async {
    final student = ref.read(currentStudentProvider).valueOrNull;
    final user = ref.read(currentUserProvider).valueOrNull;
    final academyId = user?.academyId;
    if (student == null || academyId == null || academyId.isEmpty) return;

    // Só esportes do aluno COM sistema de graduação.
    final studentSports = student
        .getSports()
        .where((s) => getSport(s).gradeSystem != GradeSystem.none)
        .toList();
    if (studentSports.isEmpty) {
      _snack('Nenhum esporte seu tem graduação.');
      return;
    }

    SportId sport = studentSports.first;
    String? gradeId;
    int stripes = 0;
    DateTime date = DateTime.now();

    // Graus permitidos para o esporte selecionado: até o TETO verificado.
    List<GradeDefinition> allowedGrades(SportId s) {
      final teto = student.getGrade(s);
      final variant = s == SportId.muaythai && teto != null
          ? resolveMuaythaiVariant(teto.currentGrade)
          : null;
      final grades = getGradesForSport(s, muaythaiVariant: variant);
      if (teto == null) return grades;
      final idx = grades.indexWhere((g) => g.id == teto.currentGrade);
      final cap = idx < 0 ? grades.length - 1 : idx;
      return grades.sublist(0, cap + 1);
    }

    int maxStripesFor(SportId s, String gid) {
      final teto = student.getGrade(s);
      final def = getGradeDefinition(s, gid);
      final max = def?.maxStripes ?? 0;
      // No grau-teto, não passar dos graus já verificados.
      if (teto != null && gid == teto.currentGrade) {
        return teto.currentStripes < max ? teto.currentStripes : max;
      }
      return max;
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bone,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (c) {
        return StatefulBuilder(builder: (c, setSheet) {
          final grades = allowedGrades(sport);
          // Garante grau válido para o esporte atual.
          if (gradeId == null || grades.every((g) => g.id != gradeId)) {
            gradeId = grades.isNotEmpty ? grades.last.id : null;
            stripes = 0;
          }
          final supportsStripes = getSport(sport).supportsStripes;
          final maxStr = gradeId == null ? 0 : maxStripesFor(sport, gradeId!);
          return _formSheet(
            title: 'ADICIONAR GRADUAÇÃO',
            subtitle: 'SÓ ATÉ A SUA FAIXA VERIFICADA (TETO).',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (studentSports.length > 1) ...[
                  _fieldLabel('ESPORTE'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: studentSports
                        .map((s) => _Chip(
                              label: (getSport(s).labelShort).toUpperCase(),
                              selected: sport == s,
                              onTap: () => setSheet(() {
                                sport = s;
                                gradeId = null;
                              }),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                ],
                _fieldLabel('GRAU'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: grades
                      .map((g) => _Chip(
                            label: g.label.toUpperCase(),
                            selected: gradeId == g.id,
                            onTap: () => setSheet(() {
                              gradeId = g.id;
                              stripes = 0;
                            }),
                          ))
                      .toList(),
                ),
                if (supportsStripes && maxStr > 0) ...[
                  const SizedBox(height: 18),
                  _fieldLabel('GRAUS (DETALHE)'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(maxStr + 1, (i) => i)
                        .map((n) => _Chip(
                              label: '$n',
                              selected: stripes == n,
                              onTap: () => setSheet(() => stripes = n),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 18),
                _dateRow(date, () async {
                  final picked = await _pickDate(date);
                  if (picked != null) setSheet(() => date = picked);
                }),
                const SizedBox(height: 22),
                _saveButton('SALVAR GRADUAÇÃO', () {
                  if (gradeId == null) return;
                  Navigator.pop(c, true);
                }),
              ],
            ),
          );
        });
      },
    );

    if (saved != true || gradeId == null) return;
    try {
      await SelfRecordsService(academyId).addGraduation(
        student.id,
        SelfGraduation(
          sport: sport.value,
          grade: gradeId!,
          stripes: stripes,
          date: date,
          createdBy: user!.id,
        ),
      );
      _refreshJornada();
      _snack('Graduação adicionada à jornada.');
    } catch (_) {
      _snack('Não consegui adicionar a graduação.');
    }
  }

  // ── Adicionar COMPETIÇÃO externa (auto-declarada) ──────────────────────────
  Future<void> _addCompetition() async {
    final student = ref.read(currentStudentProvider).valueOrNull;
    final user = ref.read(currentUserProvider).valueOrNull;
    final academyId = user?.academyId;
    if (student == null || academyId == null || academyId.isEmpty) return;

    final studentSports = student.getSports();
    SportId sport = student.getPrimarySport();
    if (!studentSports.contains(sport)) sport = studentSports.first;
    String placement = 'participant';
    DateTime date = DateTime.now();
    final nameCtrl = TextEditingController();
    final academyCtrl = TextEditingController();

    const placements = <String, String>{
      'gold': 'OURO',
      'silver': 'PRATA',
      'bronze': 'BRONZE',
      'participant': 'PARTICIPAÇÃO',
    };

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bone,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (c) {
        return StatefulBuilder(builder: (c, setSheet) {
          return _formSheet(
            title: 'COMPETIÇÃO EXTERNA',
            subtitle: 'LUTOU POR OUTRA ACADEMIA? REGISTRE AQUI.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _fieldLabel('CAMPEONATO'),
                _sheetTextField(nameCtrl, 'NOME DO CAMPEONATO'),
                const SizedBox(height: 18),
                if (studentSports.length > 1) ...[
                  _fieldLabel('ESPORTE'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: studentSports
                        .map((s) => _Chip(
                              label: (getSport(s).labelShort).toUpperCase(),
                              selected: sport == s,
                              onTap: () => setSheet(() => sport = s),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                ],
                _fieldLabel('RESULTADO'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: placements.entries
                      .map((e) => _Chip(
                            label: e.value,
                            selected: placement == e.key,
                            onTap: () => setSheet(() => placement = e.key),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 18),
                _fieldLabel('ACADEMIA (OPCIONAL)'),
                _sheetTextField(academyCtrl, 'POR QUAL ACADEMIA'),
                const SizedBox(height: 18),
                _dateRow(date, () async {
                  final picked = await _pickDate(date);
                  if (picked != null) setSheet(() => date = picked);
                }),
                const SizedBox(height: 22),
                _saveButton('SALVAR COMPETIÇÃO', () {
                  if (nameCtrl.text.trim().isEmpty) {
                    _snack('Dá um nome pro campeonato.');
                    return;
                  }
                  Navigator.pop(c, true);
                }),
              ],
            ),
          );
        });
      },
    );

    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      final academy = academyCtrl.text.trim();
      try {
        await SelfRecordsService(academyId).addCompetition(
          student.id,
          SelfCompetition(
            sport: sport.value,
            name: nameCtrl.text.trim(),
            date: date,
            placement: placement,
            external: true,
            externalAcademy: academy.isNotEmpty ? academy : null,
            createdBy: user!.id,
          ),
        );
        _refreshJornada();
        _snack('Competição adicionada à jornada.');
      } catch (_) {
        _snack('Não consegui adicionar a competição.');
      }
    }
    nameCtrl.dispose();
    academyCtrl.dispose();
  }

  // ── Componentes das folhas de formulário (estilo fighter) ──────────────────
  Widget _formSheet({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: _sheetGrabber()),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                  color: _ink,
                )),
            const SizedBox(height: 6),
            Text(subtitle, style: _eyebrow(_smoke, 11)),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: _eyebrow(_ink, 11)),
      );

  Widget _sheetTextField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      textCapitalization: TextCapitalization.words,
      cursorColor: _blood,
      style: const TextStyle(fontWeight: FontWeight.w700, color: _ink),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: _smoke, fontWeight: FontWeight.w600),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        filled: true,
        fillColor: _ink.withValues(alpha: 0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _ink.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _ink.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _blood, width: 1.4),
        ),
      ),
    );
  }

  Widget _dateRow(DateTime date, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _ink.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _ink.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            const Icon(Icons.event, size: 18, color: _smoke),
            const SizedBox(width: 12),
            Text('DATA', style: _eyebrow(_smoke, 11)),
            const Spacer(),
            Text(
              _dmy(date),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _ink,
                fontFeatures: _tabular,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveButton(String label, VoidCallback onTap) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
            color: _bone,
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // HISTÓRICO — o feed unificado (verificado + self) + o self-log 1-tap
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildHistorico() {
    if (_loadingFeed) {
      return const Center(
        child: CircularProgressIndicator(color: _ink, strokeWidth: 2),
      );
    }
    if (_feedError == 'no-user') {
      return _centerNote(
        'ENTRE PRA VER',
        'Seu histórico de treino vive na sua conta.',
        icon: LucideIcons.logIn,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _historyList()),
        const SizedBox(height: 12),
        _logButton(),
        if (_showGraduationCaveat) ...[
          const SizedBox(height: 9),
          Text(
            'REGISTRO AVULSO — NÃO CONTA PRA GRADUAÇÃO',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: _smoke,
            ),
          ),
        ],
        const SizedBox(height: 18),
      ],
    );
  }

  /// O aviso "avulso não conta pra graduação" só faz sentido quando a academia
  /// do aluno gradua POR PRESENÇA. Sem academia OU sem autoGraduationEnabled não
  /// há "graduação por treino" pro avulso deixar de contar → esconde o aviso.
  bool get _showGraduationCaveat {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user?.academyId == null || user!.academyId!.isEmpty) return false;
    return ref
            .watch(academySettingsProvider)
            .valueOrNull
            ?.autoGraduationEnabled ==
        true;
  }

  Widget _historyList() {
    if (_feed.isEmpty) {
      final hasAcademy = _academyId != null && _academyId!.isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasAcademy ? LucideIcons.calendarDays : LucideIcons.clipboardList,
                size: 40,
                color: _smoke.withValues(alpha: 0.55),
              ),
              const SizedBox(height: 16),
              Text(
                hasAcademy
                    ? 'AS PRESENÇAS DA AULA\nAPARECEM AQUI SOZINHAS.'
                    : 'SEU HISTÓRICO DE TREINO\nAPARECE AQUI.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: _smoke,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            children: [
              Container(width: 14, height: 2, color: _blood),
              const SizedBox(width: 8),
              Text('HISTÓRICO',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                    color: _ink,
                  )),
              const Spacer(),
              Text('VERIFICADO = PROFESSOR · AUTO = VOCÊ',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: _smoke,
                  )),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: _feed.length,
            itemBuilder: (_, i) {
              final e = _feed[i];
              return _TrainRow(
                entry: e,
                onTap: e.isSelf
                    ? () => _openEdit(e)
                    : (e.verifiedId != null
                        ? () => _openCount(
                              date: e.date,
                              sport: e.sport != null
                                  ? SportId.fromString(e.sport!)
                                  : null,
                              linkedAttendanceId: e.verifiedId,
                            )
                        : null),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _logButton() {
    return Pressable(
      onTap: _saving ? null : () => _openCount(),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: _blood,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: _blood.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Text(
              'TREINOU SEM PROFESSOR?',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: Color(0xFFF2D4D4),
              ),
            ),
            SizedBox(height: 6),
            Text(
              'REGISTRAR TREINO',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: _bone,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'MARQUE SUAS ROLAS DO DIA',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: Color(0xFFF2D4D4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sai do logger COUNT sem gravar (volta ao HISTÓRICO).
  void _cancelCount() {
    setState(() {
      _phase = _Phase.idle;
      _editing = false;
      _logRef = null;
    });
  }

  // ════════════════════════════════════════════════════════════════════════
  // FASE COUNT — o coração: um número em ~2 toques. Stepper gigante + chips de
  // atalho + opcionais leves (intensidade/modalidade). Musculação vira check-in.
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildCount() {
    final studentSports =
        ref.watch(currentStudentProvider).valueOrNull?.getSports() ??
            const [SportId.bjj];
    final sport = _sport ?? SportId.bjj;
    final unit = sparringUnit(sport);
    final hasSparring = unit != null;
    final unitLabel = hasSparring
        ? (_sparringCount == 1 ? unit.one : unit.many).toUpperCase()
        : '';
    final isToday = DateUtils.isSameDay(_logDate, DateTime.now());

    final title = !hasSparring
        ? 'TREINEI HOJE'
        : 'QUANTAS ${unit.many.toUpperCase()} HOJE?';

    return Column(
      children: [
        // Voltar
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Row(
            children: [
              Pressable(
                onTap: _cancelCount,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: const Icon(Icons.arrow_back, color: _ink, size: 24),
                ),
              ),
              const Spacer(),
              if (_editing)
                Text('EDITAR', style: _eyebrow(_smoke, 11)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text(title,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                      color: _ink,
                    )),
                if (_linkedAttendanceId != null) ...[
                  const SizedBox(height: 8),
                  Text('ANEXANDO À AULA VERIFICADA',
                      style: _eyebrow(_blood, 10.5)),
                ] else if (!isToday) ...[
                  const SizedBox(height: 8),
                  Text('DIA ${_dmy(_logDate)}', style: _eyebrow(_smoke, 10.5)),
                ],
                const SizedBox(height: 28),
                if (hasSparring) ...[
                  _stepper(unitLabel),
                  const SizedBox(height: 24),
                  _quickCountChips(),
                ] else
                  _checkinCard(sport),
                const SizedBox(height: 30),
                _optionalDivider(),
                const SizedBox(height: 20),
                _fieldLabel('INTENSIDADE'),
                _intensityChips(),
                if (studentSports.length > 1) ...[
                  const SizedBox(height: 20),
                  _fieldLabel('MODALIDADE'),
                  _countSportChips(studentSports),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        _countSaveBar(),
        if (_showGraduationCaveat)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 14),
            child: Text(
              'REGISTRO AVULSO — NÃO CONTA PRA GRADUAÇÃO',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: _smoke,
              ),
            ),
          ),
      ],
    );
  }

  Widget _stepper(String unitLabel) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _stepBtn(Icons.remove, () => _bumpCount(-1),
                enabled: _sparringCount > 0),
            SizedBox(
              width: 132,
              child: Text(
                '$_sparringCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 88,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  fontFeatures: _tabular,
                  letterSpacing: -3,
                  color: _blood,
                ),
              ),
            ),
            _stepBtn(Icons.add, () => _bumpCount(1),
                enabled: _sparringCount < _kMaxSparring),
          ],
        ),
        const SizedBox(height: 4),
        Text(unitLabel, style: _eyebrow(_smoke, 13)),
      ],
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap, {required bool enabled}) {
    return _RepeatButton(
      enabled: enabled,
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: enabled ? _ink : _ink.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(icon,
            size: 30, color: enabled ? _bone : _ink.withValues(alpha: 0.25)),
      ),
    );
  }

  Widget _quickCountChips() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: _kQuickCounts.map((n) {
        final sel = _sparringCount == n;
        return _Chip(
          label: '$n',
          selected: sel,
          onTap: () => _setCount(n),
        );
      }).toList(),
    );
  }

  /// Card de check-in p/ esportes SEM sparring (musculação). Sem número.
  Widget _checkinCard(SportId sport) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: BoxDecoration(
        color: _ink.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hair),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.check, size: 30, color: _blood),
          const SizedBox(height: 12),
          Text('TREINEI — CHECK-IN', style: _eyebrow(_ink, 13)),
          const SizedBox(height: 6),
          Text(
            '${getSport(sport).label.toUpperCase()} NÃO TEM SPARRING.\nSÓ MARQUE O TREINO.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: _smoke,
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionalDivider() {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: _hair)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('OPCIONAL', style: _eyebrow(_smoke, 10)),
        ),
        Expanded(child: Container(height: 1, color: _hair)),
      ],
    );
  }

  Widget _intensityChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _intensities.entries.map((e) {
        return _Chip(
          label: e.value,
          selected: _intensity == e.key,
          onTap: () => _selectIntensity(e.key),
        );
      }).toList(),
    );
  }

  Widget _countSportChips(List<SportId> studentSports) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: studentSports.map((id) {
        return _Chip(
          label: (sports[id]?.labelShort ?? id.value).toUpperCase(),
          selected: _sport == id,
          onTap: () => setState(() => _sport = id),
        );
      }).toList(),
    );
  }

  Widget _countSaveBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        children: [
          if (_editing) ...[
            Pressable(
              onTap: _deleteLog,
              child: Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _blood, width: 1.6),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.delete_outline, color: _blood, size: 24),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Pressable(
              onTap: _saving ? null : _saveCount,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: _ink,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: _saving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: _bone, strokeWidth: 2.4),
                      )
                    : Text(
                        _editing ? 'SALVAR' : 'SALVAR TREINO',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.6,
                          color: _bone,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── FASE REWARD: criação/edição do self-log (verified nunca entra aqui) ───
  Widget _buildReward() {
    return Column(
      children: [
        // Voltar — sai do detalhe/edição sem precisar rolar até o botão.
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Row(
            children: [
              Pressable(
                onTap: _done,
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  child: const Icon(Icons.arrow_back, color: _ink, size: 24),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _rewardHeader(),
                const SizedBox(height: 28),
                const _SectionLabel('COMO FOI?'),
                const SizedBox(height: 10),
                _feelingChips(),
                const SizedBox(height: 24),
                const _SectionLabel('MODALIDADE'),
                const SizedBox(height: 10),
                _sportChips(),
                const SizedBox(height: 24),
                const _SectionLabel('DRILOU O QUÊ?'),
                const SizedBox(height: 10),
                _tokenField(
                  controller: _techCtrl,
                  hint: 'ex.: armlock, raspagem...',
                  onAdd: _addTech,
                  values: _techniques,
                  onRemove: _removeTech,
                ),
                const SizedBox(height: 24),
                const _SectionLabel('ROLOU COM QUEM?'),
                const SizedBox(height: 10),
                _tokenField(
                  controller: _partnerCtrl,
                  hint: 'nome do parceiro...',
                  onAdd: _addPartner,
                  values: _partners,
                  onRemove: _removePartner,
                ),
                const SizedBox(height: 24),
                const _SectionLabel('FOCO DO DIA'),
                const SizedBox(height: 10),
                _focoDoDiaField(),
              ],
            ),
          ),
        ),
        _doneBar(),
      ],
    );
  }

  Widget _rewardHeader() {
    final sport = _sport ?? SportId.bjj;
    final unit = sparringUnit(sport);
    final hasSparring = unit != null;
    final unitLabel = hasSparring
        ? (_rewardCount == 1 ? unit.one : unit.many).toUpperCase()
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
      decoration: BoxDecoration(
        color: _ink,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SuccessCheck(size: 26, color: _blood),
              const SizedBox(width: 10),
              Text(
                'REGISTRADO',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: _ash,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (hasSparring)
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedCountUp(
                  value: _rewardCount,
                  style: const TextStyle(
                    fontSize: 64,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    fontFeatures: _tabular,
                    letterSpacing: -2,
                    color: _bone,
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    unitLabel,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: _ash,
                    ),
                  ),
                ),
              ],
            )
          else
            const Text(
              'TREINO FEITO',
              style: TextStyle(
                fontSize: 34,
                height: 1.0,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                color: _bone,
              ),
            ),
          if (_showGraduationCaveat) ...[
            const SizedBox(height: 10),
            Text(
              'TREINO AVULSO · NÃO CONTA PRA FAIXA',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _ash,
              ),
            ),
          ],
          // "+N que seu último treino" — SÓ quando subiu (nunca desmotiva).
          if (_rewardDelta != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(LucideIcons.trendingUp, size: 15, color: _blood),
                const SizedBox(width: 8),
                Text(
                  '+$_rewardDelta QUE SEU ÚLTIMO TREINO',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: _blood,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _feelingChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _feelings.entries.map((e) {
        final sel = _feeling == e.key;
        return _Chip(
          label: e.value,
          selected: sel,
          onTap: () => _selectFeeling(e.key),
        );
      }).toList(),
    );
  }

  Widget _sportChips() {
    // Só os esportes que o aluno treina (não o catálogo inteiro). Legado/sem
    // ficha → BJJ.
    final studentSports =
        ref.watch(currentStudentProvider).valueOrNull?.getSports() ??
            const [SportId.bjj];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: studentSports.map((id) {
        final sel = _sport == id;
        return _Chip(
          label: (sports[id]?.labelShort ?? id.value).toUpperCase(),
          selected: sel,
          onTap: () => _selectSport(id),
        );
      }).toList(),
    );
  }

  Widget _tokenField({
    required TextEditingController controller,
    required String hint,
    required VoidCallback onAdd,
    required List<String> values,
    required ValueChanged<String> onRemove,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.words,
                onSubmitted: (_) => onAdd(),
                cursorColor: _blood,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(
                    color: _smoke,
                    fontWeight: FontWeight.w600,
                  ),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  filled: true,
                  fillColor: _ink.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: _ink.withValues(alpha: 0.12),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: _ink.withValues(alpha: 0.12),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _blood, width: 1.6),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Pressable(
              onTap: onAdd,
              child: Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: _ink,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add, color: _bone, size: 24),
              ),
            ),
          ],
        ),
        if (values.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values
                .map((v) => _Chip(
                      label: v.toUpperCase(),
                      selected: true,
                      onTap: () => onRemove(v),
                      trailingClose: true,
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }

  /// Campo opcional "FOCO DO DIA" — texto livre ≤140 chars, persiste em
  /// training_log.note via _patchLog. Nunca bloqueia o save (onSubmitted apenas
  /// dispara a persistência; _done() garante o patch mesmo sem Enter pressionado).
  Widget _focoDoDiaField() {
    return TextField(
      controller: _noteCtrl,
      maxLength: 140,
      maxLines: 2,
      minLines: 1,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: _blood,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: _ink,
        height: 1.4,
      ),
      decoration: InputDecoration(
        hintText: 'FOCO DO DIA — o que você treinou hoje?',
        hintStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: _smoke.withValues(alpha: 0.55),
        ),
        counterStyle: TextStyle(
          fontSize: 10,
          color: _smoke,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        filled: true,
        fillColor: _ink.withValues(alpha: 0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _ink.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _ink.withValues(alpha: 0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _blood, width: 1.6),
        ),
      ),
      onChanged: (v) => setState(() => _note = v.trim().isEmpty ? null : v.trim()),
      onSubmitted: (v) =>
          _patchLog({'note': v.trim().isEmpty ? FieldValue.delete() : v.trim()}),
    );
  }

  Widget _doneBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      child: Row(
        children: [
          if (_editing) ...[
            Pressable(
              onTap: _deleteLog,
              child: Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _blood, width: 1.6),
                ),
                alignment: Alignment.center,
                child:
                    const Icon(Icons.delete_outline, color: _blood, size: 24),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Pressable(
              onTap: _done,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: _ink,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  _editing ? 'PRONTO' : 'FECHOU',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                    color: _bone,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _centerNote(String title, String body, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 40, color: _smoke.withValues(alpha: 0.55)),
            const SizedBox(height: 20),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: _ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
              color: _smoke,
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers de formatação / cor da jornada ────────────────────────────────

  /// Cor da faixa real, com guard de luminância: faixas muito claras (branca)
  /// caem para um cinza visível sobre o card branco.
  Color _beltColor(SportId sport, String belt) {
    final c = getGradeColor(sport, belt);
    return c.computeLuminance() > 0.85 ? const Color(0xFF9CA3AF) : c;
  }

  /// Rótulo do marco: "FAIXA AZUL" (troca de faixa) ou "2º GRAU AZUL" (grau).
  String _gradLabel(SportId sport, FighterGraduation g) {
    final label = getGradeLabel(sport, g.belt).toUpperCase();
    if (g.isBeltChange) return 'FAIXA $label';
    return '${g.stripes}º GRAU $label';
  }

  String _positionLabel(String position) {
    switch (position) {
      case 'gold':
        return 'OURO';
      case 'silver':
        return 'PRATA';
      case 'bronze':
        return 'BRONZE';
      default:
        return 'PARTICIPAÇÃO';
    }
  }

  String _monthsLabel(int m) => m == 1 ? '1 MÊS' : '$m MESES';

  String _gradesLabel(int g) => g == 1 ? '+1 GRAU' : '+$g GRAUS';

  String _dmy(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  TextStyle _eyebrow(Color c, double size) => TextStyle(
        color: c,
        fontSize: size,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      );

  Widget _miniSportChip(SportId sport) {
    final label = sports[sport]?.labelShort ?? sport.value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _bone,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _hair),
      ),
      child: Text(label.toUpperCase(), style: _eyebrow(_ink, 9)),
    );
  }

  Widget _sectionHeader(String text, {VoidCallback? onAdd}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 2),
      child: Row(
        children: [
          Container(width: 14, height: 2, color: _blood),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.8,
              color: _ink,
            ),
          ),
          if (onAdd != null) ...[
            const Spacer(),
            Pressable(
              onTap: onAdd,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, size: 16, color: _blood),
                  const SizedBox(width: 4),
                  Text('ADICIONAR', style: _eyebrow(_blood, 11)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Linha do histórico unificado ────────────────────────────────────────────

class _TrainRow extends StatelessWidget {
  final TrainEntry entry;

  /// null → linha não navega (verified é read-only pelo lutador).
  final VoidCallback? onTap;
  const _TrainRow({required this.entry, this.onTap});

  @override
  Widget build(BuildContext context) {
    const ink = _DiarioScreenState._ink;
    const smoke = _DiarioScreenState._smoke;
    final d = entry.date;
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

    // Subtítulo: verified = professor; self = número + brief (sensação/téc/parc).
    final String subtitle;
    if (entry.isSelf) {
      subtitle = <String>[
        _countLabel(entry),
        if (entry.feeling != null)
          _DiarioScreenState._feelings[entry.feeling!] ?? '',
        if (entry.techniques.isNotEmpty) '${entry.techniques.length} TÉC',
        if (entry.partners.isNotEmpty) '${entry.partners.length} PARC',
      ].where((s) => s.isNotEmpty).join(' · ');
    } else {
      subtitle = (entry.subtitle ?? '').toUpperCase();
    }

    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: ink.withValues(alpha: 0.10))),
      ),
      child: Row(
        children: [
          _SourceBadge(source: entry.source),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: ink,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: smoke,
                    ),
                  ),
                ],
                // Nota "FOCO DO DIA" — só self-log, 3ª linha discreta.
                if (entry.isSelf &&
                    entry.note != null &&
                    entry.note!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    entry.note!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                      color: smoke.withValues(alpha: 0.8),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            dateStr,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: smoke,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          // Self → editar (chevron). Verified → anexar rolas ("+ ROLAS").
          if (entry.isSelf) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right,
                size: 18, color: smoke.withValues(alpha: 0.7)),
          ] else if (onTap != null) ...[
            const SizedBox(width: 8),
            Text('+ ROLAS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: _DiarioScreenState._blood,
                )),
          ],
        ],
      ),
    );

    if (onTap == null) return row;
    return Pressable(onTap: onTap, child: row);
  }

  /// Rótulo do número do dia usando a UNIDADE do esporte (multi-modal).
  /// Ex.: "8 ROLAS", "5 ROUNDS". Vazio quando não há count.
  String _countLabel(TrainEntry e) {
    if (e.sparringCount <= 0) return '';
    final sportId =
        e.sport != null ? SportId.fromString(e.sport!) : SportId.bjj;
    final unit = sparringUnit(sportId);
    if (unit == null) return '';
    final u = (e.sparringCount == 1 ? unit.one : unit.many).toUpperCase();
    return '${e.sparringCount} $u';
  }
}

/// Selo de procedência: VERIFICADO (academia) vs AUTO (self-log).
class _SourceBadge extends StatelessWidget {
  final TrainSource source;
  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    const ink = _DiarioScreenState._ink;
    const bone = _DiarioScreenState._bone;
    final verified = source == TrainSource.verified;
    return Container(
      width: 92,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: verified ? ink : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: verified ? ink : ink.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Text(
        verified ? 'VERIFICADO' : 'AUTO',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.0,
          color: verified ? bone : ink,
        ),
      ),
    );
  }
}

// ── Componentes anti-slop reutilizados na tela ──────────────────────────────

class _Kicker extends StatelessWidget {
  final String text;
  const _Kicker(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 2.0,
        color: _DiarioScreenState._blood,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        color: _DiarioScreenState._ink,
      ),
    );
  }
}

/// Botão de repetição: tap único dispara uma vez; long-press acelera (repeat
/// 120ms). Usado no stepper do logger count-first (± sparrings).
class _RepeatButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool enabled;
  const _RepeatButton({
    required this.child,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton> {
  Timer? _timer;

  void _start() {
    widget.onTap();
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) => widget.onTap(),
    );
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      onLongPressStart: widget.enabled ? (_) => _start() : null,
      onLongPressEnd: widget.enabled ? (_) => _stop() : null,
      onLongPressCancel: _stop,
      child: widget.child,
    );
  }
}

/// Chip retangular (lê como fightwear): raio 8, sem pílula.
class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool trailingClose;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailingClose = false,
  });

  @override
  Widget build(BuildContext context) {
    const ink = _DiarioScreenState._ink;
    const bone = _DiarioScreenState._bone;
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? ink : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? ink : ink.withValues(alpha: 0.18),
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: selected ? bone : ink,
              ),
            ),
            if (trailingClose) ...[
              const SizedBox(width: 6),
              const Icon(Icons.close, size: 14, color: bone),
            ],
          ],
        ),
      ),
    );
  }
}
