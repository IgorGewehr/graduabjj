import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/number_format.dart';
import '../../core/theme.dart';
import '../../services/firebase_service.dart';
import '../../services/workout_execution_service.dart';
import '../../widgets/polish/polish.dart';

/// Portal: progresso de um exercício (A6 fase 4) — PR, gráfico no tempo e
/// histórico de sessões. Somente leitura.
class ExerciseProgressScreen extends StatefulWidget {
  final String studentId;
  final String exerciseName;
  const ExerciseProgressScreen({
    super.key,
    required this.studentId,
    required this.exerciseName,
  });

  @override
  State<ExerciseProgressScreen> createState() => _ExerciseProgressScreenState();
}

class _Metric {
  final String key, label, unit;
  final double Function(WorkoutExecution) extract;
  const _Metric(this.key, this.label, this.unit, this.extract);
}

class _ExerciseProgressScreenState extends State<ExerciseProgressScreen> {
  static final List<_Metric> _metrics = [
    _Metric('load', 'Carga', 'kg', (e) => e.bestLoadKg),
    _Metric('orm', '1RM est.', 'kg', (e) => e.best1RMKg),
    _Metric('volume', 'Volume', 'kg', (e) => e.volume),
  ];

  List<WorkoutExecution> _history = []; // mais recente primeiro
  bool _loading = true;
  bool _error = false;
  String _metricKey = 'load';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final h = await WorkoutExecutionService(FirebaseService.academyId)
          .getHistoryForExercise(widget.studentId, widget.exerciseName);
      if (mounted) setState(() { _history = h; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        title: Text(widget.exerciseName, overflow: TextOverflow.ellipsis),
      ),
      body: _loading
          ? _loadingState()
          : _error
              ? _errorState()
              : _history.isEmpty
                  ? _empty()
                  : _content(),
    );
  }

  Widget _loadingState() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PolishSkeleton.stats(count: 2, height: 80),
            const SizedBox(height: 20),
            PolishSkeleton.shimmer(
              child: PolishSkeleton.bar(height: 180, radius: 12),
            ),
            const SizedBox(height: 20),
            PolishSkeleton.list(count: 4, scrollable: false, showAvatar: false),
          ],
        ),
      );

  Widget _errorState() => PolishedEmptyState(
        icon: LucideIcons.alertTriangle,
        title: 'Erro ao carregar o progresso',
        subtitle: 'Verifique sua conexao e tente novamente.',
        accent: AppTheme.error,
        actionLabel: 'Tentar novamente',
        onAction: () {
          FeedbackUtils.tapHaptic();
          _load();
        },
      );

  Widget _empty() => const PolishedEmptyState(
        icon: LucideIcons.lineChart,
        title: 'Sem registros ainda',
        subtitle: 'Registre as séries deste exercício no seu treino para ver a '
            'evolução aqui.',
      );

  Widget _content() {
    double prLoad = 0, pr1RM = 0;
    for (final e in _history) {
      if (e.bestLoadKg > prLoad) prLoad = e.bestLoadKg;
      if (e.best1RMKg > pr1RM) pr1RM = e.best1RMKg;
    }
    final metric = _metrics.firstWhere((m) => m.key == _metricKey);
    // Pontos ascendentes (data → valor), só os > 0.
    final points = <({DateTime date, double value})>[];
    for (final e in _history.reversed) {
      final v = metric.extract(e);
      if (v > 0) points.add((date: e.date, value: v));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            Expanded(child: _prCard('Recorde de carga', prLoad)),
            const SizedBox(width: 12),
            Expanded(child: _prCard('Recorde 1RM est.', pr1RM)),
          ],
        ),
        const SizedBox(height: 16),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(LucideIcons.trendingUp,
                    size: 18, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('Evolução', style: AppTheme.titleSmall),
              ]),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in _metrics)
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
              SizedBox(
                height: 200,
                child: points.length < 2
                    ? Center(
                        child: Text('Precisa de 2+ sessões para o gráfico.',
                            style: AppTheme.labelSmall
                                .copyWith(color: AppTheme.textSecondary)))
                    : _Chart(points: points, unit: metric.unit),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Histórico (${_history.length})',
            style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        for (final e in _history) _sessionCard(e, prLoad),
      ],
    );
  }

  Widget _prCard(String label, double v) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppTheme.labelSmall
                    .copyWith(color: AppTheme.textSecondary)),
            const SizedBox(height: 4),
            Text(v > 0 ? '${fmtNum(v)} kg' : '—',
                style: AppTheme.titleMedium
                    .copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _sessionCard(WorkoutExecution e, double prLoad) {
    final isPR = prLoad > 0 && e.bestLoadKg >= prLoad;
    final sets = e.sets
        .map((s) =>
            '${s.reps}×${fmtNum(s.load)}${s.rpe != null ? ' @${s.rpe}' : ''}')
        .join('  ·  ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isPR ? AppTheme.success.withValues(alpha: 0.5) : AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(DateFormat('dd/MM/yyyy').format(e.date),
                  style: AppTheme.bodySmall
                      .copyWith(fontWeight: FontWeight.w600)),
              if (isPR) ...[
                const SizedBox(width: 6),
                Text('🏆',
                    style: AppTheme.labelSmall.copyWith(fontSize: 12)),
              ],
              const Spacer(),
              if (e.bestLoadKg > 0)
                Text('melhor ${fmtNum(e.bestLoadKg)} kg',
                    style: AppTheme.labelSmall.copyWith(
                        color:
                            isPR ? AppTheme.success : AppTheme.textSecondary)),
            ],
          ),
          if (sets.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(sets,
                style: AppTheme.labelSmall.copyWith(color: AppTheme.primary)),
          ],
          if ((e.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(e.notes!,
                style: AppTheme.labelSmall
                    .copyWith(color: AppTheme.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  final List<({DateTime date, double value})> points;
  final String unit;
  const _Chart({required this.points, required this.unit});

  @override
  Widget build(BuildContext context) {
    final n = points.length;
    final values = points.map((p) => p.value).toList();
    double minV = values.reduce(math.min), maxV = values.reduce(math.max);
    if (minV == maxV) {
      minV -= 1;
      maxV += 1;
    }
    final pad = (maxV - minV) * 0.15;
    final minY = minV - pad, maxY = maxV + pad;
    final yInterval = (maxY - minY) / 4;
    final dec = yInterval < 2 ? 1 : 0;
    final step = math.max(1, (n / 4).ceil());

    return LineChart(LineChartData(
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
            getTitlesWidget: (v, _) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(fmtNum(v, maxDecimals: dec),
                  style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary, fontSize: 10)),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: 1,
            getTitlesWidget: (v, _) {
              final i = v.round();
              if ((v - i).abs() > 0.01 || i < 0 || i >= n) {
                return const SizedBox.shrink();
              }
              if (i % step != 0 && i != n - 1) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(DateFormat('dd/MM').format(points[i].date),
                    style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary, fontSize: 10)),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => spots.map((s) {
            final p = points[s.x.round().clamp(0, n - 1)];
            return LineTooltipItem(
              '${fmtNum(p.value)} $unit\n${DateFormat('dd/MM/yy').format(p.date)}',
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
          spots: [for (var i = 0; i < n; i++) FlSpot(i.toDouble(), points[i].value)],
          isCurved: true,
          curveSmoothness: 0.2,
          color: AppTheme.primary,
          barWidth: 3,
          dotData: FlDotData(show: n <= 12),
          belowBarData: BarAreaData(
              show: true, color: AppTheme.primary.withValues(alpha: 0.12)),
        ),
      ],
    ));
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: child,
      );
}
