import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/feedback_utils.dart';
import '../../../core/theme.dart';
import '../../../models/student.dart';
import '../../../widgets/loading_button.dart';

// ============================================
// EDIT SHEETS
// ============================================

/// Edit Personal Data Sheet
class EditPersonalDataSheet extends StatefulWidget {
  final Student student;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const EditPersonalDataSheet({
    super.key,
    required this.student,
    required this.onSave,
  });

  @override
  State<EditPersonalDataSheet> createState() => _EditPersonalDataSheetState();
}

class _EditPersonalDataSheetState extends State<EditPersonalDataSheet> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _cpfController;
  late final TextEditingController _rgController;
  late final TextEditingController _weightController;
  DateTime? _birthDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(text: widget.student.nickname);
    _phoneController = TextEditingController(text: widget.student.phone);
    _emailController = TextEditingController(text: widget.student.email);
    _cpfController = TextEditingController(text: widget.student.cpf);
    _rgController = TextEditingController(text: widget.student.rg);
    _weightController = TextEditingController(
      text: widget.student.weight?.toString(),
    );
    _birthDate = widget.student.birthDate;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _cpfController.dispose();
    _rgController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await widget.onSave({
        'nickname': _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        'cpf': _cpfController.text.trim().isEmpty
            ? null
            : _cpfController.text.trim(),
        'rg': _rgController.text.trim().isEmpty
            ? null
            : _rgController.text.trim(),
        'weight': _weightController.text.trim().isEmpty
            ? null
            : double.tryParse(_weightController.text.trim()),
        'birthDate': _birthDate,
      });
      if (mounted) {
        context.showSuccess('Dados atualizados!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _EditSheet(
      title: 'Dados Pessoais',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        _SheetTextField(
          label: 'Apelido',
          controller: _nicknameController,
          hint: 'Como gostaria de ser chamado',
        ),
        _SheetDateField(
          label: 'Data de nascimento',
          value: _birthDate,
          onChanged: (d) => setState(() => _birthDate = d),
        ),
        _SheetTextField(
          label: 'Telefone',
          controller: _phoneController,
          hint: '(00) 00000-0000',
          keyboardType: TextInputType.phone,
        ),
        _SheetTextField(
          label: 'Email',
          controller: _emailController,
          hint: 'seu@email.com',
          keyboardType: TextInputType.emailAddress,
        ),
        _SheetTextField(
          label: 'CPF',
          controller: _cpfController,
          hint: '000.000.000-00',
          keyboardType: TextInputType.number,
        ),
        _SheetTextField(
          label: 'RG',
          controller: _rgController,
          hint: 'Numero do RG',
        ),
        _SheetTextField(
          label: 'Peso (kg)',
          controller: _weightController,
          hint: 'Ex: 75.5',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
    );
  }
}

/// Edit Address Sheet
class EditAddressSheet extends StatefulWidget {
  final Student student;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const EditAddressSheet({
    super.key,
    required this.student,
    required this.onSave,
  });

  @override
  State<EditAddressSheet> createState() => _EditAddressSheetState();
}

class _EditAddressSheetState extends State<EditAddressSheet> {
  late final TextEditingController _zipCodeController;
  late final TextEditingController _streetController;
  late final TextEditingController _numberController;
  late final TextEditingController _complementController;
  late final TextEditingController _neighborhoodController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final address = widget.student.address;
    _zipCodeController = TextEditingController(text: address?.zipCode);
    _streetController = TextEditingController(text: address?.street);
    _numberController = TextEditingController(text: address?.number);
    _complementController = TextEditingController(text: address?.complement);
    _neighborhoodController = TextEditingController(
      text: address?.neighborhood,
    );
    _cityController = TextEditingController(text: address?.city);
    _stateController = TextEditingController(text: address?.state);
  }

  @override
  void dispose() {
    _zipCodeController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _complementController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final hasData =
          _streetController.text.trim().isNotEmpty ||
          _cityController.text.trim().isNotEmpty;
      await widget.onSave({
        'address': hasData
            ? {
                'zipCode': _zipCodeController.text.trim(),
                'street': _streetController.text.trim(),
                'number': _numberController.text.trim(),
                'complement': _complementController.text.trim().isEmpty
                    ? null
                    : _complementController.text.trim(),
                'neighborhood': _neighborhoodController.text.trim(),
                'city': _cityController.text.trim(),
                'state': _stateController.text.trim(),
              }
            : null,
      });
      if (mounted) {
        context.showSuccess('Endereco atualizado!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _EditSheet(
      title: 'Endereco',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        _SheetTextField(
          label: 'CEP',
          controller: _zipCodeController,
          hint: '00000-000',
          keyboardType: TextInputType.number,
        ),
        _SheetTextField(
          label: 'Rua',
          controller: _streetController,
          hint: 'Nome da rua',
        ),
        _SheetTextField(
          label: 'Numero',
          controller: _numberController,
          hint: '123',
          keyboardType: TextInputType.number,
        ),
        _SheetTextField(
          label: 'Complemento',
          controller: _complementController,
          hint: 'Apto, bloco...',
        ),
        _SheetTextField(
          label: 'Bairro',
          controller: _neighborhoodController,
          hint: 'Nome do bairro',
        ),
        _SheetTextField(
          label: 'Cidade',
          controller: _cityController,
          hint: 'Nome da cidade',
        ),
        _SheetTextField(
          label: 'Estado',
          controller: _stateController,
          hint: 'UF',
        ),
      ],
    );
  }
}

/// Combined Edit Health & Emergency Contact Sheet
class EditHealthAndEmergencySheet extends StatefulWidget {
  final Student student;
  final Future<void> Function(Map<String, dynamic>) onSave;

  const EditHealthAndEmergencySheet({
    super.key,
    required this.student,
    required this.onSave,
  });

  @override
  State<EditHealthAndEmergencySheet> createState() =>
      _EditHealthAndEmergencySheetState();
}

class _EditHealthAndEmergencySheetState
    extends State<EditHealthAndEmergencySheet> {
  // Health controllers
  late final TextEditingController _bloodTypeController;
  late final TextEditingController _allergiesController;
  late final TextEditingController _healthNotesController;
  // Emergency controllers
  late final TextEditingController _emergencyNameController;
  late final TextEditingController _emergencyPhoneController;
  late final TextEditingController _emergencyRelationshipController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _bloodTypeController = TextEditingController(
      text: widget.student.bloodType,
    );
    _allergiesController = TextEditingController(
      text: widget.student.allergies?.join(', '),
    );
    _healthNotesController = TextEditingController(
      text: widget.student.healthNotes,
    );
    _emergencyNameController = TextEditingController(
      text: widget.student.emergencyContact?.name,
    );
    _emergencyPhoneController = TextEditingController(
      text: widget.student.emergencyContact?.phone,
    );
    _emergencyRelationshipController = TextEditingController(
      text: widget.student.emergencyContact?.relationship,
    );
  }

  @override
  void dispose() {
    _bloodTypeController.dispose();
    _allergiesController.dispose();
    _healthNotesController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _emergencyRelationshipController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final allergiesText = _allergiesController.text.trim();
      final hasEmergencyData =
          _emergencyNameController.text.trim().isNotEmpty ||
          _emergencyPhoneController.text.trim().isNotEmpty;

      await widget.onSave({
        'bloodType': _bloodTypeController.text.trim().isEmpty
            ? null
            : _bloodTypeController.text.trim(),
        'allergies': allergiesText.isEmpty
            ? null
            : allergiesText
                  .split(',')
                  .map((a) => a.trim())
                  .where((a) => a.isNotEmpty)
                  .toList(),
        'healthNotes': _healthNotesController.text.trim().isEmpty
            ? null
            : _healthNotesController.text.trim(),
        'emergencyContact': hasEmergencyData
            ? {
                'name': _emergencyNameController.text.trim(),
                'phone': _emergencyPhoneController.text.trim(),
                'relationship': _emergencyRelationshipController.text.trim(),
              }
            : null,
      });
      if (mounted) {
        context.showSuccess('Dados atualizados!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) context.showError('Erro: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _EditSheet(
      title: 'Saude e Emergencia',
      isSaving: _isSaving,
      onSave: _save,
      children: [
        // Health section label
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'SAUDE',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        _SheetTextField(
          label: 'Tipo sanguineo',
          controller: _bloodTypeController,
          hint: 'Ex: A+, O-, AB+',
        ),
        _SheetTextField(
          label: 'Alergias',
          controller: _allergiesController,
          hint: 'Separe por virgula',
        ),
        _SheetTextField(
          label: 'Observacoes',
          controller: _healthNotesController,
          hint: 'Lesoes, medicamentos...',
          maxLines: 3,
        ),
        // Emergency section label
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: Text(
            'CONTATO DE EMERGENCIA',
            style: AppTheme.labelSmall.copyWith(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        _SheetTextField(
          label: 'Nome',
          controller: _emergencyNameController,
          hint: 'Nome do contato',
        ),
        _SheetTextField(
          label: 'Telefone',
          controller: _emergencyPhoneController,
          hint: '(00) 00000-0000',
          keyboardType: TextInputType.phone,
        ),
        _SheetTextField(
          label: 'Parentesco',
          controller: _emergencyRelationshipController,
          hint: 'Ex: Mae, Pai, Conjuge',
        ),
      ],
    );
  }
}

// ============================================
// SHARED SHEET COMPONENTS
// ============================================

/// Base Edit Sheet
class _EditSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool isSaving;
  final VoidCallback onSave;

  const _EditSheet({
    required this.title,
    required this.children,
    required this.isSaving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppTheme.titleLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Form
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
            // Save Button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: Border(top: BorderSide(color: AppTheme.divider)),
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: LoadingButton(
                    isLoading: isSaving,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onSave();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Salvar',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sheet Text Field
class _SheetTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;

  const _SheetTextField({
    required this.label,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.labelMedium.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            style: AppTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textDisabled,
              ),
              filled: true,
              fillColor: AppTheme.surfaceVariant.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sheet Date Field
class _SheetDateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  const _SheetDateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTheme.labelMedium.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    value ??
                    DateTime.now().subtract(const Duration(days: 365 * 20)),
                firstDate: DateTime(1940),
                lastDate: DateTime.now(),
              );
              if (picked != null) onChanged(picked);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value != null
                          ? DateFormat('dd/MM/yyyy').format(value!)
                          : 'Selecionar data',
                      style: AppTheme.bodyMedium.copyWith(
                        color: value != null
                            ? AppTheme.textPrimary
                            : AppTheme.textDisabled,
                      ),
                    ),
                  ),
                  Icon(
                    LucideIcons.calendar,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
