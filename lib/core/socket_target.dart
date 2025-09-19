import 'dart:async';
import 'dart:typed_data';

import 'package:socket_client/socket_client.dart'; // asumsi: CustomSocket ada di sini
import '../utils/utils.dart';

class SocketTarget {
  final String host;
  final int port;

  final OnData onData;
  final OnError onError;
  final OnDone onDone;

  // Konfigurasi koneksi
  final Duration _timeout;
  final int _maxPendingItems;

  // (opsional) forward opsi ke CustomSocket.connect
  final ProxyMode proxyMode;
  final List<ProxyConfig> proxies;

  CustomSocket? _socket;
  StreamSubscription<Uint8List>? _sub;

  bool _connected = false;
  bool _connecting = false;
  Completer<bool>? _connectC;

  final List<Uint8List> _pending = <Uint8List>[];
  bool _flushing = false;

  bool get isConnected => _connected;
  bool get isConnecting => _connecting;
  int get pendingLength => _pending.length;

  SocketTarget({
    required this.host,
    required this.port,
    required this.onData,
    required this.onError,
    required this.onDone,
    Duration timeout = const Duration(seconds: 30),
    int maxPendingItems = 1000,

    // forward ke engine socket kamu (opsional)
    this.proxyMode = ProxyMode.NONE,
    this.proxies = const [],
  }) : _timeout = timeout,
       _maxPendingItems = maxPendingItems;

  /// Connect (idempotent). Mengembalikan true jika terkoneksi.
  Future<bool> connect() async {
    if (_connected && _socket != null) {
      if (_pending.isNotEmpty) await _flushPending();
      return true;
    }
    if (_connectC != null) return _connectC!.future;

    _connecting = true;
    final completer = _connectC = Completer<bool>();

    try {
      // Tutup resource lama kalau ada (kejaga-jaga)
      await _sub?.cancel();
      _sub = null;
      try {
        await _socket?.close();
      } catch (_) {}
      try {
        _socket?.destroy();
      } catch (_) {}

      // Koneksi baru
      _socket = await CustomSocket.connect(
        host,
        port,
        timeout: _timeout,
        proxyMode: proxyMode,
        proxies: proxies,
      );

      // Pasang listener ke socket
      _sub = _socket!.listen(
        (Uint8List data) => onData(data),
        onDone: () {
          _connected = false;
          onDone();
        },
        onError: (Object e, [StackTrace? st]) {
          _connected = false;
          onError(e, st ?? StackTrace.current);
        },
        cancelOnError: false,
      );

      _connected = true;

      // Flush antrian setelah connect
      await _flushPending();

      if (!completer.isCompleted) completer.complete(true);
      return true;
    } catch (e, st) {
      // Laporkan error
      onError(e, st);

      // Bersih-bersih minimal
      try {
        await _sub?.cancel();
      } catch (_) {}
      _sub = null;
      try {
        await _socket?.close();
      } catch (_) {}
      try {
        _socket?.destroy();
      } catch (_) {}
      _socket = null;
      _connected = false;

      if (!completer.isCompleted) completer.complete(false);
      return false;
    } finally {
      _connecting = false;
      // pastikan completer selesai
      if (!completer.isCompleted) completer.complete(false);
      _connectC = null;
    }
  }

  /// Tambah payload ke socket.
  /// Jika belum terkoneksi:
  ///  - antrikan payload,
  ///  - dan auto-connect (non-blocking). Set [awaitConnect]=true jika ingin menunggu.
  Future<void> add(Uint8List payload, {bool awaitConnect = false}) async {
    if (!_connected || _socket == null) {
      _enqueue(payload);
      if (!_connecting) {
        final fut = connect();
        if (awaitConnect) {
          // tunggu hasil connect (opsional)
          final ok = await fut;
          if (ok) await _flushPending();
        }
      }
      return;
    }

    try {
      _socket!.add(payload);
    } catch (e, st) {
      // Jika kirim gagal → antrikan kembali dan coba reconnect
      _enqueue(payload);
      onError(e, st);
      _connected = false;
      try {
        await _sub?.cancel();
      } catch (_) {}
      _sub = null;
      try {
        await _socket?.close();
      } catch (_) {}
      try {
        _socket?.destroy();
      } catch (_) {}
      _socket = null;

      if (!_connecting) {
        // non-blocking reconnect
        unawaited(connect());
      }
    }
  }

  /// Tutup koneksi. Secara default juga membersihkan antrian.
  Future<void> close({bool clearQueue = true}) async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      await _socket?.close();
    } catch (_) {}
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;

    _connected = false;
    _connecting = false;

    if (clearQueue) _pending.clear();
  }

  // ===== internals =====

  void _enqueue(Uint8List payload) {
    // Copy defensif, antisipasi caller reuse buffer
    final copy = Uint8List.fromList(payload);

    if (_pending.length >= _maxPendingItems) {
      // Drop paling lama (backpressure) + kabari
      _pending.removeAt(0);
      onError(
        StateError('[SOCKET] Pending queue penuh; item terlama dibuang'),
        StackTrace.current,
      );
    }
    _pending.add(copy);
  }

  Future<void> _flushPending() async {
    if (_flushing) return;
    if (!_connected || _socket == null) return;

    _flushing = true;
    try {
      while (_connected && _socket != null && _pending.isNotEmpty) {
        final data = _pending.first;
        _socket!.add(data);
        _pending.removeAt(0);
      }
    } catch (e, st) {
      // Gagal mengirim salah satu item → biarkan sisanya tetap di queue
      onError(StateError('[SOCKET] Flush pending gagal: $e'), st);
    } finally {
      _flushing = false;
    }
  }
}
