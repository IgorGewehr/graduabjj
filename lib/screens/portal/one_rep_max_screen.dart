import 'package:flutter/material.dart';

import '../../core/number_format.dart';
import '../../core/strength_math.dart';
import '../../core/theme.dart';

/// Calculadora de 1RM (E2) — pura, sem backend. Carga + reps → 1RM estimado
/// (Epley) + tabela de %1RM com carga e faixa de reps sugerida.
class OneRepMaxScreen extends StatefulWidget {
  const OneRepMaxScreen({super.key});

  @override
  State<OneRepMaxScreen> createState() => _OneRepMaxScreenState();
}

class _OneRepMaxScreenState extends State<OneRepMaxScreen> {
  final _load = TextEditingController();
  final _reps = TextEditingController(text: '5');

  @override
  void dispose() {
    _load.dispose();
    _reps.dispose();
    super.dispose();
  }

  double get _oneRM {
    final load = double.tryParse(_load.text.replaceAll(',', '.')) ?? 0;
    final reps = int.tryParse(_reps.text) ?? 0;
    return epley1RM(load, reps);
  }

  @override
  Widget build(BuildContext context) {
    final oneRM = _oneRM;
    final table = percentTable(oneRM);
    return Scaffold(
      appBar: AppBar(title: const Text('Calculadora de 1RM')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quanto você levantou?',
                      style: AppTheme.titleSmall
                          .copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _load,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Carga (kg)',
                              border: OutlineInputBorder()),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _reps,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Reps',
                              border: OutlineInputBorder()),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (oneRM <= 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('Informe carga e repetições para estimar o 1RM.'),
              ),
            )
          else ...[
            Center(
              child: Column(
                children: [
                  Text('1RM estimado',
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textSecondary)),
                  Text('${fmtNum(oneRM)} kg',
                      style: AppTheme.headlineLarge.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primary)),
                  Text('fórmula de Epley',
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Tabela de %1RM',
                style: AppTheme.titleSmall
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < table.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            child: Text('${table[i].pct}%',
                                style: AppTheme.bodyMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary)),
                          ),
                          Expanded(
                            child: Text('${fmtNum(table[i].load)} kg',
                                style: AppTheme.bodyMedium
                                    .copyWith(fontWeight: FontWeight.w600)),
                          ),
                          Text(table[i].repHint,
                              style: AppTheme.bodySmall
                                  .copyWith(color: AppTheme.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Estimativas — a força real varia por exercício e dia. Use como guia.',
              style:
                  AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
