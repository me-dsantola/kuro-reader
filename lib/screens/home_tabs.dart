import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/mangadex_service.dart';
import '../services/storage_service.dart';
import '../services/download_manager.dart';
import 'manga_detail_screen.dart';
import 'reader_screen.dart';

// Paleta Oficial YOMI (Preto Obsidiana, Branco, Vermelho Enso/Torii e Rosa Sakura)
class YomiPalette {
  static const Color pitchBlack = Color(0xFF070709);
  static const Color surface = Color(0xFF121217);
  static const Color ensoRed = Color(0xFFE11D48);
  static const Color crimsonGlow = Color(0xFF9F1239);
  static const Color sakuraPink = Color(0xFFF472B6);
  static const Color sakuraSoft = Color(0xFFFBCFE8);
  static const Color pureWhite = Color(0xFFFAFAFA);
}

/// Logotipo tipográfico branco com o "O" vermelho em estilo Enso japonês
class YomiEnsoLogo extends StatelessWidget {
  final double fontSize;
  const YomiEnsoLogo({super.key, this.fontSize = 23});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Y',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            color: YomiPalette.pureWhite,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.5),
          child: CustomPaint(
            size: Size(fontSize * 0.86, fontSize * 0.86),
            painter: _EnsoOPainter(),
          ),
        ),
        Text(
          'MI',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            color: YomiPalette.pureWhite,
          ),
        ),
      ],
    );
  }
}

class _EnsoOPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = YomiPalette.ensoRed
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.22
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromLTWH(2, 2, size.width - 4, size.height - 4);
    canvas.drawArc(rect, -0.55, 5.25, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Banner Horizontal YOMI com Sol Vermelho, Montanhas, Torii e Pétalas de Sakura
class YomiSakuraBanner extends StatelessWidget {
  const YomiSakuraBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 118,
      width: double.infinity,
      child: CustomPaint(
        painter: _ToriiSakuraBannerPainter(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                YomiPalette.pitchBlack.withOpacity(0.92),
              ],
            ),
          ),
          alignment: Alignment.bottomLeft,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: YomiPalette.ensoRed.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: YomiPalette.ensoRed, width: 1),
                ),
                child: const Text(
                  'MULTI-FONTE ATIVA',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: YomiPalette.sakuraSoft,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'MangaDex + Yomi Adult Vault',
                style: TextStyle(
                  fontSize: 12,
                  color: YomiPalette.pureWhite.withOpacity(0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToriiSakuraBannerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Fundo noturno avermelhado
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1A0810), Color(0xFF070709)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Sol Vermelho Japonês
    final sunCenter = Offset(size.width * 0.78, size.height * 0.48);
    final sunPaint = Paint()..color = YomiPalette.ensoRed.withOpacity(0.85);
    canvas.drawCircle(sunCenter, 34, sunPaint);

    // Silhueta das Montanhas ao fundo
    final mountainPaint = Paint()..color = const Color(0xFF0E0B12);
    final mountainPath = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height * 0.62)
      ..lineTo(size.width * 0.22, size.height * 0.35)
      ..lineTo(size.width * 0.48, size.height * 0.70)
      ..lineTo(size.width * 0.70, size.height * 0.42)
      ..lineTo(size.width, size.height * 0.68)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(mountainPath, mountainPaint);

    // Silhueta minimalista do Torii dentro do Sol Vermelho
    final toriiPaint = Paint()
      ..color = YomiPalette.pitchBlack
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final tx = sunCenter.dx;
    final ty = sunCenter.dy;
    canvas.drawLine(Offset(tx - 18, ty - 10), Offset(tx + 18, ty - 10), toriiPaint);
    canvas.drawLine(Offset(tx - 14, ty - 4), Offset(tx + 14, ty - 4), toriiPaint);
    canvas.drawLine(Offset(tx - 10, ty - 10), Offset(tx - 12, ty + 18), toriiPaint);
    canvas.drawLine(Offset(tx + 10, ty - 10), Offset(tx + 12, ty + 18), toriiPaint);

    // Pétalas de Sakura flutuando
    final sakuraPaint = Paint()..color = YomiPalette.sakuraPink.withOpacity(0.55);
    final petals = [
      Offset(size.width * 0.12, size.height * 0.28),
      Offset(size.width * 0.28, size.height * 0.50),
      Offset(size.width * 0.45, size.height * 0.22),
      Offset(size.width * 0.62, size.height * 0.35),
      Offset(size.width * 0.88, size.height * 0.25),
    ];
    for (final p in petals) {
      canvas.drawOval(Rect.fromCenter(center: p, width: 7, height: 4), sakuraPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================================
// ABA 1: EXPLORAR (ROLL DE LANÇAMENTOS + TAGS +/- + NSFW TOGGLE)
// ============================================================================
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Manga> _mangas = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;

  final Set<CanonicalTag> _includedTags = {};
  final Set<CanonicalTag> _excludedTags = {};
  bool _sortByLatest = true;

  @override
  void initState() {
    super.initState();
    _loadMangas(reset: true);
    _scrollController.addListener(_onScroll);
    StorageService.nsfwModeNotifier.addListener(_onNsfwModeChanged);
  }

  @override
  void dispose() {
    StorageService.nsfwModeNotifier.removeListener(_onNsfwModeChanged);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onNsfwModeChanged() {
    _loadMangas(reset: true);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 450 &&
        !_isLoading &&
        !_isLoadingMore) {
      _loadMoreMangas();
    }
  }

  YomiSearchFilter get _currentFilter => YomiSearchFilter(
        query: _searchController.text,
        includedTags: _includedTags,
        excludedTags: _excludedTags,
        allowNsfw: StorageService.nsfwMode.allowNsfwFetch,
        sortByLatest: _sortByLatest,
      );

  Future<void> _loadMangas({bool reset = true}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await MangaDexService.fetchMergedCatalog(
        filter: _currentFilter,
        reset: reset,
      );
      if (mounted) {
        setState(() {
          _mangas = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreMangas() async {
    setState(() => _isLoadingMore = true);
    try {
      final result = await MangaDexService.fetchMergedCatalog(
        filter: _currentFilter,
        reset: false,
      );
      if (mounted && result.isNotEmpty) {
        setState(() {
          _mangas.addAll(result);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingMore = false);
  }

  void _openTagFilterModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: YomiPalette.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filtros Unificados & Tags',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            _includedTags.clear();
                            _excludedTags.clear();
                          });
                        },
                        child: const Text(
                          'Limpar',
                          style: TextStyle(color: YomiPalette.sakuraPink),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    '1 toque = Incluir (+ Vermelho) • 2 toques = Excluir (- Sakura)',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: CanonicalTag.values.where((tag) {
                      if (!StorageService.nsfwMode.allowNsfwFetch && tag.isNsfwOnly) {
                        return false;
                      }
                      return true;
                    }).map((tag) {
                      final isInc = _includedTags.contains(tag);
                      final isExc = _excludedTags.contains(tag);

                      Color bgColor = YomiPalette.pitchBlack;
                      Color borderColor = Colors.white24;
                      IconData? icon;

                      if (isInc) {
                        bgColor = YomiPalette.ensoRed.withOpacity(0.25);
                        borderColor = YomiPalette.ensoRed;
                        icon = Icons.add_circle_outline;
                      } else if (isExc) {
                        bgColor = YomiPalette.sakuraPink.withOpacity(0.20);
                        borderColor = YomiPalette.sakuraPink;
                        icon = Icons.remove_circle_outline;
                      }

                      return InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          setModalState(() {
                            if (!isInc && !isExc) {
                              _includedTags.add(tag);
                            } else if (isInc) {
                              _includedTags.remove(tag);
                              _excludedTags.add(tag);
                            } else {
                              _excludedTags.remove(tag);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icon != null) ...[
                                Icon(icon, size: 15, color: borderColor),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                tag.label,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  decoration:
                                      isExc ? TextDecoration.lineThrough : null,
                                  color: isExc
                                      ? YomiPalette.sakuraPink
                                      : YomiPalette.pureWhite,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: YomiPalette.ensoRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _loadMangas(reset: true);
                      },
                      icon: const Icon(Icons.done_all_rounded),
                      label: const Text(
                        'Aplicar Filtros nas Duas Fontes',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final latestRoll = _mangas.take(8).toList();

    return Scaffold(
      appBar: AppBar(
        title: const YomiEnsoLogo(),
        actions: [
          // Toggle Ordenação (Recentes vs Populares)
          IconButton(
            tooltip: _sortByLatest ? 'Ordenado por Lançamento' : 'Ordenado por Popularidade',
            icon: Icon(
              _sortByLatest ? Icons.schedule_rounded : Icons.local_fire_department_rounded,
              color: _sortByLatest ? YomiPalette.sakuraPink : YomiPalette.ensoRed,
            ),
            onPressed: () {
              setState(() => _sortByLatest = !_sortByLatest);
              _loadMangas(reset: true);
            },
          ),
          // Botão de Segurança NSFW (Oculto / Sakura Blur / Visível)
          ValueListenableBuilder<NsfwDisplayMode>(
            valueListenable: StorageService.nsfwModeNotifier,
            builder: (context, mode, _) {
              IconData icon = Icons.shield_outlined;
              Color color = Colors.greenAccent;
              if (mode == NsfwDisplayMode.blurred) {
                icon = Icons.blur_on_rounded;
                color = YomiPalette.sakuraPink;
              } else if (mode == NsfwDisplayMode.visible) {
                icon = Icons.explicit_rounded;
                color = YomiPalette.ensoRed;
              }

              return IconButton(
                tooltip: mode.label,
                icon: Icon(icon, color: color),
                onPressed: () async {
                  await StorageService.cycleNsfwMode();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Modo de Conteúdo: ${StorageService.nsfwMode.label}'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _loadMangas(reset: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Pesquisar no MangaDex + Adult Vault...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.38)),
                      prefixIcon: const Icon(Icons.search, color: YomiPalette.ensoRed),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white54),
                              onPressed: () {
                                _searchController.clear();
                                _loadMangas(reset: true);
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: YomiPalette.surface,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Badge(
                  isLabelVisible:
                      _includedTags.isNotEmpty || _excludedTags.isNotEmpty,
                  label: Text('${_includedTags.length + _excludedTags.length}'),
                  backgroundColor: YomiPalette.ensoRed,
                  child: IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: YomiPalette.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _openTagFilterModal,
                    icon: const Icon(Icons.tune_rounded, color: YomiPalette.sakuraPink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: YomiPalette.ensoRed))
          : _error != null && _mangas.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded, size: 48, color: YomiPalette.ensoRed),
                        const SizedBox(height: 12),
                        const Text(
                          'Sem conexão. Acesse sua Biblioteca ou a aba Offline.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _loadMangas(reset: true),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar novamente'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: YomiPalette.ensoRed,
                  onRefresh: () => _loadMangas(reset: true),
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      // Banner Estético Japonês (Torii + Sol Vermelho + Sakura)
                      const SliverToBoxAdapter(child: YomiSakuraBanner()),

                      // Aviso de Fallback Resiliente (se alguma API estiver em 429)
                      SliverToBoxAdapter(
                        child: ValueListenableBuilder<String?>(
                          valueListenable: MangaDexService.sourceStatusBanner,
                          builder: (context, msg, _) {
                            if (msg == null) return const SizedBox.shrink();
                            return Container(
                              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: YomiPalette.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: YomiPalette.sakuraPink.withOpacity(0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.bolt_rounded,
                                    size: 16,
                                    color: YomiPalette.sakuraPink,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      msg,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                      // Roll de Lançamentos Cronológico (Carrossel Horizontal)
                      if (latestRoll.isNotEmpty && _searchController.text.isEmpty) ...[
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                            child: Row(
                              children: [
                                Icon(Icons.new_releases_rounded, size: 18, color: YomiPalette.ensoRed),
                                SizedBox(width: 6),
                                Text(
                                  'Roll de Lançamentos (Tempo Real)',
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 190,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              scrollDirection: Axis.horizontal,
                              itemCount: latestRoll.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 12),
                              itemBuilder: (context, idx) => SizedBox(
                                width: 122,
                                child: MangaGridCard(
                                  manga: latestRoll[idx],
                                  heroPrefix: 'roll',
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(16, 18, 16, 4),
                            child: Text(
                              'Catálogo Unificado',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],

                      // Grade Infinita Mesclada
                      SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.63,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 16,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => MangaGridCard(
                              manga: _mangas[index],
                              heroPrefix: 'explore',
                            ),
                            childCount: _mangas.length,
                          ),
                        ),
                      ),
                      if (_isLoadingMore)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: CircularProgressIndicator(color: YomiPalette.ensoRed),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}

// ============================================================================
// ABA 2: MINHA BIBLIOTECA
// ============================================================================
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bookmarks_rounded, color: YomiPalette.ensoRed),
            SizedBox(width: 10),
            Text('Minha Biblioteca'),
          ],
        ),
      ),
      body: ValueListenableBuilder<NsfwDisplayMode>(
        valueListenable: StorageService.nsfwModeNotifier,
        builder: (context, _, __) {
          return ValueListenableBuilder(
            valueListenable: StorageService.favBox.listenable(),
            builder: (context, Box box, _) {
              final favorites = StorageService.getFavorites();

              if (favorites.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.favorite_border_rounded,
                          size: 64,
                          color: Colors.white.withOpacity(0.2),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Sua biblioteca está vazia',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Toque no coração em qualquer obra do MangaDex ou 18+ para salvá-la aqui.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withOpacity(0.5)),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.63,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                ),
                itemCount: favorites.length,
                itemBuilder: (context, index) => MangaGridCard(
                  manga: favorites[index],
                  heroPrefix: 'lib',
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// ABA 3: CAPÍTULOS OFFLINE
// ============================================================================
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.download_for_offline_rounded, color: YomiPalette.ensoRed),
            SizedBox(width: 10),
            Text('Capítulos Offline'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Apagar todos os downloads',
            icon: const Icon(Icons.delete_sweep_outlined, color: YomiPalette.sakuraPink),
            onPressed: () async {
              await DownloadManager.deleteAllDownloads();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Armazenamento offline limpo!')),
                );
              }
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<NsfwDisplayMode>(
        valueListenable: StorageService.nsfwModeNotifier,
        builder: (context, _, __) {
          return ValueListenableBuilder(
            valueListenable: StorageService.downloadsBox.listenable(),
            builder: (context, Box box, _) {
              final items = StorageService.getAllDownloadedChapters();

              if (items.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 64,
                          color: Colors.white.withOpacity(0.2),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Nenhum capítulo salvo no aparelho',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                itemBuilder: (context, index) {
                  final entry = items[index];
                  final manga = Manga.fromMap(Map<String, dynamic>.from(entry['manga']));
                  final chapter = Chapter.fromMap(Map<String, dynamic>.from(entry['chapter']));
                  final paths = List<String>.from(entry['paths'] ?? []);

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: manga.getCoverUrl(),
                        httpHeaders: manga.customHeaders,
                        width: 48,
                        height: 68,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 48,
                          height: 68,
                          color: YomiPalette.surface,
                          child: const Icon(Icons.book, color: Colors.white38),
                        ),
                      ),
                    ),
                    title: Text(
                      manga.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Cap. ${chapter.chapterNumber} (${chapter.language}) • ${paths.length} págs',
                      style: const TextStyle(color: YomiPalette.sakuraPink, fontSize: 12.5),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.white54),
                      onPressed: () => DownloadManager.deleteChapter(chapter.id),
                    ),
                    onTap: () {
                      StorageService.markChapterAsRead(manga.id, chapter, read: true);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReaderScreen(
                            manga: manga,
                            chapter: chapter,
                            allChapters: [chapter],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// CARD UNIFICADO COM BADGE DE FONTE (MDX / 18+) E SAKURA BLUR
// ============================================================================
class MangaGridCard extends StatefulWidget {
  final Manga manga;
  final String heroPrefix;

  const MangaGridCard({
    super.key,
    required this.manga,
    required this.heroPrefix,
  });

  @override
  State<MangaGridCard> createState() => _MangaGridCardState();
}

class _MangaGridCardState extends State<MangaGridCard> {
  bool _peekUnblurred = false;

  @override
  Widget build(BuildContext context) {
    final heroTag = '${widget.heroPrefix}_cover_${widget.manga.compositeId}';
    final isAdultSource = widget.manga.source == MangaSourceType.adultSource;

    return ValueListenableBuilder<NsfwDisplayMode>(
      valueListenable: StorageService.nsfwModeNotifier,
      builder: (context, nsfwMode, _) {
        final shouldBlur = widget.manga.isNsfw &&
            nsfwMode == NsfwDisplayMode.blurred &&
            !_peekUnblurred;

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MangaDetailScreen(
                manga: widget.manga,
                heroTag: heroTag,
              ),
            ),
          ),
          onLongPress: widget.manga.isNsfw
              ? () => setState(() => _peekUnblurred = !_peekUnblurred)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Hero(
                  tag: heroTag,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: widget.manga.getCoverUrl(highRes: false),
                          httpHeaders: widget.manga.customHeaders,
                          memCacheWidth: 350,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: YomiPalette.surface,
                            child: const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: YomiPalette.ensoRed,
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: YomiPalette.surface,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                        if (shouldBlur)
                          BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                            child: Container(
                              color: Colors.black.withOpacity(0.45),
                              alignment: Alignment.center,
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.visibility_off_rounded,
                                    color: YomiPalette.sakuraPink,
                                    size: 22,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '18+ Segure p/ ver',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: YomiPalette.sakuraSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Badge da Fonte (MDX ou 18+)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isAdultSource
                                  ? YomiPalette.sakuraPink.withOpacity(0.92)
                                  : YomiPalette.ensoRed.withOpacity(0.90),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              widget.manga.source.badge,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: isAdultSource ? Colors.black : Colors.white,
                              ),
                            ),
                          ),
                        ),
                        // Coração se estiver nos favoritos
                        ValueListenableBuilder(
                          valueListenable: StorageService.favBox
                              .listenable(keys: [widget.manga.id]),
                          builder: (context, Box box, _) {
                            if (!StorageService.isFavorite(widget.manga.id)) {
                              return const SizedBox.shrink();
                            }
                            return Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.75),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.favorite_rounded,
                                  size: 13,
                                  color: YomiPalette.ensoRed,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.manga.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
