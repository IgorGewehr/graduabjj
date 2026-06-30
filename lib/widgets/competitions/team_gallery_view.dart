import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';
import '../../models/competition_photo.dart';
import '../../providers/providers.dart';
import '../../services/competition_photo_service.dart';
import 'photo_card.dart';
import 'photo_fullscreen_viewer.dart';

/// Team Gallery View - shows all team photos with competition filter
class TeamGalleryView extends ConsumerStatefulWidget {
  const TeamGalleryView({super.key});

  @override
  ConsumerState<TeamGalleryView> createState() => _TeamGalleryViewState();
}

class _TeamGalleryViewState extends ConsumerState<TeamGalleryView> {
  List<CompetitionPhoto> _photos = [];
  bool _isLoading = true;
  String? _filterCompetitionId;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    // In an admin-only session selectedAcademyIdProvider is never bootstrapped,
    // so fall back to the authenticated user's academy (mirrors
    // competition_detail_screen.dart's _resolveAcademyId).
    final academyId = ref.read(selectedAcademyIdProvider) ??
        ref.read(currentUserProvider).valueOrNull?.academyId;
    if (academyId == null) return;

    setState(() => _isLoading = true);
    try {
      final photoService = CompetitionPhotoService();
      final allPhotos = await photoService.getAllPhotos(academyId: academyId);
      final teamPhotos = allPhotos
          .where((p) => p.studentId == '__team__' || p.photoType == 'team')
          .toList();

      if (mounted) {
        setState(() {
          _photos = teamPhotos;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Get unique competitions from photos
  Map<String, String> get _competitions {
    final map = <String, String>{};
    for (final photo in _photos) {
      map.putIfAbsent(photo.competitionId, () => photo.competitionName);
    }
    return map;
  }

  List<CompetitionPhoto> get _filteredPhotos {
    if (_filterCompetitionId == null) return _photos;
    return _photos
        .where((p) => p.competitionId == _filterCompetitionId)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(LucideIcons.arrowLeft, size: 20),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Galeria da Equipe',
              style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
            ),
            if (!_isLoading)
              Text(
                '${_filteredPhotos.length} foto${_filteredPhotos.length != 1 ? 's' : ''}',
                style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary),
              ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Filter chips
                if (_competitions.length > 1) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: const Text('Todos'),
                            selected: _filterCompetitionId == null,
                            onSelected: (_) =>
                                setState(() => _filterCompetitionId = null),
                          ),
                        ),
                        ..._competitions.entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                entry.value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              selected:
                                  _filterCompetitionId == entry.key,
                              onSelected: (_) => setState(
                                  () => _filterCompetitionId = entry.key),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Photos grid
                Expanded(
                  child: _filteredPhotos.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                LucideIcons.image,
                                size: 48,
                                color: AppTheme.textDisabled,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _photos.isEmpty
                                    ? 'Nenhuma foto de equipe ainda'
                                    : 'Nenhuma foto para este campeonato',
                                style: AppTheme.bodyMedium.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              if (_photos.isEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Adicione fotos da equipe na galeria de cada campeonato',
                                  style: AppTheme.bodySmall.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadPhotos,
                          child: GridView.builder(
                            padding: const EdgeInsets.all(20),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.75,
                            ),
                            itemCount: _filteredPhotos.length,
                            itemBuilder: (context, index) {
                              final photo = _filteredPhotos[index];
                              return PhotoCard(
                                photo: photo,
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PhotoFullscreenViewer(
                                        photos: _filteredPhotos,
                                        initialIndex: index,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
