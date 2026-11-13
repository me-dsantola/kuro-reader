import 'dart:async';
import 'package:flutter/material.dart';
import '../services/cloud_auth_service.dart';
import '../services/cloud_sync_service.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import '../widgets/yomi_brand_widgets.dart';

/// Mandatory Auth Gate Screen shown when the user is not signed in with a Google Account.
/// Once authenticated, checks whether a cloud backup exists to restore, or prompts
/// profile personalization.
class KuroAuthScreen extends StatefulWidget {
  final VoidCallback onAuthenticated;

  const KuroAuthScreen({super.key, required this.onAuthenticated});

  @override
  State<KuroAuthScreen> createState() => _KuroAuthScreenState();
}

class _KuroAuthScreenState extends State<KuroAuthScreen> {
  bool _isLoading = false;
  String? _statusMessage;

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

      if (mounted) {
        setState(() {
          _statusMessage = 'Verificando dados na nuvem...';
        });
      }

      // Check if user has an existing cloud backup in Firestore
      try {
        final meta = await CloudSyncService.checkCloudBackupMetadata();
        if (meta != null) {
          if (mounted) {
            setState(() {
              _statusMessage = 'Restaurando sua biblioteca da nuvem...';
            });
          }
          await CloudSyncService.restoreFromCloud();
        }
      } catch (_) {}

      // If profile is not configured yet, pre-populate name from Google displayName
      final currentProfile = StorageService.profileNotifier.value;
      if (!currentProfile.isConfigured && user.displayName != null && user.displayName!.isNotEmpty) {
        await StorageService.updateUserProfile(
          currentProfile.copyWith(name: user.displayName),
        );
      }

      if (mounted) {
        widget.onAuthenticated();
      }
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

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileAdaptivePalette>(
      valueListenable: ProfilePaletteService.paletteNotifier,
      builder: (context, palette, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF070709),
          body: Stack(
            children: [
              // Subtle Ensō ambient glow in the top-right
              Positioned(
                top: -80,
                right: -80,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        palette.primary.withValues(alpha: 0.22),
                        palette.primary.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // App Logo
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: palette.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: palette.primary.withValues(alpha: 0.35),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: palette.primary.withValues(alpha: 0.18),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Image.asset(
                            'assets/images/yomi_logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.auto_stories_rounded,
                              size: 42,
                              color: palette.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Title
                        const YomiEnsoLogo(fontSize: 28),
                        const SizedBox(height: 10),
                        const Text(
                          'Sua biblioteca de mangás, manhwas e quadrinhos sincronizada na nuvem.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 36),

                        // Feature highlights
                        _buildFeatureRow(
                          icon: Icons.cloud_sync_rounded,
                          color: palette.primary,
                          title: 'Backup e Sincronização em Nuvem',
                          subtitle: 'Seus favoritos, histórico e listas salvos na sua conta Google.',
                          palette: palette,
                        ),
                        const SizedBox(height: 14),
                        _buildFeatureRow(
                          icon: Icons.offline_pin_rounded,
                          color: palette.secondary,
                          title: 'Experiência Offline Completa',
                          subtitle: 'Baixe capítulos inteiros e leia quando e onde quiser sem internet.',
                          palette: palette,
                        ),
                        const SizedBox(height: 14),
                        _buildFeatureRow(
                          icon: Icons.face_retouching_natural_rounded,
                          color: palette.primary,
                          title: 'Perfil Personalizado & Mascote',
                          subtitle: 'Crie seu Blobatar interativo e temas visuais adaptativos exclusivos.',
                          palette: palette,
                        ),
                        const SizedBox(height: 38),

                        // Google Sign-In Action Area
                        ValueListenableBuilder<String?>(
                          valueListenable: CloudAuthService.lastAuthError,
                          builder: (context, errorMsg, _) {
                            if (errorMsg == null) return const SizedBox.shrink();
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      errorMsg,
                                      style: const TextStyle(fontSize: 12, color: Colors.redAccent),
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

                        // Primary Google Sign-In Button
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF1E1E1E),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _isLoading ? null : _handleGoogleSignIn,
                            child: _isLoading
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        palette.primary,
                                      ),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      // Google G custom icon
                                      _buildGoogleGLogo(),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Continuar com o Google',
                                        style: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Mandatory login notice
                        const Text(
                          'O login é obrigatório para inicializar sua biblioteca e garantir a restauração segura dos seus mangás.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white38,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required ProfileAdaptivePalette palette,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colors.white60,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleGLogo() {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      child: const Icon(
        Icons.g_mobiledata_rounded,
        size: 28,
        color: Color(0xFF4285F4),
      ),
    );
  }
}
