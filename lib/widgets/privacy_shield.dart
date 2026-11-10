import 'package:flutter/material.dart';

/// Placed above the Navigator so pushed routes receive the same protection.
class PrivacyShield extends StatefulWidget {
  final Widget child;
  const PrivacyShield({super.key, required this.child});

  @override
  State<PrivacyShield> createState() => _PrivacyShieldState();
}

class _PrivacyShieldState extends State<PrivacyShield>
    with WidgetsBindingObserver {
  bool _shielded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _shielded = state != null && state != AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final shielded = state != AppLifecycleState.resumed;
    if (_shielded != shielded) setState(() => _shielded = shielded);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ExcludeSemantics(
        excluding: _shielded,
        child: IgnorePointer(ignoring: _shielded, child: widget.child),
      ),
      if (_shielded)
        const Positioned.fill(
          child: Material(
            color: Color(0xFF070709),
            child: Center(child: Text('Proteção de Privacidade Ativa')),
          ),
        ),
    ],
  );
}
