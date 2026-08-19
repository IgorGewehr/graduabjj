import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme.dart';
import '../../../models/academy.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/portal_providers.dart';
import '../../../services/settings_service.dart';
import '../../polish/polish.dart';
import '../quiz_card_option.dart';

/// Passo 1 do Nível 1: Modalidades & Perfil do Espaço
class QuizStepModalities extends ConsumerStatefulWidget {
  final VoidCallback onNext;

  const QuizStepModalities({
    super.key,
    required this.onNext,
  });

  @override
  ConsumerState<QuizStepModalities> createState() => _QuizStepModalitiesState();
}

class _QuizStepModalitiesState extends ConsumerState<QuizStepModalities> {
  AcademyProfile _selectedProfile = AcademyProfile.fight;
  final Set<String> _selectedSports = {'bjj'};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(academySettingsProvider).valueOrNull;
    if (settings != null) {
      _selectedProfile = AcademyProfileExtension.fromString(settings.profile);
      if (settings.sports.isNotEmpty) {
        _selectedSports.clear();
        _selectedSports.addAll(settings.sports);
      } else {
        if (_selectedProfile == AcademyProfile.fitness) {
          _selectedSports.add('musculacao');
        } else {
          _selectedSports.add('bjj');
        }
      }
    }
  }

  void _onProfileChanged(AcademyProfile profile) {
    setState(() {
      _selectedProfile = profile;
      if (profile == AcademyProfile.fitness) {
        _selectedSports.add('musculacao');
      } else if (profile == AcademyProfile.fight) {
        if (!_selectedSports.any((s) => s != 'musculacao')) {
          _selectedSports.add('bjj');
        }
      }
    });
  }

  void _toggleSport(String sportId) {
    setState(() {
      if (_selectedSports.contains(sportId)) {
        if (_selectedSports.length > 1) {
          _selectedSports.remove(sportId);
        }
      } else {
        _selectedSports.add(sportId);
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final academyId = ref.read(currentUserProvider).valueOrNull?.academyId;
      if (academyId != null) {
        final service = SettingsService(academyId);
        await service.updateAcademyProfile(_selectedProfile.value);
        await service.updateAcademySports(_selectedSports.toList());
        ref.invalidate(academySettingsProvider);
      }
      widget.onNext();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar modalidades: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableSports = [
      (id: 'bjj', name: 'Jiu-Jitsu (BJJ)', icon: LucideIcons.shield),
      (id: 'muaythai', name: 'Muay Thai', icon: LucideIcons.flame),
      (id: 'musculacao', name: 'Musculação / Fitness', icon: LucideIcons.dumbbell),
      (id: 'boxing', name: 'Boxe', icon: LucideIcons.target),
      (id: 'judo', name: 'Judô', icon: LucideIcons.award),
      (id: 'kickboxing', name: 'Kickboxing', icon: LucideIcons.zap),
      (id: 'mma', name: 'MMA', icon: LucideIcons.swords),
      (id: 'lutalivre', name: 'Luta Livre', icon: LucideIcons.activity),
      (id: 'karate', name: 'Karatê', icon: LucideIcons.star),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Qual é o foco do seu espaço?',
                style: AppTheme.headlineMedium.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Personalizaremos o vocabulário e os módulos para o seu modelo.',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ).entrance(),
          const SizedBox(height: 20),
          QuizCardOption(
            title: 'Artes Marciais & Lutas',
            subtitle: 'Foco em turmas, faixas, graus e presença no tatame.',
            icon: LucideIcons.award,
            isSelected: _selectedProfile == AcademyProfile.fight,
            onTap: () => _onProfileChanged(AcademyProfile.fight),
          ),
          QuizCardOption(
            title: 'Musculação & Fitness',
            subtitle: 'Foco em check-in livre, treinos personalizados e catraca.',
            icon: LucideIcons.dumbbell,
            isSelected: _selectedProfile == AcademyProfile.fitness,
            onTap: () => _onProfileChanged(AcademyProfile.fitness),
          ),
          QuizCardOption(
            title: 'Híbrido (Lutas + Fitness)',
            subtitle: 'Centro de treinamento completo com artes marciais e musculação.',
            icon: LucideIcons.sparkles,
            isSelected: _selectedProfile == AcademyProfile.hybrid,
            onTap: () => _onProfileChanged(AcademyProfile.hybrid),
          ),
          const SizedBox(height: 24),
          Text(
            'Quais modalidades você ensina?',
            style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Selecione todas as modalidades oferecidas:',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: availableSports.map((sport) {
              final isSelected = _selectedSports.contains(sport.id);
              return FilterChip(
                selected: isSelected,
                avatar: Icon(
                  sport.icon,
                  size: 16,
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
                label: Text(sport.name),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textPrimary,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
                backgroundColor: AppTheme.surfaceVariant,
                selectedColor: AppTheme.textPrimary,
                checkmarkColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: isSelected ? AppTheme.textPrimary : AppTheme.divider,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                onSelected: (_) => _toggleSport(sport.id),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
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
                      'Continuar',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
