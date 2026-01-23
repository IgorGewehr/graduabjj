import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/student.dart';
import '../../services/services.dart';

/// Admin Graduation Screen - Promote students
class AdminGraduationScreen extends ConsumerStatefulWidget {
  const AdminGraduationScreen({super.key});

  @override
  ConsumerState<AdminGraduationScreen> createState() => _AdminGraduationScreenState();
}

class _AdminGraduationScreenState extends ConsumerState<AdminGraduationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _eligibleStudents = [];
  List<BeltProgression> _recentPromotions = [];
  Map<String, int> _beltDistribution = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final service = BeltProgressionService(FirebaseService.academyId);

      final results = await Future.wait([
        service.getEligibleStudents(),
        service.getRecentPromotions(limit: 20),
        service.getBeltDistribution(),
      ]);

      setState(() {
        _eligibleStudents = results[0] as List<Map<String, dynamic>>;
        _recentPromotions = results[1] as List<BeltProgression>;
        _beltDistribution = results[2] as Map<String, int>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Graduação'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Elegíveis (${_eligibleStudents.length})'),
            const Tab(text: 'Histórico'),
            const Tab(text: 'Distribuição'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildEligibleTab(),
                _buildHistoryTab(),
                _buildDistributionTab(),
              ],
            ),
    );
  }

  Widget _buildEligibleTab() {
    if (_eligibleStudents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.military_tech_outlined, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              'Nenhum aluno elegível',
              style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'Todos os alunos estão em dia com suas graduações',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _eligibleStudents.length,
      itemBuilder: (context, index) {
        final data = _eligibleStudents[index];
        return _EligibleStudentCard(
          data: data,
          onPromote: () => _showPromotionDialog(data),
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    if (_recentPromotions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_outlined, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              'Nenhuma graduação registrada',
              style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _recentPromotions.length,
      itemBuilder: (context, index) {
        final promotion = _recentPromotions[index];
        return _PromotionHistoryCard(promotion: promotion);
      },
    );
  }

  Widget _buildDistributionTab() {
    final total = _beltDistribution.values.fold<int>(0, (a, b) => a + b);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Distribuição de Faixas',
            style: AppTheme.headlineSmall.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Total: $total alunos ativos',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          ...['white', 'blue', 'purple', 'brown', 'black'].map((belt) {
            final count = _beltDistribution[belt] ?? 0;
            final percentage = total > 0 ? (count / total * 100) : 0.0;
            return _BeltDistributionBar(
              belt: belt,
              count: count,
              percentage: percentage,
            );
          }),
        ],
      ),
    );
  }

  void _showPromotionDialog(Map<String, dynamic> studentData) {
    final eligibility = studentData['eligibility'] as EligibilityResult;
    final currentBelt = studentData['currentBelt'] as String;
    final currentStripes = studentData['currentStripes'] as int;
    final studentId = studentData['id'] as String;
    final studentName = studentData['fullName'] as String;

    bool isStripePromotion = eligibility.nextStripes != null && eligibility.nextStripes! > 0;
    String? selectedBelt = eligibility.nextBelt;
    int selectedStripes = eligibility.nextStripes ?? 0;
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Confirmar Graduação'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Student info
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: _getBeltColor(currentBelt),
                      child: Text(
                        studentName.substring(0, 1),
                        style: TextStyle(
                          color: currentBelt == 'white' ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                    title: Text(studentName),
                    subtitle: Text(
                      'Atual: ${_getBeltLabel(currentBelt)} ${currentStripes > 0 ? "• $currentStripes grau(s)" : ""}',
                    ),
                  ),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Promotion type
                  const Text('Tipo de graduação:', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Grau'),
                          selected: isStripePromotion,
                          onSelected: currentStripes < 4 ? (selected) {
                            setDialogState(() {
                              isStripePromotion = true;
                              selectedBelt = currentBelt;
                              selectedStripes = currentStripes + 1;
                            });
                          } : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Faixa'),
                          selected: !isStripePromotion,
                          onSelected: (selected) {
                            setDialogState(() {
                              isStripePromotion = false;
                              selectedBelt = _getNextBelt(currentBelt);
                              selectedStripes = 0;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // New belt/stripe display
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_forward, color: Colors.green.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isStripePromotion
                                ? '$selectedStripes° grau na faixa ${_getBeltLabel(selectedBelt!)}'
                                : 'Faixa ${_getBeltLabel(selectedBelt!)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Colors.green.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Notes
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Observações (opcional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await _promoteStudent(
                    studentId: studentId,
                    studentName: studentName,
                    newBelt: selectedBelt!,
                    newStripes: selectedStripes,
                    notes: notesController.text.isEmpty ? null : notesController.text,
                  );
                },
                icon: const Icon(Icons.military_tech),
                label: const Text('Graduar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _promoteStudent({
    required String studentId,
    required String studentName,
    required String newBelt,
    required int newStripes,
    String? notes,
  }) async {
    try {
      final service = BeltProgressionService(FirebaseService.academyId);
      await service.promote(
        studentId: studentId,
        studentName: studentName,
        newBelt: newBelt,
        newStripes: newStripes,
        promotedBy: 'admin', // TODO: Get actual admin ID
        promotedByName: 'Administrador',
        notes: notes,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$studentName foi graduado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  String _getNextBelt(String currentBelt) {
    const beltOrder = ['white', 'blue', 'purple', 'brown', 'black'];
    final index = beltOrder.indexOf(currentBelt);
    if (index < beltOrder.length - 1) {
      return beltOrder[index + 1];
    }
    return currentBelt;
  }

  String _getBeltLabel(String belt) {
    const labels = {
      'white': 'Branca',
      'blue': 'Azul',
      'purple': 'Roxa',
      'brown': 'Marrom',
      'black': 'Preta',
    };
    return labels[belt] ?? belt;
  }

  Color _getBeltColor(String belt) {
    const colors = {
      'white': Color(0xFFF5F5F5),
      'blue': Color(0xFF2563EB),
      'purple': Color(0xFF7C3AED),
      'brown': Color(0xFF92400E),
      'black': Color(0xFF171717),
    };
    return colors[belt] ?? Colors.grey;
  }
}

/// Eligible Student Card
class _EligibleStudentCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onPromote;

  const _EligibleStudentCard({
    required this.data,
    required this.onPromote,
  });

  @override
  Widget build(BuildContext context) {
    final eligibility = data['eligibility'] as EligibilityResult;
    final currentBelt = data['currentBelt'] as String;
    final currentStripes = data['currentStripes'] as int;
    final totalClasses = data['totalClasses'] as int;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: _getBeltColor(currentBelt),
                  child: Text(
                    (data['fullName'] as String).substring(0, 1),
                    style: TextStyle(
                      color: currentBelt == 'white' ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['fullName'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Row(
                        children: [
                          _buildBeltIndicator(currentBelt, currentStripes),
                          const SizedBox(width: 8),
                          Text(
                            '$totalClasses treinos',
                            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      eligibility.message,
                      style: TextStyle(color: Colors.green.shade900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPromote,
                icon: const Icon(Icons.military_tech),
                label: const Text('Graduar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBeltIndicator(String belt, int stripes) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _getBeltColor(belt),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _getBeltShortLabel(belt),
            style: TextStyle(
              fontSize: 10,
              color: belt == 'white' ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (stripes > 0) ...[
            const SizedBox(width: 4),
            Text(
              '• $stripes',
              style: TextStyle(
                fontSize: 10,
                color: belt == 'white' ? Colors.black : Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getBeltColor(String belt) {
    const colors = {
      'white': Color(0xFFF5F5F5),
      'blue': Color(0xFF2563EB),
      'purple': Color(0xFF7C3AED),
      'brown': Color(0xFF92400E),
      'black': Color(0xFF171717),
    };
    return colors[belt] ?? Colors.grey;
  }

  String _getBeltShortLabel(String belt) {
    const labels = {
      'white': 'BR',
      'blue': 'AZ',
      'purple': 'RX',
      'brown': 'MR',
      'black': 'PT',
    };
    return labels[belt] ?? belt.toUpperCase().substring(0, 2);
  }
}

/// Promotion History Card
class _PromotionHistoryCard extends StatelessWidget {
  final BeltProgression promotion;

  const _PromotionHistoryCard({required this.promotion});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getBeltColor(promotion.newBelt),
          child: Icon(
            promotion.isBeltChange ? Icons.military_tech : Icons.star,
            color: promotion.newBelt == 'white' ? Colors.black : Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          promotion.isBeltChange
              ? 'Graduação para Faixa ${_getBeltLabel(promotion.newBelt)}'
              : '${promotion.newStripes}° Grau',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          DateFormat("d 'de' MMMM 'de' yyyy", 'pt_BR').format(promotion.promotionDate),
        ),
        trailing: Text(
          '${promotion.totalClasses} treinos',
          style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  String _getBeltLabel(String belt) {
    const labels = {
      'white': 'Branca',
      'blue': 'Azul',
      'purple': 'Roxa',
      'brown': 'Marrom',
      'black': 'Preta',
    };
    return labels[belt] ?? belt;
  }

  Color _getBeltColor(String belt) {
    const colors = {
      'white': Color(0xFFF5F5F5),
      'blue': Color(0xFF2563EB),
      'purple': Color(0xFF7C3AED),
      'brown': Color(0xFF92400E),
      'black': Color(0xFF171717),
    };
    return colors[belt] ?? Colors.grey;
  }
}

/// Belt Distribution Bar
class _BeltDistributionBar extends StatelessWidget {
  final String belt;
  final int count;
  final double percentage;

  const _BeltDistributionBar({
    required this.belt,
    required this.count,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getBeltLabel(belt),
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                '$count (${percentage.toStringAsFixed(1)}%)',
                style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(_getBeltColor(belt)),
              minHeight: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _getBeltLabel(String belt) {
    const labels = {
      'white': 'Branca',
      'blue': 'Azul',
      'purple': 'Roxa',
      'brown': 'Marrom',
      'black': 'Preta',
    };
    return labels[belt] ?? belt;
  }

  Color _getBeltColor(String belt) {
    const colors = {
      'white': Color(0xFF9E9E9E),
      'blue': Color(0xFF2563EB),
      'purple': Color(0xFF7C3AED),
      'brown': Color(0xFF92400E),
      'black': Color(0xFF171717),
    };
    return colors[belt] ?? Colors.grey;
  }
}
