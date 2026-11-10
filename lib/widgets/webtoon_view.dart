import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
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
class WebtoonView extends StatefulWidget {
  final ReaderPageGeometry geometry;
  final ReaderScrollController controller;
  final WebtoonPageBuilder pageBuilder;
  final Widget footer;
  final ValueChanged<double> onWidth;
  final bool localDimensionsKnown;

  const WebtoonView({
    super.key,
    required this.geometry,
    required this.controller,
    required this.pageBuilder,
    required this.footer,
    required this.onWidth,
    this.localDimensionsKnown = false,
  });

  @override
  State<WebtoonView> createState() => _WebtoonViewState();
}

class _WebtoonViewState extends State<WebtoonView> {
  final Map<int, double> _pending = {};
  double _width = 0;
  bool _scheduled = false;

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
      return CustomScrollView(
        key: const ValueKey('webtoon-scroll'),
        controller: widget.controller,
        scrollCacheExtent: const ScrollCacheExtent.pixels(800),
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
    },
  );
}
