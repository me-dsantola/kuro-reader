import 'package:flutter/material.dart';
import '../models/catalog_sort.dart';
import '../services/profile_palette_service.dart';

class CatalogSortControl extends StatelessWidget {
  final CatalogSort value;
  final ValueChanged<CatalogSort> onChanged;
  const CatalogSortControl({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<ProfileAdaptivePalette>(
        valueListenable: ProfilePaletteService.paletteNotifier,
        builder: (context, palette, _) => PopupMenuButton<CatalogSort>(
          tooltip: 'Ordenar catálogo',
          initialValue: value,
          onSelected: onChanged,
          color: palette.surface,
          position: PopupMenuPosition.under,
          itemBuilder: (context) => [
            for (final option in CatalogSort.values)
              CheckedPopupMenuItem(
                value: option,
                checked: value == option,
                child: Text(
                  option.label,
                  style: const TextStyle(color: Color(0xFFFAFAFA)),
                ),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48, maxWidth: 140),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sort_rounded, size: 20, color: palette.soft),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      value.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFFAFAFA),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: palette.soft,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
