import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/storage_service.dart';
import 'screens/home_tabs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF09090E),
    ),
  );
  runApp(const KuroReaderApp());
}

class KuroReaderApp extends StatelessWidget {
  const KuroReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KuroReader',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09090E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          secondary: Color(0xFFC084FC),
          surface: Color(0xFF14141F),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF09090E),
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
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

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    ExploreScreen(),
    LibraryScreen(),
    DownloadsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF14141F),
        indicatorColor: const Color(0xFF8B5CF6).withOpacity(0.25),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore, color: Color(0xFFC084FC)),
            label: 'Explorar',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmarks_outlined),
            selectedIcon: Icon(Icons.bookmarks, color: Color(0xFFC084FC)),
            label: 'Biblioteca',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_done_rounded),
            selectedIcon: Icon(
              Icons.download_for_offline,
              color: Color(0xFFC084FC),
            ),
            label: 'Offline',
          ),
        ],
      ),
    );
  }
}
