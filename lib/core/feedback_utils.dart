import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'theme.dart';

/// Centralized feedback utilities for consistent UX across the app
class FeedbackUtils {
  FeedbackUtils._();

  /// Show a success SnackBar with modern styling
  static void showSuccess(BuildContext context, String message, {Duration? duration}) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(LucideIcons.checkCircle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }

  /// Show an error SnackBar with modern styling
  static void showError(BuildContext context, String message, {Duration? duration}) {
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(LucideIcons.alertCircle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  /// Show a warning SnackBar with modern styling
  static void showWarning(BuildContext context, String message, {Duration? duration}) {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(LucideIcons.alertTriangle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.warning,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }

  /// Show an info SnackBar with modern styling
  static void showInfo(BuildContext context, String message, {Duration? duration}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(LucideIcons.info, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.info,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }

  /// Show a loading SnackBar (auto-dismiss when calling hideLoading)
  static void showLoading(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(minutes: 5), // Long duration, manually dismissed
      ),
    );
  }

  /// Hide the current SnackBar
  static void hideSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  /// Show a modern confirmation dialog
  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Confirmar',
    String cancelText = 'Cancelar',
    Color? confirmColor,
    IconData? icon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (confirmColor ?? AppTheme.error).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: confirmColor ?? AppTheme.error, size: 24),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                title,
                style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              cancelText,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor ?? AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Show a delete confirmation dialog
  static Future<bool> showDeleteConfirmDialog(
    BuildContext context, {
    required String itemName,
    String? customMessage,
  }) {
    return showConfirmDialog(
      context,
      title: 'Excluir $itemName?',
      message: customMessage ?? 'Esta acao nao pode ser desfeita.',
      confirmText: 'Excluir',
      confirmColor: AppTheme.error,
      icon: LucideIcons.trash2,
    );
  }

  // ── Haptics ──────────────────────────────────────────────────────────────
  // Thin, named wrappers so call sites express *intent* (tap/select/success/
  // failure) instead of guessing an impact strength. Keeps the tactile
  // vocabulary consistent app-wide.

  /// A light tick — taps on cards/tiles and minor toggles.
  static void tapHaptic() => HapticFeedback.lightImpact();

  /// A selection tick — choosing an option/segment.
  static void selectHaptic() => HapticFeedback.selectionClick();

  /// A firm thud — a genuine success (payment confirmed, graduation).
  static void successHaptic() => HapticFeedback.heavyImpact();

  /// A medium bump — a recoverable failure/validation error.
  static void errorHaptic() => HapticFeedback.mediumImpact();

  /// Runs an async [action] with standardized feedback: an optional haptic on
  /// success, a success SnackBar (when [successMessage] is set) and an error
  /// SnackBar derived from [errorMessage] on throw. Returns the action's result,
  /// or null when it threw.
  ///
  /// This is the single place that wires "do the thing → tell the user how it
  /// went" so screens stop hand-rolling try/catch + snackbar boilerplate. It is
  /// purely a feedback wrapper — it never swallows side effects, only reports
  /// the outcome, and rethrows nothing (callers branch on the null result).
  ///
  /// [context] is re-checked for mountedness via [context.mounted] before any
  /// SnackBar, so it is safe to await across an async gap.
  ///
  /// Usage:
  /// ```dart
  /// final ok = await FeedbackUtils.runWithFeedback(
  ///   context,
  ///   action: () => repo.save(item),
  ///   successMessage: 'Salvo!',
  ///   errorMessage: 'Nao foi possivel salvar.',
  /// );
  /// ```
  static Future<T?> runWithFeedback<T>(
    BuildContext context, {
    required Future<T> Function() action,
    String? successMessage,
    String errorMessage = 'Algo deu errado. Tente novamente.',
    bool successHapticFeedback = true,
  }) async {
    try {
      final result = await action();
      if (context.mounted) {
        if (successHapticFeedback) successHaptic();
        if (successMessage != null) showSuccess(context, successMessage);
      }
      return result;
    } catch (_) {
      if (context.mounted) showError(context, errorMessage);
      return null;
    }
  }
}

/// Extension for easy access from BuildContext
extension FeedbackExtension on BuildContext {
  void showSuccess(String message) => FeedbackUtils.showSuccess(this, message);
  void showError(String message) => FeedbackUtils.showError(this, message);
  void showWarning(String message) => FeedbackUtils.showWarning(this, message);
  void showInfo(String message) => FeedbackUtils.showInfo(this, message);
  void showLoading(String message) => FeedbackUtils.showLoading(this, message);
  void hideSnackBar() => FeedbackUtils.hideSnackBar(this);
}
