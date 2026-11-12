import 'dart:async';
import 'package:flutter/material.dart';

/// One dismissible, high-contrast popup, shared by every feature.
class AppFeedback {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    _entry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
  }

  static void message(BuildContext context, String message) =>
      show(context, SnackBar(content: Text(message)));

  static void show(BuildContext context, SnackBar notice) {
    if (!context.mounted) return;
    final overlay = Navigator.maybeOf(context, rootNavigator: true)?.overlay;
    if (overlay == null) return;
    dismiss();
    final theme = Theme.of(context);
    final text = notice.content is Text
        ? (notice.content as Text).data ?? ''
        : '';
    final error = RegExp(
      r'não foi|falha|erro|inválid|indisponível',
      caseSensitive: false,
    ).hasMatch(text);
    final color = error ? theme.colorScheme.error : theme.colorScheme.primary;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 12,
        left: 16,
        right: 16,
        child: _PopupCleanup(
          onDispose: () {
            if (identical(_entry, entry)) {
              _timer?.cancel();
              _timer = null;
              _entry = null;
            }
          },
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF19191F),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: color, width: 1.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        Icon(
                          error
                              ? Icons.error_outline_rounded
                              : Icons.info_outline_rounded,
                          color: color,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DefaultTextStyle(
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.4,
                            ),
                            child: notice.content,
                          ),
                        ),
                        if (notice.action != null)
                          TextButton(
                            onPressed: () {
                              dismiss();
                              notice.action!.onPressed();
                            },
                            child: Text(notice.action!.label),
                          ),
                        IconButton(
                          tooltip: 'Fechar aviso',
                          onPressed: dismiss,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white70,
                            size: 20,
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
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    _timer = Timer(const Duration(seconds: 6), dismiss);
  }
}

class _PopupCleanup extends StatefulWidget {
  final Widget child;
  final VoidCallback onDispose;
  const _PopupCleanup({required this.child, required this.onDispose});
  @override
  State<_PopupCleanup> createState() => _PopupCleanupState();
}

class _PopupCleanupState extends State<_PopupCleanup> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
