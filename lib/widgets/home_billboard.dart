import 'package:flutter/material.dart';
import '../models/manga_models.dart';

/// The artwork and actions come from the real catalog, never sample titles.
class HomeBillboard extends StatelessWidget {
  final Manga manga;
  final Widget artwork;
  final Color accent;
  final bool inList;
  final bool opening;
  final VoidCallback onRead;
  final VoidCallback onToggleList;

  const HomeBillboard({
    super.key,
    required this.manga,
    required this.artwork,
    required this.accent,
    required this.inList,
    required this.onRead,
    required this.onToggleList,
    this.opening = false,
  });

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF070709);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return Stack(
      children: [
        Positioned.fill(child: ExcludeSemantics(child: artwork)),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.25, 0.55, 0.8, 1],
                colors: [
                  Color(0x99070709),
                  Color(0x33070709),
                  Color(0xCC070709),
                  Color(0xF5070709),
                  background,
                ],
              ),
            ),
          ),
        ),
        if (wide)
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xF0070709), Color(0x66070709)],
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, wide ? 200 : 250, 20, 28),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xCC070709),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'DESTAQUE NO YOMI',
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    manga.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: wide ? 52 : 38,
                      fontWeight: FontWeight.w900,
                      height: 1.04,
                      letterSpacing: -1.4,
                      shadows: const [
                        Shadow(
                          color: Color(0xDD000000),
                          offset: Offset(0, 3),
                          blurRadius: 16,
                        ),
                        Shadow(
                          color: Color(0xFF070709),
                          offset: Offset(0, 1),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (manga.tags.isNotEmpty) ...[
                    Text(
                      manga.tags.take(3).join('  •  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(
                            color: Color(0xEE000000),
                            offset: Offset(0, 1),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Text(
                    manga.description.trim().isEmpty
                        ? 'Conheça esta história e descubra sua próxima leitura.'
                        : manga.description
                              .replaceAll(RegExp(r'\s+'), ' ')
                              .trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xDDFFFFFF),
                      fontSize: 14,
                      height: 1.5,
                      shadows: [
                        Shadow(
                          color: Color(0xFF000000),
                          offset: Offset(0, 1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final read = FilledButton.icon(
                        onPressed: opening ? null : onRead,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: opening
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          opening ? 'Abrindo…' : 'Ler Agora',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      );
                      final list = OutlinedButton.icon(
                        onPressed: onToggleList,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0xAA202026),
                          side: const BorderSide(color: Colors.white24),
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: Icon(
                          inList ? Icons.check_rounded : Icons.add_rounded,
                          size: 20,
                        ),
                        label: Text(
                          inList ? 'Na Minha Lista' : 'Minha Lista',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      );
                      if (constraints.maxWidth < 340 || textScale > 1.3) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [read, const SizedBox(height: 10), list],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: read),
                          const SizedBox(width: 10),
                          Expanded(child: list),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Three complete covers and a glimpse of the fourth on phone screens.
double homeCoverWidth(double availableWidth) =>
    ((availableWidth - 36) / 3.25).clamp(72.0, 168.0);
