import 'dart:collection';
import 'package:eventify/eventify.dart';

class CustomEventEmitter extends EventEmitter {
  /// Index listener per context (pakai identity supaya cocok untuk token Object()).
  final Map<Object?, Set<Listener>> _byContext = HashMap.identity();

  // ===================== Register =====================

  @override
  Listener on(String event, Object? context, EventCallback callback) {
    final l = super.on(event, context, callback);
    final set = _byContext.putIfAbsent(context, () => HashSet.identity());
    set.add(l);
    return l;
  }

  /// Versi `once` buatan sendiri (karena super tidak menyediakannya).
  /// Listener akan otomatis dilepas setelah callback dipanggil sekali.
  Listener once(String event, Object? context, EventCallback callback) {
    late Listener self;
    self = on(event, context, (ev, args) {
      try {
        callback(ev, args);
      } finally {
        off(self); // lepas diri sendiri
      }
    });
    return self;
  }

  /// Daftar beberapa event sekaligus.
  Iterable<Listener> onMany(
    Iterable<String> events,
    Object? context,
    EventCallback cb,
  ) => events.map((e) => on(e, context, cb));

  /// Daftar beberapa event sekali-aksi sekaligus.
  Iterable<Listener> onceMany(
    Iterable<String> events,
    Object? context,
    EventCallback cb,
  ) => events.map((e) => once(e, context, cb));

  // ===================== Unregister =====================

  @override
  void off(Listener? listener) {
    if (listener == null) return;

    // Bersihkan index kita dulu
    final ctx = listener.context;
    final set = _byContext[ctx];
    if (set != null) {
      set.remove(listener);
      if (set.isEmpty) _byContext.remove(ctx);
    }

    // Delegasikan ke super
    super.off(listener);
  }

  /// Copot semua listener yang didaftarkan dengan [context] ini.
  void removeAllByContext(Object? context) {
    final set = _byContext.remove(context);
    if (set == null) return;
    for (final l in set.toList()) {
      try {
        super.off(l);
      } catch (_) {}
    }
  }

  /// Copot listener untuk [event] tertentu + [context] ini.
  void removeByEventAndContext(String event, Object? context) {
    final set = _byContext[context];
    if (set == null) return;
    final target = set.where((l) => l.eventName == event).toList();
    for (final l in target) {
      try {
        super.off(l);
      } catch (_) {}
      set.remove(l);
    }
    if (set.isEmpty) _byContext.remove(context);
  }

  // ===================== Mass removal hooks =====================
  // (Tetap @override jika memang ada di EventEmitter versi kamu;
  //  kalau nggak ada, hapus @override.)

  @override
  void removeAllByEvent(String event) {
    super.removeAllByEvent(event);
    _byContext.removeWhere((_, set) {
      set.removeWhere((l) => l.eventName == event);
      return set.isEmpty;
    });
  }

  @override
  void removeAllByCallback(EventCallback callback) {
    super.removeAllByCallback(callback);
    _byContext.removeWhere((_, set) {
      set.removeWhere((l) => l.callback == callback);
      return set.isEmpty;
    });
  }

  @override
  void clear() {
    super.clear();
    _byContext.clear();
  }

  // ===================== Util =====================

  bool hasListenersFor(String event) {
    for (final set in _byContext.values) {
      if (set.any((l) => l.eventName == event)) return true;
    }
    return false;
  }

  int countForContext(Object? context) => (_byContext[context]?.length) ?? 0;
}
