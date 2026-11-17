import 'package:flutter/material.dart';
import '../services/kuro_cosmetics_service.dart';
import '../services/cloud_auth_service.dart';
import '../widgets/yomi_bloub_companion.dart';
import '../widgets/kuro_accessories.dart';

class KuroWardrobeScreen extends StatefulWidget {
  const KuroWardrobeScreen({super.key});
  @override
  State<KuroWardrobeScreen> createState() => _KuroWardrobeScreenState();
}

class _KuroWardrobeScreenState extends State<KuroWardrobeScreen> {
  final store = KuroCosmeticsService.instance;
  bool preview = false, busy = false, orbit = false;
  String? eventOverride, _account;
  String notice = '';
  int _request = 0;
  Map<String, String> draft = Map.of(emptyKuroEquipment);
  @override
  void initState() {
    super.initState();
    _account = store.uid;
    store.addListener(_changed);
    store.ensureCatalog().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _changed() {
    if (!mounted) return;
    setState(() {
      if (_account != store.uid) {
        _account = store.uid;
        preview = false;
        draft = Map.of(emptyKuroEquipment);
        eventOverride = null;
        _request++;
        busy = false;
        notice = '';
      }
    });
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    final request = ++_request;
    setState(() {
      busy = true;
      notice = '';
    });
    try {
      await action();
      if (mounted && request == _request) {
        setState(() => notice = 'Guarda-roupa atualizado.');
      }
    } catch (_) {
      if (mounted && request == _request) {
        setState(
          () => notice =
              'Não foi possível confirmar. Confira a conexão, a conta e o período do evento.',
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = store.catalog;
    if (catalog == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Guarda-roupa do Kuro')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final owned = preview
        ? catalog.items.map((i) => i['id'] as String).toSet()
        : store.owned;
    final equipment = preview ? draft : store.equipment;
    final event = catalog.active(
      DateTime.now(),
      override: preview ? eventOverride : null,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Guarda-roupa do Kuro')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: YomiBloubCompanion(
              key: ValueKey(orbit),
              size: 250,
              context: orbit ? BloubContext.profile : BloubContext.reader,
              equipment: equipment,
              interactive: false,
            ),
          ),
          Text(
            event == null
                ? 'Um bom dia para novas histórias.'
                : 'Temporada: ${event['name']}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Os itens resgatados continuam na sua conta depois que o evento termina.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
          TextButton(
            onPressed: () => setState(() => orbit = !orbit),
            child: Text(
              orbit ? 'Voltar ao descanso' : 'Testar órbita e acessórios',
            ),
          ),
          OutlinedButton(
            onPressed: () => setState(() {
              preview = !preview;
              draft = Map.of(store.equipment);
              eventOverride = null;
            }),
            child: Text(
              preview
                  ? 'Sair da experimentação'
                  : 'Experimentar todos os itens sem salvar',
            ),
          ),
          if (preview) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: eventOverride ?? 'auto',
              decoration: const InputDecoration(labelText: 'Simular temporada'),
              items: [
                const DropdownMenuItem(
                  value: 'auto',
                  child: Text('Data atual'),
                ),
                const DropdownMenuItem(
                  value: 'none',
                  child: Text('Sem evento'),
                ),
                ...catalog.events.map(
                  (e) => DropdownMenuItem(
                    value: e['id'] as String,
                    child: Text(e['name'] as String),
                  ),
                ),
              ],
              onChanged: (v) =>
                  setState(() => eventOverride = v == 'auto' ? null : v),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'A simulação não concede recompensas nem altera a data de resgate.',
                style: TextStyle(fontSize: 12, color: Colors.white60),
              ),
            ),
          ],
          if (store.uid == null && !preview)
            TextButton(
              onPressed: () => run(() async {
                await CloudAuthService.signInWithGoogle();
              }),
              child: const Text('Entrar para resgatar e salvar'),
            ),
          if (notice.isNotEmpty || store.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                notice.isNotEmpty ? notice : store.error!,
                style: const TextStyle(color: Colors.amberAccent),
              ),
            ),
          for (final slot in kuroSlots) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    {
                      'aura': 'Auras',
                      'scarf': 'Cachecóis',
                      'hat': 'Gorros e chapéus',
                      'floating': 'Objetos flutuantes',
                    }[slot]!,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          final next = {...equipment, slot: ''};
                          if (preview) {
                            setState(() => draft = next);
                          } else {
                            run(() => store.save(next));
                          }
                        },
                  child: const Text('Desequipar'),
                ),
              ],
            ),
            for (final item in catalog.items.where(
              (i) => i['category'] == slot,
            ))
              Builder(
                builder: (context) {
                  final id = item['id'] as String,
                      has = owned.contains(id),
                      available = catalog.available(
                        item['event'] as String,
                        DateTime.now(),
                      ),
                      equipped = equipment[slot] == id;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(height: 3, color: kuroItemColor(item)),
                          const SizedBox(height: 10),
                          Text(item['name'] as String),
                          Text(
                            has
                                ? 'No seu guarda-roupa'
                                : available
                                ? 'Resgate disponível'
                                : 'Aguarde a temporada',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white60,
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed:
                                  busy ||
                                      equipped ||
                                      (!has && !available) ||
                                      (!preview && !store.ready)
                                  ? null
                                  : () {
                                      if (has) {
                                        final next = {...equipment, slot: id};
                                        if (preview) {
                                          setState(() => draft = next);
                                        } else {
                                          run(() => store.save(next));
                                        }
                                      } else if (store.uid == null) {
                                        run(() async {
                                          await CloudAuthService.signInWithGoogle();
                                        });
                                      } else {
                                        run(() => store.claim(id));
                                      }
                                    },
                              child: Text(
                                equipped
                                    ? 'Equipado'
                                    : has
                                    ? 'Vestir'
                                    : available
                                    ? 'Resgatar'
                                    : 'Indisponível',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ],
      ),
    );
  }
}
