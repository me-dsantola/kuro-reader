import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/manga_models.dart';
import '../services/cloud_auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import '../widgets/yomi_brand_widgets.dart';

/// Mandatory Auth Gate Screen shown when the user is not signed in with a Google Account.
/// Designed with an ultra-clean, minimalist AMOLED aesthetic:
/// - Official vector Ensō / Pages logo from the branding pack (transparent background, dynamic accent)
/// - Clean typography without clutter or marketing feature cards
/// - Premium Google Sign-in pill button
class KuroAuthScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const KuroAuthScreen({super.key, required this.onAuthenticated});

  @override
  State<KuroAuthScreen> createState() => _KuroAuthScreenState();
}

class _KuroAuthScreenState extends State<KuroAuthScreen> {
  bool _isLoading = false;
  String? _statusMessage;

  Future<void> _completePostSignIn(User user) async {
    final previousUid = StorageService.activeUserUid;
    final isSwitchingAccount = previousUid != null && previousUid != user.uid;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _statusMessage = 'Verificando dados na nuvem...';
      });
    }

    // Check if user has an existing cloud backup in Firestore
    Map<String, dynamic>? meta;
    try {
      meta = await CloudSyncService.checkCloudBackupMetadata();
    } catch (_) {}

    if (meta != null) {
      // Se trocou de conta ou é uma sessão nova, limpa o estado residual
      if (isSwitchingAccount || previousUid == null) {
        await StorageService.clearUserDataForNewSession();
      }
      if (mounted) {
        setState(() {
          _statusMessage = 'Restaurando sua biblioteca da nuvem...';
        });
      }
      await CloudSyncService.restoreFromCloud();
      await StorageService.setActiveUserUid(user.uid);
    } else {
      // Novo usuário ou usuário sem backup em nuvem:
      // JAMAIS herda favoritos, histórico ou perfil de outros usuários do aparelho.
      if (mounted) {
        setState(() {
          _statusMessage = 'Preparando seu novo perfil...';
        });
      }
      await StorageService.clearUserDataForNewSession();
      final displayName = user.displayName?.trim() ?? '';
      final emailPrefix = user.email?.split('@').first.trim() ?? '';
      final resolvedName = displayName.isNotEmpty
          ? displayName
          : (emailPrefix.isNotEmpty ? emailPrefix : 'Leitor YOMI');
      final freshProfile = UserProfile(
        name: resolvedName,
        avatarImagePath: user.photoURL,
        isConfigured: false,
      );
      await StorageService.updateUserProfile(freshProfile);
      await ProfilePaletteService.refreshGlobalPalette(freshProfile);
      await StorageService.setActiveUserUid(user.uid);
    }

    if (mounted) {
      widget.onAuthenticated();
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Conectando ao Google...';
    });

    try {
      final user = await CloudAuthService.signInWithGoogle();
      if (user == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _statusMessage = null;
          });
        }
        return;
      }

      await _completePostSignIn(user);
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openEmailAuthSheet(ProfileAdaptivePalette palette) async {
    CloudAuthService.lastAuthError.value = null;
    final User? signedUser = await showModalBottomSheet<User>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EmailAuthModalSheet(palette: palette),
    );
    if (signedUser == null || !mounted) return;
    try {
      await _completePostSignIn(signedUser);
    } catch (_) {
      if (mounted) {
        setState(() {
          _statusMessage = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileAdaptivePalette>(
      valueListenable: ProfilePaletteService.paletteNotifier,
      builder: (context, palette, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF070709),
          body: Stack(
            children: [
              // Subtle centered radial ambient glow behind the logo
              Center(
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        palette.primary.withValues(alpha: 0.16),
                        palette.primary.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      const Spacer(flex: 3),

                      // Official Vector SVG Brand Mark (transparent background, dynamic palette)
                      YomiBrandSvgLogo(
                        width: 96,
                        height: 92,
                        palette: palette,
                        iconOnly: true,
                      ),
                      const SizedBox(height: 28),

                      // Minimalist Typography
                      const Text(
                        'YOMI',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6.0,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Sua biblioteca definitiva de mangás.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white60,
                          letterSpacing: 0.2,
                          height: 1.3,
                        ),
                      ),

                      const Spacer(flex: 3),

                      // Inline Error (if any, styled discreetly)
                      ValueListenableBuilder<String?>(
                        valueListenable: CloudAuthService.lastAuthError,
                        builder: (context, errorMsg, _) {
                          if (errorMsg == null) return const SizedBox.shrink();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 18),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline_rounded,
                                      color: Colors.redAccent,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        errorMsg,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () {
                                      widget.onAuthenticated();
                                    },
                                    child: const Text(
                                      'Entrar no modo local',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.white70,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      if (_statusMessage != null) ...[
                        Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // White Minimalist Google Sign-In Pill Button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1E1E1E),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          onPressed: _isLoading ? null : _handleGoogleSignIn,
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      palette.primary,
                                    ),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildGoogleGLogo(),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Continuar com o Google',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.15,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Subtle Secondary Email & Password Option
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.04,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                          ),
                          onPressed: _isLoading
                              ? null
                              : () => _openEmailAuthSheet(palette),
                          icon: const Icon(
                            Icons.mail_outline_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            'Entrar com E-mail e Senha',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Subtle Security & Sync Footer
                      const Text(
                        'Personalize seu perfil com e-mail ou Google. Conecte o Drive no perfil para guardar originais e backups.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white38,
                          letterSpacing: 0.2,
                        ),
                      ),

                      const Spacer(flex: 1),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGoogleGLogo() {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleGLogoPainter()),
    );
  }
}

/// Official Google 'G' vector mark painter
class _GoogleGLogoPainter extends CustomPainter {
  const _GoogleGLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale, scale);

    // Blue horizontal bar and arc
    final bluePath = Path()
      ..moveTo(23.49, 12.27)
      ..cubicTo(23.49, 11.48, 23.42, 10.73, 23.3, 10.0)
      ..lineTo(12.0, 10.0)
      ..lineTo(12.0, 14.64)
      ..lineTo(18.45, 14.64)
      ..cubicTo(18.17, 16.14, 17.31, 17.41, 16.03, 18.26)
      ..lineTo(16.03, 21.3)
      ..lineTo(19.92, 21.3)
      ..cubicTo(22.2, 19.2, 23.49, 16.02, 23.49, 12.27)
      ..close();
    canvas.drawPath(bluePath, Paint()..color = const Color(0xFF4285F4));

    // Green bottom arc
    final greenPath = Path()
      ..moveTo(12.0, 24.0)
      ..cubicTo(15.24, 24.0, 17.96, 22.92, 19.92, 21.3)
      ..lineTo(16.03, 18.26)
      ..cubicTo(14.96, 18.98, 13.59, 19.41, 12.0, 19.41)
      ..cubicTo(8.87, 19.41, 6.22, 17.29, 5.27, 14.44)
      ..lineTo(1.24, 14.44)
      ..lineTo(1.24, 17.56)
      ..cubicTo(3.23, 21.52, 7.3, 24.0, 12.0, 24.0)
      ..close();
    canvas.drawPath(greenPath, Paint()..color = const Color(0xFF34A853));

    // Yellow left arc
    final yellowPath = Path()
      ..moveTo(5.27, 14.44)
      ..cubicTo(5.03, 13.72, 4.9, 12.95, 4.9, 12.16)
      ..cubicTo(4.9, 11.37, 5.03, 10.6, 5.27, 9.88)
      ..lineTo(5.27, 6.76)
      ..lineTo(1.24, 6.76)
      ..cubicTo(0.45, 8.33, 0.0, 10.19, 0.0, 12.16)
      ..cubicTo(0.0, 14.13, 0.45, 15.99, 1.24, 17.56)
      ..lineTo(5.27, 14.44)
      ..close();
    canvas.drawPath(yellowPath, Paint()..color = const Color(0xFFFBBC05));

    // Red top arc
    final redPath = Path()
      ..moveTo(12.0, 4.91)
      ..cubicTo(13.76, 4.91, 15.34, 5.52, 16.59, 6.7)
      ..lineTo(20.0, 3.29)
      ..cubicTo(17.95, 1.38, 15.24, 0.24, 12.0, 0.24)
      ..cubicTo(7.3, 0.24, 3.23, 2.72, 1.24, 6.68)
      ..lineTo(5.27, 9.8)
      ..cubicTo(6.22, 6.95, 8.87, 4.91, 12.0, 4.91)
      ..close();
    canvas.drawPath(redPath, Paint()..color = const Color(0xFFEA4335));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EmailAuthModalSheet extends StatefulWidget {
  final ProfileAdaptivePalette palette;

  const _EmailAuthModalSheet({required this.palette});

  @override
  State<_EmailAuthModalSheet> createState() => _EmailAuthModalSheetState();
}

class _EmailAuthModalSheetState extends State<_EmailAuthModalSheet> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _isRegister = false;
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _localError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final name = _nameCtrl.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _localError = 'Informe um endereço de e-mail válido.');
      return;
    }
    if (password.length < 6) {
      setState(() => _localError = 'A senha deve ter pelo menos 6 caracteres.');
      return;
    }

    setState(() {
      _submitting = true;
      _localError = null;
    });

    final User? user = _isRegister
        ? await CloudAuthService.registerWithEmailPassword(
            name: name.isNotEmpty ? name : email.split('@').first,
            email: email,
            password: password,
          )
        : await CloudAuthService.signInWithEmailPassword(email, password);

    if (!mounted) return;
    if (user != null) {
      Navigator.of(context).pop(user);
      return;
    }

    setState(() {
      _submitting = false;
      _localError =
          CloudAuthService.lastAuthError.value ??
          'Não foi possível autenticar com este e-mail.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final accent = widget.palette.primary;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E0E14),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _isRegister ? 'Criar conta YOMI' : 'Entrar com E-mail',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Use a mesma conta do portal web para sincronizar sua biblioteca.',
              style: TextStyle(fontSize: 12.5, color: Colors.white60),
            ),
            const SizedBox(height: 16),

            // Mode toggle pills
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF161620),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ModeTabButton(
                      label: 'Entrar',
                      selected: !_isRegister,
                      accent: accent,
                      onTap: () => setState(() {
                        _isRegister = false;
                        _localError = null;
                      }),
                    ),
                  ),
                  Expanded(
                    child: _ModeTabButton(
                      label: 'Criar conta',
                      selected: _isRegister,
                      accent: accent,
                      onTap: () => setState(() {
                        _isRegister = true;
                        _localError = null;
                      }),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_isRegister) ...[
              TextField(
                controller: _nameCtrl,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: _fieldDecoration(
                  'Nome ou apelido',
                  Icons.person_outline_rounded,
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _fieldDecoration(
                'E-mail',
                Icons.mail_outline_rounded,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitting ? null : _submit(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _fieldDecoration(
                'Senha',
                Icons.lock_outline_rounded,
                suffix: IconButton(
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: Colors.white54,
                  ),
                ),
              ),
            ),

            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Fotos e GIFs compactos estão incluídos. Você pode vincular o Google depois para guardar originais e backups.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            if (_localError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.28)),
                ),
                child: Text(
                  _localError!,
                  style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                ),
              ),
            ],

            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Text(
                        _isRegister ? 'Criar Conta e Entrar' : 'Entrar',
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(
    String label,
    IconData icon, {
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
      prefixIcon: Icon(icon, size: 18, color: Colors.white54),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFF14141E),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: widget.palette.primary),
      ),
    );
  }
}

class _ModeTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ModeTabButton({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.white60,
          ),
        ),
      ),
    );
  }
}
