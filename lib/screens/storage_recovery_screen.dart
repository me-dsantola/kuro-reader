import '../widgets/app_feedback.dart';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';

/// Never opens normal screens while their Hive boxes are unavailable.
class StorageRecoveryScreen extends StatefulWidget {
  final VoidCallback onRecovered;
  const StorageRecoveryScreen({super.key, required this.onRecovered});

  @override
  State<StorageRecoveryScreen> createState() => _StorageRecoveryScreenState();
}

class _StorageRecoveryScreenState extends State<StorageRecoveryScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await StorageService.init();
      if (mounted) widget.onRecovered();
    } catch (_) {
      if (mounted) {
        AppFeedback.show(
          context,
          const SnackBar(
            content: Text(
              'Não foi possível acessar os dados. Confira o espaço livre no aparelho e tente novamente.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storage_rounded, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Não foi possível abrir seus dados',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Seus dados não serão apagados. Libere espaço se necessário e tente novamente.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _retrying ? null : _retry,
                icon: const Icon(Icons.refresh),
                label: Text(
                  _retrying ? 'Tentando novamente…' : 'Tentar novamente',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
