import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/access_control/turnstile_registry.dart';
import '../../core/feedback_utils.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import 'device_enrollment_screen.dart';

/// Tela de CRUD das catracas (devices) da academia.
///
/// Cada documento vive em `academies/{academyId}/devices/{deviceId}` e é o que o
/// backend de ingestão (functions/access_control/ingest.js) lê para autenticar e
/// rotear o evento de acesso. Campos relevantes:
///   - vendor (controlid|zkteco|intelbras) — indexa o REGISTRY de adapters.
///   - secret (HMAC) — segredo compartilhado; NUNCA sai do server na ingestão.
///   - enabled — gate fail-closed (device desligado => 403 no portão).
///   - name — rótulo humano.
///   - userMap (externalUserId -> studentId) — enrollment é FASE FUTURA (TODO).
///   - sport?/category?/scheduleToleranceMinutes? — pistas p/ o class_resolver.
///
/// O `vendor` aqui DEVE bater com o id do adapter no backend; por isso o seletor
/// lê de [kTurnstileVendors] (fonte única). O `secret` é gerado no cliente e
/// mostrado UMA vez para o admin copiar e configurar na catraca física.
class AdminDevicesScreen extends ConsumerWidget {
  const AdminDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // O academyId vem do usuário atual (mesmo padrão das outras telas admin —
    // ver competitions_screen.dart). Sem academia, não há onde gravar.
    final currentUser = ref.watch(currentUserProvider).valueOrNull;
    final academyId = currentUser?.academyId;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Catracas'),
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      floatingActionButton: academyId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openForm(context, academyId, null, null),
              backgroundColor: AppTheme.primary,
              icon: const Icon(LucideIcons.plus, color: Colors.white),
              label: const Text(
                'Adicionar',
                style: TextStyle(color: Colors.white),
              ),
            ),
      body: academyId == null
          ? const _NoAcademyState()
          : _DevicesList(academyId: academyId),
    );
  }

  /// Abre o bottom sheet de criação/edição. [deviceId]+[data] nulos => criação.
  static void _openForm(
    BuildContext context,
    String academyId,
    String? deviceId,
    Map<String, dynamic>? data,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeviceFormSheet(
        academyId: academyId,
        deviceId: deviceId,
        existing: data,
      ),
    );
  }
}

/// Lista reativa das catracas cadastradas (stream do Firestore).
class _DevicesList extends StatelessWidget {
  const _DevicesList({required this.academyId});

  final String academyId;

  CollectionReference<Map<String, dynamic>> get _col => FirebaseFirestore
      .instance
      .collection('academies')
      .doc(academyId)
      .collection('devices');

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _col.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(message: snapshot.error.toString());
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const _EmptyState();
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final doc = docs[i];
            return _DeviceCard(
              academyId: academyId,
              deviceId: doc.id,
              data: doc.data(),
            );
          },
        );
      },
    );
  }
}

/// Card de uma catraca: nome + fabricante + estado (enabled). Toca para editar.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.academyId,
    required this.deviceId,
    required this.data,
  });

  final String academyId;
  final String deviceId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] as String?)?.trim();
    final vendorId = data['vendor'] as String?;
    final vendor = turnstileVendorById(vendorId);
    final enabled = data['enabled'] == true;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () =>
          AdminDevicesScreen._openForm(context, academyId, deviceId, data),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                LucideIcons.scanFace,
                color: enabled ? AppTheme.primary : AppTheme.textDisabled,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name == null || name.isEmpty ? 'Catraca sem nome' : name,
                    style: AppTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    vendor?.label ?? (vendorId ?? 'Fabricante nao definido'),
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _StatusPill(enabled: enabled),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppTheme.success : AppTheme.textDisabled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        enabled ? 'Ativa' : 'Inativa',
        style: AppTheme.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Bottom sheet de criação/edição da catraca.
class _DeviceFormSheet extends StatefulWidget {
  const _DeviceFormSheet({
    required this.academyId,
    this.deviceId,
    this.existing,
  });

  final String academyId;
  final String? deviceId;
  final Map<String, dynamic>? existing;

  @override
  State<_DeviceFormSheet> createState() => _DeviceFormSheetState();
}

class _DeviceFormSheetState extends State<_DeviceFormSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _sportController;
  late final TextEditingController _categoryController;
  late final TextEditingController _toleranceController;

  late final TextEditingController _portalDoorController;

  late String _vendorId;
  late bool _enabled;
  late String _secret;
  // Modo de resposta da Control iD (ver adapters/controlid.js + ingest.js):
  //   'monitor' = push fire-and-forget (só registra presença; catraca decide
  //               embarcado); 'online' = SÍNCRONO — a nuvem decide o giro e
  //               responde grant/deny + ação (abre a catraca "como o QR").
  late String _responseMode;
  // Ação física quando concede no modo online: 'catra' (giro) ou 'door' (porta).
  late String _controlidAction;
  // Sentido liberado do giro (só quando controlidAction == 'catra').
  late String _catraSense;
  bool _saving = false;

  bool get _isEdit => widget.deviceId != null;
  bool get _isControlId => _vendorId == 'controlid';
  bool get _isOnline => _isControlId && _responseMode == 'online';

  @override
  void initState() {
    super.initState();
    final data = widget.existing ?? const <String, dynamic>{};
    _nameController = TextEditingController(
      text: (data['name'] as String?) ?? '',
    );
    _sportController = TextEditingController(
      text: (data['sport'] as String?) ?? '',
    );
    _categoryController = TextEditingController(
      text: (data['category'] as String?) ?? '',
    );
    final tol = data['scheduleToleranceMinutes'];
    _toleranceController = TextEditingController(
      text: tol == null ? '' : tol.toString(),
    );
    final door = data['portalDoor'];
    _portalDoorController = TextEditingController(
      text: door == null ? '1' : door.toString(),
    );
    // Default para o primeiro fabricante do registry quando criando.
    _vendorId = (data['vendor'] as String?) ?? kTurnstileVendors.first.id;
    _enabled = data['enabled'] == true || !_isEdit; // novas catracas ja ativas.
    // Mantém o secret existente na edição; gera um novo só na criação.
    _secret = (data['secret'] as String?) ?? _generateSecret();
    // Modo online é o alvo da integração de presença por catraca (Control iD
    // iDFace). Default 'online' para Control iD novo; preserva o salvo na edição.
    _responseMode = (data['responseMode'] as String?) ??
        (_vendorId == 'controlid' ? 'online' : 'monitor');
    _controlidAction = (data['controlidAction'] as String?) ?? 'catra';
    _catraSense = (data['catraSense'] as String?) ?? 'clockwise';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sportController.dispose();
    _categoryController.dispose();
    _toleranceController.dispose();
    _portalDoorController.dispose();
    super.dispose();
  }

  /// Gera um segredo HMAC aleatório (hex de 32 bytes) usando o RNG seguro.
  /// É o segredo compartilhado entre a catraca física e o backend.
  static String _generateSecret() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _regenerateSecret() {
    setState(() => _secret = _generateSecret());
  }

  /// URL que a catraca deve chamar. Leva academia + deviceId + segredo (?k=) na
  /// query, que o `verifyDeviceAuth` do backend valida (token compartilhado). No
  /// modo online inclui o sub-path `new_user_identified.fcgi` (detecção do modo
  /// síncrono no ingest.js); no monitor mostra só a base (o device anexa /dao…).
  String _deviceUrl() {
    final projectId = Firebase.app().options.projectId;
    final base =
        'https://us-central1-$projectId.cloudfunctions.net/ingestAccessEvent';
    final query =
        '?acad=${widget.academyId}&deviceId=${widget.deviceId}&k=$_secret';
    if (_isOnline) return '$base/new_user_identified.fcgi$query';
    return '$base$query';
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      FeedbackUtils.showWarning(context, 'Informe um nome para a catraca.');
      return;
    }

    setState(() => _saving = true);

    // Campos opcionais usados pelo class_resolver/financial_gate no backend.
    final sport = _sportController.text.trim();
    final category = _categoryController.text.trim();
    final toleranceRaw = _toleranceController.text.trim();
    final tolerance = int.tryParse(toleranceRaw);

    final payload = <String, dynamic>{
      'name': name,
      'vendor': _vendorId,
      'secret': _secret,
      'enabled': _enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    // Opcionais (sport/category/tolerance): só grava quando preenchido — evita
    // sobrescrever com null na edição (merge) e poluir o doc no create. Limpar
    // um campo já setado exige removê-lo no console; aceitável p/ config de HW.
    if (sport.isNotEmpty) payload['sport'] = sport;
    if (category.isNotEmpty) payload['category'] = category;
    if (tolerance != null) payload['scheduleToleranceMinutes'] = tolerance;

    // Config do modo de resposta da Control iD (lida pelo ingest.js/controlid).
    if (_isControlId) {
      payload['responseMode'] = _responseMode;
      if (_responseMode == 'online') {
        payload['controlidAction'] = _controlidAction;
        if (_controlidAction == 'catra') {
          payload['catraSense'] = _catraSense;
        } else {
          final doorNum = int.tryParse(_portalDoorController.text.trim());
          payload['portalDoor'] = doorNum == null || doorNum <= 0 ? 1 : doorNum;
        }
      }
    }

    try {
      final col = FirebaseFirestore.instance
          .collection('academies')
          .doc(widget.academyId)
          .collection('devices');

      if (_isEdit) {
        // merge:true preserva userMap (enrollment — fase futura) e createdAt.
        await col.doc(widget.deviceId).set(payload, SetOptions(merge: true));
      } else {
        // userMap começa vazio: o enrollment externalUserId->studentId é uma
        // fase futura (TODO). createdAt só na criação.
        payload['userMap'] = <String, dynamic>{};
        payload['createdAt'] = FieldValue.serverTimestamp();
        await col.add(payload);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      FeedbackUtils.showSuccess(
        context,
        _isEdit ? 'Catraca atualizada.' : 'Catraca cadastrada.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      FeedbackUtils.showError(context, 'Erro ao salvar: $e');
    }
  }

  Future<void> _delete() async {
    final ok = await FeedbackUtils.showDeleteConfirmDialog(
      context,
      itemName: 'catraca',
      customMessage:
          'A catraca deixa de ser reconhecida pelo backend e o portão para de '
          'registrar presenças por ela. Esta ação não pode ser desfeita.',
    );
    if (!ok || !mounted) return;

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('academies')
          .doc(widget.academyId)
          .collection('devices')
          .doc(widget.deviceId)
          .delete();
      if (!mounted) return;
      Navigator.of(context).pop();
      FeedbackUtils.showSuccess(context, 'Catraca removida.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      FeedbackUtils.showError(context, 'Erro ao remover: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _isEdit ? 'Editar catraca' : 'Nova catraca',
                style: AppTheme.titleLarge,
              ),
              const SizedBox(height: 20),

              // Nome -----------------------------------------------------------
              _FieldLabel('Nome'),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                decoration: _inputDecoration('Ex.: Catraca entrada principal'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 18),

              // Fabricante -----------------------------------------------------
              _FieldLabel('Fabricante'),
              const SizedBox(height: 6),
              _VendorSelector(
                value: _vendorId,
                onChanged: (v) => setState(() => _vendorId = v),
              ),
              const SizedBox(height: 18),

              // Modo de resposta + ação física (só Control iD) -----------------
              if (_isControlId) ...[
                _FieldLabel('Modo de operação'),
                const SizedBox(height: 6),
                _SegmentedChoice(
                  value: _responseMode,
                  options: const [
                    _ChoiceOption(
                      'online',
                      'Online (abre a catraca)',
                      'A nuvem decide e libera o giro na hora — marca presença '
                          'como o QR. Recomendado.',
                    ),
                    _ChoiceOption(
                      'monitor',
                      'Monitor (só registra)',
                      'A catraca decide sozinha; o app só registra a presença '
                          'depois. Sem liberar giro pela nuvem.',
                    ),
                  ],
                  onChanged: (v) => setState(() => _responseMode = v),
                ),
                const SizedBox(height: 14),
                if (_isOnline) ...[
                  _FieldLabel('Ao liberar, acionar'),
                  const SizedBox(height: 6),
                  _SegmentedChoice(
                    value: _controlidAction,
                    options: const [
                      _ChoiceOption('catra', 'Catraca (giro)',
                          'Equipamento com giro (iDBlock/iDFace catraca).'),
                      _ChoiceOption('door', 'Porta/fechadura',
                          'Fechadura elétrica ou porta (iDAccess).'),
                    ],
                    onChanged: (v) => setState(() => _controlidAction = v),
                  ),
                  const SizedBox(height: 14),
                  if (_controlidAction == 'catra') ...[
                    _FieldLabel('Sentido do giro liberado'),
                    const SizedBox(height: 6),
                    _SegmentedChoice(
                      value: _catraSense,
                      options: const [
                        _ChoiceOption('clockwise', 'Horário', ''),
                        _ChoiceOption('anticlockwise', 'Anti-horário', ''),
                      ],
                      onChanged: (v) => setState(() => _catraSense = v),
                    ),
                  ] else ...[
                    _FieldLabel('Número da porta (door)'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _portalDoorController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _inputDecoration('Ex.: 1'),
                    ),
                  ],
                  const SizedBox(height: 18),
                ],
              ],

              // Enabled --------------------------------------------------------
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: AppTheme.primary,
                  title: Text('Catraca ativa', style: AppTheme.bodyMedium),
                  subtitle: Text(
                    'Quando desligada, o backend recusa os acessos dela.',
                    style: AppTheme.labelSmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ),
              const SizedBox(height: 18),

              // Secret HMAC ----------------------------------------------------
              _FieldLabel('Segredo (HMAC)'),
              const SizedBox(height: 6),
              _SecretBox(
                secret: _secret,
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: _secret));
                  FeedbackUtils.showSuccess(context, 'Segredo copiado.');
                },
                onRegenerate: _regenerateSecret,
              ),
              const SizedBox(height: 6),
              Text(
                'Copie e configure este segredo na catraca física. Ele assina '
                'cada evento (HMAC) e é validado pelo backend. Regenerar invalida '
                'o segredo antigo.',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 18),

              // Opcionais (sport/category/tolerance) ---------------------------
              _FieldLabel('Esporte (opcional)'),
              const SizedBox(height: 6),
              TextField(
                controller: _sportController,
                decoration: _inputDecoration('Ex.: bjj, muaythai, boxe'),
              ),
              const SizedBox(height: 14),
              _FieldLabel('Categoria/Turma (opcional)'),
              const SizedBox(height: 6),
              TextField(
                controller: _categoryController,
                decoration: _inputDecoration('Ex.: adulto, kids'),
              ),
              const SizedBox(height: 14),
              _FieldLabel('Tolerância de horário em minutos (opcional)'),
              const SizedBox(height: 6),
              TextField(
                controller: _toleranceController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _inputDecoration('Ex.: 15'),
              ),
              const SizedBox(height: 14),

              // URL do servidor + enrollment (só na edição — precisam do
              // deviceId, que é o id do doc criado ao salvar).
              if (_isEdit) ...[
                _FieldLabel('URL para configurar na catraca'),
                const SizedBox(height: 6),
                _UrlBox(url: _deviceUrl()),
                const SizedBox(height: 6),
                Text(
                  _isOnline
                      ? 'Cole esta URL como servidor de eventos da Control iD '
                          '(modo Pro/Online). Ela já leva a academia, o ID da '
                          'catraca e o segredo. Regenerar o segredo muda a URL.'
                      : 'Cole a base como servidor de eventos (modo Monitor). O '
                          'equipamento anexa /dao, /catra_event e '
                          '/device_is_alive automaticamente.',
                  style: AppTheme.labelSmall
                      .copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DeviceEnrollmentScreen(
                          academyId: widget.academyId,
                          deviceId: widget.deviceId!,
                          deviceName: _nameController.text.trim().isEmpty
                              ? 'Catraca'
                              : _nameController.text.trim(),
                        ),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    minimumSize: const Size(double.infinity, 0),
                  ),
                  icon: const Icon(LucideIcons.users, size: 18),
                  label: const Text('Vincular alunos (enrollment)'),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.infoLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.info, size: 18, color: AppTheme.info),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Salve a catraca para ver a URL de configuração e '
                          'vincular os alunos (enrollment).',
                          style: AppTheme.labelSmall
                              .copyWith(color: AppTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // Ações ----------------------------------------------------------
              Row(
                children: [
                  if (_isEdit) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _delete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.error,
                          side: const BorderSide(color: AppTheme.error),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(LucideIcons.trash2, size: 18),
                        label: const Text('Remover'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isEdit ? 'Salvar' : 'Cadastrar'),
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

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textDisabled),
      filled: true,
      fillColor: AppTheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
      ),
    );
  }
}

/// Seletor de fabricante — lê de [kTurnstileVendors] (fonte única; espelha o
/// registry de adapters do backend). Adicionar marca = UMA entrada lá.
class _VendorSelector extends StatelessWidget {
  const _VendorSelector({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final v in kTurnstileVendors)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => onChanged(v.id),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: value == v.id ? AppTheme.primary : AppTheme.border,
                    width: value == v.id ? 2 : 1,
                  ),
                  color: value == v.id
                      ? AppTheme.primary.withValues(alpha: 0.06)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      value == v.id
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: value == v.id
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            v.label,
                            style: AppTheme.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            v.integration,
                            style: AppTheme.labelSmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Caixa que mostra o segredo HMAC com ações de copiar e regenerar.
class _SecretBox extends StatelessWidget {
  const _SecretBox({
    required this.secret,
    required this.onCopy,
    required this.onRegenerate,
  });

  final String secret;
  final VoidCallback onCopy;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              secret,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: AppTheme.textPrimary,
              ),
              maxLines: 2,
            ),
          ),
          IconButton(
            tooltip: 'Copiar',
            onPressed: onCopy,
            icon: const Icon(LucideIcons.copy, size: 18),
            color: AppTheme.primary,
          ),
          IconButton(
            tooltip: 'Gerar novo',
            onPressed: onRegenerate,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            color: AppTheme.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// Uma opção de [_SegmentedChoice]: valor persistido + rótulo + descrição.
class _ChoiceOption {
  final String value;
  final String label;
  final String hint;
  const _ChoiceOption(this.value, this.label, this.hint);
}

/// Seletor de escolha única em cartões empilhados (mesma linguagem do
/// _VendorSelector). Usado para modo de operação / ação física / sentido do giro.
class _SegmentedChoice extends StatelessWidget {
  const _SegmentedChoice({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<_ChoiceOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => onChanged(o.value),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: value == o.value ? AppTheme.primary : AppTheme.border,
                    width: value == o.value ? 2 : 1,
                  ),
                  color: value == o.value
                      ? AppTheme.primary.withValues(alpha: 0.06)
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(
                      value == o.value
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: value == o.value
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.label,
                            style: AppTheme.bodyMedium
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (o.hint.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              o.hint,
                              style: AppTheme.labelSmall
                                  .copyWith(color: AppTheme.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Caixa que mostra a URL de configuração da catraca com botão de copiar.
class _UrlBox extends StatelessWidget {
  const _UrlBox({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              url,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copiar URL',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              FeedbackUtils.showSuccess(context, 'URL copiada.');
            },
            icon: const Icon(LucideIcons.copy, size: 18),
            color: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTheme.labelMedium.copyWith(
        color: AppTheme.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.scanFace, size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text('Nenhuma catraca cadastrada', style: AppTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Adicione a primeira catraca para integrar o controle de acesso '
              'da academia.',
              textAlign: TextAlign.center,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoAcademyState extends StatelessWidget {
  const _NoAcademyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Selecione uma academia para gerenciar as catracas.',
          textAlign: TextAlign.center,
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.alertTriangle,
              size: 40,
              color: AppTheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'Erro ao carregar catracas',
              style: AppTheme.titleMedium.copyWith(color: AppTheme.error),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.labelSmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
