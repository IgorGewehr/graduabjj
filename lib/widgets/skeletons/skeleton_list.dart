import 'package:flutter/material.dart';

import 'skeleton_card.dart';

/// A vertical list of [SkeletonCard]s used as a placeholder while a list
/// view is loading.
class SkeletonList extends StatelessWidget {
  /// Number of skeleton cards to render.
  final int itemCount;

  /// Vertical gap between cards.
  final double spacing;

  /// Outer padding around the list.
  final EdgeInsetsGeometry padding;

  /// Whether each card shows the leading avatar placeholder.
  final bool showAvatar;

  /// Height of each individual card.
  final double itemHeight;

  /// Whether the list itself should scroll.
  /// When `false`, the list shrink-wraps and disables its own scroll, which is
  /// useful when nested inside another scroll view.
  final bool scrollable;

  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.spacing = 8,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    this.showAvatar = true,
    this.itemHeight = 80,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      shrinkWrap: !scrollable,
      physics: scrollable ? null : const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      separatorBuilder: (_, _) => SizedBox(height: spacing),
      itemBuilder: (_, _) =>
          SkeletonCard(showAvatar: showAvatar, height: itemHeight),
    );
  }
}
