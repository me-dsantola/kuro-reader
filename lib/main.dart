import 'widgets/app_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_overview_screen.dart';
import 'screens/storage_recovery_screen.dart';
import 'screens/home_tabs.dart';
import 'services/appearance_controller.dart';
import 'services/device_state_service.dart';
import 'services/profile_palette_service.dart';
import 'services/scroll_chrome_controller.dart';
import 'services/storage_service.dart';
import 'services/mangadex_service.dart';
import 'services/yomi_theme_system.dart';
import 'widgets/adaptive_app_shell.dart';
import 'widgets/frosted_surface.dart';
import 'widgets/privacy_shield.dart';
import 'widgets/yomi_blobatar_studio.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF070709),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  var storageReady = false;
  try {
    await StorageService.init();
    AppearanceController.instance.start();
    YomiThemeController.instance.start();
    ProfilePaletteService.bindToProfileNotifier(StorageService.profileNotifier);
    storageReady = true;
  } catch (_) {
    debugPrint('Falha ao iniciar o armazenamento local.');
  }
  DeviceStateService.instance.start();
  runApp(YomiApp(storageReady: storageReady));
}

class YomiApp extends StatefulWidget {
  final bool storageReady;
  const YomiApp({super.key, this.storageReady = true});

  @override
  State<YomiApp> createState() => _YomiAppState();
}

class _YomiAppState extends State<YomiApp> {
  late bool _storageReady;

  @override
  void initState() {
    super.initState();
    _storageReady = widget.storageReady;
  }

  void _onStorageRecovered() {
    AppearanceController.instance.start();
    YomiThemeController.instance.start();
    ProfilePaletteService.bindToProfileNotifier(StorageService.profileNotifier);
    setState(() => _storageReady = true);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<YomiThemeTokens>(
      valueListenable: YomiThemeController.instance,
      builder: (context, themeTokens, _) {
        return MaterialApp(
          title: 'YOMI',
          debugShowCheckedModeBanner: false,
          builder: (context, child) => AdaptiveAppShell(
            slowDisplayDelay: const Duration(milliseconds: 900),
            child: PrivacyShield(child: child ?? const SizedBox.shrink()),
          ),
          themeMode: themeTokens.isLight ? ThemeMode.light : ThemeMode.dark,
          theme: ThemeData(
            useMaterial3: true,
            brightness: themeTokens.brightness,
            scaffoldBackgroundColor: themeTokens.background,
            colorScheme: ColorScheme(
              brightness: themeTokens.brightness,
              primary: themeTokens.accentPrimary,
              onPrimary: Colors.white,
              secondary: themeTokens.accentSecondary,
              onSecondary: Colors.white,
              error: Colors.redAccent,
              onError: Colors.white,
              surface: themeTokens.surface,
              onSurface: themeTokens.textPrimary,
            ),
            progressIndicatorTheme: ProgressIndicatorThemeData(
              color: themeTokens.accentPrimary,
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: themeTokens.accentPrimary,
                foregroundColor: Colors.white,
              ),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: themeTokens.background,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              centerTitle: false,
              titleTextStyle: TextStyle(
                color: themeTokens.textPrimary,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            cardTheme: CardThemeData(
              color: themeTokens.cardSurface,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: themeTokens.border, width: 1),
              ),
            ),
          ),
          home: _storageReady
              ? const MainNavigationShell()
              : StorageRecoveryScreen(onRecovered: _onStorageRecovered),
        );
      },
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell>
    with SingleTickerProviderStateMixin {
  late int _currentIndex;
  bool _isForward = true;
  final _visitedTabs = <int>{};
  final List<int> _backHistory = [];
  final _chrome = ScrollChromeController();
  late final AnimationController _transition;
  late InternetState _lastInternet;
  int _refreshGeneration = 0;
  bool get _offline => DeviceStateService.instance.isOffline;

  void _syncNetwork() {
    final current = DeviceStateService.instance.value.internet;
    if (current == _lastInternet) return;
    final reconnected =
        _lastInternet == InternetState.offline &&
        current == InternetState.online;
    _lastInternet = current;
    setState(() {
      if (_offline) {
        if (_currentIndex != 3) _currentIndex = 1;
        _visitedTabs.removeWhere((index) => index != 1 && index != 3);
        _visitedTabs.add(_currentIndex);
      } else if (reconnected) {
        _refreshGeneration++;
        _visitedTabs.add(0);
        MangaDexService.resetAggregator();
      }
    });
    _chrome.show();
    if (reconnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          AppFeedback.message(
            context,
            'Conexão restabelecida. Atualizando catálogos; todos os menus disponíveis.',
          );
        }
      });
    }
  }

  List<_FloatingNavItem> get _navigationItems => _primaryNavItems
      .where((item) => !_offline || item.tabIndex == 1 || item.tabIndex == 3)
      .toList();

  @override
  void initState() {
    super.initState();
    _transition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      value: 1.0,
    );
    _lastInternet = DeviceStateService.instance.value.internet;
    DeviceStateService.instance.addListener(_syncNetwork);
    ProfilePaletteService.bindToProfileNotifier(StorageService.profileNotifier);
    // Tab indices matching the YOMI bottom bar:
    // 0: Início, 1: Biblioteca, 2: Explorar, 3: Perfil, 4: Ajustes
    final openOnProfile =
        StorageService.userProfile.openOnProfileByDefault == true;
    _currentIndex = openOnProfile ? 3 : (_offline ? 1 : 0);
    _visitedTabs.add(_currentIndex);
    _backHistory.add(_currentIndex);
    AppearanceController.instance.addListener(_syncChrome);
  }

  void _syncChrome() {
    if (!AppearanceController.instance.value.autoHideMenus) {
      _chrome.show();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppearanceController.instance.removeListener(_syncChrome);
    DeviceStateService.instance.removeListener(_syncNetwork);
    _transition.dispose();
    _chrome.dispose();
    super.dispose();
  }

  void _switchTab(int index, {bool fromBack = false}) {
    if (_offline && index != 1 && index != 3) return;
    if (index == _currentIndex) return;

    if (!fromBack) {
      if (_backHistory.isEmpty || _backHistory.last != _currentIndex) {
        _backHistory.add(_currentIndex);
      }
      _backHistory.add(index);
    }

    _isForward = fromBack ? false : (index > _currentIndex);
    _currentIndex = index;
    _visitedTabs.add(index);
    _chrome.show();

    final disableAnimations =
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false) ||
        !AppearanceController.instance.value.tabTransitions;

    if (disableAnimations) {
      _transition.value = 1.0;
      setState(() {});
    } else {
      _transition.forward(from: 0.0);
      setState(() {});
    }
  }

  static const List<_FloatingNavItem> _primaryNavItems = [
    _FloatingNavItem(
      tabIndex: 0,
      label: 'Início',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _FloatingNavItem(
      tabIndex: 1,
      label: 'Biblioteca',
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book_rounded,
    ),
    _FloatingNavItem(
      tabIndex: 2,
      label: 'Explorar',
      icon: Icons.explore_outlined,
      selectedIcon: Icons.explore_rounded,
    ),
    _FloatingNavItem(
      tabIndex: 3,
      label: 'Perfil',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        StorageService.profileNotifier,
        ProfilePaletteService.paletteNotifier,
      ]),
      builder: (context, _) {
        final profile = StorageService.profileNotifier.value;
        if (!profile.isConfigured) {
          return const FirstTimeProfileOnboardingScreen();
        }

        final palette = ProfilePaletteService.paletteNotifier.value;
        final pages = [
          HomeOverviewScreen(
            key: ValueKey('home_$_refreshGeneration'),
            onExplore: () => _switchTab(2),
            onLibrary: () => _switchTab(1),
            onProfile: () => _switchTab(3),
          ),
          LibraryScreen(
            key: ValueKey('library_$_refreshGeneration'),
            onExplore: _offline ? null : () => _switchTab(2),
          ),
          ExploreScreen(key: ValueKey('explore_$_refreshGeneration')),
          ProfileDashboardScreen(
            onGoToExplore: _offline ? null : () => _switchTab(2),
            onGoToSettings: _offline ? null : () => _switchTab(4),
          ),
          const SettingsScreen(),
        ];

        final disableAnimations = MediaQuery.disableAnimationsOf(context);
        return PopScope(
          canPop: _backHistory.length <= 1,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_backHistory.length > 1) {
              _backHistory.removeLast();
              final previous = _backHistory.last;
              _switchTab(previous, fromBack: true);
            }
          },
          child: Scaffold(
            extendBody: true,
            body: NotificationListener<ScrollNotification>(
              onNotification: (notification) =>
                  AppearanceController.instance.value.autoHideMenus
                  ? _chrome.onScroll(notification)
                  : false,
              child: Column(
                children: [
                  if (_offline)
                    SafeArea(
                      bottom: false,
                      child: Material(
                        color: palette.primary.withValues(alpha: 0.16),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.wifi_off_rounded,
                                color: palette.secondary,
                              ),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Modo offline · funcionalidades reduzidas\nPerfil, Biblioteca e capítulos baixados disponíveis.',
                                  style: TextStyle(fontSize: 12, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: FadeTransition(
                      opacity: disableAnimations ||
                              !AppearanceController
                                  .instance
                                  .value
                                  .tabTransitions
                          ? const AlwaysStoppedAnimation(1.0)
                          : _transition,
                      child: SlideTransition(
                        position: disableAnimations ||
                                !AppearanceController
                                    .instance
                                    .value
                                    .tabTransitions
                            ? const AlwaysStoppedAnimation(Offset.zero)
                            : Tween<Offset>(
                                begin: Offset(_isForward ? -0.12 : 0.12, 0),
                                end: Offset.zero,
                              )
                                .chain(CurveTween(curve: Curves.easeOutCubic))
                                .animate(_transition),
                        child: IndexedStack(
                          index: _currentIndex,
                          children: [
                            for (var i = 0; i < pages.length; i++)
                              _visitedTabs.contains(i)
                                  ? TickerMode(
                                      enabled: i == _currentIndex,
                                      child: pages[i],
                                    )
                                  : const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: ListenableBuilder(
            listenable: _chrome,
            builder: (context, _) {
              final visible = _chrome.visible;
              return AnimatedSlide(
                duration: disableAnimations
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                offset: Offset(0, visible ? 0 : 1.35),
                curve: Curves.easeOutCubic,
                child: IgnorePointer(
                  ignoring: !visible,
                  child: ExcludeSemantics(
                    excluding: !visible,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Center(
                          heightFactor: 1,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: _offline ? 240 : 328,
                            ),
                            child: FrostedSurface(
                              borderRadius: BorderRadius.circular(999),
                              child: SizedBox(
                                height: 58,
                                child: _buildAnimatedLiquidTabBar(
                                  palette: palette,
                                  disableAnimations: disableAnimations,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

  int get _activeVisualSlot {
    final mappedTab = _currentIndex == 4 ? 3 : _currentIndex;
    final idx = _navigationItems.indexWhere((e) => e.tabIndex == mappedTab);
    return idx >= 0 ? idx : 0;
  }

  Widget _buildAnimatedLiquidTabBar({
    required ProfileAdaptivePalette palette,
    required bool disableAnimations,
  }) {
    final activeSlot = _activeVisualSlot;
    final items = _navigationItems;
    final count = items.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final slotWidth = totalWidth / count;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (details) {
            final dx = details.localPosition.dx.clamp(0.0, totalWidth - 1);
            final slot = (dx ~/ slotWidth).clamp(0, count - 1);
            final targetTab = items[slot].tabIndex;
            if (targetTab != _currentIndex) {
              _switchTab(targetTab);
            }
          },
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: activeSlot.toDouble()),
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            builder: (context, slotPos, _) {
              final clampedSlot = slotPos.clamp(0.0, (count - 1).toDouble());
              final distFromRest =
                  (clampedSlot - clampedSlot.roundToDouble()).abs() * 2.0;
              final stretchPx = (distFromRest * 14.0).clamp(0.0, 14.0);
              final shrinkY = (distFromRest * 2.0).clamp(0.0, 2.0);
              final centerRatio = count > 1
                  ? (clampedSlot / (count - 1)) * 2.0 - 1.0
                  : 0.0;

              final pillLeft = (clampedSlot * slotWidth + 5.0 - stretchPx / 2)
                  .clamp(3.0, totalWidth - slotWidth + 3.0);
              final pillWidth = (slotWidth - 10.0 + stretchPx).clamp(
                36.0,
                totalWidth,
              );

              return Stack(
                fit: StackFit.expand,
                children: [
                  // Iluminação ambiente que acompanha a aba ativa (estilo iOS 26)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: RadialGradient(
                            center: Alignment(centerRatio, 0),
                            radius: 1.35,
                            colors: [
                              palette.primary.withValues(alpha: 0.22),
                              palette.secondary.withValues(alpha: 0.06),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Cápsula líquida de vidro deslizante entre os menus
                  Positioned(
                    left: pillLeft,
                    width: pillWidth,
                    top: 5.0 + shrinkY,
                    bottom: 5.0 + shrinkY,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              palette.secondary.withValues(alpha: 0.28),
                              palette.primary.withValues(alpha: 0.24),
                              palette.primary.withValues(alpha: 0.12),
                            ],
                          ),
                          border: Border.all(
                            color: palette.soft.withValues(alpha: 0.48),
                            width: 1.1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: palette.primary.withValues(alpha: 0.34),
                              blurRadius: 16,
                              spreadRadius: 0.5,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Ícones e rótulos das abas
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < count; i++)
                        Expanded(
                          child: _buildDockItem(
                            item: items[i],
                            selected: i == activeSlot,
                            palette: palette,
                            disableAnimations: disableAnimations,
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDockItem({
    required _FloatingNavItem item,
    required bool selected,
    required ProfileAdaptivePalette palette,
    required bool disableAnimations,
  }) {
    final color = selected ? Colors.white : Colors.white60;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _switchTab(item.tabIndex),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 1),
          child: AnimatedScale(
            scale: selected ? 1.03 : 1.0,
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 21,
                  color: selected ? palette.soft : color,
                ),
                const SizedBox(height: 1),
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingNavItem {
  final int tabIndex;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _FloatingNavItem({
    required this.tabIndex,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}
