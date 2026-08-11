import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';

/// Campo de busca visualmente consistente que mantém a digitação responsiva e
/// só notifica a lista depois de uma pausa curta.
///
/// O botão de limpar é imediato: além de limpar o texto, cancela o debounce e
/// restaura a listagem completa sem esperar outro frame de busca.
class DebouncedSearchField extends StatefulWidget {
  const DebouncedSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.controller,
    this.trailing,
    this.debounce = const Duration(milliseconds: 250),
    this.backgroundColor,
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final Widget? trailing;
  final Duration debounce;
  final Color? backgroundColor;

  @override
  State<DebouncedSearchField> createState() => _DebouncedSearchFieldState();
}

class _DebouncedSearchFieldState extends State<DebouncedSearchField> {
  late TextEditingController _controller;
  late bool _ownsController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _attachController(widget.controller);
  }

  @override
  void didUpdateWidget(covariant DebouncedSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController();
      _attachController(widget.controller);
    }
  }

  void _attachController(TextEditingController? external) {
    _ownsController = external == null;
    _controller = external ?? TextEditingController();
    _controller.addListener(_refreshClearAction);
  }

  void _detachController() {
    _controller.removeListener(_refreshClearAction);
    if (_ownsController) _controller.dispose();
  }

  void _refreshClearAction() {
    if (mounted) setState(() {});
  }

  void _schedule(String value) {
    _timer?.cancel();
    if (value.isEmpty || widget.debounce == Duration.zero) {
      widget.onChanged(value);
      return;
    }
    _timer = Timer(widget.debounce, () {
      if (mounted) widget.onChanged(value);
    });
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    widget.onChanged('');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _detachController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: _schedule,
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textDisabled,
                ),
                prefixIcon: Icon(
                  LucideIcons.search,
                  color: AppTheme.textSecondary,
                  size: 20,
                ),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar busca',
                        onPressed: _clear,
                        icon: Icon(
                          LucideIcons.x,
                          color: AppTheme.textSecondary,
                          size: 18,
                        ),
                      ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
          if (widget.trailing != null) ...[
            Container(width: 1, height: 24, color: AppTheme.divider),
            widget.trailing!,
          ],
        ],
      ),
    );
  }
}
