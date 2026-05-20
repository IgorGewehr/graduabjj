import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../api/dto/financial_dto.dart' as api_fin;
import '../../../api/repositories.dart' as tatami_repos;
import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
// abacate_pay_service.dart removido — CardData não é mais enviado ao backend.
import '../../../providers/selected_academy_provider.dart';

/// Card Payment Bottom Sheet
class OrderCardPaymentSheet extends ConsumerStatefulWidget {
  final String orderId;
  final double amount;
  final String studentId;
  final String studentName;
  final VoidCallback onPaymentSuccess;

  const OrderCardPaymentSheet({
    super.key,
    required this.orderId,
    required this.amount,
    required this.studentId,
    required this.studentName,
    required this.onPaymentSuccess,
  });

  @override
  ConsumerState<OrderCardPaymentSheet> createState() =>
      _OrderCardPaymentSheetState();
}

class _OrderCardPaymentSheetState extends ConsumerState<OrderCardPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _cardNumberController = TextEditingController();
  final _cardHolderController = TextEditingController();
  final _expirationController = TextEditingController();
  final _cvvController = TextEditingController();
  final _cpfController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _cardNumberController.dispose();
    _cardHolderController.dispose();
    _expirationController.dispose();
    _cvvController.dispose();
    _cpfController.dispose();
    super.dispose();
  }

  String _formatCardNumber(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digitsOnly.length && i < 16; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digitsOnly[i]);
    }
    return buffer.toString();
  }

  String _formatExpiration(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length >= 2) {
      return '${digitsOnly.substring(0, 2)}/${digitsOnly.substring(2, digitsOnly.length.clamp(2, 4))}';
    }
    return digitsOnly;
  }

  String _formatCpf(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digitsOnly.length && i < 11; i++) {
      if (i == 3 || i == 6) buffer.write('.');
      if (i == 9) buffer.write('-');
      buffer.write(digitsOnly[i]);
    }
    return buffer.toString();
  }

  Future<void> _handlePayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final academyId = ref.read(safeAcademyIdProvider) ?? '';

    try {
      await ref.read(tatami_repos.financialRepoProvider).payWithCard(
            academyId,
            widget.orderId,
            body: api_fin.PayIntentRequest(
              customerName: widget.studentName,
            ),
          );

      // Tatami: POST pay/card retorna receiptUrl (redirect) ou confirma
      // diretamente. Qualquer resposta sem exceção = aprovado.
      if (mounted) {
        context.showSuccess('Pagamento aprovado!');
        widget.onPaymentSuccess();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao processar pagamento: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      LucideIcons.creditCard,
                      color: AppTheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pagar com Cartao',
                          style: AppTheme.titleLarge.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'R\$ ${widget.amount.toStringAsFixed(2)}',
                          style: AppTheme.titleMedium.copyWith(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Error Message
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.errorLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.alertCircle,
                        color: AppTheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Card Number
              TextFormField(
                controller: _cardNumberController,
                decoration: const InputDecoration(
                  labelText: 'Numero do Cartao',
                  hintText: '0000 0000 0000 0000',
                  prefixIcon: Icon(LucideIcons.creditCard),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final formatted = _formatCardNumber(value);
                  if (formatted != value) {
                    _cardNumberController.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: formatted.length,
                      ),
                    );
                  }
                },
                validator: (value) {
                  if (value == null || value.replaceAll(' ', '').length < 16) {
                    return 'Numero do cartao invalido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Card Holder
              TextFormField(
                controller: _cardHolderController,
                decoration: const InputDecoration(
                  labelText: 'Nome no Cartao',
                  hintText: 'NOME COMO NO CARTAO',
                  prefixIcon: Icon(LucideIcons.user),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Nome obrigatorio';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Expiration and CVV
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _expirationController,
                      decoration: const InputDecoration(
                        labelText: 'Validade',
                        hintText: 'MM/AA',
                        prefixIcon: Icon(LucideIcons.calendar),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        final formatted = _formatExpiration(value);
                        if (formatted != value) {
                          _expirationController.value = TextEditingValue(
                            text: formatted,
                            selection: TextSelection.collapsed(
                              offset: formatted.length,
                            ),
                          );
                        }
                      },
                      validator: (value) {
                        if (value == null ||
                            !value.contains('/') ||
                            value.length < 5) {
                          return 'Invalido';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _cvvController,
                      decoration: const InputDecoration(
                        labelText: 'CVV',
                        hintText: '000',
                        prefixIcon: Icon(LucideIcons.lock),
                      ),
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 4,
                      validator: (value) {
                        if (value == null || value.length < 3) {
                          return 'Invalido';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // CPF
              TextFormField(
                controller: _cpfController,
                decoration: const InputDecoration(
                  labelText: 'CPF do Titular',
                  hintText: '000.000.000-00',
                  prefixIcon: Icon(LucideIcons.fileText),
                ),
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  final formatted = _formatCpf(value);
                  if (formatted != value) {
                    _cpfController.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: formatted.length,
                      ),
                    );
                  }
                },
                validator: (value) {
                  if (value == null ||
                      value.replaceAll(RegExp(r'\D'), '').length < 11) {
                    return 'CPF invalido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _handlePayment,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(LucideIcons.check),
                  label: Text(_isLoading ? 'Processando...' : 'Pagar'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              // Security Note
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    LucideIcons.shield,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Pagamento seguro',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
