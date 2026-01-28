import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';

/// Form Tab Configuration
class FormTab {
  final String key;
  final String label;
  final IconData? icon;
  final bool hasErrors;

  const FormTab({
    required this.key,
    required this.label,
    this.icon,
    this.hasErrors = false,
  });
}

/// Modern Form Tabs with progress bar and animated indicator
class FormTabs extends StatefulWidget {
  final List<FormTab> tabs;
  final String activeTab;
  final ValueChanged<String> onTabChange;
  final double progress;
  final bool showProgress;
  final Widget child;

  const FormTabs({
    super.key,
    required this.tabs,
    required this.activeTab,
    required this.onTabChange,
    this.progress = 0,
    this.showProgress = true,
    required this.child,
  });

  @override
  State<FormTabs> createState() => _FormTabsState();
}

class _FormTabsState extends State<FormTabs> with SingleTickerProviderStateMixin {
  final GlobalKey _tabsKey = GlobalKey();
  final List<GlobalKey> _tabKeys = [];
  double _indicatorLeft = 0;
  double _indicatorWidth = 0;

  @override
  void initState() {
    super.initState();
    _tabKeys.addAll(widget.tabs.map((_) => GlobalKey()));
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateIndicator());
  }

  @override
  void didUpdateWidget(FormTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTab != widget.activeTab || oldWidget.tabs != widget.tabs) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateIndicator());
    }
  }

  void _updateIndicator() {
    final activeIndex = widget.tabs.indexWhere((t) => t.key == widget.activeTab);
    if (activeIndex < 0 || activeIndex >= _tabKeys.length) return;

    final tabKey = _tabKeys[activeIndex];
    final tabContext = tabKey.currentContext;
    final tabsContext = _tabsKey.currentContext;

    if (tabContext == null || tabsContext == null) return;

    final tabBox = tabContext.findRenderObject() as RenderBox?;
    final tabsBox = tabsContext.findRenderObject() as RenderBox?;

    if (tabBox == null || tabsBox == null) return;

    final tabPosition = tabBox.localToGlobal(Offset.zero, ancestor: tabsBox);

    setState(() {
      _indicatorLeft = tabPosition.dx;
      _indicatorWidth = tabBox.size.width;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress Bar
        if (widget.showProgress) _buildProgressBar(),

        // Tabs Container
        _buildTabs(),

        // Content
        Expanded(child: widget.child),
      ],
    );
  }

  Widget _buildProgressBar() {
    final isComplete = widget.progress >= 100;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progresso do formulário',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              Text(
                '${widget.progress.round()}%',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(3),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      width: constraints.maxWidth * (widget.progress / 100).clamp(0, 1),
                      decoration: BoxDecoration(
                        color: isComplete ? AppTheme.success : AppTheme.textPrimary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      key: _tabsKey,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.divider),
        ),
      ),
      child: Stack(
        children: [
          // Tabs Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: widget.tabs.asMap().entries.map((entry) {
                final index = entry.key;
                final tab = entry.value;
                final isActive = tab.key == widget.activeTab;

                return GestureDetector(
                  key: _tabKeys[index],
                  onTap: () => widget.onTabChange(tab.key),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (tab.icon != null) ...[
                          Icon(
                            tab.icon,
                            size: 18,
                            color: isActive ? AppTheme.textPrimary : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          tab.label,
                          style: AppTheme.bodyMedium.copyWith(
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                            color: isActive ? AppTheme.textPrimary : AppTheme.textSecondary,
                          ),
                        ),
                        if (tab.hasErrors) ...[
                          const SizedBox(width: 6),
                          Icon(
                            LucideIcons.alertCircle,
                            size: 14,
                            color: AppTheme.error,
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Animated Indicator
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            bottom: 0,
            left: _indicatorLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              width: _indicatorWidth,
              height: 2,
              decoration: BoxDecoration(
                color: AppTheme.textPrimary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Form Tab Panel - Shows content only when active
class FormTabPanel extends StatelessWidget {
  final String tabKey;
  final String activeTab;
  final Widget child;

  const FormTabPanel({
    super.key,
    required this.tabKey,
    required this.activeTab,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (tabKey != activeTab) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: KeyedSubtree(
        key: ValueKey(tabKey),
        child: child,
      ),
    );
  }
}

/// Stepper-style Form Tabs (alternative design)
class FormStepper extends StatelessWidget {
  final List<FormTab> steps;
  final int currentStep;
  final ValueChanged<int>? onStepTapped;

  const FormStepper({
    super.key,
    required this.steps,
    required this.currentStep,
    this.onStepTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;
          final isActive = index == currentStep;
          final isCompleted = index < currentStep;
          final hasError = step.hasErrors;

          return Expanded(
            child: GestureDetector(
              onTap: onStepTapped != null ? () => onStepTapped!(index) : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // Line before
                      if (index > 0)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: isCompleted || isActive
                                ? AppTheme.primary
                                : AppTheme.divider,
                          ),
                        ),

                      // Circle
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasError
                              ? AppTheme.error
                              : isCompleted
                                  ? AppTheme.success
                                  : isActive
                                      ? AppTheme.primary
                                      : AppTheme.surfaceVariant,
                          border: Border.all(
                            color: hasError
                                ? AppTheme.error
                                : isCompleted
                                    ? AppTheme.success
                                    : isActive
                                        ? AppTheme.primary
                                        : AppTheme.divider,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: hasError
                              ? Icon(LucideIcons.x, size: 16, color: Colors.white)
                              : isCompleted
                                  ? Icon(LucideIcons.check, size: 16, color: Colors.white)
                                  : step.icon != null
                                      ? Icon(
                                          step.icon,
                                          size: 16,
                                          color: isActive
                                              ? Colors.white
                                              : AppTheme.textSecondary,
                                        )
                                      : Text(
                                          '${index + 1}',
                                          style: AppTheme.labelSmall.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: isActive
                                                ? Colors.white
                                                : AppTheme.textSecondary,
                                          ),
                                        ),
                        ),
                      ),

                      // Line after
                      if (index < steps.length - 1)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: isCompleted
                                ? AppTheme.primary
                                : AppTheme.divider,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    step.label,
                    style: AppTheme.labelSmall.copyWith(
                      color: isActive || isCompleted
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
