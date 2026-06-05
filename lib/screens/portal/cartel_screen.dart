import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/cartel.dart';
import '../../core/theme.dart';
import '../../models/fight_record.dart';
import '../../providers/providers.dart';
import '../../services/fight_record_service.dart';
import '../../services/firebase_service.dart';
import '../../widgets/polish/polish.dart';

String _sportLabel(String? v) {
  switch (v) {
    case 'boxing':
      return 'Boxe';
    case 'kickboxing':
      return 'Kickboxing';
    case 'muaythai':
      return 'Muay Thai';
    default:
      return '';
  }
}

Color _resultColor(FightResult r) {
  switch (r) {
    case FightResult.win:
      return AppTheme.success;
    case FightResult.loss:
      return AppTheme.error;
    case FightResult.draw:
      return AppTheme.warning;
    case FightResult.nc:
      return AppTheme.textSecondary;
  }
}

/// Portal "Meu cartel" (C3) — read-only fighter record (staff manage it).
class CartelScreen extends ConsumerStatefulWidget {
  const CartelScreen({super.key});

  @override
  ConsumerState<CartelScreen> createState() => _CartelScreenState();
}

class _CartelScreenState extends ConsumerState<CartelScreen> {
  late final FightRecordService _service =
      FightRecordService(FirebaseService.academyId);

  bool _loading = true;
  List<FightRecord> _fights = [];

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
      final list = await _service.getByStudent(student.id);
      if (!mounted) return;
      setState(() {
        _fights = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meu cartel')),
      body: _loading
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: PolishSkeleton.list(count: 4, scrollable: false),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _summaryCard(summarizeCartel(_fights.map((f) => f.pair))),
                  const SizedBox(height: 16),
                  if (_fights.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: PolishedEmptyState(
                        icon: LucideIcons.swords,
                        title: 'Cartel vazio',
                        subtitle:
                            'Seu instrutor ainda não registrou nenhuma luta.',
                      ),
                    )
                  else
                    ..._fights.map(_fightCard),
                ],
              ),
            ),
    );
  }

  Widget _summaryCard(CartelSummary s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(s.record,
                style: AppTheme.headlineLarge.copyWith(
                    fontWeight: FontWeight.w800, color: AppTheme.primary)),
            const SizedBox(height: 4),
            Text('${s.total} ${s.total == 1 ? 'luta' : 'lutas'}',
                style: AppTheme.bodySmall
                    .copyWith(color: AppTheme.textSecondary)),
            if (s.koWins > 0 || s.subWins > 0) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (s.koWins > 0)
                    Chip(label: Text('${s.koWins} por nocaute')),
                  if (s.subWins > 0)
                    Chip(label: Text('${s.subWins} por finalização')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fightCard(FightRecord f) {
    final dd = f.date.day.toString().padLeft(2, '0');
    final mm = f.date.month.toString().padLeft(2, '0');
    final color = _resultColor(f.result);
    final sub = <String>[
      f.method.label,
      if (f.opponent != null && f.opponent!.isNotEmpty) 'vs ${f.opponent}',
      if (f.weightClass != null && f.weightClass!.isNotEmpty) f.weightClass!,
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text(f.result.tag,
              style: AppTheme.bodyMedium
                  .copyWith(color: color, fontWeight: FontWeight.w800)),
        ),
        title: Text('${f.event} · $dd/$mm/${f.date.year}',
            style: AppTheme.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text([
          sub.join(' · '),
          if (f.sport != null) _sportLabel(f.sport),
        ].where((e) => e.isNotEmpty).join('\n')),
        isThreeLine: f.sport != null,
        trailing: (f.videoUrl != null && f.videoUrl!.isNotEmpty)
            ? IconButton(
                icon: const Icon(LucideIcons.playCircle),
                color: AppTheme.primary,
                onPressed: () => _openVideo(f.videoUrl!),
              )
            : null,
      ),
    );
  }

  Future<void> _openVideo(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
