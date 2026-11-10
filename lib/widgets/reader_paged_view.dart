import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'reader_page_image.dart';

class ReaderPagedView extends StatelessWidget {
  final PageController controller;
  final int pageCount;
  final ImageProvider Function(int) imageForPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRetry;
  final VoidCallback onToggleHud;

  const ReaderPagedView({
    super.key,
    required this.controller,
    required this.pageCount,
    required this.imageForPage,
    required this.onPageChanged,
    required this.onRetry,
    required this.onToggleHud,
  });

  @override
  Widget build(BuildContext context) => PhotoViewGallery.builder(
    pageController: controller,
    itemCount: pageCount,
    onPageChanged: onPageChanged,
    loadingBuilder: (context, progress) => const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: Color(0xFFE11D48),
        ),
      ),
    ),
    builder: (context, index) => PhotoViewGalleryPageOptions(
      imageProvider: imageForPage(index),
      semanticLabel: 'Página ${index + 1}',
      errorBuilder: (context, error, stack) =>
          PageLoadFailure(pageNumber: index + 1, onRetry: () => onRetry(index)),
      onTapUp: (context, details, value) => onToggleHud(),
      minScale: PhotoViewComputedScale.contained,
      initialScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 3,
    ),
  );
}
