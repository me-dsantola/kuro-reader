import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import 'cloud_auth_service.dart';

const kuroSlots = ['aura', 'scarf', 'hat', 'floating'];
const emptyKuroEquipment = <String, String>{
  'aura': '',
  'scarf': '',
  'hat': '',
  'floating': '',
};

class KuroCatalog {
  final List<Map<String, dynamic>> items, events;
  KuroCatalog(Map<String, dynamic> source)
    : items = (source['items'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList(),
      events = (source['events'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  Map<String, dynamic>? item(String id) {
    for (final i in items) {
      if (i['id'] == id) return i;
    }
    return null;
  }

  bool available(String event, DateTime now) {
    if (event == 'always') return true;
    final definitions = events.where((e) => e['id'] == event);
    if (definitions.isEmpty) return false;
    final d = now.toUtc().subtract(const Duration(hours: 3)),
        day = d.month * 100 + d.day,
        e = definitions.first;
    final start = e['start'] as int, end = e['end'] as int;
    return start < end ? day >= start && day < end : day >= start || day < end;
  }

  Map<String, dynamic>? active(DateTime now, {String? override}) {
    final matches =
        events
            .where(
              (e) => override != null
                  ? e['id'] == override
                  : available(e['id'] as String, now),
            )
            .toList()
          ..sort(
            (a, b) => (b['priority'] as int).compareTo(a['priority'] as int),
          );
    return matches.isEmpty ? null : matches.first;
  }

  Map<String, String> sanitize(dynamic input, Set<String> owned) {
    final map = input is Map ? input : {};
    return {
      for (final slot in kuroSlots)
        slot:
            map[slot] is String &&
                owned.contains(map[slot]) &&
                item(map[slot] as String)?['category'] == slot
            ? map[slot] as String
            : '',
    };
  }
}

/// Grants live outside the editable profile/backup. Cached data is scoped by UID.
class KuroCosmeticsService extends ChangeNotifier {
  static final instance = KuroCosmeticsService();
  KuroCatalog? catalog;
  Set<String> owned = {};
  Map<String, String> equipment = Map.of(emptyKuroEquipment);
  String? uid, error;
  bool ready = true;
  bool _initialized = false;
  int _generation = 0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _items;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _state;
  Box<dynamic>? _cache;
  Timer? _calendar;
  Map<String, dynamic>? get season => catalog?.active(DateTime.now());
  Future<void> ensureCatalog() async {
    catalog ??= KuroCatalog(
      jsonDecode(await rootBundle.loadString('assets/mascot/cosmetics.json'))
          as Map<String, dynamic>,
    );
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await ensureCatalog();
    _cache = await Hive.openBox<dynamic>('kuro_cosmetics_cache');
    CloudAuthService.currentUser.addListener(_accountChanged);
    _calendar = Timer.periodic(
      const Duration(minutes: 1),
      (_) => notifyListeners(),
    );
    _accountChanged();
  }

  void _accountChanged() {
    unawaited(bindAccount(CloudAuthService.currentUser.value?.uid));
  }

  Future<void> bindAccount(String? next) async {
    final generation = ++_generation;
    uid = next;
    owned = {};
    equipment = Map.of(emptyKuroEquipment);
    error = null;
    ready = next == null;
    notifyListeners();
    final previousItems = _items, previousState = _state;
    _items = null;
    _state = null;
    await Future.wait([
      previousItems?.cancel() ?? Future<void>.value(),
      previousState?.cancel() ?? Future<void>.value(),
    ]);
    if (generation != _generation) return;
    uid = next;
    owned = {};
    equipment = Map.of(emptyKuroEquipment);
    error = null;
    ready = next == null;
    if (next == null) {
      notifyListeners();
      return;
    }
    final cached = _cache?.get(next);
    if (cached is Map && catalog != null) {
      owned = Set<String>.from((cached['owned'] as List?) ?? []);
      equipment = catalog!.sanitize(cached['equipment'], owned);
    }
    notifyListeners();
    if (!CloudAuthService.isFirebaseAvailable.value) {
      error = 'Entre na conta para sincronizar o guarda-roupa.';
      ready = true;
      notifyListeners();
      return;
    }
    final db = FirebaseFirestore.instance;
    dynamic rawEquipment = {};
    bool gotItems = false, gotState = false;
    void update() {
      if (generation != _generation || catalog == null) return;
      equipment = catalog!.sanitize(rawEquipment, owned);
      ready = gotItems && gotState;
      error = null;
      unawaited(
        _cache?.put(next, {'owned': owned.toList(), 'equipment': equipment}) ??
            Future<void>.value(),
      );
      notifyListeners();
    }

    void fail(Object e) {
      if (generation != _generation) return;
      error = 'Não foi possível sincronizar o guarda-roupa. Confira a conexão.';
      ready = true;
      notifyListeners();
    }

    _items = db
        .collection('kuroUsers')
        .doc(next)
        .collection('items')
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
          if (generation != _generation || snap.metadata.hasPendingWrites) {
            return;
          }
          owned = snap.docs
              .map((d) => d.id)
              .where((id) => catalog?.item(id) != null)
              .toSet();
          gotItems = true;
          update();
        }, onError: fail);
    _state = db
        .collection('kuroUsers')
        .doc(next)
        .collection('state')
        .doc('equipment')
        .snapshots(includeMetadataChanges: true)
        .listen((snap) {
          if (generation != _generation || snap.metadata.hasPendingWrites) {
            return;
          }
          rawEquipment = snap.data() ?? {};
          gotState = true;
          update();
        }, onError: fail);
  }

  Future<void> claim(String id) async {
    final account = uid;
    if (account == null) throw StateError('Entre na sua conta para resgatar.');
    if (catalog?.item(id) == null) throw StateError('Item desconhecido.');
    final ref = FirebaseFirestore.instance
        .collection('kuroUsers')
        .doc(account)
        .collection('items')
        .doc(id);
    await FirebaseFirestore.instance
        .runTransaction((tx) async {
          final snap = await tx.get(ref);
          if (!snap.exists) {
            tx.set(ref, {
              'itemId': id,
              'claimedAt': FieldValue.serverTimestamp(),
            });
          }
        })
        .timeout(const Duration(seconds: 15));
  }

  Future<void> save(Map<String, String> value) async {
    final account = uid;
    if (account == null) throw StateError('Entre na sua conta para salvar.');
    final safe = catalog!.sanitize(value, owned);
    if (!mapEquals(safe, value)) {
      throw StateError('Resgate o item antes de equipar.');
    }
    await FirebaseFirestore.instance
        .collection('kuroUsers')
        .doc(account)
        .collection('state')
        .doc('equipment')
        .set({...safe, 'updatedAt': FieldValue.serverTimestamp()})
        .timeout(const Duration(seconds: 15));
  }

  @override
  void dispose() {
    _calendar?.cancel();
    unawaited(_items?.cancel() ?? Future<void>.value());
    unawaited(_state?.cancel() ?? Future<void>.value());
    CloudAuthService.currentUser.removeListener(_accountChanged);
    super.dispose();
  }
}
