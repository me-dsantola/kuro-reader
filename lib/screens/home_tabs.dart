import 'package:flutter/material.dart';
import '../services/device_state_service.dart';
import '../services/profile_palette_service.dart';
import '../widgets/yomi_brand_widgets.dart';
import 'downloads_screen.dart';
import 'library_collection_screen.dart';

export '../widgets/yomi_brand_widgets.dart';
export 'profile_dashboard_screen.dart';
export 'explore_screen.dart';
export 'downloads_screen.dart';
export 'settings_screen.dart';

// ============================================================================
// ABA 2: MINHA BIBLIOTECA (IDENTIDADE VISUAL LUAR + FAVORITOS + LISTAS)
// ============================================================================
class LibraryScreen extends StatelessWidget {
  final VoidCallback? onExplore;
  const LibraryScreen({super.key, this.onExplore});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      DeviceStateService.instance,
      ProfilePaletteService.paletteNotifier,
    ]),
    builder: (context, _) {
      final palette = ProfilePaletteService.paletteNotifier.value;
      return DefaultTabController(
        key: ValueKey(DeviceStateService.instance.isOffline),
        length: 2,
        initialIndex: DeviceStateService.instance.isOffline ? 1 : 0,
        child: Material(
          color: YomiPalette.pitchBlack,
          child: Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorColor: palette.primary,
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: Colors.transparent,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white38,
                    labelStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: const [
                      Tab(text: 'Minha Biblioteca'),
                      Tab(text: 'Baixados'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    LibraryCollectionScreen(onExplore: onExplore),
                    const DownloadsScreen(),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
