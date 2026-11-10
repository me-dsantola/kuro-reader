import 'package:flutter/material.dart';
import '../models/catalog_sort.dart';

class CatalogSortControl extends StatelessWidget {
  final CatalogSort value;
  final ValueChanged<CatalogSort> onChanged;
  const CatalogSortControl({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<CatalogSort>(
    tooltip: 'Ordenar catálogo',
    initialValue: value,
    onSelected: onChanged,
    color: const Color(0xFF181820),
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
      const PopupMenuDivider(),
      const PopupMenuItem<CatalogSort>(
        enabled: false,
        child: SizedBox(
          width: 240,
          child: Text(
            'Recentes e populares usam a classificação de cada fonte. A–Z organiza os títulos carregados, incluindo novas páginas.',
            style: TextStyle(fontSize: 11, color: Colors.white70),
          ),
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
            const Icon(Icons.sort_rounded, size: 20, color: Color(0xFFFBCFE8)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                value.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFFFAFAFA)),
              ),
            ),
            const Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: Color(0xFFFBCFE8),
            ),
          ],
        ),
      ),
    ),
  );
}
