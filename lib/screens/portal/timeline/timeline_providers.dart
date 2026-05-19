import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/repositories.dart' as tatami_repos;
import '../../../providers/providers.dart';
import '../../../services/belt_progression_service.dart';
import 'timeline_models.dart';

/// Belt progressions provider for timeline
final studentBeltProgressionsProvider =
    FutureProvider.family<List<BeltProgression>, String>((
      ref,
      studentId,
    ) async {
      final currentUser = await ref.watch(currentUserProvider.future);
      if (currentUser?.academyId == null) return [];

      final academyId = currentUser!.academyId!;
      final page = await ref
          .watch(tatami_repos.studentRepoProvider)
          .listBeltProgressions(academyId, studentId, limit: 100);
      return page.items.map(beltProgressionFromApi).toList();
    });
