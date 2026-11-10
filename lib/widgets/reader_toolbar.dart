import 'package:flutter/material.dart';
import 'frosted_surface.dart';

class ReaderToolbar extends StatelessWidget {
  final String title;
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

  const ReaderToolbar({
    super.key,
    required this.title,
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
  });

  @override
  Widget build(BuildContext context) => FrostedSurface(
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
                IconButton(
                  tooltip: webtoon
                      ? 'Usar modo paginado'
                      : 'Usar rolagem contínua',
                  onPressed: onMode,
                  icon: Icon(
                    webtoon
                        ? Icons.view_carousel_rounded
                        : Icons.view_day_rounded,
                    color: const Color(0xFFF472B6),
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
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFFBCFE8),
                      ),
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
                    icon: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: Color(0xFFF472B6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
