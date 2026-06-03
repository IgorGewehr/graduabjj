import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../models/training_video.dart';
import '../../providers/providers.dart';
import '../../services/services.dart';
import '../../widgets/common/sport_chip.dart';
import '../../widgets/polish/polish.dart';

/// Student-facing list of training videos assigned to them. Tapping a video
/// opens it externally (YouTube/Vimeo app or browser for uploaded files) via
/// url_launcher — no in-app player dependency required.
class VideosScreen extends ConsumerStatefulWidget {
  const VideosScreen({super.key});

  @override
  ConsumerState<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends ConsumerState<VideosScreen> {
  bool _loading = true;
  List<TrainingVideo> _videos = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final student = await ref.read(currentStudentProvider.future);
      if (student != null) {
        _videos = await TrainingVideoService(FirebaseService.academyId)
            .getForStudent(studentId: student.id, sports: student.getSports());
      } else {
        _videos = [];
      }
    } catch (_) {
      _videos = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _play(TrainingVideo v) async {
    final uri = Uri.tryParse(v.url);
    if (uri == null) {
      context.showError('Link invalido.');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      context.showError('Nao foi possivel abrir o video.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Videos'),
        backgroundColor: AppTheme.surface,
      ),
      body: _loading
          ? PolishSkeleton.list(count: 6)
          : _videos.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _videos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final v = _videos[i];
                      return Pressable(
                        onTap: () => _play(v),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.divider),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.play_circle_outline,
                                    color: AppTheme.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v.title,
                                      style: AppTheme.bodyLarge.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (v.description != null &&
                                        v.description!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        v.description!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppTheme.labelSmall.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (v.sportId != null) SportChip(sportId: v.sportId!),
                            ],
                          ),
                        ),
                      ).entrance(index: i);
                    },
                  ),
                ),
    );
  }

  Widget _empty() {
    return const PolishedEmptyState(
      icon: Icons.video_library_outlined,
      title: 'Nenhum video disponivel ainda.',
      subtitle: 'Quando seu professor liberar videos, eles aparecem aqui.',
    );
  }
}
