import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'skeletons/skeleton_avatar.dart';

/// Cached network image wrapper.
///
/// Uses [CachedNetworkImage] under the hood so images are persisted across
/// navigations. Designed to be a drop-in replacement for `Image.network`
/// throughout the app.
///
/// - Handles `null`/empty URLs by rendering [errorIcon].
/// - Honors [memCacheWidth]/[memCacheHeight] (auto-derived from `width`/
///   `height` when not provided) so we don't blow up the image cache with
///   full-resolution decodes.
/// - Optional [borderRadius] clips the image with the same radius.
class AppCachedImage extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? placeholder;
  final Widget? errorIcon;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Color? backgroundColor;

  const AppCachedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholder,
    this.errorIcon,
    this.memCacheWidth,
    this.memCacheHeight,
    this.backgroundColor,
  });

  int? _resolveMemCache(double? logical, int? override) {
    if (override != null) return override;
    if (logical == null || logical.isInfinite || logical.isNaN) return null;
    // Multiply by 2 to keep retina sharpness, cap at 1024 to avoid bloat.
    final value = (logical * 2).round();
    if (value <= 0) return null;
    return value > 1024 ? 1024 : value;
  }

  Widget _wrap(Widget child) {
    Widget result = child;
    if (backgroundColor != null) {
      result = Container(
        width: width,
        height: height,
        color: backgroundColor,
        child: result,
      );
    }
    if (borderRadius != null) {
      result = ClipRRect(borderRadius: borderRadius!, child: result);
    }
    return result;
  }

  Widget _defaultPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: AppTheme.surfaceVariant,
    );
  }

  Widget _defaultError() {
    return Container(
      width: width,
      height: height,
      color: AppTheme.surfaceVariant,
      alignment: Alignment.center,
      child: const Icon(
        Icons.broken_image_outlined,
        color: AppTheme.textSecondary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return _wrap(errorIcon ?? _defaultError());
    }

    final image = CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: _resolveMemCache(width, memCacheWidth),
      memCacheHeight: _resolveMemCache(height, memCacheHeight),
      placeholder: (_, _) => placeholder ?? _defaultPlaceholder(),
      errorWidget: (_, _, _) => errorIcon ?? _defaultError(),
    );

    return _wrap(image);
  }
}

/// Circular cached avatar.
///
/// Drop-in replacement for `CircleAvatar(backgroundImage: NetworkImage(url))`.
/// Falls back to [child] (typically initials) when [imageUrl] is null/empty.
class AppCachedAvatar extends StatelessWidget {
  final String? imageUrl;
  final double radius;
  final Widget? child;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const AppCachedAvatar({
    super.key,
    required this.imageUrl,
    this.radius = 20,
    this.child,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        child: child,
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? AppTheme.surfaceVariant,
      foregroundColor: foregroundColor,
      backgroundImage: CachedNetworkImageProvider(url),
      onBackgroundImageError: (_, _) {},
      child: child,
    );
  }
}

/// Re-export so callers can use [SkeletonAvatar] as a placeholder without
/// importing the skeletons barrel directly.
typedef AppCachedAvatarSkeleton = SkeletonAvatar;
