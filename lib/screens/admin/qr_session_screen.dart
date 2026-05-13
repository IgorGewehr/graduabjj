import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/services.dart';

/// Admin Attendance QR Screen
///
/// Lists every active class that has a schedule for today and lets the
/// professor open a fullscreen QR that students scan to register attendance
/// directly (no pending check-in step).
class AdminQrSessionScreen extends ConsumerStatefulWidget {
  const AdminQrSessionScreen({super.key});

  @override
  ConsumerState<AdminQrSessionScreen> createState() =>
      _AdminQrSessionScreenState();
}

class _AdminQrSessionScreenState extends ConsumerState<AdminQrSessionScreen> {
  bool _isLoading = true;
  List<_ClassWithSchedule> _classes = [];

  static const _weekdayLabels = [
    'Domingo',
    'Segunda',
    'Terca',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sabado',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final user = ref.read(currentUserProvider).valueOrNull;
      if (user?.academyId == null) {
        setState(() {
          _classes = [];
          _isLoading = false;
        });
        return;
      }

      final classService = ClassService(user!.academyId!);
      final today = DateTime.now();
      final dayOfWeek = today.weekday % 7;
      final all = await classService.list();

      final entries = <_ClassWithSchedule>[];
      for (final cls in all) {
        for (final s in cls.schedule) {
          if (s.dayOfWeek == dayOfWeek) {
            entries.add(_ClassWithSchedule(cls: cls, schedule: s));
          }
        }
      }
      entries.sort((a, b) => a.schedule.startTime.compareTo(b.schedule.startTime));

      setState(() {
        _classes = entries;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _openQr(_ClassWithSchedule entry, String academyId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _QrFullscreenPage(
          academyId: academyId,
          classId: entry.cls.id,
          className: entry.cls.name,
          startTime: entry.schedule.startTime,
          endTime: entry.schedule.endTime,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    final academyId = user?.academyId;
    final today = DateTime.now();
    final dayOfWeek = today.weekday % 7;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chamada por QR'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            tooltip: 'Atualizar',
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : academyId == null
              ? Center(
                  child: Text(
                    'Academia nao encontrada',
                    style: AppTheme.bodyMedium.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IntroCard(weekdayLabel: _weekdayLabels[dayOfWeek]),
                        const SizedBox(height: 16),
                        if (_classes.isEmpty)
                          _EmptyState()
                        else
                          ..._classes.map(
                            (entry) => _ClassTile(
                              entry: entry,
                              onTap: () => _openQr(entry, academyId),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }
}

class _ClassWithSchedule {
  final BJJClass cls;
  final ClassSchedule schedule;
  _ClassWithSchedule({required this.cls, required this.schedule});
}

class _IntroCard extends StatelessWidget {
  final String weekdayLabel;
  const _IntroCard({required this.weekdayLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.infoLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.info.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.qrCode, color: AppTheme.info, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Turmas de $weekdayLabel',
                  style: AppTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Selecione a turma para mostrar o QR. Os alunos matriculados podem escanear para registrar presenca dentro da janela de horario (30min antes ate 1h depois).',
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.calendarX, size: 40, color: AppTheme.textDisabled),
          const SizedBox(height: 12),
          Text(
            'Nenhuma turma com aula hoje',
            style: AppTheme.titleMedium.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ClassTile extends StatelessWidget {
  final _ClassWithSchedule entry;
  final VoidCallback onTap;
  const _ClassTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final happeningNow = entry.cls.isHappeningNow();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: happeningNow
                        ? AppTheme.successLight
                        : AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    LucideIcons.qrCode,
                    color: happeningNow
                        ? AppTheme.success
                        : AppTheme.textSecondary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.cls.name,
                              style: AppTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (happeningNow)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.success,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'AO VIVO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${entry.schedule.startTime} - ${entry.schedule.endTime}',
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fullscreen page that displays a rotating QR for one class.
///
/// The payload includes a timestamp and is regenerated periodically. Tokens
/// older than [kQrTokenTtl] are rejected by [QrAttendanceService], so each
/// frame the student scans must be reasonably fresh — preventing replay of a
/// stale screenshot or a photo of an old screen.
class _QrFullscreenPage extends StatefulWidget {
  final String academyId;
  final String classId;
  final String className;
  final String startTime;
  final String endTime;

  const _QrFullscreenPage({
    required this.academyId,
    required this.classId,
    required this.className,
    required this.startTime,
    required this.endTime,
  });

  @override
  State<_QrFullscreenPage> createState() => _QrFullscreenPageState();
}

class _QrFullscreenPageState extends State<_QrFullscreenPage> {
  static const Duration _rotateInterval = Duration(seconds: 30);

  Timer? _timer;
  late QrPayload _payload;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _payload = QrPayload.now(
      academyId: widget.academyId,
      classId: widget.classId,
    );
    _timer = Timer.periodic(_rotateInterval, (_) {
      if (!mounted) return;
      setState(() {
        _payload = QrPayload.now(
          academyId: widget.academyId,
          classId: widget.classId,
        );
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final shortSide = mq.size.shortestSide;
    final qrSize = (shortSide * 0.7).clamp(220.0, 520.0);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      widget.className,
                      style: AppTheme.displaySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.startTime} - ${widget.endTime}',
                      style: AppTheme.titleMedium.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: QrImageView(
                        data: _payload.encode(),
                        version: QrVersions.auto,
                        size: qrSize,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF111111),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF111111),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _RotationIndicator(
                      key: ValueKey(_payload.issuedAtSeconds),
                      interval: _rotateInterval,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'O QR renova a cada ${_rotateInterval.inSeconds}s. Mantenha esta tela aberta durante a aula.',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(LucideIcons.x, size: 22),
                onPressed: () => Navigator.of(context).pop(),
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Linear progress that counts down a single rotation cycle. Resets each
/// time the parent rebuilds with a new key.
class _RotationIndicator extends StatefulWidget {
  final Duration interval;
  const _RotationIndicator({super.key, required this.interval});

  @override
  State<_RotationIndicator> createState() => _RotationIndicatorState();
}

class _RotationIndicatorState extends State<_RotationIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.interval,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final remaining = 1 - _controller.value;
          return Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: remaining,
                  minHeight: 4,
                  backgroundColor: AppTheme.surfaceVariant,
                  valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Proximo QR em ${(remaining * widget.interval.inSeconds).ceil()}s',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

