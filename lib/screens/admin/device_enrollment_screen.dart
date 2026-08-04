import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/feedback_utils.dart';
import '../../core/theme.dart';

/// Enrollment da catraca: vincula o **ID do usuário na catraca** (o número que a
/// Control iD atribui à face ao cadastrá-la no equipamento) ao **aluno** do
/// GraduaBJJ. É esse mapa que a Cloud Function `ingestAccessEvent` usa para
/// resolver `externalUserId -> studentId` e marcar a presença certa.
///
/// Persistência: dois campos-mapa no doc `academies/{academyId}/devices/{id}`:
///   - `userMap`  : `{ idNaCatraca: studentId }`  (fonte da verdade no backend)
///   - `userNames`: `{ idNaCatraca: nome }`        (rótulo p/ auditoria)
/// Gravações usam `merge:true` (mapas deep-merge → não apagam outros vínculos);
/// remoções usam `FieldValue.delete()` na chave.
class DeviceEnrollmentScreen extends StatelessWidget {
  const DeviceEnrollmentScreen({
    super.key,
    required this.academyId,
    required this.deviceId,
    required this.deviceName,
  });

  final String academyId;
  final String deviceId;
  final String deviceName;

  DocumentReference<Map<String, dynamic>> get _deviceRef => FirebaseFirestore
      .instance
      .collection('academies')
      .doc(academyId)
      .collection('devices')
      .doc(deviceId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Vínculos de alunos'),
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddSheet(context),
        backgroundColor: AppTheme.primary,
        icon: const Icon(LucideIcons.userPlus, color: Colors.white),
        label: const Text('Vincular aluno',
            style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _deviceRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _Message(icon: LucideIcons.alertTriangle, color: AppTheme.error,
                text: 'Erro ao carregar: ${snap.error}');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!.data() ?? const {};
          final userMap = Map<String, dynamic>.from(
              (data['userMap'] as Map?) ?? const {});
          final userNames = Map<String, dynamic>.from(
              (data['userNames'] as Map?) ?? const {});

          final entries = userMap.entries.toList()
            ..sort((a, b) {
              final na = int.tryParse(a.key);
              final nb = int.tryParse(b.key);
              if (na != null && nb != null) return na.compareTo(nb);
              return a.key.compareTo(b.key);
            });

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(deviceName: deviceName)),
              if (entries.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyEnrollment(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  sliver: SliverList.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final name = (userNames[e.key] as String?)?.trim();
                      return _MappingCard(
                        controlIdUserId: e.key,
                        studentId: e.value.toString(),
                        studentName: name,
                        onRemove: () => _remove(context, e.key, name),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _remove(
      BuildContext context, String controlIdUserId, String? name) async {
    final ok = await FeedbackUtils.showDeleteConfirmDialog(
      context,
      itemName: 'vínculo',
      customMessage:
          'O aluno ${name ?? 'ID $controlIdUserId'} deixa de ter a presença '
          'marcada por esta catraca (ID $controlIdUserId). A face segue no '
          'equipamento — só o vínculo com o app é removido.',
    );
    if (!ok) return;
    try {
      await _deviceRef.update({
        'userMap.$controlIdUserId': FieldValue.delete(),
        'userNames.$controlIdUserId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (context.mounted) FeedbackUtils.showSuccess(context, 'Vínculo removido.');
    } catch (e) {
      if (context.mounted) FeedbackUtils.showError(context, 'Erro ao remover: $e');
    }
  }

  void _openAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMappingSheet(
        academyId: academyId,
        deviceRef: _deviceRef,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.deviceName});
  final String deviceName;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.infoLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.info, size: 18, color: AppTheme.info),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cadastre a FACE do aluno no equipamento Control iD (ele gera um '
              '"ID do usuário"). Aqui você liga esse ID ao aluno para a presença '
              'ser marcada automaticamente na catraca "$deviceName".',
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _MappingCard extends StatelessWidget {
  const _MappingCard({
    required this.controlIdUserId,
    required this.studentId,
    required this.studentName,
    required this.onRemove,
  });

  final String controlIdUserId;
  final String studentId;
  final String? studentName;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'ID $controlIdUserId',
              style: AppTheme.labelSmall.copyWith(
                color: AppTheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              studentName == null || studentName!.isEmpty
                  ? 'Aluno $studentId'
                  : studentName!,
              style: AppTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Remover vínculo',
            onPressed: onRemove,
            icon: const Icon(LucideIcons.trash2, size: 18),
            color: AppTheme.error,
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet: escolhe o aluno (busca) e informa o ID dele na catraca.
class _AddMappingSheet extends StatefulWidget {
  const _AddMappingSheet({required this.academyId, required this.deviceRef});

  final String academyId;
  final DocumentReference<Map<String, dynamic>> deviceRef;

  @override
  State<_AddMappingSheet> createState() => _AddMappingSheetState();
}

class _AddMappingSheetState extends State<_AddMappingSheet> {
  final _searchController = TextEditingController();
  final _userIdController = TextEditingController();
  String _query = '';
  String? _selectedStudentId;
  String? _selectedStudentName;
  bool _saving = false;

  @override
  void dispose() {
    _searchController.dispose();
    _userIdController.dispose();
    super.dispose();
  }

  Query<Map<String, dynamic>> get _studentsQuery => FirebaseFirestore.instance
      .collection('academies')
      .doc(widget.academyId)
      .collection('students')
      .orderBy('fullName');

  Future<void> _save() async {
    final studentId = _selectedStudentId;
    final userId = _userIdController.text.trim();
    if (studentId == null) {
      FeedbackUtils.showWarning(context, 'Selecione um aluno.');
      return;
    }
    if (userId.isEmpty) {
      FeedbackUtils.showWarning(context, 'Informe o ID do aluno na catraca.');
      return;
    }
    setState(() => _saving = true);
    try {
      // merge:true faz deep-merge dos mapas → adiciona a chave sem apagar os
      // outros vínculos já cadastrados.
      await widget.deviceRef.set({
        'userMap': {userId: studentId},
        'userNames': {userId: _selectedStudentName ?? ''},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.of(context).pop();
      FeedbackUtils.showSuccess(context, 'Aluno vinculado.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      FeedbackUtils.showError(context, 'Erro ao vincular: $e');
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
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
            Text('Vincular aluno à catraca', style: AppTheme.titleLarge),
            const SizedBox(height: 16),

            // ID na catraca -------------------------------------------------
            Text('ID do aluno na catraca',
                style: AppTheme.labelMedium
                    .copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _userIdController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _dec('Número gerado no equipamento (ex.: 42)'),
            ),
            const SizedBox(height: 16),

            // Aluno ---------------------------------------------------------
            Text('Aluno', style: AppTheme.labelMedium
                .copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: _dec('Buscar aluno pelo nome')
                  .copyWith(prefixIcon: const Icon(LucideIcons.search, size: 18)),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _studentsQuery.snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final docs = snap.data!.docs.where((d) {
                    final status = d.data()['status'];
                    if (status == 'deleted' || status == 'inactive') return false;
                    if (_query.isEmpty) return true;
                    final name = (d.data()['fullName'] as String? ?? '')
                        .toLowerCase();
                    return name.contains(_query);
                  }).toList();
                  if (docs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhum aluno encontrado.'),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      final name = (d.data()['fullName'] as String?) ?? 'Aluno';
                      final selected = _selectedStudentId == d.id;
                      return ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        leading: Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: selected
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                          size: 20,
                        ),
                        title: Text(name, style: AppTheme.bodyMedium),
                        onTap: () => setState(() {
                          _selectedStudentId = d.id;
                          _selectedStudentName = name;
                        }),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
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
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Vincular'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textDisabled),
        filled: true,
        fillColor: AppTheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

class _EmptyEnrollment extends StatelessWidget {
  const _EmptyEnrollment();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.users, size: 48, color: AppTheme.textDisabled),
            const SizedBox(height: 16),
            Text('Nenhum aluno vinculado', style: AppTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Vincule o ID da face de cada aluno (gerado no equipamento) ao '
              'cadastro dele para a presença ser marcada na catraca.',
              textAlign: TextAlign.center,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: AppTheme.bodyMedium
                    .copyWith(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}
