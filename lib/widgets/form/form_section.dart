import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';

/// Modern Form Section with collapsible support, badges, and variants
class FormSection extends StatefulWidget {
  /// Section title
  final String title;

  /// Optional subtitle/description
  final String? subtitle;

  /// Optional icon
  final IconData? icon;

  /// Section content
  final Widget child;

  /// Whether section is collapsible
  final bool collapsible;

  /// Initial collapsed state (only for collapsible)
  final bool defaultCollapsed;

  /// Optional badge (e.g., "Obrigatório", "Opcional")
  final String? badge;

  /// Badge color variant
  final BadgeVariant badgeVariant;

  /// Section visual variant
  final FormSectionVariant variant;

  /// Content padding
  final FormSectionPadding padding;

  const FormSection({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.child,
    this.collapsible = false,
    this.defaultCollapsed = false,
    this.badge,
    this.badgeVariant = BadgeVariant.defaultVariant,
    this.variant = FormSectionVariant.card,
    this.padding = FormSectionPadding.medium,
  });

  @override
  State<FormSection> createState() => _FormSectionState();
}

class _FormSectionState extends State<FormSection> with SingleTickerProviderStateMixin {
  late bool _isCollapsed;
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _isCollapsed = widget.defaultCollapsed;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(
      begin: 0,
      end: -0.25,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    if (_isCollapsed) {
      _animationController.value = 1;
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleCollapse() {
    setState(() {
      _isCollapsed = !_isCollapsed;
      if (_isCollapsed) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  Color get _badgeBackgroundColor {
    switch (widget.badgeVariant) {
      case BadgeVariant.warning:
        return const Color(0xFFFEF3C7);
      case BadgeVariant.success:
        return const Color(0xFFDCFCE7);
      case BadgeVariant.error:
        return const Color(0xFFFEE2E2);
      case BadgeVariant.defaultVariant:
        return AppTheme.surfaceVariant;
    }
  }

  Color get _badgeTextColor {
    switch (widget.badgeVariant) {
      case BadgeVariant.warning:
        return const Color(0xFF92400E);
      case BadgeVariant.success:
        return const Color(0xFF166534);
      case BadgeVariant.error:
        return const Color(0xFF991B1B);
      case BadgeVariant.defaultVariant:
        return AppTheme.textSecondary;
    }
  }

  double get _paddingValue {
    switch (widget.padding) {
      case FormSectionPadding.none:
        return 0;
      case FormSectionPadding.small:
        return 12;
      case FormSectionPadding.medium:
        return 16;
      case FormSectionPadding.large:
        return 20;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCard = widget.variant == FormSectionVariant.card;
    final isOutlined = widget.variant == FormSectionVariant.outlined;
    final hasDecoration = isCard || isOutlined;

    return Container(
      decoration: BoxDecoration(
        color: isCard ? AppTheme.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: hasDecoration
            ? Border.all(color: isCard ? AppTheme.divider : AppTheme.surfaceVariant)
            : null,
      ),
      clipBehavior: hasDecoration ? Clip.antiAlias : Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(hasDecoration),

          // Content
          if (widget.collapsible)
            AnimatedCrossFade(
              firstChild: _buildContent(hasDecoration),
              secondChild: const SizedBox.shrink(),
              crossFadeState: _isCollapsed
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeInOut,
            )
          else
            _buildContent(hasDecoration),
        ],
      ),
    );
  }

  Widget _buildHeader(bool hasDecoration) {
    return GestureDetector(
      onTap: widget.collapsible ? _toggleCollapse : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.all(hasDecoration ? _paddingValue : 0),
        decoration: BoxDecoration(
          color: hasDecoration ? AppTheme.surfaceVariant.withOpacity(0.5) : Colors.transparent,
          border: hasDecoration && !_isCollapsed
              ? Border(bottom: BorderSide(color: AppTheme.divider))
              : null,
        ),
        child: Row(
          children: [
            // Icon
            if (widget.icon != null) ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.icon,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
            ],

            // Title and Subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.title,
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (widget.badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _badgeBackgroundColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.badge!.toUpperCase(),
                            style: AppTheme.labelSmall.copyWith(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: _badgeTextColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle!,
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Collapse Icon
            if (widget.collapsible)
              RotationTransition(
                turns: _rotationAnimation,
                child: Icon(
                  LucideIcons.chevronDown,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool hasDecoration) {
    return Padding(
      padding: EdgeInsets.all(hasDecoration ? _paddingValue : 0),
      child: widget.child,
    );
  }
}

/// Badge color variants
enum BadgeVariant {
  defaultVariant,
  warning,
  success,
  error,
}

/// Form section visual variants
enum FormSectionVariant {
  /// Default with no decoration
  defaultVariant,
  /// Card with background and border
  card,
  /// Outlined with border only
  outlined,
}

/// Form section padding options
enum FormSectionPadding {
  none,
  small,
  medium,
  large,
}

/// Form Divider with optional label
class FormDivider extends StatelessWidget {
  final String? label;
  final FormDividerSpacing spacing;

  const FormDivider({
    super.key,
    this.label,
    this.spacing = FormDividerSpacing.medium,
  });

  double get _spacingValue {
    switch (spacing) {
      case FormDividerSpacing.small:
        return 12;
      case FormDividerSpacing.medium:
        return 20;
      case FormDividerSpacing.large:
        return 28;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (label != null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: _spacingValue),
        child: Row(
          children: [
            Expanded(child: Container(height: 1, color: AppTheme.divider)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                label!.toUpperCase(),
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                  fontSize: 10,
                ),
              ),
            ),
            Expanded(child: Container(height: 1, color: AppTheme.divider)),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: _spacingValue),
      child: Container(height: 1, color: AppTheme.divider),
    );
  }
}

enum FormDividerSpacing {
  small,
  medium,
  large,
}

/// Form Row for inline fields (responsive)
class FormRow extends StatelessWidget {
  final List<Widget> children;
  final double gap;
  final CrossAxisAlignment crossAxisAlignment;

  const FormRow({
    super.key,
    required this.children,
    this.gap = 12,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Stack vertically on narrow screens
        if (constraints.maxWidth < 400) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children.map((child) {
              final index = children.indexOf(child);
              return Padding(
                padding: EdgeInsets.only(top: index > 0 ? gap : 0),
                child: child,
              );
            }).toList(),
          );
        }

        // Row on wider screens
        return Row(
          crossAxisAlignment: crossAxisAlignment,
          children: children.asMap().entries.map((entry) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: entry.key > 0 ? gap : 0),
                child: entry.value,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
