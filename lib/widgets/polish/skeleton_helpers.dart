import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../skeletons/skeletons.dart';

/// Thin wrappers that keep shimmer skeletons consistent across the app. These
/// REUSE the existing `lib/widgets/skeletons` widgets — they do not duplicate
/// them — and centralize the shimmer base/highlight colors.
class PolishSkeleton {
  PolishSkeleton._();

  /// Standard shimmer base color (matches existing skeleton_*.dart).
  static final Color baseColor = Colors.grey[300]!;

  /// Standard shimmer highlight color.
  static final Color highlightColor = Colors.grey[100]!;

  /// Wrap any plain (un-shimmered) placeholder so it shimmers with the app's
  /// standard colors. Useful for one-off custom placeholders.
  ///
  /// Usage: `PolishSkeleton.shimmer(child: myGreyBox)`
  static Widget shimmer({required Widget child}) {
    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: child,
    );
  }

  /// A vertical list of [SkeletonCard]s — the default loading state for lists.
  ///
  /// Usage: `PolishSkeleton.list(count: 5)`
  static Widget list({int count = 4, double itemHeight = 80}) {
    return SkeletonList(itemCount: count, itemHeight: itemHeight);
  }
}
