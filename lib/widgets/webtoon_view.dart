import 'package:flutter/material.dart';
import '../models/reader_page_geometry.dart';
import 'reader_scroll_controller.dart';

typedef WebtoonPageBuilder =
    Widget Function(
      BuildContext context,
      int index,
      ValueChanged<double> onRatio,
    );

/// Page geometry survives image disposal and cache eviction. New online
/// dimensions are applied during layout with the visible page anchored.
/// Supports pinch-to-zoom and double-tap-to-zoom without breaking vertical scroll.
class WebtoonView extends StatefulWidget {
  final ReaderPageGeometry geometry;
  final ReaderScrollController controller;
  final WebtoonPageBuilder pageBuilder;
  final Widget footer;
  final ValueChanged<double> onWidth;
  final bool localDimensionsKnown;
  final VoidCallback? onTap;

  const WebtoonView({
    super.key,
    required this.geometry,
    required this.controller,
    required this.pageBuilder,
    required this.footer,
    required this.onWidth,
    this.localDimensionsKnown = false,
    this.onTap,
  });

  @override
  State<WebtoonView> createState() => _WebtoonViewState();
}

class _WebtoonViewState extends State<WebtoonView> {
  final Map<int, double> _pending = {};
  final TransformationController _zoomController = TransformationController();
  double _width = 0;
  bool _scheduled = false;
  int _activePointers = 0;
  bool _isZoomed = false;
  Offset _lastDoubleTapLocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _zoomController.addListener(_onZoomChanged);
  }

  @override
  void dispose() {
    _zoomController.removeListener(_onZoomChanged);
    _zoomController.dispose();
    super.dispose();
  }

  void _onZoomChanged() {
    final scale = _zoomController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.02;
    if (zoomed != _isZoomed && mounted) {
      setState(() => _isZoomed = zoomed);
    }
  }

  void _resetZoom() {
    _zoomController.value = Matrix4.identity();
    if (_isZoomed && mounted) {
      setState(() => _isZoomed = false);
    }
  }

  void _handleDoubleTap() {
    final currentScale = _zoomController.value.getMaxScaleOnAxis();
    if (currentScale > 1.05) {
      _resetZoom();
      return;
    }
    const targetScale = 2.25;
    final dx = -_lastDoubleTapLocal.dx * (targetScale - 1.0);
    final dy = -_lastDoubleTapLocal.dy * (targetScale - 1.0);
    _zoomController.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0.0, 1.0)
      ..scaleByDouble(targetScale, targetScale, 1.0, 1.0);
  }

  void _ratio(int index, double ratio) {
    if (!ratio.isFinite || ratio <= 0) return;
    if (widget.geometry.hasRatio(index) &&
        (widget.localDimensionsKnown ||
            (widget.geometry.ratioAt(index) - ratio).abs() < 0.001)) {
      return;
    }
    _pending[index] = ratio;
    _schedule();
  }

  void _schedule() {
    if (_scheduled || _pending.isEmpty) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || _width <= 0 || !widget.controller.hasClients) return;
      final position = widget.controller.position;
      final corrected = widget.geometry.updateRatios(
        _pending,
        _width,
        position.pixels,
      );
      widget.controller.correctLayoutOffset(corrected);
      setState(_pending.clear);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_width > 0 &&
          constraints.maxWidth != _width &&
          widget.controller.hasClients) {
        final corrected = widget.geometry.reflowOffset(
          widget.controller.offset,
          _width,
          constraints.maxWidth,
        );
        widget.controller.correctLayoutOffset(corrected);
      }
      _width = constraints.maxWidth;
      widget.onWidth(_width);

      final scrollView = CustomScrollView(
        key: const ValueKey('webtoon-scroll'),
        controller: widget.controller,
        physics: (_activePointers >= 2 || _isZoomed)
            ? const NeverScrollableScrollPhysics()
            : null,
        cacheExtent: 800,
        slivers: [
          SliverVariedExtentList.builder(
            itemCount: widget.geometry.pageCount,
            itemExtentBuilder: (index, dimensions) =>
                widget.geometry.extentAt(index, _width),
            addAutomaticKeepAlives: false,
            itemBuilder: (context, index) => widget.pageBuilder(
              context,
              index,
              (ratio) => _ratio(index, ratio),
            ),
          ),
          SliverToBoxAdapter(child: widget.footer),
        ],
      );

      return Listener(
        onPointerDown: (_) {
          _activePointers++;
          if (_activePointers == 2 && mounted) setState(() {});
        },
        onPointerUp: (_) {
          _activePointers = (_activePointers - 1).clamp(0, 10);
          if (_activePointers < 2 && mounted) setState(() {});
        },
        onPointerCancel: (_) {
          _activePointers = (_activePointers - 1).clamp(0, 10);
          if (_activePointers < 2 && mounted) setState(() {});
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onTap,
          onDoubleTapDown: (details) =>
              _lastDoubleTapLocal = details.localPosition,
          onDoubleTap: _handleDoubleTap,
          child: Stack(
            children: [
              InteractiveViewer(
                transformationController: _zoomController,
                minScale: 1.0,
                maxScale: 4.0,
                panEnabled: _isZoomed,
                scaleEnabled: true,
                child: scrollView,
              ),
              if (_isZoomed)
                Positioned(
                  bottom: 24,
                  right: 16,
                  child: SafeArea(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(
                          0xFF121217,
                        ).withValues(alpha: 0.88),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _resetZoom,
                      icon: const Icon(Icons.zoom_out_map_rounded, size: 16),
                      label: const Text('Resetar Zoom (1x)'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
