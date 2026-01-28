import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme.dart';

/// Modern Input Field with icons, states, and formatting
class InputField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final String? successText;
  final bool success;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final Widget? suffix;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLines;
  final int? maxLength;
  final bool enabled;
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final FormFieldValidator<String>? validator;
  final List<TextInputFormatter>? inputFormatters;
  final AutovalidateMode? autovalidateMode;
  final FocusNode? focusNode;
  final TextCapitalization textCapitalization;

  const InputField({
    super.key,
    this.controller,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.successText,
    this.success = false,
    this.prefixIcon,
    this.suffixIcon,
    this.suffix,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.maxLength,
    this.enabled = true,
    this.readOnly = false,
    this.onChanged,
    this.onTap,
    this.validator,
    this.inputFormatters,
    this.autovalidateMode,
    this.focusNode,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  State<InputField> createState() => _InputFieldState();
}

class _InputFieldState extends State<InputField> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  Color get _borderColor {
    if (_hasError || widget.errorText != null) return AppTheme.error;
    if (widget.success) return AppTheme.success;
    if (_isFocused) return AppTheme.textPrimary;
    return AppTheme.divider;
  }

  Color get _iconColor {
    if (_hasError || widget.errorText != null) return AppTheme.error;
    if (widget.success) return AppTheme.success;
    if (_isFocused) return AppTheme.textPrimary;
    return AppTheme.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final hasError = _hasError || widget.errorText != null;
    final hasSuccess = widget.success && !hasError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          obscureText: widget.obscureText,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          onChanged: widget.onChanged,
          onTap: widget.onTap,
          inputFormatters: widget.inputFormatters,
          autovalidateMode: widget.autovalidateMode,
          textCapitalization: widget.textCapitalization,
          validator: (value) {
            final error = widget.validator?.call(value);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _hasError != (error != null)) {
                setState(() => _hasError = error != null);
              }
            });
            return error;
          },
          style: AppTheme.bodyMedium.copyWith(
            color: widget.enabled ? AppTheme.textPrimary : AppTheme.textDisabled,
          ),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hintText,
            errorText: widget.errorText,
            counterText: '',
            labelStyle: AppTheme.bodyMedium.copyWith(
              color: _isFocused ? _iconColor : AppTheme.textSecondary,
            ),
            hintStyle: AppTheme.bodyMedium.copyWith(
              color: AppTheme.textDisabled,
            ),
            prefixIcon: widget.prefixIcon != null
                ? Icon(widget.prefixIcon, size: 20, color: _iconColor)
                : null,
            suffixIcon: _buildSuffixIcon(hasError, hasSuccess),
            filled: true,
            fillColor: hasError
                ? AppTheme.error.withOpacity(0.02)
                : hasSuccess
                    ? AppTheme.success.withOpacity(0.02)
                    : AppTheme.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _borderColor, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.error, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.divider.withOpacity(0.5)),
            ),
          ),
        ),

        // Helper text
        if (widget.helperText != null && !hasError && !hasSuccess) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              widget.helperText!,
              style: AppTheme.labelSmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],

        // Success text
        if (hasSuccess && widget.successText != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Row(
              children: [
                Icon(LucideIcons.checkCircle, size: 12, color: AppTheme.success),
                const SizedBox(width: 4),
                Text(
                  widget.successText!,
                  style: AppTheme.labelSmall.copyWith(
                    color: AppTheme.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget? _buildSuffixIcon(bool hasError, bool hasSuccess) {
    if (widget.suffix != null) return widget.suffix;

    if (hasError) {
      return Icon(LucideIcons.alertCircle, size: 20, color: AppTheme.error);
    }

    if (hasSuccess) {
      return Icon(LucideIcons.checkCircle, size: 20, color: AppTheme.success);
    }

    if (widget.suffixIcon != null) {
      return Icon(widget.suffixIcon, size: 20, color: _iconColor);
    }

    return null;
  }
}

// ============================================
// Specialized Input Components
// ============================================

/// Phone Input with Brazilian formatting (00) 00000-0000
class PhoneInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  const PhoneInput({
    super.key,
    this.controller,
    this.label = 'Telefone',
    this.errorText,
    this.onChanged,
    this.validator,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InputField(
      controller: controller,
      label: label,
      hintText: '(00) 00000-0000',
      errorText: errorText,
      prefixIcon: LucideIcons.phone,
      keyboardType: TextInputType.phone,
      enabled: enabled,
      onChanged: onChanged,
      validator: validator,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        _PhoneInputFormatter(),
      ],
    );
  }
}

class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 11) {
      return oldValue;
    }

    String formatted = '';
    for (int i = 0; i < digits.length; i++) {
      if (i == 0) formatted += '(';
      if (i == 2) formatted += ') ';
      if (i == 7) formatted += '-';
      formatted += digits[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// CPF Input with Brazilian formatting 000.000.000-00
class CPFInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  const CPFInput({
    super.key,
    this.controller,
    this.label = 'CPF',
    this.errorText,
    this.onChanged,
    this.validator,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InputField(
      controller: controller,
      label: label,
      hintText: '000.000.000-00',
      errorText: errorText,
      prefixIcon: LucideIcons.creditCard,
      keyboardType: TextInputType.number,
      enabled: enabled,
      onChanged: onChanged,
      validator: validator,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        _CPFInputFormatter(),
      ],
    );
  }
}

class _CPFInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 11) {
      return oldValue;
    }

    String formatted = '';
    for (int i = 0; i < digits.length; i++) {
      if (i == 3 || i == 6) formatted += '.';
      if (i == 9) formatted += '-';
      formatted += digits[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// CEP Input with Brazilian formatting 00000-000
class CEPInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final bool success;
  final String? successText;

  const CEPInput({
    super.key,
    this.controller,
    this.label = 'CEP',
    this.errorText,
    this.onChanged,
    this.validator,
    this.enabled = true,
    this.success = false,
    this.successText,
  });

  @override
  Widget build(BuildContext context) {
    return InputField(
      controller: controller,
      label: label,
      hintText: '00000-000',
      errorText: errorText,
      prefixIcon: LucideIcons.mapPin,
      keyboardType: TextInputType.number,
      enabled: enabled,
      onChanged: onChanged,
      validator: validator,
      success: success,
      successText: successText,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        _CEPInputFormatter(),
      ],
    );
  }
}

class _CEPInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) {
      return oldValue;
    }

    String formatted = '';
    for (int i = 0; i < digits.length; i++) {
      if (i == 5) formatted += '-';
      formatted += digits[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Currency Input with Brazilian formatting R$ 0,00
class CurrencyInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  const CurrencyInput({
    super.key,
    this.controller,
    this.label = 'Valor',
    this.errorText,
    this.onChanged,
    this.validator,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InputField(
      controller: controller,
      label: label,
      hintText: '0,00',
      errorText: errorText,
      prefixIcon: LucideIcons.dollarSign,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      enabled: enabled,
      onChanged: onChanged,
      validator: validator,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
        _CurrencyInputFormatter(),
      ],
    );
  }
}

class _CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Allow decimal with comma or dot
    String text = newValue.text.replaceAll('.', ',');

    // Only allow one comma
    final parts = text.split(',');
    if (parts.length > 2) {
      return oldValue;
    }

    // Limit decimal places to 2
    if (parts.length == 2 && parts[1].length > 2) {
      text = '${parts[0]},${parts[1].substring(0, 2)}';
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Email Input with validation
class EmailInput extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  const EmailInput({
    super.key,
    this.controller,
    this.label = 'E-mail',
    this.errorText,
    this.onChanged,
    this.validator,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return InputField(
      controller: controller,
      label: label,
      hintText: 'exemplo@email.com',
      errorText: errorText,
      prefixIcon: LucideIcons.mail,
      keyboardType: TextInputType.emailAddress,
      enabled: enabled,
      onChanged: onChanged,
      validator: validator ?? _defaultEmailValidator,
      textCapitalization: TextCapitalization.none,
    );
  }

  String? _defaultEmailValidator(String? value) {
    if (value == null || value.isEmpty) return null;
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'E-mail inválido';
    }
    return null;
  }
}

/// Date Picker Input
class DateInput extends StatelessWidget {
  final DateTime? value;
  final String? label;
  final String? errorText;
  final ValueChanged<DateTime?>? onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool enabled;

  const DateInput({
    super.key,
    this.value,
    this.label = 'Data',
    this.errorText,
    this.onChanged,
    this.firstDate,
    this.lastDate,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final displayText = value != null
        ? '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}'
        : 'Selecionar data';

    return GestureDetector(
      onTap: enabled
          ? () async {
              final date = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: firstDate ?? DateTime(1920),
                lastDate: lastDate ?? DateTime.now().add(const Duration(days: 365)),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: ColorScheme.light(
                        primary: AppTheme.primary,
                        onPrimary: Colors.white,
                        surface: AppTheme.surface,
                        onSurface: AppTheme.textPrimary,
                      ),
                    ),
                    child: child!,
                  );
                },
              );
              onChanged?.call(date);
            }
          : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          prefixIcon: Icon(
            LucideIcons.calendar,
            size: 20,
            color: enabled ? AppTheme.textSecondary : AppTheme.textDisabled,
          ),
          suffixIcon: Icon(
            LucideIcons.chevronDown,
            size: 20,
            color: enabled ? AppTheme.textSecondary : AppTheme.textDisabled,
          ),
          filled: true,
          fillColor: AppTheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.divider),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.divider.withOpacity(0.5)),
          ),
        ),
        child: Text(
          displayText,
          style: AppTheme.bodyMedium.copyWith(
            color: value != null
                ? (enabled ? AppTheme.textPrimary : AppTheme.textDisabled)
                : AppTheme.textDisabled,
          ),
        ),
      ),
    );
  }
}
