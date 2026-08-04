import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

// =============================================================================
// Tokens anti-slop (padrão FIGHTER). Bone + ink + UM acento vermelho.
// =============================================================================
class _T {
  _T._();
  static const bone = Color(0xFFF4F3EF);
  static const card = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0A0A0A);
  static const blood = Color(0xFFE0301E);
  static const smoke = Color(0xFF6E6E68);
  static const ash = Color(0xFF9A9A93);
}

TextStyle _eyebrow(Color c, double s) => TextStyle(
    color: c, fontSize: s, fontWeight: FontWeight.w800, letterSpacing: 1.4);

/// Register Screen - Flow selection (Link Code vs Academy Owner)
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.bone,
      body: SafeArea(
        child: Column(
          children: [
            // Back button
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _IconButtonInk(
                    icon: LucideIcons.arrowLeft,
                    onTap: () => context.go('/login'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo
                    Center(
                      child: Image.asset(
                        'assets/images/mydojo_logo.png',
                        width: 96,
                        height: 96,
                      ),
                    ).animate().fadeIn(duration: 300.ms).scale(
                          begin: const Offset(0.85, 0.85),
                        ),

                    const SizedBox(height: 28),

                    // Eyebrow
                    Text(
                      'BEM-VINDO AO TATAME',
                      textAlign: TextAlign.center,
                      style: _eyebrow(_T.blood, 12),
                    ).animate().fadeIn(delay: 80.ms),

                    const SizedBox(height: 10),

                    // Title
                    const Text(
                      'CRIAR CONTA',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _T.ink,
                        fontSize: 34,
                        height: 1.0,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ).animate().fadeIn(delay: 100.ms),

                    const SizedBox(height: 10),

                    Text(
                      'Escolha como deseja se cadastrar.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _T.smoke,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ).animate().fadeIn(delay: 200.ms),

                    const SizedBox(height: 36),

                    // Option 1: Link Code (Student) — fluxo principal (blood CTA)
                    _FlowOptionCard(
                      icon: LucideIcons.key,
                      eyebrow: 'ALUNO',
                      title: 'Tenho código de acesso',
                      subtitle:
                          'Cadastre-se como aluno usando o código fornecido pela sua academia.',
                      buttonText: 'USAR CÓDIGO DE ACESSO',
                      primary: true,
                      onTap: () => context.go('/link-code'),
                    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.08),

                    const SizedBox(height: 16),

                    // Divider
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 1,
                            color: _T.ink.withValues(alpha: 0.10),
                          ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14),
                          child: Text('OU', style: _eyebrow(_T.ash, 11)),
                        ),
                        Expanded(
                          child: Container(
                            height: 1,
                            color: _T.ink.withValues(alpha: 0.10),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 400.ms),

                    const SizedBox(height: 16),

                    // Option 2: Academy Owner
                    _FlowOptionCard(
                      icon: LucideIcons.graduationCap,
                      eyebrow: 'PROFESSOR',
                      title: 'Sou dono de academia',
                      subtitle:
                          'Cadastre sua academia e gerencie alunos, graduações e muito mais.',
                      buttonText: 'CRIAR MINHA ACADEMIA',
                      primary: false,
                      onTap: () => context.go('/criar-academia'),
                    ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.08),

                    const SizedBox(height: 28),

                    // Login link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'Já tem uma conta? ',
                          style: TextStyle(
                            color: _T.smoke,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => context.go('/login'),
                          behavior: HitTestBehavior.opaque,
                          child: const Text(
                            'ENTRAR',
                            style: TextStyle(
                              color: _T.blood,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(delay: 600.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small ink line-icon button (back).
class _IconButtonInk extends StatelessWidget {
  const _IconButtonInk({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _T.card,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: _T.ink),
      ),
    );
  }
}

/// Flow Option Card Widget
class _FlowOptionCard extends StatelessWidget {
  final IconData icon;
  final String eyebrow;
  final String title;
  final String subtitle;
  final String buttonText;
  final bool primary;
  final VoidCallback onTap;

  const _FlowOptionCard({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = primary ? _T.blood : _T.ink;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _T.card,
          border: Border.all(
            color: _T.ink.withValues(alpha: 0.10),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Icon tile
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 24, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(eyebrow, style: _eyebrow(_T.ash, 10)),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: const TextStyle(
                          color: _T.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Subtitle
            Text(
              subtitle,
              style: const TextStyle(
                color: _T.smoke,
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),

            // CTA button
            _CtaButton(
              label: buttonText,
              primary: primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// CTA button: primary = filled blood; secondary = ink outline.
class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.label, required this.primary});
  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: primary ? _T.blood : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: primary
            ? null
            : Border.all(color: _T.ink.withValues(alpha: 0.22), width: 1.4),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: primary ? Colors.white : _T.ink,
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            LucideIcons.arrowRight,
            size: 17,
            color: primary ? Colors.white : _T.ink,
          ),
        ],
      ),
    );
  }
}
