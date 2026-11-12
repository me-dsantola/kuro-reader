import '../services/appearance_controller.dart';
import '../services/profile_palette_service.dart';
import 'package:flutter/material.dart';
import 'frosted_surface.dart';

class ReaderToolbar extends StatelessWidget {
  final String title;
  final ProfileAdaptivePalette? palette;
  final String chapter;
  final int page;
  final int total;
  final bool offline;
  final bool webtoon;
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
    ]),
    builder: (context, _) {
      final colors = AppearanceController.instance.value.reactiveReader
          ? palette ?? ProfilePaletteService.paletteNotifier.value
          : ProfilePaletteService.paletteNotifier.value;
      return IconTheme(
        data: IconThemeData(color: colors.soft),
        child: FrostedSurface(
          palette: colors,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Voltar para a obra',
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
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
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (onOpenManga != null)
                        IconButton(
                          tooltip: 'Ver página do mangá',
                          onPressed: onOpenManga,
                          icon: Icon(
                            Icons.menu_book_rounded,
                            color: colors.soft,
                          ),
                        ),
                      IconButton(
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
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Cap. $chapter · ${page + 1}/$total${offline ? ' · Offline' : ''}',
                            style: TextStyle(fontSize: 12, color: colors.soft),
                          ),
                        ),
                        if (onPrevious != null)
                          IconButton(
                            tooltip: 'Capítulo anterior',
                            onPressed: onPrevious,
                            icon: const Icon(Icons.skip_previous_rounded),
                          ),
                        if (onNext != null)
                          IconButton(
                            tooltip: 'Próximo capítulo',
                            onPressed: onNext,
                            icon: const Icon(Icons.skip_next_rounded),
                          ),
                        IconButton(
                          tooltip: 'Marcar capítulo como concluído',
                          onPressed: onComplete,
                          icon: Icon(
                            Icons.check_circle_outline_rounded,
                            color: colors.secondary,
                          ),
                        ),
                      ],
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
