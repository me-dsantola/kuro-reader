import 'package:flutter/material.dart';
import '../services/appearance_controller.dart';
import '../services/profile_palette_service.dart';
import '../services/storage_service.dart';
import 'frosted_surface.dart';
import 'yomi_blobatar_studio.dart';

class ReaderToolbar extends StatelessWidget {
  final String title;
  final ProfileAdaptivePalette? palette;
  final String chapter;
  final int page;
  final int total;
  final bool offline;
  final bool webtoon;
  final bool visible;
  final VoidCallback onBack;
  final VoidCallback onMode;
  final VoidCallback onComplete;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onOpenManga;

  const ReaderToolbar({
    super.key,
    required this.title,
    this.palette,
    required this.chapter,
    required this.page,
    required this.total,
    required this.offline,
    required this.webtoon,
    this.visible = true,
    required this.onBack,
    required this.onMode,
    required this.onComplete,
    this.onPrevious,
    this.onNext,
    this.onOpenManga,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      AppearanceController.instance,
      ProfilePaletteService.paletteNotifier,
      StorageService.profileNotifier,
    ]),
    builder: (context, _) {
      final colors = AppearanceController.instance.value.reactiveReader
          ? palette ?? ProfilePaletteService.paletteNotifier.value
          : ProfilePaletteService.paletteNotifier.value;
      final profile = StorageService.profileNotifier.value;
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      final progress =
          total > 0 ? ((page + 1) / total).clamp(0.0, 1.0) : 0.0;

      return IconTheme(
        data: IconThemeData(color: colors.soft),
        child: FrostedSurface(
          palette: colors,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 8, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        tooltip: 'Voltar para a obra',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: onOpenManga,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 4,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  'Cap. $chapter · ${page + 1}/$total${offline ? ' · Offline' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colors.soft,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (onPrevious != null)
                        IconButton(
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 44,
                          ),
                          tooltip: 'Capítulo anterior',
                          onPressed: onPrevious,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                      if (onNext != null)
                        IconButton(
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 44,
                          ),
                          tooltip: 'Próximo capítulo',
                          onPressed: onNext,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                      IconButton(
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 44,
                        ),
                        tooltip: webtoon
                            ? 'Usar modo paginado'
                            : 'Usar rolagem contínua',
                        onPressed: onMode,
                        icon: Icon(
                          webtoon
                              ? Icons.view_carousel_rounded
                              : Icons.view_day_rounded,
                          color: colors.secondary,
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 44,
                        ),
                        tooltip: 'Marcar capítulo como concluído',
                        onPressed: onComplete,
                        icon: Icon(
                          Icons.check_circle_outline_rounded,
                          color: colors.secondary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      // Blobatar discreto e pausado quando os controles estão ocultos
                      TickerMode(
                        enabled: visible && !reduceMotion,
                        child: Semantics(
                          label: 'Mascote ${profile.effectiveBlobatarName}',
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.primary.withValues(alpha: 0.7),
                                width: 1.2,
                              ),
                            ),
                            child: ClipOval(
                              child: YomiProfileBlobatar(
                                profile: profile.copyWith(
                                  blobatarAnimated: visible &&
                                      !reduceMotion &&
                                      profile.blobatarAnimated,
                                ),
                                size: 30,
                                adaptiveHue: colors.hue,
                                interactiveCycleOnTap: false,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      color: colors.primary,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
