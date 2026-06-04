import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../skeletons/skeletons.dart';

/// Thin wrappers that keep shimmer skeletons consistent across the app. These
/// REUSE the existing `lib/widgets/skeletons` widgets — they do not duplicate
/// them — and centralize the shimmer base/highlight colors so every loading
/// surface mirrors its final layout with one rhythm.
///
/// Use these instead of a bare [CircularProgressIndicator]: pick the variant
/// whose shape matches the content that is loading.
///
/// * [list]   → vertical list of cards (student/attendance/competition rows)
/// * [grid]   → 2-column image grid (store, gallery)
/// * [stats]  → a row of KPI cards (dashboard headers)
/// * [card]   → a single card placeholder
/// * [avatar] → a circular avatar placeholder
/// * [header] → a page-header block (title line + subtitle line, optional avatar)
/// * [shimmer]→ wrap any custom grey placeholder with the standard shimmer
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
  /// Pass [scrollable] `false` when nesting inside another scroll view.
  ///
  /// Usage: `PolishSkeleton.list(count: 5)`
  static Widget list({
    int count = 4,
    double itemHeight = 80,
    bool showAvatar = true,
    bool scrollable = true,
    EdgeInsetsGeometry? padding,
  }) {
    return SkeletonList(
      itemCount: count,
      itemHeight: itemHeight,
      showAvatar: showAvatar,
      scrollable: scrollable,
      padding: padding ??
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    );
  }

  /// A 2-column grid of card-shaped skeletons — the default loading state for
  /// image/product listings (store, gallery).
  ///
  /// Usage: `PolishSkeleton.grid(count: 6)`
  static Widget grid({
    int count = 6,
    int crossAxisCount = 2,
    double childAspectRatio = 0.75,
    bool scrollable = true,
    EdgeInsetsGeometry? padding,
  }) {
    return SkeletonGrid(
      itemCount: count,
      crossAxisCount: crossAxisCount,
      childAspectRatio: childAspectRatio,
      scrollable: scrollable,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 20),
    );
  }

  /// A row of KPI / stat-card placeholders — the default loading state for the
  /// dashboard metric headers.
  ///
  /// Usage: `PolishSkeleton.stats(count: 3)`
  static Widget stats({
    int count = 2,
    double height = 80,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
  }) {
    return SkeletonStats(count: count, height: height, padding: padding);
  }

  /// A single card placeholder (avatar + 2 lines). Handy inside a custom
  /// layout that isn't a full [list].
  ///
  /// Usage: `PolishSkeleton.card()`
  static Widget card({
    double height = 80,
    bool showAvatar = true,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return SkeletonCard(
      height: height,
      showAvatar: showAvatar,
      padding: padding,
    );
  }

  /// A circular avatar placeholder.
  ///
  /// Usage: `PolishSkeleton.avatar(size: 64)`
  static Widget avatar({double size = 48}) {
    return SkeletonAvatar(size: size);
  }

  /// A page-header placeholder: an optional leading avatar next to a long
  /// title line and a shorter subtitle line. Mirrors the common
  /// `AcademyPageHeader` / profile-header rhythm while it loads.
  ///
  /// Usage: `PolishSkeleton.header()`
  static Widget header({
    bool showAvatar = true,
    double avatarSize = 56,
    EdgeInsetsGeometry padding =
        const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
  }) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (showAvatar) ...[
            avatar(size: avatarSize),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                shimmer(child: _bar(width: double.infinity, height: 18)),
                const SizedBox(height: 10),
                shimmer(child: _bar(width: 160, height: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A single shimmer bar — the building block for custom skeleton rows.
  ///
  /// Usage: `PolishSkeleton.shimmer(child: PolishSkeleton.bar(width: 120))`
  static Widget bar({
    double width = double.infinity,
    double height = 14,
    double radius = 4,
  }) =>
      _bar(width: width, height: height, radius: radius);

  static Widget _bar({
    double width = double.infinity,
    double height = 14,
    double radius = 4,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
