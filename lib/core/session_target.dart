import 'dart:async';

/// onDispose dipanggil saat handler dihapus/di-clear.
/// Boleh async, dan boleh null (artinya tidak perlu dispose).
typedef DisposeFn<T> = FutureOr<void> Function(T handler);

class SessionTarget<E, T> {
  final DisposeFn<T>? onDispose;
  final bool disposeInParallel;
  final Duration? disposeTimeout;

  bool _isClearing = false;
  final Map<E, T> _sessions = <E, T>{};

  SessionTarget({
    required this.onDispose,
    this.disposeInParallel = false,
    this.disposeTimeout,
  });

  bool get isClearing => _isClearing;
  int get length => _sessions.length;
  Iterable<E> get keys => _sessions.keys;
  Iterable<T> get values => _sessions.values;
  Map<E, T> get asUnmodifiableMap => Map.unmodifiable(_sessions);

  /// Tambah session baru. Jika [replace] = false dan key sudah ada → throw.
  /// Return: handler lama jika tergantikan; null jika key baru.
  Future<T?> addSession(E session, T handler, {bool replace = true}) async {
    if (_isClearing) {
      throw StateError('Sedang clear(), tidak bisa addSession sekarang.');
    }
    if (!replace && _sessions.containsKey(session)) {
      throw StateError('Session sudah ada dan replace=false: $session');
    }
    final old = _sessions[session];
    _sessions[session] = handler;

    // Kalau ada handler lama dan replace=true → dispose lama
    if (old != null && onDispose != null) {
      await _safeDispose(old);
    }
    return old;
  }

  /// Upsert (tambahkan kalau belum ada; kalau ada, replace).
  Future<T?> upsert(E session, T handler) =>
      addSession(session, handler, replace: true);

  /// Replace hanya jika sudah ada, kalau belum ada → throw.
  Future<T> replace(E session, T handler) async {
    final old = _requireExisting(session);
    _sessions[session] = handler;
    if (onDispose != null) {
      await _safeDispose(old);
    }
    return old;
  }

  /// Hapus sebuah session. Return true jika ada yang dihapus.
  Future<bool> removeSession(E session, {bool dispose = true}) async {
    final handler = _sessions.remove(session);
    if (handler == null) return false;

    if (dispose && onDispose != null) {
      await _safeDispose(handler);
    }
    return true;
  }

  /// Hapus semua session yang memenuhi predicate.
  /// Return jumlah item yang dihapus.
  Future<int> removeWhere(
    bool Function(E key, T value) test, {
    bool dispose = true,
  }) async {
    final toRemove = <E>[];
    _sessions.forEach((k, v) {
      if (test(k, v)) toRemove.add(k);
    });

    int count = 0;
    if (dispose && onDispose != null) {
      // Dispose satu per satu (menghormati urutan)
      for (final k in toRemove) {
        final h = _sessions.remove(k);
        if (h != null) {
          await _safeDispose(h);
          count++;
        }
      }
    } else {
      for (final k in toRemove) {
        if (_sessions.remove(k) != null) count++;
      }
    }
    return count;
  }

  /// Hapus sekumpulan session.
  Future<void> removeAll(Iterable<E> sessions, {bool dispose = true}) async {
    for (final s in sessions) {
      await removeSession(s, dispose: dispose);
    }
  }

  /// Ambil handler; null jika tidak ada.
  T? getSession(E session) => _sessions[session];

  /// Ambil handler, atau lempar jika tidak ada.
  T _requireExisting(E session) {
    final h = _sessions[session];
    if (h == null) {
      throw StateError('Session tidak ditemukan: $session');
    }
    return h;
  }

  bool hasSession(E session) => _sessions.containsKey(session);

  /// Clear semua session. Jika [disposeInParallel] true, dispose dibikin paralel.
  Future<void> clear() async {
    if (_isClearing) return;
    _isClearing = true;
    try {
      if (_sessions.isEmpty || onDispose == null) {
        _sessions.clear();
        return;
      }

      final handlers = List<T>.from(_sessions.values);
      _sessions.clear();

      if (!disposeInParallel) {
        // Sequential (lebih aman untuk resource yang saling bergantung)
        for (final h in handlers) {
          await _safeDispose(h);
        }
      } else {
        // Parallel (cepat), tapi hati-hati jika ada shared resource
        final futures = handlers.map(_safeDispose).toList(growable: false);
        await Future.wait(futures, eagerError: false);
      }
    } finally {
      _isClearing = false;
    }
  }

  // ===== Internals =====

  Future<void> _safeDispose(T handler) async {
    if (onDispose == null) return;
    try {
      final res = onDispose!(handler);
      if (res is Future) {
        if (disposeTimeout == null) {
          await res;
        } else {
          await res.timeout(disposeTimeout!);
        }
      }
    } catch (_) {
      // sengaja ditelan; boleh diganti logging jika perlu
    }
  }
}
