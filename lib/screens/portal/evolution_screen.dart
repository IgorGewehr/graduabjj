import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/body_composition.dart';
import '../../core/number_format.dart';
import '../../core/theme.dart';
import '../../models/physical_assessment.dart';
import '../../models/student.dart';
import '../../providers/providers.dart';
import '../../widgets/cached_image.dart';

/// Portal "Minha Evolução" — student-facing physical-assessment progress:
/// snapshot + deltas vs. previous, time-series charts (fl_chart) and
/// before/after photo comparison. Read-only; assessments are created by staff.
class EvolutionScreen extends ConsumerWidget {
  const EvolutionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The portal shell (portal_shell.dart) already provides the Scaffold,
    // AppBar and bottom nav, so this screen returns body content directly —
    // adding our own Scaffold/AppBar here would stack a second app bar.
    final studentAsync = ref.watch(currentStudentProvider);
    return studentAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _Message(
        icon: LucideIcons.alertTriangle,
        title: 'Erro ao carregar',
        subtitle: '$e',
        onRetry: () => ref.invalidate(currentStudentProvider),
      ),
      data: (student) {
        if (student == null) {
          return const _Message(
            icon: LucideIcons.userX,
            title: 'Perfil não vinculado',
            subtitle: 'Sua conta ainda não está vinculada a um aluno.',
          );
        }
        final listAsync =
            ref.watch(studentPhysicalAssessmentsProvider(student.id));
        return listAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Message(
            icon: LucideIcons.alertTriangle,
            title: 'Erro ao carregar',
            subtitle: '$e',
            onRetry: () =>
                ref.invalidate(studentPhysicalAssessmentsProvider(student.id)),
          ),
          data: (assessments) {
            if (assessments.isEmpty) {
              return RefreshIndicator(
                onRefresh: () => ref.refresh(
                    studentPhysicalAssessmentsProvider(student.id).future),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 80),
                    _Message(
                      icon: LucideIcons.lineChart,
                      title: 'Nenhuma avaliação ainda',
                      subtitle:
                          'As avaliações físicas registradas pelo seu '
                          'instrutor aparecerão aqui — com gráficos de '
                          'evolução e comparação de fotos.',
                    ),
                  ],
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () {
                // Also refresh the student so a just-set goal/meta shows up.
                ref.invalidate(currentStudentProvider);
                return ref.refresh(
                    studentPhysicalAssessmentsProvider(student.id).future);
              },
              child: _EvolutionContent(
                  assessments: assessments, student: student),
            );
          },
        );
      },
    );
  }
}

/// One charted metric extracted from an assessment.
class _Metric {
  final String key;
  final String label;
  final String unit;
  final double? Function(PhysicalAssessment) extract;
  const _Metric(this.key, this.label, this.unit, this.extract);
}

class _EvolutionContent extends StatefulWidget {
  /// Most-recent first (as returned by the service).
  final List<PhysicalAssessment> assessments;
  final Student student;
  const _EvolutionContent({required this.assessments, required this.student});

  @override
  State<_EvolutionContent> createState() => _EvolutionContentState();
}

class _EvolutionContentState extends State<_EvolutionContent> {
  static const _allMetrics = <_Metric>[
    _Metric('weight', 'Peso', 'kg', _weight),
    _Metric('bmi', 'IMC', '', _bmi),
    _Metric('bodyFat', '% Gordura', '%', _bodyFat),
    _Metric('leanMass', 'Massa magra', 'kg', _leanMass),
    _Metric('fatMass', 'Massa gorda', 'kg', _fatMass),
    _Metric('visceral', 'G. visceral', '', _visceral),
    _Metric('bmr', 'TMB', 'kcal', _bmr),
    _Metric('waist', 'Cintura', 'cm', _waist),
    _Metric('hip', 'Quadril', 'cm', _hip),
  ];

  static double? _weight(PhysicalAssessment a) => a.weightKg;
  static double? _bmi(PhysicalAssessment a) => a.bmi;
  static double? _bodyFat(PhysicalAssessment a) => a.bodyFatPct;
  // Lean/fat mass: prefer the stored (manual/bioimpedance) value, else derive
  // from weight + % gordura so charts work even without a device reading.
  static double? _leanMass(PhysicalAssessment a) =>
      a.leanMassKg ?? _derivedSplit(a)?.leanMassKg;
  static double? _fatMass(PhysicalAssessment a) =>
      a.fatMassKg ?? _derivedSplit(a)?.fatMassKg;

  static ({double fatMassKg, double leanMassKg})? _derivedSplit(
      PhysicalAssessment a) {
    final w = a.weightKg, bf = a.bodyFatPct;
    if (w == null || bf == null) return null;
    return bodyMassSplit(weightKg: w, bodyFatPct: bf);
  }
  static double? _visceral(PhysicalAssessment a) => a.visceralFatLevel;
  static double? _bmr(PhysicalAssessment a) => a.bmrKcal;
  static double? _waist(PhysicalAssessment a) => a.measurements['waist'];
  static double? _hip(PhysicalAssessment a) => a.measurements['hip'];

  static const _photoLabels = {
    'front': 'Frente', 'side': 'Lado', 'back': 'Costas',
  };

  static const _goalLabels = {
    'hipertrofia': 'Hipertrofia', 'emagrecimento': 'Emagrecimento',
    'condicionamento': 'Condicionamento', 'manutencao': 'Manutenção',
  };

  late List<PhysicalAssessment> _desc; // most-recent first
  late List<PhysicalAssessment> _asc; // oldest first

  // Pre-computed ascending series per metric.
  final Map<String, List<({DateTime date, double value})>> _series = {};
  late List<_Metric> _chartable;
  String _metricKey = '';

  late List<String> _anglesWithPhotos;
  String _angle = '';

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(covariant _EvolutionContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The provider hands a NEW list instance on refresh; the State is reused,
    // so recompute the derived data instead of showing stale values.
    if (!identical(oldWidget.assessments, widget.assessments)) _recompute();
  }

  /// (Re)derives series, chartable metrics and photo angles from
  /// [widget.assessments]. Keeps the current metric/angle selection when it is
  /// still valid; otherwise falls back to the first available.
  void _recompute() {
    _desc = widget.assessments;
    _asc = widget.assessments.reversed.toList();

    _series.clear();
    for (final m in _allMetrics) {
      final pts = <({DateTime date, double value})>[];
      for (final a in _asc) {
        final v = m.extract(a);
        if (v != null) pts.add((date: a.date, value: v));
      }
      _series[m.key] = pts;
    }
    // Only metrics with ≥2 points can form a line.
    _chartable =
        _allMetrics.where((m) => (_series[m.key]?.length ?? 0) >= 2).toList();
    if (_chartable.every((m) => m.key != _metricKey)) {
      _metricKey = _chartable.isNotEmpty ? _chartable.first.key : '';
    }

    _anglesWithPhotos = ['front', 'side', 'back']
        .where((angle) =>
            _asc.any((a) => a.photos.any((p) => p.angle == angle)))
        .toList();
    if (!_anglesWithPhotos.contains(_angle)) {
      _angle = _anglesWithPhotos.isNotEmpty ? _anglesWithPhotos.first : '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _snapshotCard(),
        ..._metaSection(),
        if (_chartable.isNotEmpty) ...[
          const SizedBox(height: 16),
          _chartSection(),
        ],
        if (_anglesWithPhotos.isNotEmpty) ...[
          const SizedBox(height: 16),
          _photoSection(),
        ],
        const SizedBox(height: 16),
        _historySection(),
      ],
    );
  }

  // ---------------------------------------------------------------- snapshot
  Widget _snapshotCard() {
    final latest = _desc.first;
    final prev = _desc.length > 1 ? _desc[1] : null;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.activity,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text('Última avaliação', style: AppTheme.titleSmall),
              const Spacer(),
              Text(DateFormat('dd/MM/yyyy').format(latest.date),
                  style: AppTheme.labelSmall
                      .copyWith(color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat('Peso', latest.weightKg, 'kg',
                  delta: _delta(latest.weightKg, prev?.weightKg)),
              _stat('IMC', latest.bmi, '',
                  delta: _delta(latest.bmi, prev?.bmi)),
              _stat('% Gordura', latest.bodyFatPct, '%',
                  delta: _delta(latest.bodyFatPct, prev?.bodyFatPct)),
            ],
          ),
          if (latest.bmiClass != null || latest.goal != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (latest.bmiClass != null)
                  _tag('IMC: ${latest.bmiClass}'),
                if (latest.goal != null)
                  _tag('Meta: ${_goalLabels[latest.goal] ?? latest.goal}',
                      icon: LucideIcons.target),
              ],
            ),
          ],
          if (prev != null) ...[
            const SizedBox(height: 8),
            Text('Variação vs. ${DateFormat('dd/MM/yy').format(prev.date)}',
                style: AppTheme.labelSmall
                    .copyWith(color: AppTheme.textSecondary)),
          ],
        ],
      ),
    );
  }

  double? _delta(double? now, double? before) {
    if (now == null || before == null) return null;
    return now - before;
  }

  Widget _stat(String label, double? value, String unit, {double? delta}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTheme.labelSmall
                  .copyWith(color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Text(value == null ? '—' : '${_fmt(value)}${unit.isEmpty ? '' : ' $unit'}',
              style: AppTheme.titleMedium
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          if (delta != null && delta.abs() >= 0.05)
            Row(
              children: [
                Icon(
                  delta > 0
                      ? LucideIcons.arrowUpRight
                      : LucideIcons.arrowDownRight,
                  size: 12,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 2),
                Text(
                  '${delta > 0 ? '+' : ''}${_fmt(delta)}',
                  style: AppTheme.labelSmall
                      .copyWith(color: AppTheme.textSecondary),
                ),
              ],
            )
          else
            const SizedBox(height: 16),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------- meta
  /// Progress card toward the student's active goal (target weight / %fat).
  /// Direction-agnostic: progress is measured from the first measurement to
  /// the target, so it works for both losing and gaining.
  List<Widget> _metaSection() {
    final bars = <Widget>[];
    final tw = widget.student.targetWeightKg;
    final tbf = widget.student.targetBodyFatPct;
    if (tw != null) {
      final b = _goalBar(
          label: 'Peso', unit: 'kg', target: tw, points: _series['weight']);
      if (b != null) bars.add(b);
    }
    if (tbf != null) {
      final b = _goalBar(
          label: '% Gordura',
          unit: '%',
          target: tbf,
          points: _series['bodyFat']);
      if (b != null) bars.add(b);
    }
    if (bars.isEmpty) return const [];

    return [
      const SizedBox(height: 16),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.target,
                    size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('Meta', style: AppTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < bars.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              bars[i],
            ],
          ],
        ),
      ),
    ];
  }

  Widget? _goalBar({
    required String label,
    required String unit,
    required double target,
    required List<({DateTime date, double value})>? points,
  }) {
    if (points == null || points.isEmpty) return null;
    final baseline = points.first.value;
    final current = points.last.value;
    final denom = target - baseline;
    final atTarget = (current - target).abs() < 0.05;
    final double progress = atTarget
        ? 1.0
        : denom.abs() < 1e-9
            ? 0.0
            : ((current - baseline) / denom).clamp(0.0, 1.0);
    // Reached covers overshoot too (e.g. lost more weight than the target),
    // so we never show "faltam X" once the goal is met or passed.
    final reached = atTarget || progress >= 1.0;
    final remaining = (target - current).abs();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: AppTheme.bodySmall
                    .copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
              '${_fmt(current)} → ${_fmt(target)} $unit',
              style: AppTheme.labelSmall
                  .copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: AppTheme.surfaceVariant,
            valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          reached
              ? 'Meta atingida! 🎉'
              : 'Faltam ${_fmt(remaining)} $unit (${(progress * 100).round()}%)',
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- chart
  Widget _chartSection() {
    final metric = _chartable.firstWhere((m) => m.key == _metricKey,
        orElse: () => _chartable.first);
    final points = _series[metric.key]!;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.trendingUp,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text('Evolução', style: AppTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final m in _chartable)
                ChoiceChip(
                  label: Text(m.label),
                  selected: m.key == _metricKey,
                  onSelected: (_) => setState(() => _metricKey = m.key),
                  labelStyle: AppTheme.labelSmall.copyWith(
                    color: m.key == _metricKey
                        ? Colors.white
                        : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  selectedColor: AppTheme.primary,
                  backgroundColor: AppTheme.surfaceVariant,
                  showCheckmark: false,
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(height: 220, child: _LineChartView(points: points, unit: metric.unit)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ photos
  Widget _photoSection() {
    final withAngle = _asc
        .where((a) => a.photos.any((p) => p.angle == _angle))
        .toList();
    final first = withAngle.first;
    final last = withAngle.last;
    final before = first.photos.firstWhere((p) => p.angle == _angle);
    final after = last.photos.firstWhere((p) => p.angle == _angle);
    final single = identical(first, last);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.image, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text('Comparação de fotos', style: AppTheme.titleSmall),
            ],
          ),
          if (_anglesWithPhotos.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final angle in _anglesWithPhotos)
                  ChoiceChip(
                    label: Text(_photoLabels[angle] ?? angle),
                    selected: angle == _angle,
                    onSelected: (_) => setState(() => _angle = angle),
                    labelStyle: AppTheme.labelSmall.copyWith(
                      color: angle == _angle
                          ? Colors.white
                          : AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    selectedColor: AppTheme.primary,
                    backgroundColor: AppTheme.surfaceVariant,
                    showCheckmark: false,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (single)
            _photoTile('Atual', first.date, after.url)
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _photoTile('Antes', first.date, before.url)),
                const SizedBox(width: 12),
                Expanded(child: _photoTile('Depois', last.date, after.url)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _photoTile(String label, DateTime date, String url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTheme.labelSmall.copyWith(fontWeight: FontWeight.w700)),
        Text(DateFormat('dd/MM/yy').format(date),
            style:
                AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary)),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 3 / 4,
          child: AppCachedImage(
            imageUrl: url,
            fit: BoxFit.cover,
            borderRadius: BorderRadius.circular(10),
            backgroundColor: AppTheme.surfaceVariant,
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- history
  Widget _historySection() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(LucideIcons.list, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text('Histórico', style: AppTheme.titleSmall),
              const Spacer(),
              Text('${_desc.length}',
                  style: AppTheme.labelSmall
                      .copyWith(color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          for (final a in _desc)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text(DateFormat('dd/MM/yyyy').format(a.date),
                      style: AppTheme.bodySmall),
                  const Spacer(),
                  if (a.weightKg != null)
                    _pill('${_fmt(a.weightKg!)} kg'),
                  if (a.bmi != null) ...[
                    const SizedBox(width: 6),
                    _pill('IMC ${_fmt(a.bmi!)}'),
                  ],
                  if (a.bodyFatPct != null) ...[
                    const SizedBox(width: 6),
                    _pill('${_fmt(a.bodyFatPct!)}%'),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tag(String text, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: AppTheme.textSecondary),
              const SizedBox(width: 4),
            ],
            Text(text,
                style: AppTheme.labelSmall
                    .copyWith(color: AppTheme.textSecondary)),
          ],
        ),
      );

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text,
            style:
                AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary)),
      );

  static String _fmt(double v) => fmtNum(v);
}

/// fl_chart line view for one ascending series.
class _LineChartView extends StatelessWidget {
  final List<({DateTime date, double value})> points;
  final String unit;
  const _LineChartView({required this.points, required this.unit});

  @override
  Widget build(BuildContext context) {
    final n = points.length;
    final values = points.map((p) => p.value).toList();
    double minV = values.reduce(math.min);
    double maxV = values.reduce(math.max);
    if (minV == maxV) {
      minV -= 1;
      maxV += 1;
    }
    final pad = (maxV - minV) * 0.15;
    final minY = minV - pad;
    final maxY = maxV + pad;
    final yInterval = (maxY - minY) / 4;
    final dec = yInterval < 2 ? 1 : 0;
    final labelStep = math.max(1, (n / 4).ceil());

    final spots = [
      for (var i = 0; i < n; i++) FlSpot(i.toDouble(), points[i].value),
    ];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (n - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval <= 0 ? null : yInterval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: AppTheme.border, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: yInterval <= 0 ? null : yInterval,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  fmtNum(value, maxDecimals: dec),
                  style: AppTheme.labelSmall
                      .copyWith(color: AppTheme.textSecondary, fontSize: 10),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if ((value - i).abs() > 0.01 || i < 0 || i >= n) {
                  return const SizedBox.shrink();
                }
                if (i % labelStep != 0 && i != n - 1) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('dd/MM').format(points[i].date),
                    style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary, fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
              final i = s.x.round().clamp(0, n - 1);
              final p = points[i];
              return LineTooltipItem(
                '${_fmtV(p.value)}${unit.isEmpty ? '' : ' $unit'}\n'
                '${DateFormat('dd/MM/yy').format(p.date)}',
                const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppTheme.primary,
            barWidth: 3,
            dotData: FlDotData(show: n <= 12),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.primary.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtV(double v) => fmtNum(v);
}

/// Simple rounded surface card used across the screen.
class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: child,
    );
  }
}

/// Centered icon + title + subtitle for empty/error/unlinked states.
class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;
  const _Message(
      {required this.icon,
      required this.title,
      required this.subtitle,
      this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(title,
                style: AppTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle,
                style: AppTheme.bodySmall
                    .copyWith(color: AppTheme.textSecondary),
                textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('Tentar novamente'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
