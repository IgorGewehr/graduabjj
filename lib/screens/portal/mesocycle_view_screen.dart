import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/meso.dart';
import '../../core/theme.dart';
import '../../models/mesocycle.dart';
import '../../providers/providers.dart';
import '../../services/firebase_service.dart';
import '../../services/mesocycle_service.dart';
import '../../widgets/polish/polish.dart';

/// Portal "Periodização" (E1) — read-only view of the student's assigned
/// mesocycles, with the current week highlighted when a start date is set.
class MesocycleViewScreen extends ConsumerStatefulWidget {
  const MesocycleViewScreen({super.key});

  @override
  ConsumerState<MesocycleViewScreen> createState() =>
      _MesocycleViewScreenState();
}

class _MesocycleViewScreenState extends ConsumerState<MesocycleViewScreen> {
  late final MesocycleService _service =
      MesocycleService(FirebaseService.academyId);
  bool _loading = true;
  List<Mesocycle> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final student = await ref.read(currentStudentProvider.future);
    if (student == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final list = await _service.getForStudent(
          studentId: student.id, sports: student.getSports());
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Periodização')),
      body: _loading
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: PolishSkeleton.list(count: 4, scrollable: false))
          : _items.isEmpty
              ? const PolishedEmptyState(
                  icon: LucideIcons.calendarRange,
                  title: 'Sem periodização',
                  subtitle:
                      'Seu professor ainda não liberou um programa de semanas.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: _items.map(_mesoCard).toList(),
                  ),
                ),
    );
  }

  Widget _mesoCard(Mesocycle m) {
    final current = currentMesoWeek(m.startDate, DateTime.now(), m.totalWeeks);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.name,
                style:
                    AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700)),
            if (m.description != null && m.description!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(m.description!,
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textSecondary)),
            ],
            if (current != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Você está na semana $current de ${m.totalWeeks}',
                    style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.primary, fontWeight: FontWeight.w700)),
              ),
            ],
            const SizedBox(height: 10),
            for (final w in m.weeks) _weekRow(w, w.index == current),
          ],
        ),
      ),
    );
  }

  Widget _weekRow(MesoWeek w, bool isCurrent) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppTheme.primary.withValues(alpha: 0.08)
            : AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: isCurrent
            ? Border.all(color: AppTheme.primary.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: w.deload
                ? AppTheme.warning.withValues(alpha: 0.18)
                : AppTheme.primary.withValues(alpha: 0.14),
            child: Text('${w.index}',
                style: AppTheme.bodySmall.copyWith(
                    fontWeight: FontWeight.w800,
                    color: w.deload ? AppTheme.warning : AppTheme.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (w.focus.isNotEmpty)
                      Text(w.focus,
                          style: AppTheme.bodyMedium
                              .copyWith(fontWeight: FontWeight.w600)),
                    if (w.deload) ...[
                      const SizedBox(width: 6),
                      Text('deload',
                          style: AppTheme.bodySmall
                              .copyWith(color: AppTheme.warning)),
                    ],
                  ],
                ),
                if (w.prescription.isNotEmpty)
                  Text(w.prescription,
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
