import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_overview_screen.dart';
import 'screens/home_tabs.dart';
import 'services/appearance_controller.dart';
import 'services/device_state_service.dart';
import 'services/profile_palette_service.dart';
import 'services/scroll_chrome_controller.dart';
import 'services/storage_service.dart';
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
    ProfilePaletteService.bindToProfileNotifier(StorageService.profileNotifier);
    storageReady = true;
  } catch (_) {
    debugPrint('Falha ao iniciar o armazenamento local.');
  }
  DeviceStateService.instance.start();
  runApp(YomiApp(storageReady: storageReady));
}

class YomiApp extends StatelessWidget {
  final bool storageReady;
  const YomiApp({super.key, this.storageReady = true});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ProfileAdaptivePalette>(
      valueListenable: ProfilePaletteService.paletteNotifier,
      builder: (context, palette, _) {
        return MaterialApp(
          title: 'YOMI',
          debugShowCheckedModeBanner: false,
          builder: (context, child) => AdaptiveAppShell(
            slowDisplayDelay: const Duration(milliseconds: 900),
            child: PrivacyShield(child: child ?? const SizedBox.shrink()),
          ),
          themeMode: ThemeMode.dark,
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: YomiPalette.pitchBlack,
            colorScheme: ColorScheme.dark(
              primary: palette.primary,
              onPrimary: YomiPalette.pureWhite,
              secondary: palette.secondary,
              surface: YomiPalette.surface,
              onSurface: YomiPalette.pureWhite,
            ),
            progressIndicatorTheme: ProgressIndicatorThemeData(
              color: palette.primary,
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: palette.primary,
                foregroundColor: YomiPalette.pureWhite,
              ),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: YomiPalette.pitchBlack,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              centerTitle: false,
              titleTextStyle: TextStyle(
                color: YomiPalette.pureWhite,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            cardTheme: CardThemeData(
              color: YomiPalette.surface,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Colors.white10, width: 1),
              ),
            ),
          ),
          home: storageReady
              ? const MainNavigationShell()
              : const _StorageRecoveryScreen(),
        );
      },
    );
  }
}

class _StorageRecoveryScreen extends StatelessWidget {
  const _StorageRecoveryScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: YomiPalette.pitchBlack,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 56,
                color: YomiPalette.ensoRed,
              ),
              SizedBox(height: 16),
              Text(
                'Não foi possível abrir seus dados',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Feche e reabra o aplicativo ou verifique o armazenamento disponível no dispositivo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  late int _currentIndex;
  final _chrome = ScrollChromeController();

  @override
  void initState() {
    super.initState();
    ProfilePaletteService.bindToProfileNotifier(StorageService.profileNotifier);
    // Tab indices matching the YOMI bottom bar:
    // 0: Início, 1: Biblioteca, 2: Explorar, 3: Perfil, 4: Offline, 5: Ajustes
    final openOnProfile =
        StorageService.userProfile.openOnProfileByDefault == true;
    _currentIndex = openOnProfile ? 3 : 0;
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
    _chrome.dispose();
    super.dispose();
  }

  void _switchTab(int index) {
    _chrome.show();
    setState(() => _currentIndex = index);
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
    _FloatingNavItem(
      tabIndex: 4,
      label: 'Offline',
      icon: Icons.download_for_offline_outlined,
      selectedIcon: Icons.download_for_offline_rounded,
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
            onExplore: () => _switchTab(2),
            onLibrary: () => _switchTab(1),
            onProfile: () => _switchTab(3),
          ),
          const LibraryScreen(),
          const ExploreScreen(),
          ProfileDashboardScreen(
            onGoToExplore: () => _switchTab(2),
            onGoToSettings: () => _switchTab(5),
          ),
          const DownloadsScreen(),
          const SettingsScreen(),
        ];

        final disableAnimations = MediaQuery.disableAnimationsOf(context);
        return Scaffold(
          extendBody: true,
          body: NotificationListener<ScrollNotification>(
            onNotification: (notification) =>
                AppearanceController.instance.value.autoHideMenus
                ? _chrome.onScroll(notification)
                : false,
            child: IndexedStack(index: _currentIndex, children: pages),
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
                        child: FrostedSurface(
                          borderRadius: BorderRadius.circular(26),
                          child: SizedBox(
                            height: 66,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                for (final item in _primaryNavItems)
                                  Expanded(
                                    child: _buildDockItem(
                                      item: item,
                                      selected:
                                          _currentIndex == item.tabIndex ||
                                          (_currentIndex == 5 &&
                                              item.tabIndex == 3),
                                      accentColor: palette.primary,
                                    ),
                                  ),
                              ],
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
        );
      },
    );
  }

  Widget _buildDockItem({
    required _FloatingNavItem item,
    required bool selected,
    required Color accentColor,
  }) {
    final color = selected ? accentColor : Colors.white54;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _switchTab(item.tabIndex),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? accentColor.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 22,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              Flexible(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: color,
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
