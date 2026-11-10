import 'services/appearance_controller.dart';
import 'services/scroll_chrome_controller.dart';
import 'widgets/scroll_chrome_bar.dart';
import 'widgets/frosted_surface.dart';
import 'services/device_state_service.dart';
import 'widgets/adaptive_app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/storage_service.dart';
import 'screens/home_tabs.dart';
import 'screens/home_overview_screen.dart';
import 'screens/storage_recovery_screen.dart';
import 'widgets/privacy_shield.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  DeviceStateService.instance.start();
  bool storageReady = false;
  try {
    await StorageService.init();
    AppearanceController.instance.start();
    storageReady = true;
  } catch (_) {
    debugPrint('Armazenamento local indisponível; aguardando recuperação.');
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: YomiPalette.pitchBlack,
    ),
  );

  runApp(YomiApp(storageReady: storageReady));
}

class YomiApp extends StatelessWidget {
  final bool storageReady;
  const YomiApp({super.key, this.storageReady = true});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YOMI',
      navigatorObservers: [yomiRouteObserver],
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: YomiPalette.pitchBlack,
        colorScheme: const ColorScheme.dark(
          primary: YomiPalette.ensoRed,
          onPrimary: YomiPalette.pureWhite,
          secondary: YomiPalette.sakuraPink,
          surface: YomiPalette.surface,
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: YomiPalette.sakuraSoft),
        ),
        chipTheme: const ChipThemeData(
          labelStyle: TextStyle(color: YomiPalette.pureWhite),
          secondaryLabelStyle: TextStyle(color: YomiPalette.pureWhite),
          checkmarkColor: YomiPalette.pureWhite,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: YomiPalette.pitchBlack,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.white,
          ),
        ),
      ),
      builder: (context, child) => PrivacyShield(
        child: AdaptiveAppShell(child: child ?? const SizedBox()),
      ),
      home: storageReady
          ? const MainNavigationShell()
          : Builder(
              builder: (context) => StorageRecoveryScreen(
                onRecovered: () {
                  AppearanceController.instance.start();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => const MainNavigationShell(),
                    ),
                  );
                },
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

final RouteObserver<PageRoute<dynamic>> yomiRouteObserver =
    RouteObserver<PageRoute<dynamic>>();

class _MainNavigationShellState extends State<MainNavigationShell>
    with RouteAware {
  final _chrome = ScrollChromeController();
  PageRoute<dynamic>? _observedRoute;

  void _selectTab(int index) {
    _chrome.show();
    setState(() => _selectedIndex = index);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _observedRoute) {
      yomiRouteObserver.unsubscribe(this);
      _observedRoute = route;
      yomiRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() => _chrome.show();

  @override
  void dispose() {
    yomiRouteObserver.unsubscribe(this);
    _chrome.dispose();
    super.dispose();
  }

  // Start with lightweight reading shortcuts; keep profile one tap away.
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // Preserve the user's existing startup preference after moving Profile
    // to its own tab. Older installations defaulted to opening Profile.
    _selectedIndex = StorageService.profileNotifier.value.openOnProfileByDefault
        ? 4
        : 0;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeOverviewScreen(
        onExplore: () => _selectTab(1),
        onLibrary: () => _selectTab(2),
      ),
      const ExploreScreen(),
      const LibraryScreen(),
      const DownloadsScreen(),
      ProfileDashboardScreen(
        onGoToExplore: () => _selectTab(1),
        onGoToSettings: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      ),
    ];

    return Scaffold(
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (ModalRoute.of(context)?.isCurrent == true &&
              AppearanceController.instance.value.autoHideMenus) {
            return _chrome.onScroll(notification);
          }
          return false;
        },
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            for (var i = 0; i < pages.length; i++)
              TickerMode(enabled: i == _selectedIndex, child: pages[i]),
          ],
        ),
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: Listenable.merge([_chrome, AppearanceController.instance]),
        builder: (context, _) {
          final preferences = AppearanceController.instance.value;
          final glass =
              preferences.style == InterfaceStyle.glass &&
              !MediaQuery.highContrastOf(context);
          final bar = NavigationBar(
            backgroundColor: glass ? Colors.transparent : YomiPalette.surface,
            indicatorColor: YomiPalette.ensoRed.withValues(alpha: 0.25),
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(
                  Icons.home_rounded,
                  color: YomiPalette.ensoRed,
                ),
                label: 'Início',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(
                  Icons.explore_rounded,
                  color: YomiPalette.ensoRed,
                ),
                label: 'Explorar',
              ),
              NavigationDestination(
                icon: Icon(Icons.bookmarks_outlined),
                selectedIcon: Icon(
                  Icons.bookmarks_rounded,
                  color: YomiPalette.ensoRed,
                ),
                label: 'Biblioteca',
              ),
              NavigationDestination(
                icon: Icon(Icons.download_done_rounded),
                selectedIcon: Icon(
                  Icons.download_for_offline_rounded,
                  color: YomiPalette.sakuraPink,
                ),
                label: 'Offline',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(
                  Icons.person_rounded,
                  color: YomiPalette.sakuraPink,
                ),
                label: 'Perfil',
              ),
            ],
          );
          return ScrollChromeBar(
            visible:
                (!preferences.autoHideMenus || _chrome.visible) &&
                MediaQuery.viewInsetsOf(context).bottom == 0,
            child: glass
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: FrostedSurface(child: bar),
                    ),
                  )
                : bar,
          );
        },
      ),
    );
  }
}
