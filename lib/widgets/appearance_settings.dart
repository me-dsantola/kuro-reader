import 'package:flutter/material.dart';
import '../services/appearance_controller.dart';

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
              'Não foi possível salvar a aparência. Tente novamente.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<AppearancePreferences>(
    valueListenable: AppearanceController.instance,
    builder: (context, preferences, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Aparência e movimento',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFFFBCFE8),
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
                title: const Text('Vidro suave'),
                subtitle: const Text(
                  'Transparência discreta nos menus. A economia de bateria e o alto contraste mantêm as superfícies opacas.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                value: preferences.style == InterfaceStyle.glass,
                onChanged: (enabled) => _save(
                  context,
                  AppearanceController.instance.setStyle(
                    enabled ? InterfaceStyle.glass : InterfaceStyle.enso,
                  ),
                ),
              ),
              const Divider(height: 1, color: Colors.white10),
              SwitchListTile.adaptive(
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
    ),
  );
}
