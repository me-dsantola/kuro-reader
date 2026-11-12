import 'package:flutter/material.dart';

class ContinueReadingItem {
  final String mangaId;
  final String mangaTitle;
  final String chapterId;
  final String chapterTitle;
  final int currentPage;
  final int totalPages;
  final ImageProvider coverProvider;

  const ContinueReadingItem({
    required this.mangaId,
    required this.mangaTitle,
    required this.chapterId,
    required this.chapterTitle,
    required this.currentPage,
    required this.totalPages,
    required this.coverProvider,
  });

  double get progress =>
      totalPages > 0 ? (currentPage / totalPages).clamp(0.0, 1.0) : 0.0;
}

class SharedContinueReadingCard extends StatefulWidget {
  final ContinueReadingItem item;
  final VoidCallback onResume;
  final Color accentColor;

  const SharedContinueReadingCard({
    super.key,
    required this.item,
    required this.onResume,
    required this.accentColor,
  });

  @override
  State<SharedContinueReadingCard> createState() =>
      _SharedContinueReadingCardState();
}

class _SharedContinueReadingCardState extends State<SharedContinueReadingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _coverScale;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _coverScale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handleHighlight(bool highlighted, bool reduceMotion) {
    if (reduceMotion) return;
    if (highlighted) {
      _pressController.forward();
    } else {
      _pressController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final progress = widget.item.progress;

    return Semantics(
      button: true,
      label:
          'Continuar lendo ${widget.item.mangaTitle}, ${widget.item.chapterTitle}, página ${widget.item.currentPage} de ${widget.item.totalPages}',
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onResume,
          onHighlightChanged: (v) => _handleHighlight(v, reduceMotion),
          onHover: (v) => _handleHighlight(v, reduceMotion),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                // Capa com a mesma animação elástica da Biblioteca
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 64,
                    height: 92,
                    child: AnimatedBuilder(
                      animation: _coverScale,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: reduceMotion ? 1.0 : _coverScale.value,
                          child: child,
                        );
                      },
                      child: Image(
                        image: widget.item.coverProvider,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Colors.black26,
                          child: Icon(Icons.menu_book_rounded),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.item.mangaTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.item.chapterTitle} • Pág. ${widget.item.currentPage}/${widget.item.totalPages}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: progress),
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 350),
                        builder: (context, value, _) {
                          return LinearProgressIndicator(
                            value: value,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(4),
                            color: widget.accentColor,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.play_circle_fill_rounded,
                    color: widget.accentColor, size: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
