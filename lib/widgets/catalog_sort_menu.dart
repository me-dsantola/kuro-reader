import 'package:flutter/material.dart';
import '../models/manga_models.dart';

enum CatalogOrder { source, title }

List<Manga> orderCatalog(List<Manga> mangas, CatalogOrder order) {
  final result = List<Manga>.of(mangas);
  if (order == CatalogOrder.title) {
    result.sort((a, b) {
      final comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return comparison != 0
          ? comparison
          : a.compositeId.compareTo(b.compositeId);
    });
  }
  return result;
}

/// Sorting the loaded list never resets source cursors or starts a new search.
class CatalogSortMenu extends StatelessWidget {
  final CatalogOrder value;
  final ValueChanged<CatalogOrder> onChanged;
  const CatalogSortMenu({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<CatalogOrder>(
    tooltip: 'Ordenar catálogo',
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (_) => [
      const PopupMenuItem<CatalogOrder>(
        enabled: false,
        child: Text(
          'Ordenar resultados carregados',
          style: TextStyle(fontSize: 12),
        ),
      ),
      CheckedPopupMenuItem(
        key: const ValueKey('catalog-sort-source'),
        value: CatalogOrder.source,
        checked: value == CatalogOrder.source,
        child: const Text('Padrão do catálogo'),
      ),
      CheckedPopupMenuItem(
        key: const ValueKey('catalog-sort-title'),
        value: CatalogOrder.title,
        checked: value == CatalogOrder.title,
        child: const Text('Título (A–Z)'),
      ),
    ],
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sort_rounded, color: Color(0xFFF472B6)),
          SizedBox(width: 6),
          Text(
            'Ordenar',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}
