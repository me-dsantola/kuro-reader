import 'package:flutter/foundation.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/manga_models.dart';
import '../services/mangadex_service.dart';
import '../services/storage_service.dart';
import '../services/download_manager.dart';
import '../services/favorite_updates_service.dart';
import 'manga_detail_screen.dart';
import 'reader_screen.dart';

class YomiPalette {
  static const Color pitchBlack = Color(0xFF070709);
  static const Color surface = Color(0xFF121217);
  static const Color surfaceElevated = Color(0xFF181820);
  static const Color ensoRed = Color(0xFFE11D48);
  static const Color crimsonGlow = Color(0xFF9F1239);
  static const Color sakuraPink = Color(0xFFF472B6);
  static const Color sakuraSoft = Color(0xFFFBCFE8);
  static const Color pureWhite = Color(0xFFFAFAFA);
}


/// Widget Inteligente de Capa Multi-CDN (Nativo sem sqflite + Fallback i0.wp.com / wsrv.nl / codetabs + Auto-Recuperação AniList)
class YomiCoverImage extends StatefulWidget {
  final Manga manga;
  final bool highRes;
  final double? width;
  final double? height;
  final BoxFit fit;

  const YomiCoverImage({
    super.key,
    required this.manga,
    this.highRes = false,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  State<YomiCoverImage> createState() => _YomiCoverImageState();
}

class _YomiCoverImageState extends State<YomiCoverImage> {
  late List<String> _candidates;
  int _index = 0;
  bool _triedTitleRecovery = false;
  bool _exhausted = false;

  @override
  void initState() {
    super.initState();
    _initCandidates();
  }

  @override
  void didUpdateWidget(covariant YomiCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manga.compositeId != widget.manga.compositeId ||
        oldWidget.highRes != widget.highRes) {
      _initCandidates();
    }
  }

  void _initCandidates() {
    _candidates = List<String>.from(
      widget.manga.getAllCandidateCoverUrls(highRes: widget.highRes),
    );
    _index = 0;
    _triedTitleRecovery = false;
    _exhausted = false;
    if (_candidates.isEmpty) {
      _recoverCoverByTitle();
    }
  }

  Future<void> _recoverCoverByTitle() async {
    if (_triedTitleRecovery) {
      if (mounted) setState(() => _exhausted = true);
      return;
    }
    _triedTitleRecovery = true;
    final resolved =
        await MangaDexService.resolveCoverUrlByTitle(widget.manga.title);
    if (!mounted) return;
    if (resolved != null && resolved.isNotEmpty) {
      final newUrls = yomiCandidateImageUrls(resolved);
      if (newUrls.isNotEmpty) {
        setState(() {
          _candidates.addAll(newUrls);
          _exhausted = false;
        });
        return;
      }
    }
    setState(() => _exhausted = true);
  }

  void _advanceToNextCandidate() {
    if (!mounted) return;
    if (_index + 1 < _candidates.length) {
      setState(() => _index++);
    } else if (!_triedTitleRecovery) {
      _recoverCoverByTitle();
    } else if (!_exhausted) {
      setState(() => _exhausted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_exhausted || _candidates.isEmpty || _index >= _candidates.length) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: YomiPalette.surface,
        padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
               _triedTitleRecovery && _exhausted
                  ? Icons.auto_stories_rounded
                  : Icons.sync_rounded,
              color: YomiPalette.ensoRed,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              widget.manga.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ],
        ),
      );
    }

    final currentUrl = _candidates[_index];
    return Image.network(
      currentUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      headers: kIsWeb ? null : widget.manga.customHeaders,
      // Decode covers close to their displayed size. Without this, large
      // source images can consume tens of MB per grid item and cause jank.
      cacheWidth: (() {
        final logicalWidth = widget.width ??
            (widget.highRes
                ? MediaQuery.sizeOf(context).width
                : MediaQuery.sizeOf(context).width / 3);
        final pixelRatio = MediaQuery.devicePixelRatioOf(context);
        return (logicalWidth * pixelRatio).ceil().clamp(160, 1080).toInt();
      })(),
      gaplessPlayback: true,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: widget.width,
          height: widget.height,
          color: YomiPalette.surface,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: YomiPalette.ensoRed,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _advanceToNextCandidate();
        });
        return Container(
          width: widget.width,
          height: widget.height,
          color: YomiPalette.surface,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: YomiPalette.sakuraPink,
            ),
          ),
        );
      },
    );
  }
}

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

class YomiSakuraBanner extends StatelessWidget {
  final String badgeText;
  final String subtitleText;

  const YomiSakuraBanner({
    super.key,
    this.badgeText = '6 FONTES INTEGRADAS',
    this.subtitleText = 'MangaDex • AniList • MyAnimeList • ComicK • HQs',
  });

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
                YomiPalette.pitchBlack.withValues(alpha: 0.92),
              ],
            ),
          ),
          alignment: Alignment.bottomLeft,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: YomiPalette.ensoRed.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: YomiPalette.ensoRed, width: 1),
                ),
                child: Text(
                  badgeText,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: YomiPalette.sakuraSoft,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitleText,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: YomiPalette.pureWhite.withValues(alpha: 0.85),
                  ),
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
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1E0712), Color(0xFF070709)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Halo difuso do Sol Vermelho
    final sunCenter = Offset(size.width * 0.80, size.height * 0.46);
    final haloPaint = Paint()
      ..color = YomiPalette.ensoRed.withValues(alpha: 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(sunCenter, 48, haloPaint);

    final sunPaint = Paint()..color = YomiPalette.ensoRed.withValues(alpha: 0.88);
    canvas.drawCircle(sunCenter, 34, sunPaint);

    final mountainPaint = Paint()..color = const Color(0xFF0D0A12);
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

    final sakuraPaint = Paint()..color = YomiPalette.sakuraPink.withValues(alpha: 0.60);
    final petals = [
      Offset(size.width * 0.12, size.height * 0.28),
      Offset(size.width * 0.28, size.height * 0.50),
      Offset(size.width * 0.45, size.height * 0.22),
      Offset(size.width * 0.62, size.height * 0.35),
      Offset(size.width * 0.88, size.height * 0.25),
      Offset(size.width * 0.72, size.height * 0.18),
    ];
    for (final p in petals) {
      canvas.drawOval(Rect.fromCenter(center: p, width: 7.5, height: 4.2), sakuraPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================================
// ABA 0 (PRINCIPAL DE CARA): PERFIL REFORMULADO (IDENTIDADE ENSO / TORII / SAKURA)
// ============================================================================
class ProfileDashboardScreen extends StatelessWidget {
  final VoidCallback onGoToExplore;
  final VoidCallback onGoToSettings;

  const ProfileDashboardScreen({
    super.key,
    required this.onGoToExplore,
    required this.onGoToSettings,
  });

  static const List<IconData> _avatarIcons = [
    Icons.self_improvement_rounded,
    Icons.local_fire_department_rounded,
    Icons.auto_fix_high_rounded,
    Icons.bolt_rounded,
    Icons.shield_moon_rounded,
    Icons.psychology_rounded,
  ];

  void _openEditProfileModal(BuildContext context, UserProfile current) {
    final nameCtrl = TextEditingController(text: current.name);
    final bioCtrl = TextEditingController(text: current.bio);
    final genreCtrl = TextEditingController(text: current.favoriteGenre);
    int selectedAvatar = current.avatarIndex;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: YomiPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune_rounded, color: YomiPalette.ensoRed),
                      const SizedBox(width: 8),
                      const Text(
                        'Personalizar Identidade YOMI',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(_avatarIcons.length, (idx) {
                      final isSel = idx == selectedAvatar;
                      return GestureDetector(
                        onTap: () => setModal(() => selectedAvatar = idx),
                        child: CustomPaint(
                          painter: isSel ? _EnsoOPainter() : null,
                          child: Padding(
                            padding: const EdgeInsets.all(5),
                            child: CircleAvatar(
                              radius: 22,
                              backgroundColor: isSel
                                  ? YomiPalette.ensoRed.withValues(alpha: 0.25)
                                  : YomiPalette.pitchBlack,
                              child: Icon(
                                _avatarIcons[idx],
                                color: isSel ? YomiPalette.sakuraSoft : Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: 'Nome / Codinome no Clã YOMI',
                      filled: true,
                      fillColor: YomiPalette.pitchBlack,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bioCtrl,
                    decoration: InputDecoration(
                      labelText: 'Assinatura / Bio de Leitura',
                      filled: true,
                      fillColor: YomiPalette.pitchBlack,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: genreCtrl,
                    decoration: InputDecoration(
                      labelText: 'Gêneros & Universos Favoritos',
                      filled: true,
                      fillColor: YomiPalette.pitchBlack,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: YomiPalette.ensoRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        await StorageService.updateUserProfile(
                          UserProfile(
                            name: nameCtrl.text.trim().isEmpty
                                ? 'Leitor YOMI'
                                : nameCtrl.text.trim(),
                            bio: bioCtrl.text.trim(),
                            avatarIndex: selectedAvatar,
                            favoriteGenre: genreCtrl.text.trim(),
                            openOnProfileByDefault:
                                current.openOnProfileByDefault,
                            isConfigured: true,
                          ),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.verified_rounded),
                      label: const Text(
                        'Salvar Identidade no Cofre Local',
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
    return Scaffold(
      appBar: AppBar(
        title: const YomiEnsoLogo(),
        actions: [
          TextButton.icon(
            onPressed: onGoToExplore,
            icon: const Icon(
              Icons.explore_rounded,
              size: 18,
              color: YomiPalette.ensoRed,
            ),
            label: const Text(
              'Catálogo',
              style: TextStyle(
                color: YomiPalette.pureWhite,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ajustes & Backup',
            icon: const Icon(Icons.settings_outlined, color: YomiPalette.sakuraPink),
            onPressed: onGoToSettings,
          ),
        ],
      ),
      body: ValueListenableBuilder<UserProfile>(
        valueListenable: StorageService.profileNotifier,
        builder: (context, profile, _) {
          return ValueListenableBuilder(
            valueListenable: StorageService.historyBox.listenable(),
            builder: (context, Box historyBox, _) {
              return ValueListenableBuilder(
                valueListenable: StorageService.favBox.listenable(),
                builder: (context, Box favBox, _) {
                  final metrics = StorageService.computeReadingMetrics();
                  final continueList = StorageService.getContinueReadingList();
                  final favorites = StorageService.getFavorites();

                  return ListView(
                    padding: const EdgeInsets.only(bottom: 36),
                    children: [
                      // 1. HERO HEADER ARTÍSTICO DO PERFIL (TORII + SOL VERMELHO + AVATAR ENSO)
                      SizedBox(
                        height: 225,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(
                              painter: _ToriiSakuraBannerPainter(),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.15),
                                    YomiPalette.pitchBlack.withValues(alpha: 0.95),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 16,
                              right: 16,
                              bottom: 14,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: YomiPalette.surface.withValues(alpha: 0.88),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: YomiPalette.ensoRed.withValues(alpha: 0.45),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: YomiPalette.ensoRed.withValues(alpha: 0.14),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        // Avatar emoldurado pelo Círculo Enso Japonês
                                        GestureDetector(
                                          onTap: () => _openEditProfileModal(
                                              context, profile),
                                          child: SizedBox(
                                            width: 68,
                                            height: 68,
                                            child: CustomPaint(
                                              painter: _EnsoOPainter(),
                                              child: Center(
                                                child: CircleAvatar(
                                                  radius: 25,
                                                  backgroundColor:
                                                      const Color(0xFF1F0913),
                                                  child: Icon(
                                                    _avatarIcons[
                                                        profile.avatarIndex %
                                                            _avatarIcons.length],
                                                    size: 28,
                                                    color: YomiPalette.sakuraSoft,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2.5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: YomiPalette.ensoRed
                                                          .withValues(alpha: 0.24),
                                                      borderRadius:
                                                          BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: YomiPalette.ensoRed,
                                                        width: 0.8,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      metrics.rankTitle.toUpperCase(),
                                                      style: const TextStyle(
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.w900,
                                                        letterSpacing: 0.7,
                                                        color:
                                                            YomiPalette.sakuraSoft,
                                                      ),
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  InkWell(
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                    onTap: () =>
                                                        _openEditProfileModal(
                                                            context, profile),
                                                    child: const Padding(
                                                      padding: EdgeInsets.all(4),
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons.edit_rounded,
                                                            size: 14,
                                                            color: YomiPalette
                                                                .sakuraPink,
                                                          ),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            'Editar',
                                                            style: TextStyle(
                                                              fontSize: 11.5,
                                                              color: YomiPalette
                                                                  .sakuraPink,
                                                              fontWeight:
                                                                  FontWeight.bold,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                profile.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 21,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.4,
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                profile.bio,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.white70,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    // Barra de Progresso de Rank & Foco de Gêneros
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(
                                        value: metrics.rankProgress,
                                        minHeight: 5,
                                        backgroundColor: Colors.white10,
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
                                          YomiPalette.ensoRed,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Afinidade: ${profile.favoriteGenre}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: YomiPalette.sakuraSoft,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '${favorites.length} Favoritos • ${metrics.totalChaptersRead} Caps Lidos',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white54,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 12),

                            // 2. CONTINUAR LENDO DE CARA (ACESSO IMEDIATO AO ABRIR O APP)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.play_circle_fill_rounded,
                                      color: YomiPalette.ensoRed,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Continuar de Onde Parou',
                                      style: TextStyle(
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                                TextButton(
                                  onPressed: onGoToExplore,
                                  child: const Text(
                                    'Explorar Catálogo →',
                                    style: TextStyle(
                                      color: YomiPalette.sakuraPink,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (continueList.isEmpty)
                              InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: onGoToExplore,
                                child: Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: BoxDecoration(
                                    color: YomiPalette.surface,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: YomiPalette.ensoRed
                                              .withValues(alpha: 0.18),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.menu_book_rounded,
                                          color: YomiPalette.ensoRed,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Comece sua jornada de leitura',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'Toque aqui para abrir o catálogo Multi-Fonte (Mangás, Manhwas e HQs). O último capítulo lido ficará salvo aqui.',
                                              style: TextStyle(
                                                color: Colors.white60,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              SizedBox(
                                height: 118,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: continueList.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 12),
                                  itemBuilder: (context, idx) {
                                    final item = continueList[idx];
                                    final Manga manga = item['manga'];
                                    final Chapter chapter = item['chapter'];
                                    final savedPage =
                                        StorageService.getSavedPageIndex(
                                            chapter.id);

                                    return InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
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
                                      child: Container(
                                        width: 280,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color(0xFF1B0C14),
                                              YomiPalette.surface,
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                            color: YomiPalette.ensoRed
                                                .withValues(alpha: 0.45),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: YomiCoverImage(
                                                manga: manga,
                                                highRes: false,
                                                width: 68,
                                                height: 96,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: manga
                                                          .source.accentColor
                                                          .withValues(alpha: 0.25),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              4),
                                                    ),
                                                    child: Text(
                                                      manga.source.badge,
                                                      style: const TextStyle(
                                                        fontSize: 9,
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Text(
                                                    manga.title,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 13.5,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Text(
                                                    'Cap. ${chapter.chapterNumber} • Pág. ${savedPage + 1}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: YomiPalette
                                                          .sakuraPink,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Icon(
                                              Icons.play_arrow_rounded,
                                              color: YomiPalette.ensoRed,
                                              size: 30,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),

                            const SizedBox(height: 24),

                            // 3. TELEMETRIA DE LEITURA (HOJE, SEMANA, TOTAL, PÁGINAS)
                            const Row(
                              children: [
                                Icon(
                                  Icons.insights_rounded,
                                  color: YomiPalette.sakuraPink,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Telemetria & Ritmo de Leitura',
                                  style: TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _MetricStatCard(
                                    label: 'Capítulos Hoje',
                                    value: '${metrics.chaptersReadToday}',
                                    unit: 'lidos hoje',
                                    icon: Icons.bolt_rounded,
                                    accent: YomiPalette.ensoRed,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _MetricStatCard(
                                    label: 'Últimos 7 Dias',
                                    value: '${metrics.chaptersReadThisWeek}',
                                    unit: 'na semana',
                                    icon: Icons.calendar_today_rounded,
                                    accent: YomiPalette.sakuraPink,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _MetricStatCard(
                                    label: 'Acervo Concluído',
                                    value: '${metrics.totalChaptersRead}',
                                    unit: 'caps totais',
                                    icon: Icons.auto_stories_rounded,
                                    accent: const Color(0xFF02A9FF),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _MetricStatCard(
                                    label: 'Volume de Páginas',
                                    value: '${metrics.totalPagesRead}',
                                    unit: 'págs viradas',
                                    icon: Icons.layers_rounded,
                                    accent: const Color(0xFFF59E0B),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // 4. RECORDES & EXTREMOS (MAIS LIDO, MENOS LIDO, MAIOR E MENOR CAPÍTULO)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    YomiPalette.surfaceElevated,
                                    YomiPalette.surface,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: YomiPalette.sakuraPink.withValues(alpha: 0.28),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.workspace_premium_rounded,
                                        size: 18,
                                        color: YomiPalette.ensoRed,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Recordes & Extremos do Leitor',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                          color: YomiPalette.sakuraSoft,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  _HighlightBentoRow(
                                    badge: 'MAIS LIDO',
                                    badgeColor: YomiPalette.ensoRed,
                                    title: metrics.mostReadManga != null
                                        ? metrics.mostReadManga!.title
                                        : 'Nenhuma obra registrada ainda',
                                    subtitle: metrics.mostReadManga != null
                                        ? '${metrics.mostReadCount} capítulos lidos'
                                        : 'Abra um capítulo para iniciar o ranking',
                                  ),
                                  const Divider(color: Colors.white10, height: 16),
                                  _HighlightBentoRow(
                                    badge: 'MENOS LIDO',
                                    badgeColor: YomiPalette.sakuraPink,
                                    title: metrics.leastReadManga != null
                                        ? metrics.leastReadManga!.title
                                        : 'Aguardando leituras',
                                    subtitle: metrics.leastReadManga != null
                                        ? '${metrics.leastReadCount} capítulo(s) lido(s)'
                                        : '-',
                                  ),
                                  const Divider(color: Colors.white10, height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _ExtremeChapterBox(
                                          label: 'MAIOR CAPÍTULO',
                                          value: metrics.longestChapterRead !=
                                                  null
                                              ? 'Cap. ${metrics.longestChapterRead!.chapterNumber}'
                                              : '--',
                                          sub: metrics.longestChapterRead !=
                                                  null
                                              ? '${metrics.longestChapterRead!.pages} páginas'
                                              : '0 págs',
                                          color: const Color(0xFF02A9FF),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _ExtremeChapterBox(
                                          label: 'MENOR CAPÍTULO',
                                          value: metrics.shortestChapterRead !=
                                                  null
                                              ? 'Cap. ${metrics.shortestChapterRead!.chapterNumber}'
                                              : '--',
                                          sub: metrics.shortestChapterRead !=
                                                  null
                                              ? '${metrics.shortestChapterRead!.pages} páginas'
                                              : '0 págs',
                                          color: const Color(0xFF10B981),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // 5. VITRINE DE FAVORITOS DO PERFIL
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.favorite_rounded,
                                      color: YomiPalette.ensoRed,
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Obras Favoritas do Seu Clã',
                                      style: TextStyle(
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                                if (favorites.isNotEmpty)
                                  Text(
                                    '${favorites.length} salvas',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: YomiPalette.sakuraSoft,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (favorites.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: YomiPalette.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: const Text(
                                  'Você ainda não favoritou nenhuma obra. Toque no ícone de coração no topo de qualquer Mangá, Manhwa ou HQ para destacá-lo no seu perfil.',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12.5,
                                  ),
                                ),
                              )
                            else
                              SizedBox(
                                height: 198,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: favorites.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 12),
                                  itemBuilder: (context, idx) => SizedBox(
                                    width: 124,
                                    child: MangaGridCard(
                                      manga: favorites[idx],
                                      heroPrefix: 'profile_fav',
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
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

class _MetricStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color accent;

  const _MetricStatCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: YomiPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        unit,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightBentoRow extends StatelessWidget {
  final String badge;
  final Color badgeColor;
  final String title;
  final String subtitle;

  const _HighlightBentoRow({
    required this.badge,
    required this.badgeColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: badgeColor, width: 0.9),
          ),
          child: Text(
            badge,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExtremeChapterBox extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Color color;

  const _ExtremeChapterBox({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: YomiPalette.pitchBlack,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            sub,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ABA 1: EXPLORAR (6 FONTES SIMULTÂNEAS + SELETOR RÁPIDO DE FONTE NO TOPO)
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
  int _catalogRequestGeneration = 0;

  final Set<CanonicalTag> _includedTags = {};
  final Set<CanonicalTag> _excludedTags = {};
  final Set<MangaSourceType> _enabledSources = {
    MangaSourceType.mangadex,
    MangaSourceType.anilist,
    MangaSourceType.jikanMal,
    MangaSourceType.comick,
    MangaSourceType.comicsHq,
    MangaSourceType.adultSource,
  };
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
    if (!StorageService.nsfwMode.allowNsfwFetch) {
      _includedTags.removeWhere((t) => t.isNsfwOnly);
      _excludedTags.removeWhere((t) => t.isNsfwOnly);
    }
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
        enabledSources: _enabledSources,
        allowNsfw: StorageService.nsfwMode.allowNsfwFetch,
        sortByLatest: _sortByLatest,
        hideZeroChapters: StorageService.hideZeroChapterTitles,
      );

  Future<void> _loadMangas({bool reset = true}) async {
    final generation = ++_catalogRequestGeneration;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await MangaDexService.fetchMergedCatalog(
        filter: _currentFilter,
        reset: reset,
      );
      if (mounted && generation == _catalogRequestGeneration) {
        setState(() {
          _mangas = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && generation == _catalogRequestGeneration) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreMangas() async {
    if (_isLoading || _isLoadingMore) return;
    final generation = _catalogRequestGeneration;
    setState(() => _isLoadingMore = true);
    try {
      final result = await MangaDexService.fetchMergedCatalog(
        filter: _currentFilter,
        reset: false,
      );
      if (mounted && generation == _catalogRequestGeneration && result.isNotEmpty) {
        setState(() {
          final existingIds = _mangas.map((m) => m.compositeId).toSet();
          _mangas.addAll(
            result.where((m) => existingIds.add(m.compositeId)),
          );
        });
      }
    } catch (_) {
      // Keep the current catalog visible if a later page fails.
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _openTagFilterModal() {
    final allowNsfw = StorageService.nsfwMode.allowNsfwFetch;
    final groups = TagCategoryGroup.values.where((g) {
      if (g == TagCategoryGroup.nsfwVault && !allowNsfw) return false;
      return true;
    }).toList();

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
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.82,
              maxChildSize: 0.94,
              minChildSize: 0.5,
              builder: (context, scrollCtrl) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Catálogo de Categorias & Fontes',
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
                              'Limpar Tudo',
                              style: TextStyle(color: YomiPalette.sakuraPink),
                            ),
                          ),
                        ],
                      ),
                      const Text(
                        '1 toque = Incluir (+ Vermelho) • 2 toques = Excluir (- Sakura)',
                        style: TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          controller: scrollCtrl,
                          children: [
                            const Text(
                              'Fontes de Catálogo Ativas (6 Motores)',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: YomiPalette.sakuraSoft,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: MangaSourceType.values.where((s) {
                                if (s == MangaSourceType.adultSource &&
                                    !allowNsfw) {
                                  return false;
                                }
                                return true;
                              }).map((src) {
                                final isOn = _enabledSources.contains(src);
                                return FilterChip(
                                  selected: isOn,
                                  selectedColor:
                                      src.accentColor.withValues(alpha: 0.28),
                                  label: Text('${src.badge} • ${src.label}'),
                                  onSelected: (val) {
                                    setModalState(() {
                                      if (val) {
                                        _enabledSources.add(src);
                                      } else if (_enabledSources.length > 1) {
                                        _enabledSources.remove(src);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            for (final group in groups) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 10, bottom: 8),
                                child: Text(
                                  group.title,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: YomiPalette.sakuraSoft,
                                  ),
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: CanonicalTag.values
                                    .where((t) =>
                                        t.group == group &&
                                        (allowNsfw || !t.isNsfwOnly))
                                    .map((tag) {
                                  final isInc = _includedTags.contains(tag);
                                  final isExc = _excludedTags.contains(tag);

                                  Color bgColor = YomiPalette.pitchBlack;
                                  Color borderColor = Colors.white24;
                                  IconData? icon;

                                  if (isInc) {
                                    bgColor =
                                        YomiPalette.ensoRed.withValues(alpha: 0.25);
                                    borderColor = YomiPalette.ensoRed;
                                    icon = Icons.add_circle_outline;
                                  } else if (isExc) {
                                    bgColor =
                                        YomiPalette.sakuraPink.withValues(alpha: 0.20);
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
                                            Icon(icon,
                                                size: 15, color: borderColor),
                                            const SizedBox(width: 4),
                                          ],
                                          Text(
                                            tag.label,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              decoration: isExc
                                                  ? TextDecoration.lineThrough
                                                  : null,
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
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
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
                            'Aplicar Filtros no Catálogo',
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final latestRoll = _mangas.where((m) => !m.isCoverOnly).take(10).toList();
    final allowNsfw = StorageService.nsfwMode.allowNsfwFetch;

    return Scaffold(
      appBar: AppBar(
        title: const YomiEnsoLogo(),
        actions: [
          IconButton(
            tooltip: _sortByLatest
                ? 'Atualizações recentes'
                : 'Mais capítulos disponíveis',
            icon: Icon(
              _sortByLatest
                  ? Icons.schedule_rounded
                  : Icons.local_fire_department_rounded,
              color: _sortByLatest
                  ? YomiPalette.sakuraPink
                  : YomiPalette.ensoRed,
            ),
            onPressed: () {
              setState(() => _sortByLatest = !_sortByLatest);
              _loadMangas(reset: true);
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
                      hintText:
                          'Buscar em 6 fontes (One Piece, Solo Leveling, Batman...)',
                      hintStyle:
                          TextStyle(color: Colors.white.withValues(alpha: 0.38)),
                      prefixIcon: const Icon(Icons.search,
                          color: YomiPalette.ensoRed),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear,
                                  color: Colors.white54),
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
                    icon: const Icon(Icons.tune_rounded,
                        color: YomiPalette.sakuraPink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: YomiPalette.ensoRed))
          : _error != null && _mangas.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded,
                            size: 48, color: YomiPalette.ensoRed),
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
                      const SliverToBoxAdapter(child: YomiSakuraBanner()),

                      // BARRA RÁPIDA DE FONTES ATIVAS (MDX, ANI, MAL, CMK, HQs)
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 46,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                            children: MangaSourceType.values.where((s) {
                              if (s == MangaSourceType.adultSource && !allowNsfw) {
                                return false;
                              }
                              return true;
                            }).map((src) {
                              final isOn = _enabledSources.contains(src);
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  visualDensity: VisualDensity.compact,
                                  selected: isOn,
                                  selectedColor:
                                      src.accentColor.withValues(alpha: 0.28),
                                  backgroundColor: YomiPalette.surface,
                                  side: BorderSide(
                                    color: isOn
                                        ? src.accentColor
                                        : Colors.white12,
                                  ),
                                  label: Text(
                                    '${src.badge} • ${src.label}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isOn
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  onSelected: (val) {
                                    setState(() {
                                      if (val) {
                                        _enabledSources.add(src);
                                      } else if (_enabledSources.length > 1) {
                                        _enabledSources.remove(src);
                                      }
                                    });
                                    _loadMangas(reset: true);
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),

                      if (latestRoll.isNotEmpty &&
                          _searchController.text.isEmpty) ...[
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                            child: Row(
                              children: [
                                Icon(Icons.new_releases_rounded,
                                    size: 18, color: YomiPalette.ensoRed),
                                SizedBox(width: 6),
                                Text(
                                  'Destaques & Lançamentos Multi-Fonte',
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
                            height: 196,
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              scrollDirection: Axis.horizontal,
                              itemCount: latestRoll.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, idx) => SizedBox(
                                width: 124,
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
                              'Catálogo Unificado (Mangás, Manhwas & HQs)',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                      SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.62,
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
                              child: CircularProgressIndicator(
                                  color: YomiPalette.ensoRed),
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
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _checkingUpdates = false;

  Future<void> _checkUpdates() async {
    if (_checkingUpdates) return;
    setState(() => _checkingUpdates = true);
    var newChapters = 0;
    var failures = 0;
    // Explicit action only: no background polling or notification permission.
    final favorites = StorageService.getFavorites();
    for (final manga in favorites) {
      if (!mounted) break;
      try {
        newChapters += await FavoriteUpdatesService.checkFavorite(manga);
      } catch (_) {
        failures++;
      }
    }
    if (!mounted) return;
    setState(() => _checkingUpdates = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        failures > 0
            ? 'Verificação parcial: $newChapters capítulos novos; $failures obras indisponíveis.'
            : '$newChapters capítulos novos. Na primeira verificação, o histórico é inicializado.',
      ),
    ));
  }

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
        actions: [
          IconButton(
            tooltip: 'Verificar novos capítulos dos favoritos',
            onPressed: _checkingUpdates ? null : _checkUpdates,
            icon: _checkingUpdates
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_active_outlined),
          ),
        ],
      ),
      body: ValueListenableBuilder<NsfwDisplayMode>(
        valueListenable: StorageService.nsfwModeNotifier,
        builder: (context, _, _) {
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
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Sua biblioteca está vazia',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Toque no coração em qualquer Mangá, Manhwa ou HQ para salvá-la aqui.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ValueListenableBuilder(
                valueListenable: StorageService.settingsBox.listenable(),
                builder: (context, Box settings, _) {
                  return Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          'Toque no sino para verificar novidades. A primeira verificação registra os capítulos atuais sem alertas antigos.',
                          style: TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                      ),
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.62,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: favorites.length,
                          itemBuilder: (context, index) {
                            final manga = favorites[index];
                            final count =
                                FavoriteUpdatesService.pendingFor(manga).length;
                            return Stack(
                              children: [
                                MangaGridCard(manga: manga, heroPrefix: 'lib'),
                                if (count > 0)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: YomiPalette.ensoRed,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '$count novos',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
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
            Icon(Icons.download_for_offline_rounded,
                color: YomiPalette.ensoRed),
            SizedBox(width: 10),
            Text('Capítulos Offline'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Apagar todos os downloads',
            icon: const Icon(Icons.delete_sweep_outlined,
                color: YomiPalette.sakuraPink),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await DownloadManager.deleteAllDownloads();
              messenger.showSnackBar(
                const SnackBar(content: Text('Armazenamento offline limpo!')),
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<NsfwDisplayMode>(
        valueListenable: StorageService.nsfwModeNotifier,
        builder: (context, _, _) {
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
                          color: Colors.white.withValues(alpha: 0.2),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Nenhum capítulo salvo no aparelho',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const Divider(color: Colors.white10),
                itemBuilder: (context, index) {
                  final entry = items[index];
                  final manga = Manga.fromMap(
                      Map<String, dynamic>.from(entry['manga'] ?? {}));
                  final chapter = Chapter.fromMap(
                      Map<String, dynamic>.from(entry['chapter'] ?? {}));
                  final paths = List<String>.from(entry['paths'] ?? []);

                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: YomiCoverImage(
                        manga: manga,
                        width: 48,
                        height: 68,
                      ),
                    ),
                    title: Text(
                      manga.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    subtitle: Text(
                      'Cap. ${chapter.chapterNumber} (${chapter.language}) • ${paths.length} págs',
                      style: const TextStyle(
                          color: YomiPalette.sakuraPink, fontSize: 12.5),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Colors.white54),
                      onPressed: () => DownloadManager.deleteChapter(chapter.id),
                    ),
                    onTap: () {
                      StorageService.markChapterAsRead(manga, chapter,
                          read: true);
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
// ABA 4: CONFIGURAÇÕES (CONTROLE DE CONTEÚDO ADULTO, LEITOR & BACKUP PERMANENTE)
// ============================================================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  void _showRestoreBackupModal() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: YomiPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Restaurar Código de Backup YOMI',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cole abaixo o código que você copiou anteriormente para recuperar seu Perfil, Métricas, Histórico e Favoritos após reinstalar o app.',
              style: TextStyle(fontSize: 12.5, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Cole o código de backup aqui...',
                filled: true,
                fillColor: YomiPalette.pitchBlack,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: YomiPalette.ensoRed,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final ok =
                      await StorageService.importFullBackupJson(ctrl.text);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Perfil, Favoritos e Métricas restaurados com sucesso!'
                              : 'Código de backup inválido.',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Restaurar Agora'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.settings_rounded, color: YomiPalette.ensoRed),
            SizedBox(width: 10),
            Text('Configurações'),
          ],
        ),
      ),
      body: ValueListenableBuilder<NsfwDisplayMode>(
        valueListenable: StorageService.nsfwModeNotifier,
        builder: (context, nsfwMode, _) {
          return ValueListenableBuilder(
            valueListenable: StorageService.settingsBox.listenable(),
            builder: (context, Box settingsBox, _) {
              final lockNsfwStartup = StorageService.lockNsfwOnStartup;
              final hideZero = StorageService.hideZeroChapterTitles;
              final dataSaver = StorageService.dataSaverEnabled;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Filtro de Conteúdo Sensível / Adulto (18+)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: YomiPalette.sakuraSoft,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: YomiPalette.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        for (final mode in NsfwDisplayMode.values)
                          ListTile(
                            leading: Icon(
                              nsfwMode == mode
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: nsfwMode == mode
                                  ? YomiPalette.ensoRed
                                  : Colors.white54,
                            ),
                            title: Text(
                              mode.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              mode.subtitle,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.white60),
                            ),
                            onTap: () => StorageService.setNsfwMode(mode),
                          ),
                        const Divider(color: Colors.white10, height: 1),
                        SwitchListTile(
                          activeThumbColor: YomiPalette.ensoRed,
                          title: const Text(
                            'Sempre iniciar com Conteúdo Adulto Desligado',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'Garante que toda vez que o app for aberto, o modo 18+ volte automaticamente para Seguro (Oculto).',
                            style:
                                TextStyle(fontSize: 11.5, color: Colors.white54),
                          ),
                          value: lockNsfwStartup,
                          onChanged: (val) =>
                              StorageService.setLockNsfwOnStartup(val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Catálogo & Leitor de Alta Performance',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: YomiPalette.sakuraSoft,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: YomiPalette.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          activeThumbColor: YomiPalette.ensoRed,
                          title: const Text(
                            'Ocultar totalmente obras "Só Capa" (0 capítulos)',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'Por padrão elas aparecem em cinza no fim da pesquisa. Ative para escondê-las completamente.',
                            style:
                                TextStyle(fontSize: 11.5, color: Colors.white54),
                          ),
                          value: hideZero,
                          onChanged: (val) =>
                              StorageService.setHideZeroChapterTitles(val),
                        ),
                        const Divider(color: Colors.white10, height: 1),
                        SwitchListTile(
                          activeThumbColor: YomiPalette.ensoRed,
                          title: const Text(
                            'Economia de Dados (Data Saver)',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          subtitle: const Text(
                            'Carrega páginas otimizadas em WebP para leitura mais rápida em redes móveis.',
                            style:
                                TextStyle(fontSize: 11.5, color: Colors.white54),
                          ),
                          value: dataSaver,
                          onChanged: (val) =>
                              StorageService.setDataSaverEnabled(val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Persistência & Backup do Perfil (Anti-Desinstalação)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: YomiPalette.sakuraSoft,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: YomiPalette.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.cloud_done_rounded,
                                color: Colors.greenAccent, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Android Auto-Backup Ativo + Código de Restauração Instantânea',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Além do backup automático do Android, você pode copiar seu código de perfil abaixo para salvar no WhatsApp/Bloco de Notas e restaurar tudo em 1 segundo se apagar o app.',
                          style: TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final messenger =
                                      ScaffoldMessenger.of(context);
                                  final code =
                                      StorageService.exportFullBackupJson();
                                  await Clipboard.setData(
                                      ClipboardData(text: code));
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Código de Backup copiado para a área de transferência!',
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy_all_rounded,
                                    size: 18),
                                label: const Text('Copiar Backup'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: YomiPalette.ensoRed,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _showRestoreBackupModal,
                                icon:
                                    const Icon(Icons.restore_rounded, size: 18),
                                label: const Text('Restaurar'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// CARD UNIFICADO COM TÍTULO SEMPRE VISÍVEL + SELO DE FONTE + SÓ CAPA CINZA
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
    final isCoverOnly = widget.manga.isCoverOnly;

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
          child: Opacity(
            opacity: isCoverOnly ? 0.55 : 1.0,
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
                          ColorFiltered(
                            colorFilter: isCoverOnly
                                ? const ColorFilter.mode(
                                    Colors.grey,
                                    BlendMode.saturation,
                                  )
                                : const ColorFilter.mode(
                                    Colors.transparent,
                                    BlendMode.multiply,
                                  ),
                            child: YomiCoverImage(
                              manga: widget.manga,
                              highRes: false,
                            ),
                          ),
                          if (shouldBlur)
                            BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.45),
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
                          // Badge da Fonte (MDX, ANI, MAL, CMK, HQs ou 18+)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: widget.manga.source.accentColor
                                    .withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                widget.manga.source.badge,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          // Se tiver apenas a capa (0 capítulos), mostra faixa cinza explícita
                          if (isCoverOnly)
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                color: Colors.black87,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                alignment: Alignment.center,
                                child: const Text(
                                  'SÓ CAPA (0 CAPS)',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            )
                          else if (widget.manga.alternativeSources.isNotEmpty)
                            Positioned(
                              bottom: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: YomiPalette.sakuraPink,
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  '+${widget.manga.alternativeSources.length} fonte',
                                  style: const TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.bold,
                                    color: YomiPalette.sakuraSoft,
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
                                    color: Colors.black.withValues(alpha: 0.75),
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
                SizedBox(
                  height: 30,
                  child: Text(
                    widget.manga.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: isCoverOnly ? Colors.white54 : Colors.white,
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
}
