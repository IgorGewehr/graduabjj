import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/combo.dart';
import '../../providers/providers.dart';
import '../../services/combo_service.dart';
import '../../services/firebase_service.dart';
import '../../widgets/polish/polish.dart';

const _strikingSports = [SportId.muaythai, SportId.boxing, SportId.kickboxing];

String _sportLabel(String v) {
  switch (v) {
    case 'boxing':
      return 'Boxe';
    case 'kickboxing':
      return 'Kickboxing';
    case 'muaythai':
      return 'Muay Thai';
    default:
      return v;
  }
}

/// Portal "Combinações" (C2) — read-only library filtered to the student's
/// striking sports, grouped by sport + level.
class CombosViewScreen extends ConsumerStatefulWidget {
  const CombosViewScreen({super.key});

  @override
  ConsumerState<CombosViewScreen> createState() => _CombosViewScreenState();
}

class _CombosViewScreenState extends ConsumerState<CombosViewScreen> {
  late final ComboService _service = ComboService(FirebaseService.academyId);

  bool _loading = true;
  List<String> _sports = const [];
  String? _sport;
  List<Combo> _combos = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final student = await ref.read(currentStudentProvider.future);
    final striking = student
            ?.getSports()
            .where(_strikingSports.contains)
            .map((s) => s.value)
            .toList() ??
        const [];
    _sports = striking.isNotEmpty
        ? striking
        : _strikingSports.map((s) => s.value).toList();
    _sport = _sports.first;
    await _load();
  }

  Future<void> _load() async {
    if (_sport == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final list = await _service.getBySport(_sport!);
      if (!mounted) return;
      setState(() {
        _combos = list.where((c) => c.active).toList()
          ..sort((a, b) {
            final l =
                comboLevelOrder(a.level).compareTo(comboLevelOrder(b.level));
            return l != 0 ? l : a.order.compareTo(b.order);
          });
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openVideo(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Combinações')),
      body: Column(
        children: [
          if (_sports.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 8,
                children: _sports
                    .map((v) => ChoiceChip(
                          label: Text(_sportLabel(v)),
                          selected: _sport == v,
                          onSelected: (_) {
                            setState(() => _sport = v);
                            _load();
                          },
                        ))
                    .toList(),
              ),
            ),
          Expanded(
            child: _loading
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: PolishSkeleton.list(count: 6, scrollable: false))
                : _combos.isEmpty
                    ? const PolishedEmptyState(
                        icon: LucideIcons.swords,
                        title: 'Sem combinações',
                        subtitle:
                            'Seu instrutor ainda não cadastrou combinações para esta modalidade.',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _list(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    final children = <Widget>[];
    String? lastLevel;
    for (final c in _combos) {
      if (c.level != lastLevel) {
        lastLevel = c.level;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(comboLevelLabel(c.level),
              style:
                  AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700)),
        ));
      }
      children.add(_card(c));
    }
    return ListView(
        padding: const EdgeInsets.only(bottom: 24), children: children);
  }

  Widget _card(Combo c) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(c.name,
                      style: AppTheme.titleSmall
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
                if (c.videoUrl != null && c.videoUrl!.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _openVideo(c.videoUrl!),
                    icon: const Icon(LucideIcons.playCircle, size: 16),
                    label: const Text('Vídeo'),
                  ),
              ],
            ),
            if (c.strikes.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < c.strikes.length; i++) ...[
                    if (i > 0)
                      const Icon(LucideIcons.chevronRight,
                          size: 14, color: AppTheme.textSecondary),
                    Chip(
                      label: Text(c.strikes[i], style: AppTheme.bodySmall),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ],
              ),
            if (c.description != null && c.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(c.description!,
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}
