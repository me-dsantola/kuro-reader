import 'app_feedback.dart';
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
        AppFeedback.show(
          context,
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
                SwitchListTile.adaptive(
                  title: const Text('Efeito de vidro flutuante'),
                  subtitle: const Text(
                    'Desative para uma interface AMOLED opaca. Economia de energia e alto contraste reduzem os efeitos.',
                  ),
                  activeThumbColor: palette.primary,
                  value: preferences.style == InterfaceStyle.glass,
                  onChanged: (enabled) => _save(
                    context,
                    AppearanceController.instance.setStyle(
                      enabled ? InterfaceStyle.glass : InterfaceStyle.enso,
                    ),
                  ),
                ),
                SwitchListTile.adaptive(
                  title: const Text('Transições rápidas entre menus'),
                  subtitle: const Text(
                    'Fade e deslizamento suave; respeita a redução de movimento.',
                  ),
                  activeThumbColor: palette.primary,
                  value: preferences.tabTransitions,
                  onChanged: (enabled) => _save(
                    context,
                    AppearanceController.instance.setTabTransitions(enabled),
                  ),
                ),
                SwitchListTile.adaptive(
                  title: const Text('Cores do leitor pela obra'),
                  subtitle: const Text(
                    'O menu de leitura acompanha a capa. Desative para usar as cores do perfil.',
                  ),
                  activeThumbColor: palette.primary,
                  value: preferences.reactiveReader,
                  onChanged: (enabled) => _save(
                    context,
                    AppearanceController.instance.setReactiveReader(enabled),
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
