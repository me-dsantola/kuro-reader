import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum ChapterCountStatus {
  /// Metadado ausente ou ainda não consultado (NÃO exibir em cinza).
  unknown,

  /// Consulta em andamento (NÃO exibir em cinza).
  loading,

  /// Confirmado >= 1 capítulo disponível.
  available,

  /// Confirmado 0 capítulos pela fonte ou metadado explícito.
  confirmedZero,
}

@immutable
class ChapterAvailabilityState {
  final ChapterCountStatus status;
  final int? count;

  const ChapterAvailabilityState._(this.status, this.count);
  const ChapterAvailabilityState.unknown()
      : this._(ChapterCountStatus.unknown, null);
  const ChapterAvailabilityState.loading()
      : this._(ChapterCountStatus.loading, null);

  factory ChapterAvailabilityState.fromConfirmedCount(int? explicitCount) {
    if (explicitCount == null) return const ChapterAvailabilityState.unknown();
    if (explicitCount <= 0) {
      return const ChapterAvailabilityState._(
        ChapterCountStatus.confirmedZero,
        0,
      );
    }
    return ChapterAvailabilityState._(
      ChapterCountStatus.available,
      explicitCount,
    );
  }

  bool get isConfirmedZero => status == ChapterCountStatus.confirmedZero;
}

class ChapterAvailabilityCache {
  final Map<String, ValueNotifier<ChapterAvailabilityState>> _notifiers = {};
  final Map<String, Future<int?>> _inFlight = {};
  final int maxConcurrentFetches;
  int _activeFetches = 0;

  ChapterAvailabilityCache({this.maxConcurrentFetches = 3});

  ValueListenable<ChapterAvailabilityState> watch(
    String mangaId, {
    int? initialKnownCount,
  }) {
    final existing = _notifiers[mangaId];
    if (existing != null) {
      if (initialKnownCount != null &&
          existing.value.status == ChapterCountStatus.unknown) {
        existing.value =
            ChapterAvailabilityState.fromConfirmedCount(initialKnownCount);
      }
      return existing;
    }
    final initial =
        ChapterAvailabilityState.fromConfirmedCount(initialKnownCount);
    final notifier = ValueNotifier<ChapterAvailabilityState>(initial);
    _notifiers[mangaId] = notifier;
    return notifier;
  }

  void updateConfirmedCount(String mangaId, int count) {
    final notifier = _notifiers.putIfAbsent(
      mangaId,
      () => ValueNotifier(const ChapterAvailabilityState.unknown()),
    );
    final nextState = ChapterAvailabilityState.fromConfirmedCount(count);
    if (notifier.value.status != nextState.status ||
        notifier.value.count != nextState.count) {
      notifier.value = nextState;
    }
  }

  Future<void> ensureResolved(
    String mangaId,
    Future<int?> Function(String id) fetcher,
  ) async {
    final notifier = _notifiers.putIfAbsent(
      mangaId,
      () => ValueNotifier(const ChapterAvailabilityState.unknown()),
    );
    if (notifier.value.status == ChapterCountStatus.available ||
        notifier.value.status == ChapterCountStatus.confirmedZero ||
        _inFlight.containsKey(mangaId) ||
        _activeFetches >= maxConcurrentFetches) {
      return;
    }
    notifier.value = const ChapterAvailabilityState.loading();
    _activeFetches++;
    final future = fetcher(mangaId);
    _inFlight[mangaId] = future;
    try {
      final count = await future;
      if (count != null) {
        updateConfirmedCount(mangaId, count);
      } else {
        notifier.value = const ChapterAvailabilityState.unknown();
      }
    } catch (_) {
      notifier.value = const ChapterAvailabilityState.unknown();
    } finally {
      _activeFetches--;
      _inFlight.remove(mangaId);
    }
  }
}

/// Wrapper visual consistente para cards de mangá nas listagens (Home, Busca, Biblioteca).
class MangaAvailabilityCardWrapper extends StatelessWidget {
  final ValueListenable<ChapterAvailabilityState> availabilityListenable;
  final Widget child;
  final String mangaTitle;

  const MangaAvailabilityCardWrapper({
    super.key,
    required this.availabilityListenable,
    required this.child,
    required this.mangaTitle,
  });

  static const ColorFilter _grayscaleFilter = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0,      0,      0,      1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChapterAvailabilityState>(
      valueListenable: availabilityListenable,
      builder: (context, state, _) {
        if (!state.isConfirmedZero) {
          return child;
        }

        // Zero capítulos confirmado: dessaturação + rótulo textual explícito (não depende só de cor)
        return Semantics(
          label: '$mangaTitle — Sem capítulos disponíveis',
          child: Stack(
            children: [
              Opacity(
                opacity: 0.62,
                child: ColorFiltered(
                  colorFilter: _grayscaleFilter,
                  child: child,
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.block_rounded,
                          size: 13,
                          color: Colors.white70,
                        ),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Sem capítulos',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
