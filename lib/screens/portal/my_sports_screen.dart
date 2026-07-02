import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../widgets/polish/polish.dart';

// =============================================================================
// Fighter tokens — bone canvas, white cards, ink text, ONE red accent.
// Belt colours (getGradeColor) only ever represent a REAL faixa — never UI
// chrome.
// =============================================================================
class _T {
  _T._();
  static const bone = Color(0xFFF4F3EF);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0A0A0A);
  static const blood = Color(0xFFE0301E);
  static const smoke = Color(0xFF6E6E68);
  static const ash = Color(0xFF9A9A93);
  static const hair = Color(0x14000000); // 8% ink hairline
}

/// MODALIDADES — the student's single management surface for the sports they
/// train. Add a modality from the catalog (a sport the academy teaches enters
/// VERIFIED/locked; anything else is self-declared), pick the primary one, and
/// drop a self-declared modality. Verified modalities are read-only: the student
/// never writes to `beltProgressions` — the grade shown here is the verified
/// ceiling.
///
/// The portal shell (portal_shell.dart) provides the Scaffold + bone canvas, so
/// this screen returns body content directly.
class MySportsScreen extends ConsumerWidget {
  const MySportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentAsync = ref.watch(currentStudentProvider);

    return studentAsync.when(
      data: (student) {
        if (student == null) return _buildNoStudentState();

        // Which sports the academy actually teaches (has a turma for). Sports
        // here enter the student as VERIFIED/locked; everything else is
        // self-declared. Legacy classes without a `sport` field count as BJJ.
        final academySports = (ref.watch(classesProvider).valueOrNull ?? [])
            .map((c) => c.getSport())
            .toSet();

        final sports = student.getSports();
        final primary = student.getPrimarySport();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _Header(
              count: sports.length,
              onAdd: () => _showAddSheet(context, ref, student, academySports),
            ).fadeInQuick(),
            const SizedBox(height: 18),
            for (var i = 0; i < sports.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _SportCard(
                  student: student,
                  sport: sports[i],
                  isPrimary: sports[i] == primary,
                  isVerified: !_isSelfDeclared(student, sports[i]),
                  canRemove:
                      _isSelfDeclared(student, sports[i]) && sports.length > 1,
                  onSetPrimary: sports[i] == primary
                      ? null
                      : () => _setPrimary(context, ref, student, sports[i]),
                  onRemove: () => _removeSport(context, ref, student, sports[i]),
                ).entrance(index: i),
              ),
          ],
        );
      },
      loading: () => ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [PolishSkeleton.list(count: 4)],
      ),
      error: (error, stack) => _buildNoStudentState(),
    );
  }

  Widget _buildNoStudentState() {
    return const PolishedEmptyState(
      icon: LucideIcons.dumbbell,
      title: 'Conta nao vinculada',
      subtitle: 'Vincule sua conta a um aluno para gerenciar suas modalidades.',
    );
  }

  /// A modality is self-declared (auto) when the student added it themselves and
  /// the academy never seeded a verified grade for it: the sport is in
  /// `getSports()` but has NO entry in the STAFF-ONLY `sportData` map. VERIFIED =
  /// `sportData` carries the sport key (seeded by the academy on enrollment /
  /// promotion). The student never writes `sportData`, so its presence is the
  /// trustworthy signal.
  static bool _isSelfDeclared(Student student, SportId sport) {
    return student.sportData?[sport.value] == null;
  }

  // ===========================================================================
  // Mutations
  // ===========================================================================

  void _showAddSheet(
    BuildContext context,
    WidgetRef ref,
    Student student,
    Set<SportId> academySports,
  ) {
    final enrolled = student.getSports().toSet();
    final available =
        sportOptions.where((s) => !enrolled.contains(s)).toList();

    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddSportSheet(
        available: available,
        academySports: academySports,
        onPick: (sport) {
          Navigator.of(ctx).pop();
          _enroll(context, ref, student, sport,
              verified: academySports.contains(sport));
        },
      ),
    );
  }

  Future<void> _enroll(
    BuildContext context,
    WidgetRef ref,
    Student student,
    SportId sport, {
    required bool verified,
  }) async {
    final service = ref.read(studentServiceProvider);
    if (service == null) return;
    try {
      // The student manages ONLY the safe fields `sports` and `primarySport`.
      // `sportData` is STAFF-ONLY (the VERIFIED ceiling the CF trusts), so we
      // never seed it here — a self-declared sport simply has no `sportData`
      // entry, which the self-graduation guard reads as "no ceiling".
      final updates = <String, dynamic>{
        // Write the FULL sports list (not arrayUnion): a legacy student whose
        // `sports` field is absent trains an implicit BJJ — `getSports()`
        // carries it, so adding the first extra sport must not drop BJJ.
        'sports': <String>{
          ...student.getSports().map((s) => s.value),
          sport.value,
        }.toList(),
      };

      // The student always has an effective primary (implicit BJJ at minimum).
      // Only backfill the field when the doc has none, and to the EXISTING
      // primary — never to the sport just added.
      if (student.primarySport == null || student.primarySport!.isEmpty) {
        updates['primarySport'] = student.getPrimarySport().value;
      }

      await service.update(student.id, updates);
      ref.invalidate(currentStudentProvider);
      if (context.mounted) {
        context.showSuccess(verified
            ? '${getSport(sport).label} adicionada (verificada)'
            : '${getSport(sport).label} adicionada');
      }
    } catch (e) {
      if (context.mounted) context.showError('Erro ao adicionar: $e');
    }
  }

  Future<void> _setPrimary(
    BuildContext context,
    WidgetRef ref,
    Student student,
    SportId sport,
  ) async {
    final service = ref.read(studentServiceProvider);
    if (service == null) return;
    HapticFeedback.selectionClick();
    try {
      await service.updatePrimarySport(student.id, sport);
      ref.invalidate(currentStudentProvider);
      if (context.mounted) {
        context.showSuccess('${getSport(sport).label} e a modalidade principal');
      }
    } catch (e) {
      if (context.mounted) context.showError('Erro: $e');
    }
  }

  Future<void> _removeSport(
    BuildContext context,
    WidgetRef ref,
    Student student,
    SportId sport,
  ) async {
    final remaining = student
        .getSports()
        .where((s) => s != sport)
        .map((s) => s.value)
        .toList();
    if (remaining.isEmpty) {
      context.showError('Voce precisa manter ao menos uma modalidade.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _T.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Remover modalidade?',
            style: TextStyle(
                color: _T.ink, fontWeight: FontWeight.w800, fontSize: 17)),
        content: Text(
          'Voce nao treina mais ${getSport(sport).label}? Ela sai do seu perfil. '
          'Modalidades verificadas pela academia nao podem ser removidas aqui.',
          style: const TextStyle(color: _T.smoke, fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: _T.smoke, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remover',
                style:
                    TextStyle(color: _T.blood, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final service = ref.read(studentServiceProvider);
    if (service == null) return;
    try {
      // Only self-declared sports reach here (canRemove gates verified ones),
      // and the student writes ONLY `sports` — `sportData` is STAFF-ONLY, so we
      // never FieldValue.delete it. A self-declared sport has no `sportData`
      // entry to remove anyway.
      final updates = <String, dynamic>{
        'sports': remaining,
      };
      // Reassign the primary if we just removed it.
      if (student.getPrimarySport() == sport) {
        updates['primarySport'] = remaining.first;
      }
      await service.update(student.id, updates);
      ref.invalidate(currentStudentProvider);
      if (context.mounted) {
        context.showSuccess('${getSport(sport).label} removida');
      }
    } catch (e) {
      if (context.mounted) context.showError('Erro ao remover: $e');
    }
  }
}

// =============================================================================
// Header
// =============================================================================
class _Header extends StatelessWidget {
  const _Header({required this.count, required this.onAdd});

  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MODALIDADES',
                style: TextStyle(
                  color: _T.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                count == 1 ? '1 MODALIDADE' : '$count MODALIDADES',
                style: const TextStyle(
                  color: _T.smoke,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _AddButton(onTap: onAdd),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _T.ink,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.plus, size: 16, color: Colors.white),
              SizedBox(width: 6),
              Text(
                'ADICIONAR',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Sport card
// =============================================================================
class _SportCard extends StatelessWidget {
  const _SportCard({
    required this.student,
    required this.sport,
    required this.isPrimary,
    required this.isVerified,
    required this.canRemove,
    required this.onSetPrimary,
    required this.onRemove,
  });

  final Student student;
  final SportId sport;
  final bool isPrimary;
  final bool isVerified;
  final bool canRemove;

  /// Null when this sport is already the primary (radio already selected).
  final VoidCallback? onSetPrimary;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final def = getSport(sport);
    final grade = student.getGrade(sport);

    return Container(
      decoration: BoxDecoration(
        color: _T.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.hair),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Neutral icon box (no sport chroma — fighter style).
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _T.bone,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _T.hair),
                ),
                child: Icon(def.icon, color: _T.ink, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      def.label.toUpperCase(),
                      style: const TextStyle(
                        color: _T.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    _GradeLine(sport: sport, grade: grade),
                  ],
                ),
              ),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(LucideIcons.trash2,
                      size: 18, color: _T.ash),
                  tooltip: 'Remover modalidade',
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _SealChip(verified: isVerified),
              _PrimaryChip(isPrimary: isPrimary, onTap: onSetPrimary),
              _StartChip(label: _startLabel()),
            ],
          ),
        ],
      ),
    );
  }

  /// Reads `sportData[sport].startDate` defensively. Returns null when absent or
  /// of an unexpected type — never throws.
  String? _startLabel() {
    final raw = student.sportData?[sport.value];
    if (raw is! Map) return null;
    final value = raw['startDate'];
    DateTime? date;
    if (value is DateTime) {
      date = value;
    } else if (value is String && value.isNotEmpty) {
      date = DateTime.tryParse(value);
    } else if (value is Timestamp) {
      date = value.toDate();
    }
    if (date == null) return null;
    return DateFormat('MMM yyyy', 'pt_BR').format(date);
  }
}

class _GradeLine extends StatelessWidget {
  const _GradeLine({required this.sport, required this.grade});

  final SportId sport;
  final ({String currentGrade, int currentStripes})? grade;

  @override
  Widget build(BuildContext context) {
    if (grade == null) {
      return const Text(
        'Sem graduacao',
        style: TextStyle(
            color: _T.ash, fontSize: 12.5, fontWeight: FontWeight.w600),
      );
    }
    // Belt colour here represents the REAL faixa — the one place colour is
    // allowed. None-grade sports (musculacao/boxe/mma) return no grade above.
    final beltColor = getGradeColor(sport, grade!.currentGrade);
    final label = getGradeLabel(sport, grade!.currentGrade);
    final stripes = grade!.currentStripes;
    final text = stripes > 0
        ? '$label · ${stripes == 1 ? '1 grau' : '$stripes graus'}'
        : label;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: beltColor,
            shape: BoxShape.circle,
            border: Border.all(color: _T.hair),
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
                color: _T.smoke, fontSize: 12.5, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// VERIFICADO (academy-confirmed / has progression) vs AUTO-DECLARADO (self).
class _SealChip extends StatelessWidget {
  const _SealChip({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: verified ? _T.ink : _T.bone,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: verified ? _T.ink : _T.hair),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? LucideIcons.badgeCheck : LucideIcons.userCheck,
            size: 12,
            color: verified ? Colors.white : _T.smoke,
          ),
          const SizedBox(width: 5),
          Text(
            verified ? 'VERIFICADO' : 'AUTO-DECLARADO',
            style: TextStyle(
              color: verified ? Colors.white : _T.smoke,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Primary radio: filled red "PRINCIPAL" when selected, tappable outline
/// "DEFINIR PRINCIPAL" otherwise. Only one sport is primary at a time.
class _PrimaryChip extends StatelessWidget {
  const _PrimaryChip({required this.isPrimary, required this.onTap});

  final bool isPrimary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (isPrimary) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _T.blood,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.star, size: 12, color: Colors.white),
            SizedBox(width: 5),
            Text(
              'PRINCIPAL',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _T.hair),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.star, size: 12, color: _T.ash),
              SizedBox(width: 5),
              Text(
                'DEFINIR PRINCIPAL',
                style: TextStyle(
                  color: _T.smoke,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartChip extends StatelessWidget {
  const _StartChip({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    if (label == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.calendar, size: 12, color: _T.ash),
        const SizedBox(width: 4),
        Text(
          'Desde $label',
          style: const TextStyle(
              color: _T.ash, fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// =============================================================================
// Add-sport bottom sheet
// =============================================================================
class _AddSportSheet extends StatelessWidget {
  const _AddSportSheet({
    required this.available,
    required this.academySports,
    required this.onPick,
  });

  final List<SportId> available;
  final Set<SportId> academySports;
  final ValueChanged<SportId> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _T.bone,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _T.hair,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'ADICIONAR MODALIDADE',
            style: TextStyle(
              color: _T.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Esportes que a academia ensina entram verificados. Os demais ficam como auto-declarados.',
            style: TextStyle(color: _T.smoke, fontSize: 12.5, height: 1.35),
          ),
          const SizedBox(height: 16),
          if (available.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Voce ja treina todas as modalidades do catalogo.',
                  style: TextStyle(color: _T.smoke, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: available.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final sport = available[i];
                  return _AddSportRow(
                    sport: sport,
                    verified: academySports.contains(sport),
                    onTap: () => onPick(sport),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _AddSportRow extends StatelessWidget {
  const _AddSportRow({
    required this.sport,
    required this.verified,
    required this.onTap,
  });

  final SportId sport;
  final bool verified;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final def = getSport(sport);
    return Material(
      color: _T.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _T.hair),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _T.bone,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: _T.hair),
                ),
                child: Icon(def.icon, color: _T.ink, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      def.label,
                      style: const TextStyle(
                        color: _T.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      verified ? 'TURMA NA ACADEMIA' : 'AUTO-DECLARADO',
                      style: TextStyle(
                        color: verified ? _T.ink : _T.smoke,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.plus, size: 18, color: _T.ash),
            ],
          ),
        ),
      ),
    );
  }
}
