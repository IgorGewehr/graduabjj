import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/feedback_utils.dart';
import '../../core/sports.dart';
import '../../core/theme.dart';
import '../../models/student.dart';
import '../../providers/auth_provider.dart';
import '../../services/checkin_service.dart';
import '../../services/services.dart';

/// Admin tool for musculação check-in. Adapts to the academy's configured
/// mode: 'manual' shows a roster the reception marks present, 'qr' shows the
/// fixed QR to print, and 'button' just explains that students self check-in.
class MusculacaoAdminScreen extends ConsumerStatefulWidget {
  const MusculacaoAdminScreen({super.key});

  @override
  ConsumerState<MusculacaoAdminScreen> createState() =>
      _MusculacaoAdminScreenState();
}

class _MusculacaoAdminScreenState extends ConsumerState<MusculacaoAdminScreen> {
  bool _loading = true;
  String _mode = 'manual';
  List<Student> _students = [];
  Set<String> _presentToday = {};
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final academyId = FirebaseService.academyId;
      final settings = await SettingsService(academyId).getAcademySettings();
      _mode = settings?.musculacaoCheckinMode ?? 'manual';
      if (_mode == 'manual') {
        final all = await StudentService(academyId).getActive();
        _students = all
            .where((s) => s.getSports().contains(SportId.musculacao))
            .toList();
        _presentToday = await AttendanceService(academyId)
            .presentTodayForClass(kMusculacaoClassId);
      }
    } catch (_) {
      // Surface nothing fatal — empty state covers load failures.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _markPresent(Student s) async {
    final user = await ref.read(currentUserProvider.future);
    if (user == null) return;
    setState(() => _busy.add(s.id));
    try {
      await AttendanceService(FirebaseService.academyId).markPresent(
        studentId: s.id,
        studentName: s.fullName,
        classId: kMusculacaoClassId,
        className: kMusculacaoClassName,
        verifiedBy: user.id,
        verifiedByName: user.displayName,
        sport: SportId.musculacao.value,
      );
      if (mounted) setState(() => _presentToday.add(s.id));
    } catch (e) {
      final already = e.toString().contains('marcado');
      if (mounted) {
        if (already) {
          setState(() => _presentToday.add(s.id));
        } else {
          context.showError('Erro ao marcar presenca.');
        }
      }
    } finally {
      if (mounted) setState(() => _busy.remove(s.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Musculacao'),
        backgroundColor: AppTheme.surface,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _mode == 'qr'
              ? _buildQr()
              : _mode == 'button'
                  ? _buildButtonInfo()
                  : _buildRoster(),
    );
  }

  Widget _buildQr() {
    final data = encodeMusculacaoQr(FirebaseService.academyId);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'QR de check-in da musculacao',
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Imprima e deixe na recepcao. Os alunos escaneiam pelo app ao chegar.',
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: data,
                size: 240,
                version: QrVersions.auto,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'So funciona dentro do horario de funcionamento configurado.',
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButtonInfo() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, size: 48, color: AppTheme.primary),
            const SizedBox(height: 12),
            Text(
              'Check-in pelo app',
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Os alunos de musculacao registram presenca pelo botao "Cheguei" na '
              'tela inicial do app. Altere o modo em Configuracoes > Funcionalidades.',
              textAlign: TextAlign.center,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoster() {
    if (_students.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nenhum aluno de musculacao ativo.',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _students.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final s = _students[i];
          final done = _presentToday.contains(s.id);
          final busy = _busy.contains(s.id);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.fullName,
                    style: AppTheme.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (done)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: AppTheme.success, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        'Presente',
                        style: AppTheme.labelSmall.copyWith(
                          color: AppTheme.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                else
                  ElevatedButton(
                    onPressed: busy ? null : () => _markPresent(s),
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Presente'),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
