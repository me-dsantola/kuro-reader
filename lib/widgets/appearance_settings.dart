import 'app_feedback.dart';
import 'package:flutter/material.dart';
import '../services/appearance_controller.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import '../services/yomi_theme_system.dart';

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
      YomiThemeController.instance,
    ]),
    builder: (context, _) {
      final preferences = AppearanceController.instance.value;
      final privacyEnabled = StorageService.privacyProtectionEnabled;
      final palette = ProfilePaletteService.paletteNotifier.value;
      final themeTokens = YomiThemeController.instance.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tema da Interface',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: palette.soft,
            ),
          ),
          const SizedBox(height: 8),
          Column(
            children: [
              for (
                var row = 0;
                row < (YomiThemeId.values.length / 2).ceil();
                row++
              ) ...[
                if (row > 0) const SizedBox(height: 8),
                Row(
                  children: [
                    for (var col = 0; col < 2; col++) ...[
                      if (col > 0) const SizedBox(width: 8),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final index = row * 2 + col;
                            if (index >= YomiThemeId.values.length) {
                              return const SizedBox.shrink();
                            }
                            final id = YomiThemeId.values[index];
                            final tokens = YomiThemeTokens.forId(id);
                            final isSelected = themeTokens.id == id;
                            return Material(
                              color: tokens.cardSurface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isSelected
                                      ? tokens.accentPrimary
                                      : tokens.border,
                                  width: isSelected ? 2.0 : 1.0,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _save(
                                  context,
                                  YomiThemeController.instance.setTheme(id),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: tokens.background,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: tokens.border,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Center(
                                          child: Container(
                                            width: 9,
                                            height: 9,
                                            decoration: BoxDecoration(
                                              color: tokens.accentPrimary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          tokens.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isSelected
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            color: tokens.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(
                                          Icons.check_circle_rounded,
                                          size: 16,
                                          color: tokens.accentPrimary,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
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
                  title: const Text('Reatividade de Cores Inteligente'),
                  subtitle: const Text(
                    'Adapta os detalhes e acentos à obra em destaque, preservando o fundo do tema.',
                  ),
                  activeThumbColor: themeTokens.accentPrimary,
                  value: YomiThemeController.instance.reactiveColorsEnabled,
                  onChanged: (enabled) => _save(
                    context,
                    YomiThemeController.instance.setReactiveColors(enabled),
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
                SwitchListTile.adaptive(
                  title: const Text('Efeito Ambilight na Home'),
                  subtitle: const Text(
                    'Aura difusa e cinematográfica ao redor da obra em destaque.',
                  ),
                  activeThumbColor: themeTokens.accentPrimary,
                  value: YomiThemeController.instance.ambilightEnabled,
                  onChanged: (enabled) => _save(
                    context,
                    YomiThemeController.instance.setAmbilight(enabled),
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
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
