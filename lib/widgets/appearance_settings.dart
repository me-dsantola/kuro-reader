import 'package:flutter/material.dart';
import '../services/appearance_controller.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';

class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});
  Future<void> _save(BuildContext context, Future<void> operation) async {
    try {
      await operation;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível salvar a preferência. Tente novamente.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      AppearanceController.instance,
      StorageService.privacyProtectionNotifier,
      ProfilePaletteService.paletteNotifier,
    ]),
    builder: (context, _) {
      final preferences = AppearanceController.instance.value;
      final privacyEnabled = StorageService.privacyProtectionEnabled;
      final palette = ProfilePaletteService.paletteNotifier.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aparência, privacidade e movimento',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: palette.soft,
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: const Color(0xFF121217),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Colors.white10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.blur_on_rounded,
                    color: palette.primary,
                  ),
                  title: const Text(
                    'Efeito de vidro flutuante (Padrão)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text(
                    'Ativo automaticamente em todo o aplicativo e desativado apenas enquanto o aparelho estiver em modo de economia de energia.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
                SwitchListTile.adaptive(
                  activeThumbColor: palette.primary,
                  title: const Text('Proteção de Privacidade'),
                  subtitle: const Text(
                    'Oculta o conteúdo da tela ao alternar de aplicativo ou deixar o YOMI em segundo plano.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  value: privacyEnabled,
                  onChanged: (enabled) => _save(
                    context,
                    StorageService.setPrivacyProtectionEnabled(enabled),
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
                SwitchListTile.adaptive(
                  activeThumbColor: palette.primary,
                  title: const Text('Recolher menus ao rolar'),
                  subtitle: const Text(
                    'Mais espaço ao descer; os controles voltam ao subir. Respeita a redução de movimento do aparelho.',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  value: preferences.autoHideMenus,
                  onChanged: (enabled) => _save(
                    context,
                    AppearanceController.instance.setAutoHide(enabled),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
