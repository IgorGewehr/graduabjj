import 'package:flutter/material.dart';

import '../../core/brand_tokens.dart';

/// Strip de 8 semanas — componente COMPARTILHADO (§5.2 do plano Repaginada):
/// o professor vê na ficha do aluno a MESMA strip que o aluno vê na Jornada.
///
/// [buckets] em ordem cronológica (índice 0 = semana mais antiga, último =
/// semana corrente), tipicamente `student.last8WeeksBuckets(DateTime.now())`.
/// Semana com treino = barra cheia; sem treino = stub baixo apagado. A altura
/// da barra escala levemente com o volume (1..4+ treinos) sem virar gráfico.
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.buckets,
    this.height = 22,
    this.barWidth = 6,
    this.gap = 3,
    this.activeColor = Brand.blood,
    this.emptyColor = const Color(0x22000000),
  });

  final List<int> buckets;
  final double height;
  final double barWidth;
  final double gap;
  final Color activeColor;
  final Color emptyColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < buckets.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          _bar(buckets[i]),
        ],
      ],
    );
  }

  Widget _bar(int count) {
    // 0 → stub apagado; 1..4+ → 55%..100% da altura, cheia.
    final active = count > 0;
    final t = active ? (0.55 + 0.15 * (count.clamp(1, 4) - 1)) : 0.18;
    return Container(
      width: barWidth,
      height: height * t,
      decoration: BoxDecoration(
        color: active ? activeColor : emptyColor,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
