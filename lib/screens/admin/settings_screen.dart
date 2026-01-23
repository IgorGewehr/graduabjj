import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../services/services.dart';

/// Admin Settings Screen - Academy configuration
class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  ConsumerState<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  AcademySettings? _settings;
  bool _isLoading = true;
  bool _isSaving = false;

  // Form controllers
  final _nameController = TextEditingController();
  final _cnpjController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _pixKeyController = TextEditingController();
  final _portalSloganController = TextEditingController();
  final _autoGraduationAttendancesController = TextEditingController();

  PixKeyType? _pixKeyType;
  bool _abacatePayEnabled = false;
  bool _autoGraduationEnabled = false;
  bool _storeEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cnpjController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipCodeController.dispose();
    _pixKeyController.dispose();
    _portalSloganController.dispose();
    _autoGraduationAttendancesController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    try {
      final service = SettingsService(FirebaseService.academyId);
      final settings = await service.getAcademySettings();

      if (settings != null) {
        setState(() {
          _settings = settings;
          _nameController.text = settings.name;
          _cnpjController.text = settings.cnpj ?? '';
          _emailController.text = settings.email ?? '';
          _phoneController.text = settings.phone ?? '';
          _addressController.text = settings.address ?? '';
          _cityController.text = settings.city ?? '';
          _stateController.text = settings.state ?? '';
          _zipCodeController.text = settings.zipCode ?? '';
          _pixKeyController.text = settings.pixKey ?? '';
          _portalSloganController.text = settings.portalSlogan ?? '';
          _autoGraduationAttendancesController.text =
              settings.autoGraduationAttendances?.toString() ?? '';
          _pixKeyType = settings.pixKeyType;
          _abacatePayEnabled = settings.abacatePayEnabled;
          _autoGraduationEnabled = settings.autoGraduationEnabled;
          _storeEnabled = settings.storeEnabled;
        });
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      final service = SettingsService(FirebaseService.academyId);

      // Save basic info
      await service.updateBasicInfo(
        name: _nameController.text,
        cnpj: _cnpjController.text.isEmpty ? null : _cnpjController.text,
        email: _emailController.text.isEmpty ? null : _emailController.text,
        phone: _phoneController.text.isEmpty ? null : _phoneController.text,
        address: _addressController.text.isEmpty ? null : _addressController.text,
        city: _cityController.text.isEmpty ? null : _cityController.text,
        state: _stateController.text.isEmpty ? null : _stateController.text,
        zipCode: _zipCodeController.text.isEmpty ? null : _zipCodeController.text,
      );

      // Save PIX info
      if (_pixKeyController.text.isNotEmpty && _pixKeyType != null) {
        await service.updatePixInfo(_pixKeyController.text, _pixKeyType!);
      }

      // Save branding
      await service.updateBranding(
        portalSlogan: _portalSloganController.text.isEmpty
            ? null
            : _portalSloganController.text,
      );

      // Save auto-graduation
      await service.updateAutoGraduation(
        _autoGraduationEnabled,
        attendances: _autoGraduationAttendancesController.text.isNotEmpty
            ? int.tryParse(_autoGraduationAttendancesController.text)
            : null,
      );

      // Save store settings
      await service.updateStoreSettings(enabled: _storeEnabled);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurações salvas com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurações'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton.icon(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save),
              label: const Text('Salvar'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBasicInfoSection(),
                  const SizedBox(height: 24),
                  _buildAddressSection(),
                  const SizedBox(height: 24),
                  _buildFinancialSection(),
                  const SizedBox(height: 24),
                  _buildBrandingSection(),
                  const SizedBox(height: 24),
                  _buildFeaturesSection(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildBasicInfoSection() {
    return _SettingsSection(
      title: 'Informações Básicas',
      icon: Icons.business,
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Nome da Academia *',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cnpjController,
          decoration: const InputDecoration(
            labelText: 'CNPJ',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'E-mail',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Telefone',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAddressSection() {
    return _SettingsSection(
      title: 'Endereço',
      icon: Icons.location_on,
      children: [
        TextField(
          controller: _addressController,
          decoration: const InputDecoration(
            labelText: 'Endereço',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _cityController,
                decoration: const InputDecoration(
                  labelText: 'Cidade',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _stateController,
                decoration: const InputDecoration(
                  labelText: 'Estado',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: _zipCodeController,
                decoration: const InputDecoration(
                  labelText: 'CEP',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFinancialSection() {
    return _SettingsSection(
      title: 'Financeiro',
      icon: Icons.attach_money,
      children: [
        const Text(
          'Chave PIX',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _pixKeyController,
                decoration: const InputDecoration(
                  labelText: 'Chave PIX',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DropdownButtonFormField<PixKeyType>(
                value: _pixKeyType,
                decoration: const InputDecoration(
                  labelText: 'Tipo',
                  border: OutlineInputBorder(),
                ),
                items: PixKeyType.values.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type.label),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _pixKeyType = value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('AbacatePay'),
          subtitle: const Text('Integração com pagamentos PIX automáticos'),
          value: _abacatePayEnabled,
          onChanged: (value) {
            setState(() => _abacatePayEnabled = value);
          },
        ),
      ],
    );
  }

  Widget _buildBrandingSection() {
    return _SettingsSection(
      title: 'Personalização',
      icon: Icons.palette,
      children: [
        TextField(
          controller: _portalSloganController,
          decoration: const InputDecoration(
            labelText: 'Slogan do Portal',
            hintText: 'Ex: "Transformando vidas através do Jiu-Jitsu"',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: _settings?.logoUrl != null
              ? CircleAvatar(
                  backgroundImage: NetworkImage(_settings!.logoUrl!),
                )
              : const CircleAvatar(
                  child: Icon(Icons.image),
                ),
          title: const Text('Logo da Academia'),
          subtitle: const Text('Clique para alterar'),
          trailing: const Icon(Icons.edit),
          onTap: () {
            // TODO: Implement image picker
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Upload de imagem em desenvolvimento')),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFeaturesSection() {
    return _SettingsSection(
      title: 'Funcionalidades',
      icon: Icons.settings,
      children: [
        SwitchListTile(
          title: const Text('Graduação Automática'),
          subtitle: const Text('Sugerir graduações com base em presenças'),
          value: _autoGraduationEnabled,
          onChanged: (value) {
            setState(() => _autoGraduationEnabled = value);
          },
        ),
        if (_autoGraduationEnabled) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _autoGraduationAttendancesController,
            decoration: const InputDecoration(
              labelText: 'Presenças para sugestão',
              hintText: 'Ex: 30',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
        ],
        const Divider(),
        SwitchListTile(
          title: const Text('Loja'),
          subtitle: const Text('Habilitar módulo de loja/produtos'),
          value: _storeEnabled,
          onChanged: (value) {
            setState(() => _storeEnabled = value);
          },
        ),
      ],
    );
  }
}

/// Settings Section Widget
class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
