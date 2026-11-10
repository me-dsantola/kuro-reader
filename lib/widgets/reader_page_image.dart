import 'package:flutter/material.dart';

/// A single image stream for decoding, progress and retry. The parent reserves
/// the page extent even while this widget is loading, failing or recycled.
class ReaderPageImage extends StatefulWidget {
  final ImageProvider image;
  final int pageNumber;
  final ValueChanged<double> onRatio;
  final VoidCallback onRetry;
  final VoidCallback? onError;

  const ReaderPageImage({
    super.key,
    required this.image,
    required this.pageNumber,
    required this.onRatio,
    required this.onRetry,
    this.onError,
  });

  @override
  State<ReaderPageImage> createState() => _ReaderPageImageState();
}

class _ReaderPageImageState extends State<ReaderPageImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;
  ImageChunkEvent? _progress;
  bool _failed = false;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ReaderPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _resolve();
  }

  void _resolve() {
    final next = widget.image.resolve(createLocalImageConfiguration(context));
    if (_stream?.key == next.key) return;
    _detach();
    final generation = ++_generation;
    _failed = false;
    _progress = null;
    _info?.dispose();
    _info = null;
    _stream = next;
    _listener = ImageStreamListener(
      (info, synchronousCall) {
        if (!mounted || generation != _generation) {
          info.dispose();
          return;
        }
        setState(() {
          _info?.dispose();
          _info = info;
          _failed = false;
        });
        final ratio = info.image.width / info.image.height;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _generation) widget.onRatio(ratio);
        });
      },
      onChunk: (event) {
        if (mounted && generation == _generation) {
          setState(() => _progress = event);
        }
      },
      onError: (Object error, StackTrace? stack) {
        if (!mounted || generation != _generation) return;
        setState(() => _failed = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _generation) widget.onError?.call();
        });
      },
    );
    next.addListener(_listener!);
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
  }

  @override
  void dispose() {
    _generation++;
    _detach();
    _info?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_info != null) {
      return Semantics(
        label: 'Página ${widget.pageNumber}',
        image: true,
        child: RawImage(
          image: _info!.image,
          scale: _info!.scale,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.low,
        ),
      );
    }
    if (_failed) {
      return PageLoadFailure(
        pageNumber: widget.pageNumber,
        onRetry: widget.onRetry,
      );
    }
    final total = _progress?.expectedTotalBytes;
    return Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          semanticsLabel: 'Carregando página ${widget.pageNumber}',
          value: total != null && total > 0
              ? _progress!.cumulativeBytesLoaded / total
              : null,
          color: const Color(0xFFE11D48),
        ),
      ),
    );
  }
}

/// Both reading modes offer the same recovery action for a failed page.
class PageLoadFailure extends StatelessWidget {
  final int pageNumber;
  final VoidCallback onRetry;
  const PageLoadFailure({
    super.key,
    required this.pageNumber,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final retry = IconButton(
        tooltip: 'Tentar carregar a página $pageNumber novamente',
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, color: Color(0xFFE11D48)),
      );
      return Center(
        child: constraints.maxHeight < 110
            ? retry
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  retry,
                  const SizedBox(height: 6),
                  Text(
                    'Página $pageNumber indisponível',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
      );
    },
  );
}
