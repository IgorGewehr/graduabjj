import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/brand_tokens.dart';
import '../../core/feedback_utils.dart';

// ---------------------------------------------------------------------------
// Modelo local de preferências de notificação
// ---------------------------------------------------------------------------

class _NotifPrefs {
  final bool social;
  final bool treino;
  final bool academia;

  const _NotifPrefs({
    this.social = true,
    this.treino = true,
    this.academia = true,
  });

  factory _NotifPrefs.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const _NotifPrefs();
    return _NotifPrefs(
      social: map['social'] as bool? ?? true,
      treino: map['treino'] as bool? ?? true,
      academia: map['academia'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'social': social,
        'treino': treino,
        'academia': academia,
      };

  _NotifPrefs copyWith({bool? social, bool? treino, bool? academia}) =>
      _NotifPrefs(
        social: social ?? this.social,
        treino: treino ?? this.treino,
        academia: academia ?? this.academia,
      );
}

// ---------------------------------------------------------------------------
// Tela principal
// ---------------------------------------------------------------------------

/// Tela de preferências granulares de notificação do aluno.
///
/// Lê `users/{uid}.notificationPrefs` (ausente = true), escreve via
/// `set merge {notificationPrefs: {...}}`. Billing não é desligável.
///
/// Visual: portal fighter style — canvas bone, cards brancos, acento blood,
/// ícones ink. Padrão Brand tokens (lib/core/brand_tokens.dart).
class NotificationPrefsScreen extends ConsumerStatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  ConsumerState<NotificationPrefsScreen> createState() =>
      _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState
    extends ConsumerState<NotificationPrefsScreen> {
  static const _bone = Brand.bone;
  static const _card = Color(0xFFFFFFFF);
  static const _ink = Brand.ink;
  static const _blood = Brand.blood;
  static const _smoke = Color(0xFF6E6E68);
  static const _ash = Brand.ash;
  static const _hair = Color(0x14000000);

  _NotifPrefs _prefs = const _NotifPrefs();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache));
      final data = snap.data();
      final raw = data?['notificationPrefs'];
      if (mounted) {
        setState(() {
          _prefs = _NotifPrefs.fromMap(raw is Map<String, dynamic> ? raw : null);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        context.showError('Erro ao carregar preferencias: $e');
      }
    }
  }

  Future<void> _save(_NotifPrefs updated) async {
    final uid = _uid;
    if (uid == null) return;

    setState(() {
      _prefs = updated;
      _saving = true;
    });
    HapticFeedback.selectionClick();

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'notificationPrefs': updated.toMap()},
        SetOptions(merge: true),
      );
    } catch (e) {
      // Reverte o toggle otimista em caso de falha
      if (mounted) {
        context.showError('Erro ao salvar: $e');
        _load(); // Re-carrega do servidor
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bone,
      appBar: AppBar(
        backgroundColor: _bone,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: _ink, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Notificacoes',
          style: TextStyle(
            color: _ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _blood))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Intro
                  Text(
                    'Escolha quais notificacoes deseja receber no celular.',
                    style: TextStyle(
                      color: _smoke,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Secao header
                  _sectionHeader('CATEGORIAS'),
                  const SizedBox(height: 10),

                  // Card com os 3 switches editaveis
                  _prefCard(children: [
                    _PrefTile(
                      icon: LucideIcons.users,
                      title: 'Social',
                      subtitle: 'Curtidas e marcos dos parceiros',
                      value: _prefs.social,
                      enabled: !_saving,
                      onChanged: (v) => _save(_prefs.copyWith(social: v)),
                    ),
                    Divider(height: 1, thickness: 1, color: _hair),
                    _PrefTile(
                      icon: LucideIcons.flame,
                      title: 'Treino',
                      subtitle: 'Streak, lembretes de aula e recap da semana',
                      value: _prefs.treino,
                      enabled: !_saving,
                      onChanged: (v) => _save(_prefs.copyWith(treino: v)),
                    ),
                    Divider(height: 1, thickness: 1, color: _hair),
                    _PrefTile(
                      icon: LucideIcons.megaphone,
                      title: 'Academia',
                      subtitle: 'Avisos do professor',
                      value: _prefs.academia,
                      enabled: !_saving,
                      onChanged: (v) => _save(_prefs.copyWith(academia: v)),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // Card nao-editavel de cobrancas
                  _prefCard(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _bone,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _hair),
                            ),
                            child: const Icon(LucideIcons.creditCard,
                                size: 18, color: _ink),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Cobrancas e pagamentos',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Cobrancas e pagamentos sao sempre notificados.',
                                  style: TextStyle(
                                    color: _ash,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Switch fixo sempre ligado, desabilitado
                          Switch.adaptive(
                            value: true,
                            onChanged: null,
                            activeThumbColor: _ash,
                            activeTrackColor: _ash.withValues(alpha: 0.3),
                          ),
                        ],
                      ),
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // Nota LGPD
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _hair),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.info,
                            size: 15, color: _ash),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'As preferencias sao salvas imediatamente. '
                            'Voce tambem pode gerenciar notificacoes '
                            'nas configuracoes do seu celular.',
                            style: TextStyle(
                              color: _smoke,
                              fontSize: 12,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(width: 14, height: 2, color: _blood),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _prefCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _hair),
      ),
      child: Column(children: children),
    );
  }
}

// ---------------------------------------------------------------------------
// Tile de preferência individual
// ---------------------------------------------------------------------------

class _PrefTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _PrefTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  static const _bone = Brand.bone;
  static const _ink = Brand.ink;
  static const _blood = Brand.blood;
  static const _smoke = Color(0xFF6E6E68);
  static const _hair = Color(0x14000000);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          // Ícone
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _bone,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _hair),
            ),
            child: Icon(icon, size: 18, color: _ink),
          ),
          const SizedBox(width: 12),
          // Texto
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _smoke,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: _blood,
            activeTrackColor: _blood.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}
