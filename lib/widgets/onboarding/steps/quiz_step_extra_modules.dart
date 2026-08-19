import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/portal_providers.dart';
import '../../../services/settings_service.dart';
import '../../polish/polish.dart';
import '../quiz_card_option.dart';

/// Passo 4 do Nível 2: Módulos Extras (Loja, Vídeos, Agendamento, Avaliação)
class QuizStepExtraModules extends ConsumerStatefulWidget {
  final VoidCallback onFinish;

  const QuizStepExtraModules({
    super.key,
    required this.onFinish,
  });

  @override
  ConsumerState<QuizStepExtraModules> createState() => _QuizStepExtraModulesState();
}

class _QuizStepExtraModulesState extends ConsumerState<QuizStepExtraModules> {
  bool _storeEnabled = false;
  bool _videosEnabled = false;
  bool _bookingEnabled = false;
  bool _physicalEvolutionEnabled = false;
  bool _strikingEnabled = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(academySettingsProvider).valueOrNull;
    if (settings != null) {
      _storeEnabled = settings.storeEnabled;
      _videosEnabled = settings.trainingVideosEnabled;
      _bookingEnabled = settings.bookingEnabled;
      _physicalEvolutionEnabled = settings.physicalEvolutionEnabled;
      _strikingEnabled = settings.strikingEnabled;
    }
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
      if (academyId != null) {
        final service = SettingsService(academyId);
        await service.updateStoreSettings(enabled: _storeEnabled);
        await service.updateTrainingVideosEnabled(_videosEnabled);
        await service.updateBookingEnabled(_bookingEnabled);
        await service.updatePhysicalEvolutionEnabled(_physicalEvolutionEnabled);
        await service.updateStrikingEnabled(_strikingEnabled);
        ref.invalidate(academySettingsProvider);
      }
      widget.onFinish();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar módulos: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.sparkles, size: 14, color: AppTheme.success),
                    const SizedBox(width: 6),
                    Text(
                      'SUPERPODER #4',
                      style: AppTheme.labelSmall.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.success,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Módulos Extras',
                style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Escolha quais ferramentas avançadas você quer deixar ativas no app.',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ).entrance(),
          const SizedBox(height: 20),
          QuizCardOption(
            title: 'Loja da Academia',
            subtitle: 'Venda kimonos, faixas, rashguards e produtos no app com pagamento integrado.',
            icon: LucideIcons.shoppingBag,
            isMultiSelect: true,
            isSelected: _storeEnabled,
            onTap: () => setState(() => _storeEnabled = !_storeEnabled),
          ),
          QuizCardOption(
            title: 'Biblioteca de Videoaulas',
            subtitle: 'Disponibilize vídeos de posições e técnicas para seus alunos estudarem em casa.',
            icon: LucideIcons.video,
            isMultiSelect: true,
            isSelected: _videosEnabled,
            onTap: () => setState(() => _videosEnabled = !_videosEnabled),
          ),
          QuizCardOption(
            title: 'Reserva de Vagas & Aulas',
            subtitle: 'Limite de vagas por turma e fila de espera automática para evitar lotação.',
            icon: LucideIcons.calendarCheck,
            isMultiSelect: true,
            isSelected: _bookingEnabled,
            onTap: () => setState(() => _bookingEnabled = !_bookingEnabled),
          ),
          QuizCardOption(
            title: 'Avaliação Física & Evolução',
            subtitle: 'Acompanhamento de medidas, peso e fotos de evolução corporal dos alunos.',
            icon: LucideIcons.lineChart,
            isMultiSelect: true,
            isSelected: _physicalEvolutionEnabled,
            onTap: () => setState(() => _physicalEvolutionEnabled = !_physicalEvolutionEnabled),
          ),
          QuizCardOption(
            title: 'Timer de Rounds & Cartel de Lutas',
            subtitle: 'Cronômetro profissional de rounds de sparring e histórico de lutas de atletas.',
            icon: LucideIcons.timer,
            isMultiSelect: true,
            isSelected: _strikingEnabled,
            onTap: () => setState(() => _strikingEnabled = !_strikingEnabled),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Concluir Configuração Completa 🥋',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
