import 'dart:async';
import 'dart:typed_data';

import 'package:http_client/http_client.dart';
import 'package:socket_client/custom_socket.dart';

import '../utils/utils.dart';
import 'address.dart';
import 'session.dart';
import 'session_target.dart';
import 'socket_target.dart';

class SessionSocket<E> {
  final CustomSocket socket; // upstream tempat kita forward data
  final SessionCallback onCallback; // dipanggil saat statistik berubah
  final OnError onError; // (Object, StackTrace?)
  final OnDone onDone;

  // simpan handler per-session
  final SessionTarget<E, SocketTarget> _sessionTarget =
      SessionTarget<E, SocketTarget>(
        onDispose: (handler) async => handler.close(),
      );

  // statistik per-session
  final Map<E, Session<E>> _stats = <E, Session<E>>{};

  SessionSocket({
    required this.socket,
    required this.onCallback,
    required this.onError,
    required this.onDone,
  });

  /// Pastikan sebuah session ada & terhubung.
  /// Kalau belum ada → buat SocketTarget + connect.
  Future<void> create({
    required E sessionId,
    required Address address,
    Duration timeout = const Duration(seconds: 30),
    int maxPendingItems = 1000,
    // forward opsi proxy ke SocketTarget kalau perlu (optional)
    ProxyMode proxyMode = ProxyMode.NONE,
    List<ProxyConfig> proxies = const [],
  }) async {
    // kalau sudah ada, cukup pastikan pending dikirim
    final existing = _sessionTarget.getSession(sessionId);
    if (existing != null && existing.isConnected) {
      return;
    }

    // siapkan statistik
    final stat = _stats.putIfAbsent(
      sessionId,
      () => Session<E>(session: sessionId),
    );

    // buat handler baru
    final handler = SocketTarget(
      host: address.host,
      port: address.port,
      onData: (Uint8List payload) {
        // terima dari downstream → forward ke upstream
        stat.downBytes += payload.length;
        _safeCallback(stat);
        socket.add(payload);
      },
      onError: (error, st) async {
        onError(error, st);
      },
      onDone: () async {
        // socket downstream selesai → cleanup entri
        await closeSession(sessionId);
        onDone();
      },
      timeout: timeout,
      maxPendingItems: maxPendingItems,
      proxyMode: proxyMode,
      proxies: proxies,
    );

    // simpan/replace handler lama (kalau ada)
    // ignore: unused_local_variable
    final old = await _sessionTarget.addSession(
      sessionId,
      handler,
      replace: true,
    );
    // (old kalau ada sudah didispose di onDispose SessionTarget)

    // connect
    final ok = await handler.connect();
    if (!ok) {
      onError(
        StateError('Session $sessionId gagal connect ke $address'),
        StackTrace.current,
      );
      // biar rapih, buang entri handler tadi
      await _sessionTarget.removeSession(sessionId);
      _stats.remove(sessionId);
      return;
    }
  }

  /// Kirim data ke downstream milik [sessionId].
  /// Jika belum ada handler & [addressIfAbsent] disediakan → autocreate lalu kirim.
  Future<void> write({
    required Uint8List payload,
    required E sessionId,
    Address? addressIfAbsent,
    bool awaitConnect = false,
  }) async {
    // statistik up
    final stat = _stats.putIfAbsent(
      sessionId,
      () => Session<E>(session: sessionId),
    );
    stat.upBytes += payload.length;
    _safeCallback(stat);

    var handler = _sessionTarget.getSession(sessionId);

    // belum ada? kalau ada alamat → buat
    if (handler == null) {
      if (addressIfAbsent == null) {
        onError(
          StateError(
            'Session $sessionId belum dibuat dan tidak ada addressIfAbsent',
          ),
          StackTrace.current,
        );
        return;
      }
      await create(sessionId: sessionId, address: addressIfAbsent);
      handler = _sessionTarget.getSession(sessionId);
    }

    if (handler == null) {
      onError(
        StateError('Gagal menyiapkan handler untuk $sessionId'),
        StackTrace.current,
      );
      return;
    }

    await handler.add(payload, awaitConnect: awaitConnect);
  }

  /// Tutup & hapus satu session.
  Future<void> closeSession(E sessionId) async {
    final h = _sessionTarget.getSession(sessionId);
    if (h != null) {
      try {
        await h.close();
      } catch (_) {}
      await _sessionTarget.removeSession(sessionId);
    }
    _stats.remove(sessionId);
  }

  /// Tutup semua session.
  Future<void> clear() async {
    // tutup semua handler terlebih dahulu
    final ids = List<E>.from(_sessionTarget.keys);
    for (final id in ids) {
      final h = _sessionTarget.getSession(id);
      if (h != null) {
        try {
          await h.close();
        } catch (_) {}
      }
    }
    await _sessionTarget.clear();
    _stats.clear();
  }

  // ================= internals =================

  void _safeCallback(Session<E> s) {
    try {
      final r = onCallback(s);
      if (r is Future) {
        // fire & forget
        unawaited(r);
      }
    } catch (_) {
      // jangan sampai callback mengganggu alur kirim data
    }
  }
}
