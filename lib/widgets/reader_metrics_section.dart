import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../models/manga_models.dart';
import '../services/profile_palette_service.dart';
import '../services/reader_metrics.dart';
import 'yomi_blobatar_studio.dart';

class ReaderMetricsSection extends StatelessWidget {
  const ReaderMetricsSection({
    super.key,
    required this.metrics,
    required this.profile,
    required this.accent,
  });

  final ReaderMetrics metrics;
  final UserProfile profile;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Métricas do Leitor', style: theme.textTheme.titleLarge),
            const SizedBox(height: 14),
            Text('Todo o histórico', style: theme.textTheme.titleSmall),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                Chip(label: Text('${metrics.chapters} capítulos')),
                Chip(label: Text('${metrics.minutes} min estimados')),
                Chip(label: Text('${metrics.library} obras na biblioteca')),
                Chip(label: Text('${metrics.reading} lendo')),
                Chip(label: Text('${metrics.completed} concluídas')),
                Chip(label: Text('${metrics.favorites} favoritas')),
              ],
            ),
            const SizedBox(height: 14),
            Text('Últimos 30 dias', style: theme.textTheme.titleSmall),
            Text(
              '${metrics.monthlyChapters} capítulos · ${metrics.monthlyMinutes} min estimados · ${metrics.streak} dias seguidos',
            ),
            if (metrics.genres.isNotEmpty) Text(metrics.genres.join(' · ')),
            if (metrics.top.isNotEmpty) const Text('Obras mais lidas'),
            for (final item in metrics.top)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _ReadingCover(manga: item.key, width: 35, height: 48),
                title: Text(
                  item.key.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${item.value} cap.'),
              ),
            const SizedBox(height: 8),
            Text(
              'Estimativa de 20 segundos por página ou 5 minutos por capítulo sem número de páginas.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _MonthlyPreview(
                    metrics: metrics,
                    profile: profile,
                    accent: accent,
                  ),
                ),
              ),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Compartilhar Resumo Mensal'),
            ),
          ],
        ),
      ),
    );
  }
}

ImageProvider? _coverProvider(Manga manga) {
  final url = manga.getCoverUrl();
  return url.isEmpty ? null : NetworkImage(url, headers: manga.customHeaders);
}

class _ReadingCover extends StatelessWidget {
  const _ReadingCover({
    required this.manga,
    required this.width,
    required this.height,
    this.useImage = true,
  });
  final Manga manga;
  final double width, height;
  final bool useImage;

  @override
  Widget build(BuildContext context) {
    final provider = useImage ? _coverProvider(manga) : null;
    final fallback = SizedBox(
      width: width,
      height: height,
      child: const ColoredBox(
        color: Color(0xff2b253c),
        child: Icon(
          Icons.auto_stories_outlined,
          size: 16,
          color: Colors.white70,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: provider == null
          ? fallback
          : Image(
              image: provider,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _MonthlyPreview extends StatefulWidget {
  const _MonthlyPreview({
    required this.metrics,
    required this.profile,
    required this.accent,
  });
  final ReaderMetrics metrics;
  final UserProfile profile;
  final Color accent;

  @override
  State<_MonthlyPreview> createState() => _MonthlyPreviewState();
}

class _MonthlyPreviewState extends State<_MonthlyPreview> {
  final _card = GlobalKey();
  final _share = GlobalKey();
  final _loaded = <String>{};
  bool _story = true, _busy = false, _ready = false, _hasAvatar = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadImages();
    });
  }

  Future<void> _loadImages() async {
    Future<bool> load(ImageProvider? provider) async {
      if (provider == null) return false;
      var failed = false;
      try {
        await precacheImage(
          provider,
          context,
          onError: (_, _) {
            failed = true;
          },
        ).timeout(const Duration(seconds: 4));
        return !failed;
      } catch (_) {
        return false;
      }
    }

    await Future.wait([
      if (!widget.profile.useBlobatarAsAvatar)
        load(
          ProfilePaletteService.resolveImageProvider(
            widget.profile.avatarImagePath,
          ),
        ).then((ok) => _hasAvatar = ok),
      for (final item in widget.metrics.top)
        load(_coverProvider(item.key)).then((ok) {
          if (ok) _loaded.add(item.key.id);
        }),
    ]);
    if (mounted) setState(() => _ready = true);
  }

  Future<Uint8List> _export() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) throw StateError('Prévia fechada');
    final boundary =
        _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('PNG indisponível');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  Future<void> _send({required bool share}) async {
    setState(() => _busy = true);
    try {
      final bytes = await _export();
      if (!mounted) return;
      final name = _story ? 'yomi-resumo-stories.png' : 'yomi-resumo-feed.png';
      if (share) {
        final anchor = _share.currentContext?.findRenderObject() as RenderBox?;
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes, mimeType: 'image/png')],
            fileNameOverrides: [name],
            sharePositionOrigin: anchor == null
                ? null
                : anchor.localToGlobal(Offset.zero) & anchor.size,
          ),
        );
        if (result.status == ShareResultStatus.unavailable) {
          await FilePicker.saveFile(
            fileName: name,
            bytes: bytes,
            mimeType: 'image/png',
          );
        }
      } else {
        await FilePicker.saveFile(
          fileName: name,
          bytes: bytes,
          mimeType: 'image/png',
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Não foi possível exportar o resumo. Tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Resumo Mensal')),
    body: SafeArea(
      child: Column(
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Stories 9:16')),
              ButtonSegment(value: false, label: Text('Feed 1:1')),
            ],
            selected: {_story},
            onSelectionChanged: _busy
                ? null
                : (selection) => setState(() => _story = selection.single),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: !_ready
                  ? const Center(child: CircularProgressIndicator())
                  : FittedBox(
                      fit: BoxFit.contain,
                      child: RepaintBoundary(key: _card, child: _buildCard()),
                    ),
            ),
          ),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton(
                onPressed: !_ready || _busy ? null : () => _send(share: false),
                child: const Text('Baixar PNG'),
              ),
              FilledButton(
                key: _share,
                onPressed: !_ready || _busy ? null : () => _send(share: true),
                child: const Text('Compartilhar imagem'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  Widget _buildCard() {
    final metrics = widget.metrics;
    final profile = widget.profile;
    final savedHue = profile.blobatarHue;
    final cardHue = savedHue == null ? profile.seedHue : savedHue < 0 ? HSLColor.fromColor(widget.accent).hue : savedHue % 360;
    Widget label(
      String text,
      double size, {
      bool bold = false,
      int lines = 1,
    }) => Text(
      text,
      maxLines: lines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: size,
        height: 1.2,
        color: Colors.white,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      ),
    );
    Widget metric(int number, String title) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [label('$number', 23, bold: true), label(title, 10)],
      ),
    );
    return MediaQuery(
      data: const MediaQueryData(),
      child: Container(
        width: 360,
        height: _story ? 640 : 360,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xff111124),
              Color.lerp(const Color(0xff141323), HSLColor.fromAHSL(1, cardHue, .65, .65).toColor(), .38)!,
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 17, 20, 14),
        child: Stack(
          children: [
            Positioned(
              top: _story ? 46 : -2,
              right: _story ? 0 : -3,
              child: YomiProfileBlobatar(
                profile: profile,
                size: _story ? 162 : 105,
                adaptiveHue: HSLColor.fromColor(widget.accent).hue,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label('YOMI READER', 10, bold: true),
                const SizedBox(height: 9),
                label('Resumo de leitura', 23, bold: true),
                label('Últimos 30 dias', 11),
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (_hasAvatar)
                      YomiProfileAvatarView(profile: profile, size: 28)
                    else if (profile.useBlobatarAsAvatar)
                      YomiProfileBlobatar(
                        profile: profile,
                        size: 28,
                        adaptiveHue: HSLColor.fromColor(widget.accent).hue,
                      )
                    else
                      const Icon(
                        Icons.account_circle_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    const SizedBox(width: 7),
                    SizedBox(
                      width: 173,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          label(
                            profile.name.trim().isEmpty
                                ? 'Leitor Yomi'
                                : profile.name,
                            13,
                            bold: true,
                          ),
                          label(metrics.rank, 9),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: _story ? 102 : 12),
                Row(
                  children: [
                    metric(metrics.monthlyChapters, 'Capítulos'),
                    metric(metrics.monthlyMinutes, 'Minutos estimados'),
                    metric(metrics.streak, 'Dias seguidos'),
                  ],
                ),
                const SizedBox(height: 13),
                label(
                  metrics.genres.isEmpty
                      ? 'Sem gêneros registrados'
                      : metrics.genres.join(' · '),
                  12,
                ),
                const SizedBox(height: 9),
                label('Mais lidas', 14, bold: true),
                const SizedBox(height: 7),
                if (metrics.top.isEmpty)
                  label('Sem capítulos com obra identificada no período.', 11),
                if (metrics.top.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in metrics.top)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ReadingCover(
                                  manga: item.key,
                                  width: _story ? 98 : 38,
                                  height: _story ? 135 : 49,
                                  useImage: _loaded.contains(item.key.id),
                                ),
                                const SizedBox(height: 5),
                                label(item.key.title, 11, bold: true),
                                label('${item.value} cap.', 10),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                const Spacer(),
                label('yomi-reader.vercel.app', 10, bold: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
