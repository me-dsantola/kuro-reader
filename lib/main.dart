import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/storage_service.dart';
import 'screens/home_tabs.dart';
import 'screens/home_overview_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await StorageService.init();
  } catch (e) {
    debugPrint('Aviso na inicializacao do Hive: $e');
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: YomiPalette.pitchBlack,
    ),
  );

  runApp(const YomiApp());
}

class YomiApp extends StatelessWidget {
  const YomiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'YOMI',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: YomiPalette.pitchBlack,
        colorScheme: const ColorScheme.dark(
          primary: YomiPalette.ensoRed,
          secondary: YomiPalette.sakuraPink,
          surface: YomiPalette.surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: YomiPalette.pitchBlack,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Colors.white,
          ),
        ),
      ),
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell>
    with WidgetsBindingObserver {
  // Start with lightweight reading shortcuts; keep profile one tap away.
  int _selectedIndex = 0;
  bool _isPrivacyShieldActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final shouldShield = state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused;
    if (_isPrivacyShieldActive != shouldShield) {
      setState(() => _isPrivacyShieldActive = shouldShield);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeOverviewScreen(
        onExplore: () => setState(() => _selectedIndex = 1),
        onLibrary: () => setState(() => _selectedIndex = 2),
      ),
      const ExploreScreen(),
      const LibraryScreen(),
      const DownloadsScreen(),
      ProfileDashboardScreen(
        onGoToExplore: () => setState(() => _selectedIndex = 1),
        onGoToSettings: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      ),
    ];

    return Stack(
      children: [
        Scaffold(
          body: IndexedStack(index: _selectedIndex, children: pages),
          bottomNavigationBar: NavigationBar(
            backgroundColor: YomiPalette.surface,
            indicatorColor: YomiPalette.ensoRed.withValues(alpha: 0.25),
            selectedIndex: _selectedIndex,
            onDestinationSelected: (idx) =>
                setState(() => _selectedIndex = idx),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon:
                    Icon(Icons.home_rounded, color: YomiPalette.ensoRed),
                label: 'Início',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon:
                    Icon(Icons.explore_rounded, color: YomiPalette.ensoRed),
                label: 'Explorar',
              ),
              NavigationDestination(
                icon: Icon(Icons.bookmarks_outlined),
                selectedIcon:
                    Icon(Icons.bookmarks_rounded, color: YomiPalette.ensoRed),
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
          ),
        ),
        if (_isPrivacyShieldActive)
          const Material(
            color: YomiPalette.pitchBlack,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  YomiEnsoLogo(fontSize: 36),
                  SizedBox(height: 12),
                  Text(
                    'Proteção de Privacidade Ativa',
                    style: TextStyle(
                      fontSize: 12,
                      color: YomiPalette.sakuraPink,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
