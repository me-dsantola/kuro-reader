import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/manga_models.dart';
import '../services/profile_palette_service.dart';
import 'yomi_brand_widgets.dart';

/// Escala consistente de espaçamentos em múltiplos de 4/8 dp para a tela de detalhes.
abstract final class YomiDetailSpacing {
  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 20.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
}

class _HeaderContrastIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color iconColor;
  final VoidCallback onPressed;

  const _HeaderContrastIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.56),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.16),
          ),
        ),
        child: IconButton(
          tooltip: tooltip,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: const EdgeInsets.all(8),
          icon: Icon(icon, color: iconColor, size: 22),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// Cabeçalho responsivo com imagem de fundo, gradientes de contraste, capa e título sem cortes.
class MangaDetailHeaderSliver extends StatelessWidget {
  final Manga manga;
  final String heroTag;
  final ProfileAdaptivePalette palette;
  final String sourceLabel;
  final bool hasZeroChaptersEverywhere;
  final bool showDownloadAction;
  final bool isFavorite;
  final VoidCallback onDownloadAll;
  final VoidCallback onAddToList;
  final VoidCallback onToggleFavorite;

  static const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  const MangaDetailHeaderSliver({
    super.key,
    required this.manga,
    required this.heroTag,
    required this.palette,
    required this.sourceLabel,
    required this.hasZeroChaptersEverywhere,
    required this.showDownloadAction,
    required this.isFavorite,
    required this.onDownloadAll,
    required this.onAddToList,
    required this.onToggleFavorite,
  });

  double _measureTextHeight({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required TextScaler textScaler,
    int? maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: maxLines,
    )..layout(maxWidth: math.max(40.0, maxWidth));
    return painter.height;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final screenHeight = media.size.height;
    final topPadding = media.padding.top;
    final horizontalSafeInset = math.max(media.padding.left, media.padding.right);
    final isLandscape =
        media.orientation == Orientation.landscape || screenHeight < 500;
    final isCompactWidth = screenWidth < 360;

    final double coverWidth = isCompactWidth ? 96.0 : (isLandscape ? 104.0 : 112.0);
    final double coverHeight =
        isCompactWidth ? 136.0 : (isLandscape ? 140.0 : 164.0);
    final double horizontalGap =
        isCompactWidth ? YomiDetailSpacing.sm : YomiDetailSpacing.md;
    final double sideMargin = YomiDetailSpacing.md + horizontalSafeInset;
    final double titleFontSize = isCompactWidth ? 18.0 : 20.0;
    final int maxTitleLines = isLandscape ? 4 : 7;

    final titleStyle = TextStyle(
      fontSize: titleFontSize,
      fontWeight: FontWeight.w800,
      height: 1.22,
      color: Colors.white,
    );
    const badgeStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      height: 1.2,
    );

    final double textColumnWidth = math.max(
      120.0,
      screenWidth - (sideMargin * 2) - coverWidth - horizontalGap,
    );
    final double sourceBadgeHeight =
        _measureTextHeight(
          text: sourceLabel,
          style: badgeStyle,
          maxWidth: textColumnWidth - 16,
          textScaler: media.textScaler,
        ) +
        10.0;
    final double extraZeroBadgeHeight = hasZeroChaptersEverywhere
        ? (_measureTextHeight(
                text: '0 CAPÍTULOS',
                style: badgeStyle,
                maxWidth: textColumnWidth - 16,
                textScaler: media.textScaler,
              ) +
              14.0)
        : 0.0;
    final double titleHeight = _measureTextHeight(
      text: manga.title,
      style: titleStyle,
      maxWidth: textColumnWidth,
      textScaler: media.textScaler,
      maxLines: maxTitleLines,
    );

    final double textBlockHeight =
        sourceBadgeHeight +
        extraZeroBadgeHeight +
        YomiDetailSpacing.xs +
        titleHeight;
    final double heroContentHeight = math.max(coverHeight, textBlockHeight);
    final double minExpandedHeight = isLandscape ? 236.0 : 288.0;
    final double expandedHeight = math.max(
      minExpandedHeight,
      topPadding +
          kToolbarHeight +
          YomiDetailSpacing.md +
          heroContentHeight +
          YomiDetailSpacing.md,
    );

    Widget coverThumb = YomiCoverImage(
      manga: manga,
      highRes: true,
      width: coverWidth,
      height: coverHeight,
    );
    if (hasZeroChaptersEverywhere) {
      coverThumb = ColorFiltered(
        colorFilter: _grayscaleFilter,
        child: coverThumb,
      );
    }

    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: true,
      backgroundColor: palette.bannerDark,
      automaticallyImplyLeading: false,
      leadingWidth: 64,
      leading: Padding(
        padding: const EdgeInsets.only(left: YomiDetailSpacing.sm),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _HeaderContrastIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Voltar',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
      actions: [
        if (showDownloadAction) ...[
          _HeaderContrastIconButton(
            icon: Icons.downloading_rounded,
            tooltip: 'Baixar mangá inteiro para ler offline',
            iconColor: palette.secondary,
            onPressed: onDownloadAll,
          ),
          const SizedBox(width: YomiDetailSpacing.xs),
        ],
        _HeaderContrastIconButton(
          icon: Icons.playlist_add_rounded,
          tooltip: 'Adicionar à lista de leitura',
          onPressed: onAddToList,
        ),
        const SizedBox(width: YomiDetailSpacing.xs),
        _HeaderContrastIconButton(
          icon: isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          tooltip:
              isFavorite ? 'Remover dos favoritos' : 'Adicionar aos favoritos',
          iconColor: isFavorite ? palette.primary : Colors.white,
          onPressed: onToggleFavorite,
        ),
        const SizedBox(width: YomiDetailSpacing.sm),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            YomiCoverImage(manga: manga, highRes: true),
            ColoredBox(color: palette.bannerDark.withValues(alpha: 0.58)),
            // Scrim superior garante contraste dos botões mesmo em capas claras.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topPadding + kToolbarHeight + YomiDetailSpacing.xl,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.72),
                      Colors.black.withValues(alpha: 0.28),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    YomiPalette.pitchBlack,
                    palette.bannerDark.withValues(alpha: 0.68),
                    Colors.black.withValues(alpha: 0.14),
                  ],
                  stops: const [0.0, 0.56, 1.0],
                ),
              ),
            ),
            Positioned(
              bottom: YomiDetailSpacing.md,
              left: sideMargin,
              right: sideMargin,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Hero(
                    tag: heroTag,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: palette.primary.withValues(alpha: 0.45),
                          width: 1.4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: palette.primary.withValues(alpha: 0.28),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: coverThumb,
                      ),
                    ),
                  ),
                  SizedBox(width: horizontalGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          spacing: YomiDetailSpacing.xs,
                          runSpacing: YomiDetailSpacing.xxs,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: YomiDetailSpacing.xs,
                                vertical: YomiDetailSpacing.xxs,
                              ),
                              decoration: BoxDecoration(
                                color: palette.primary.withValues(alpha: 0.24),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: palette.primary),
                              ),
                              child: Text(
                                sourceLabel,
                                softWrap: true,
                                style: badgeStyle.copyWith(color: palette.soft),
                              ),
                            ),
                            if (hasZeroChaptersEverywhere)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: YomiDetailSpacing.xs,
                                  vertical: YomiDetailSpacing.xxs,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.48),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: Text(
                                  '0 CAPÍTULOS',
                                  style: badgeStyle.copyWith(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: YomiDetailSpacing.xs),
                        Text(
                          manga.title,
                          maxLines: maxTitleLines,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seletor inteligente de fontes com layout responsivo e expansão vertical automática.
class SmartSourceSelectorCard extends StatelessWidget {
  final Map<MangaSourceType, List<Chapter>> chaptersBySource;
  final MangaSourceType selectedSource;
  final MangaSourceType? recommendedMostCompleteSource;
  final ProfileAdaptivePalette palette;
  final ValueChanged<MangaSourceType> onSelectSource;

  const SmartSourceSelectorCard({
    super.key,
    required this.chaptersBySource,
    required this.selectedSource,
    required this.recommendedMostCompleteSource,
    required this.palette,
    required this.onSelectSource,
  });

  @override
  Widget build(BuildContext context) {
    final entries = chaptersBySource.entries.toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(YomiDetailSpacing.sm),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: palette.primary,
                ),
              ),
              const SizedBox(width: YomiDetailSpacing.xs),
              Expanded(
                child: Text(
                  'Seletor Inteligente de Fonte',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: palette.soft,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: YomiDetailSpacing.xs),
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale =
                  MediaQuery.textScalerOf(context).scale(14.0) / 14.0;
              final canUseTwoColumns =
                  entries.length >= 2 &&
                  constraints.maxWidth >= 276 &&
                  textScale <= 1.35;

              if (!canUseTwoColumns) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < entries.length; i++) ...[
                      if (i > 0) const SizedBox(height: YomiDetailSpacing.xs),
                      _SourceOptionButton(
                        source: entries[i].key,
                        chapterCount: entries[i].value.length,
                        isSelected: entries[i].key == selectedSource,
                        isBest:
                            entries[i].key == recommendedMostCompleteSource &&
                            entries[i].value.isNotEmpty,
                        palette: palette,
                        onTap: () => onSelectSource(entries[i].key),
                      ),
                    ],
                  ],
                );
              }

              final rows = <Widget>[];
              for (var i = 0; i < entries.length; i += 2) {
                final first = entries[i];
                final second = i + 1 < entries.length ? entries[i + 1] : null;
                if (i > 0) {
                  rows.add(const SizedBox(height: YomiDetailSpacing.xs));
                }
                rows.add(
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _SourceOptionButton(
                            source: first.key,
                            chapterCount: first.value.length,
                            isSelected: first.key == selectedSource,
                            isBest:
                                first.key == recommendedMostCompleteSource &&
                                first.value.isNotEmpty,
                            palette: palette,
                            onTap: () => onSelectSource(first.key),
                          ),
                        ),
                        const SizedBox(width: YomiDetailSpacing.xs),
                        if (second != null)
                          Expanded(
                            child: _SourceOptionButton(
                              source: second.key,
                              chapterCount: second.value.length,
                              isSelected: second.key == selectedSource,
                              isBest:
                                  second.key ==
                                      recommendedMostCompleteSource &&
                                  second.value.isNotEmpty,
                              palette: palette,
                              onTap: () => onSelectSource(second.key),
                            ),
                          )
                        else
                          const Spacer(),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SourceOptionButton extends StatelessWidget {
  final MangaSourceType source;
  final int chapterCount;
  final bool isSelected;
  final bool isBest;
  final ProfileAdaptivePalette palette;
  final VoidCallback onTap;

  const _SourceOptionButton({
    required this.source,
    required this.chapterCount,
    required this.isSelected,
    required this.isBest,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${source.badge} com $chapterCount capítulos',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: YomiDetailSpacing.sm,
              vertical: YomiDetailSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? palette.primary.withValues(alpha: 0.22)
                  : YomiPalette.pitchBlack.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? palette.primary
                    : Colors.white.withValues(alpha: 0.14),
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: isSelected ? palette.primary : Colors.white38,
                    ),
                    const SizedBox(width: YomiDetailSpacing.xs),
                    Expanded(
                      child: Text(
                        '${source.badge}: $chapterCount caps',
                        softWrap: true,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isBest) ...[
                  const SizedBox(height: YomiDetailSpacing.xxs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: palette.primary.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      'Mais completa',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: palette.soft,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra unificada de ações de leitura e download com estados visuais claros.
class MangaActionButtonsBar extends StatelessWidget {
  final ProfileAdaptivePalette palette;
  final Chapter? lastChapter;
  final List<Chapter> filteredChapters;
  final bool loadingChapters;
  final bool chapterLoadError;
  final bool hasZeroChaptersEverywhere;
  final ({int completed, int total})? activeBatchDownload;
  final String? batchDownloadError;
  final int downloadedCount;
  final int uniqueDownloadCount;
  final VoidCallback onStartReading;
  final VoidCallback onContinueLastChapter;
  final VoidCallback onRetryLoad;
  final VoidCallback onDownloadEntireManga;

  const MangaActionButtonsBar({
    super.key,
    required this.palette,
    required this.lastChapter,
    required this.filteredChapters,
    required this.loadingChapters,
    required this.chapterLoadError,
    required this.hasZeroChaptersEverywhere,
    required this.activeBatchDownload,
    required this.batchDownloadError,
    required this.downloadedCount,
    required this.uniqueDownloadCount,
    required this.onStartReading,
    required this.onContinueLastChapter,
    required this.onRetryLoad,
    required this.onDownloadEntireManga,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasReadableChapters = filteredChapters.isNotEmpty;
    final bool allDownloaded =
        uniqueDownloadCount > 0 && downloadedCount >= uniqueDownloadCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildReadButton(hasReadableChapters),
        if (hasReadableChapters || !loadingChapters) ...[
          const SizedBox(height: YomiDetailSpacing.xs),
          _buildDownloadSection(
            hasReadableChapters: hasReadableChapters,
            allDownloaded: allDownloaded,
          ),
        ],
      ],
    );
  }

  Widget _buildReadButton(bool hasReadableChapters) {
    if (lastChapter != null) {
      return _DetailActionButton(
        filled: true,
        backgroundColor: palette.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.play_arrow_rounded, size: 22),
        label:
            'Continuar Cap. ${lastChapter!.chapterNumber} (${lastChapter!.language})',
        onPressed: onContinueLastChapter,
      );
    }

    if (loadingChapters) {
      return _DetailActionButton(
        filled: true,
        backgroundColor: palette.surface,
        disabledBackgroundColor: palette.surface.withValues(alpha: 0.72),
        foregroundColor: Colors.white70,
        disabledForegroundColor: Colors.white70,
        icon: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: palette.primary,
          ),
        ),
        label: 'Carregando capítulos...',
        onPressed: null,
      );
    }

    if (hasReadableChapters) {
      return _DetailActionButton(
        filled: true,
        backgroundColor: palette.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.menu_book_rounded, size: 20),
        label: 'Começar a ler',
        onPressed: onStartReading,
      );
    }

    if (chapterLoadError) {
      return _DetailActionButton(
        filled: true,
        backgroundColor: const Color(0xFF3A151D),
        foregroundColor: Colors.white,
        borderColor: Colors.redAccent.withValues(alpha: 0.65),
        icon: const Icon(Icons.refresh_rounded, size: 20),
        label: 'Erro ao carregar — Tentar novamente',
        onPressed: onRetryLoad,
      );
    }

    return _DetailActionButton(
      filled: true,
      backgroundColor: palette.surface,
      disabledBackgroundColor: palette.surface.withValues(alpha: 0.65),
      foregroundColor: Colors.white54,
      disabledForegroundColor: Colors.white54,
      borderColor: Colors.white.withValues(alpha: 0.12),
      icon: Icon(
        hasZeroChaptersEverywhere
            ? Icons.block_rounded
            : Icons.translate_rounded,
        size: 18,
      ),
      label: hasZeroChaptersEverywhere
          ? 'Leitura indisponível (0 capítulos)'
          : 'Nenhum capítulo no idioma selecionado',
      onPressed: null,
    );
  }

  Widget _buildDownloadSection({
    required bool hasReadableChapters,
    required bool allDownloaded,
  }) {
    final batch = activeBatchDownload;
    if (batch != null) {
      final progress = batch.total > 0 ? batch.completed / batch.total : 0.0;
      return Container(
        padding: const EdgeInsets.all(YomiDetailSpacing.sm),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.primary.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.primary,
                  ),
                ),
                const SizedBox(width: YomiDetailSpacing.sm),
                Expanded(
                  child: Text(
                    'Baixando obra inteira: ${batch.completed} de ${batch.total} capítulos...',
                    softWrap: true,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: palette.soft,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: YomiDetailSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.clamp(0.02, 1.0),
                minHeight: 6,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(palette.primary),
              ),
            ),
          ],
        ),
      );
    }

    if (!hasReadableChapters) {
      return _DetailActionButton(
        filled: false,
        backgroundColor: palette.surface.withValues(alpha: 0.45),
        disabledBackgroundColor: palette.surface.withValues(alpha: 0.45),
        foregroundColor: Colors.white54,
        disabledForegroundColor: Colors.white54,
        borderColor: Colors.white.withValues(alpha: 0.12),
        icon: Icon(
          chapterLoadError
              ? Icons.cloud_off_rounded
              : Icons.file_download_off_rounded,
          size: 18,
        ),
        label: chapterLoadError
            ? 'Download indisponível no momento'
            : hasZeroChaptersEverywhere
            ? 'Download indisponível (0 capítulos)'
            : 'Nenhum capítulo disponível neste idioma',
        onPressed: null,
      );
    }

    if (allDownloaded) {
      return _DetailActionButton(
        filled: false,
        backgroundColor: palette.surface.withValues(alpha: 0.72),
        disabledBackgroundColor: palette.surface.withValues(alpha: 0.72),
        foregroundColor: palette.soft,
        disabledForegroundColor: palette.soft.withValues(alpha: 0.88),
        borderColor: palette.secondary.withValues(alpha: 0.45),
        icon: Icon(Icons.offline_pin_rounded, color: palette.secondary, size: 20),
        label:
            'Obra inteira baixada na Biblioteca ($downloadedCount caps)',
        onPressed: null,
      );
    }

    if (batchDownloadError != null) {
      return _DetailActionButton(
        filled: false,
        backgroundColor: const Color(0xFF281217),
        foregroundColor: Colors.white,
        borderColor: Colors.redAccent.withValues(alpha: 0.65),
        icon: const Icon(
          Icons.error_outline_rounded,
          color: Colors.redAccent,
          size: 20,
        ),
        label: downloadedCount > 0
            ? 'Erro ao baixar — Tentar novamente ($downloadedCount/$uniqueDownloadCount)'
            : 'Erro no download — Tentar novamente ($uniqueDownloadCount caps)',
        onPressed: onDownloadEntireManga,
      );
    }

    return _DetailActionButton(
      filled: false,
      backgroundColor: palette.surface.withValues(alpha: 0.75),
      foregroundColor: palette.soft,
      borderColor: palette.primary.withValues(alpha: 0.45),
      icon: Icon(
        Icons.downloading_rounded,
        color: palette.primary,
        size: 20,
      ),
      label: downloadedCount > 0
          ? 'Baixar mangá inteiro ($downloadedCount/$uniqueDownloadCount baixados)'
          : 'Baixar mangá inteiro ($uniqueDownloadCount caps)',
      onPressed: onDownloadEntireManga,
    );
  }
}

class _DetailActionButton extends StatelessWidget {
  final bool filled;
  final Color backgroundColor;
  final Color? disabledBackgroundColor;
  final Color foregroundColor;
  final Color? disabledForegroundColor;
  final Color? borderColor;
  final Widget icon;
  final String label;
  final VoidCallback? onPressed;

  const _DetailActionButton({
    required this.filled,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        icon,
        const SizedBox(width: YomiDetailSpacing.xs),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            softWrap: true,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
      ],
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    const minSize = Size(double.infinity, 50);
    const padding = EdgeInsets.symmetric(
      horizontal: YomiDetailSpacing.md,
      vertical: YomiDetailSpacing.sm,
    );

    return SizedBox(
      width: double.infinity,
      child: filled
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: backgroundColor,
                disabledBackgroundColor: disabledBackgroundColor,
                foregroundColor: foregroundColor,
                disabledForegroundColor: disabledForegroundColor,
                minimumSize: minSize,
                padding: padding,
                shape: shape,
                side: borderColor != null
                    ? BorderSide(color: borderColor!)
                    : null,
              ),
              child: content,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                backgroundColor: backgroundColor,
                disabledBackgroundColor: disabledBackgroundColor,
                foregroundColor: foregroundColor,
                disabledForegroundColor: disabledForegroundColor,
                minimumSize: minSize,
                padding: padding,
                shape: shape,
                side: BorderSide(
                  color: borderColor ?? Colors.white24,
                ),
              ),
              child: content,
            ),
    );
  }
}

/// Chips uniformes de gêneros com quebra automática e espaçamento consistente.
class MangaGenresWrap extends StatelessWidget {
  final List<String> tags;
  final ProfileAdaptivePalette palette;

  const MangaGenresWrap({
    super.key,
    required this.tags,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: YomiDetailSpacing.xs,
      runSpacing: YomiDetailSpacing.xs,
      children: tags.map((tag) {
        return Container(
          constraints: const BoxConstraints(minHeight: 30),
          padding: const EdgeInsets.symmetric(
            horizontal: YomiDetailSpacing.sm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: palette.primary.withValues(alpha: 0.24),
            ),
          ),
          child: Text(
            tag,
            softWrap: true,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.2,
              color: palette.soft,
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Seção de sinopse com preferência por português, alternância para original e expansão suave.
class MangaSynopsisSection extends StatefulWidget {
  final Manga manga;
  final ProfileAdaptivePalette palette;
  final Future<String?> Function(String text)? synopsisTranslator;

  const MangaSynopsisSection({
    super.key,
    required this.manga,
    required this.palette,
    this.synopsisTranslator,
  });

  @override
  State<MangaSynopsisSection> createState() => _MangaSynopsisSectionState();
}

class _MangaSynopsisSectionState extends State<MangaSynopsisSection> {
  bool _expanded = false;
  bool _showOriginal = false;
  String? _translatedSynopsis;
  bool _translating = false;

  @override
  void didUpdateWidget(covariant MangaSynopsisSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manga.compositeId != widget.manga.compositeId ||
        oldWidget.manga.description != widget.manga.description) {
      _expanded = false;
      _showOriginal = false;
      _translatedSynopsis = null;
      _translating = false;
    }
  }

  Future<void> _toggleLanguageOrTranslate() async {
    final pt = widget.manga.portugueseDescription;
    final orig = widget.manga.originalLanguageDescription;

    if ((pt != null && orig != null) || _translatedSynopsis != null) {
      setState(() => _showOriginal = !_showOriginal);
      return;
    }

    final translator = widget.synopsisTranslator;
    if (translator == null || _translating) return;

    setState(() => _translating = true);
    try {
      final result = await translator(widget.manga.description);
      if (!mounted) return;
      final clean = result?.trim();
      setState(() {
        _translating = false;
        if (clean != null && clean.isNotEmpty) {
          _translatedSynopsis = clean;
          _showOriginal = false;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _translating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ptText = widget.manga.portugueseDescription;
    final origText = widget.manga.originalLanguageDescription;
    final bool hasAltToggle =
        (ptText != null && origText != null && ptText.trim() != origText.trim()) ||
        _translatedSynopsis != null ||
        (widget.synopsisTranslator != null && ptText == null);

    final String activeText;
    if (_showOriginal) {
      activeText = origText ?? widget.manga.description;
    } else {
      activeText =
          ptText ?? _translatedSynopsis ?? widget.manga.preferredDescription;
    }

    final String toggleLabel;
    if (_translating) {
      toggleLabel = 'Traduzindo...';
    } else if ((ptText == null && _translatedSynopsis == null) &&
        widget.synopsisTranslator != null) {
      toggleLabel = 'Traduzir';
    } else {
      toggleLabel = _showOriginal ? 'Ver em português' : 'Ver original';
    }

    final textStyle = TextStyle(
      fontSize: 13.5,
      height: 1.48,
      color: Colors.white.withValues(alpha: 0.78),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasAltToggle) ...[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: YomiDetailSpacing.xs,
            runSpacing: YomiDetailSpacing.xs,
            children: [
              const Text(
                'Sinopse',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              InkWell(
                onTap: _translating ? null : _toggleLanguageOrTranslate,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: YomiDetailSpacing.sm,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: widget.palette.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: widget.palette.primary.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.translate_rounded,
                        size: 14,
                        color: widget.palette.secondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        toggleLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: widget.palette.soft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: YomiDetailSpacing.xs),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(text: activeText, style: textStyle),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 4,
            )..layout(maxWidth: math.max(80.0, constraints.maxWidth));
            final canExpand = painter.didExceedMaxLines || _expanded;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topLeft,
                  child: Text(
                    activeText,
                    maxLines: _expanded ? null : 4,
                    overflow: _expanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: textStyle,
                  ),
                ),
                if (canExpand) ...[
                  const SizedBox(height: YomiDetailSpacing.xxs),
                  InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: YomiDetailSpacing.xxs,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _expanded ? 'Ver menos' : 'Ver mais',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: widget.palette.secondary,
                            ),
                          ),
                          const SizedBox(width: YomiDetailSpacing.xxs),
                          Icon(
                            _expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 18,
                            color: widget.palette.secondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Cabeçalho da lista de capítulos em duas linhas independentes e seletor de idiomas proporcional.
class MangaChaptersHeader extends StatelessWidget {
  final int chapterCount;
  final bool sortAscending;
  final String selectedLanguage;
  final List<String> availableLanguages;
  final ProfileAdaptivePalette palette;
  final VoidCallback onToggleSort;
  final ValueChanged<String> onSelectLanguage;

  const MangaChaptersHeader({
    super.key,
    required this.chapterCount,
    required this.sortAscending,
    required this.selectedLanguage,
    required this.availableLanguages,
    required this.palette,
    required this.onToggleSort,
    required this.onSelectLanguage,
  });

  List<({String value, String label})> _buildLanguageOptions() {
    final options = <({String value, String label})>[
      (value: 'TODOS', label: 'Todos'),
      (value: 'PT-BR', label: 'PT'),
      (value: 'EN', label: 'EN'),
      (value: 'ES', label: 'ES'),
    ];
    final knownPrefixes = {'TODOS', 'PT', 'EN', 'ES'};
    final extras = <String>{};
    for (final raw in availableLanguages) {
      final norm = raw.trim().toUpperCase();
      if (norm.isEmpty) continue;
      final isBase =
          norm.startsWith('PT') || norm.startsWith('EN') || norm.startsWith('ES');
      if (!isBase && !knownPrefixes.contains(norm) && extras.add(norm)) {
        options.add((value: norm, label: norm));
      }
    }
    if (selectedLanguage != 'TODOS' &&
        !options.any((opt) => opt.value == selectedLanguage)) {
      options.add((value: selectedLanguage, label: selectedLanguage));
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final languageOptions = _buildLanguageOptions();
    final isCompactWidth = MediaQuery.sizeOf(context).width < 360;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  'Capítulos ($chapterCount)',
                  softWrap: true,
                  style: TextStyle(
                    fontSize: isCompactWidth ? 17 : 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: YomiDetailSpacing.xs),
            Container(
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: palette.primary.withValues(alpha: 0.28),
                ),
              ),
              child: IconButton(
                tooltip: sortAscending
                    ? 'Ordenando: Cap. 1 → Recente'
                    : 'Ordenando: Recente → Cap. 1',
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(
                  sortAscending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: palette.secondary,
                  size: 20,
                ),
                onPressed: onToggleSort,
              ),
            ),
          ],
        ),
        const SizedBox(height: YomiDetailSpacing.sm),
        Container(
          padding: const EdgeInsets.all(YomiDetailSpacing.xxs),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale =
                  MediaQuery.textScalerOf(context).scale(13.0) / 13.0;
              final minOptionWidth = 54.0 * textScale.clamp(1.0, 2.0);
              final fitsSingleRow =
                  languageOptions.length <= 4 &&
                  constraints.maxWidth >=
                      languageOptions.length * minOptionWidth;

              if (fitsSingleRow) {
                return Row(
                  children: [
                    for (var i = 0; i < languageOptions.length; i++) ...[
                      if (i > 0) const SizedBox(width: YomiDetailSpacing.xxs),
                      Expanded(
                        child: _LanguageOptionPill(
                          label: languageOptions[i].label,
                          selected:
                              selectedLanguage == languageOptions[i].value,
                          palette: palette,
                          onTap: () =>
                              onSelectLanguage(languageOptions[i].value),
                        ),
                      ),
                    ],
                  ],
                );
              }

              final columns = (constraints.maxWidth / minOptionWidth)
                  .floor()
                  .clamp(2, languageOptions.length);
              final rows = <Widget>[];
              for (var i = 0; i < languageOptions.length; i += columns) {
                if (i > 0) {
                  rows.add(const SizedBox(height: YomiDetailSpacing.xxs));
                }
                final slice = languageOptions.sublist(
                  i,
                  math.min(i + columns, languageOptions.length),
                );
                rows.add(
                  Row(
                    children: [
                      for (var j = 0; j < columns; j++) ...[
                        if (j > 0)
                          const SizedBox(width: YomiDetailSpacing.xxs),
                        Expanded(
                          child: j < slice.length
                              ? _LanguageOptionPill(
                                  label: slice[j].label,
                                  selected: selectedLanguage == slice[j].value,
                                  palette: palette,
                                  onTap: () =>
                                      onSelectLanguage(slice[j].value),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LanguageOptionPill extends StatelessWidget {
  final String label;
  final bool selected;
  final ProfileAdaptivePalette palette;
  final VoidCallback onTap;

  const _LanguageOptionPill({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Idioma $label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 40),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
              horizontal: YomiDetailSpacing.xs,
              vertical: YomiDetailSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? palette.primary.withValues(alpha: 0.28)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected ? palette.primary : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : Colors.white70,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
