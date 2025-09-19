import 'dart:async';
import 'dart:typed_data';

import '../exc/stomp_exception.dart';
import 'component/stomp_config.dart';
import 'component/stomp_handler.dart';

class StompClientV2 {
  final StompConfig config;

  StompHandler? _handler;
  bool _isActive = false;

  bool get connected => _handler?.connected ?? false;
  bool get isActive => _isActive;

  // ====== Offline SEND queue ======
  final int maxPendingSends;
  final Duration pendingTtl;
  final List<_PendingSend> _pending = [];

  // simpan subscriptions buat replay saat reconnect
  final List<_SavedSub> _savedSubs = [];

  StompClientV2({
    required this.config,
    this.maxPendingSends = 200, // batas antrean
    this.pendingTtl = const Duration(minutes: 5), // TTL pesan
  });

  Future<void> activate() async {
    if (_isActive && connected) {
      config.onDebugMessage('[STOMP] Already active & connected.');
      return;
    }
    _isActive = true;
    await _connect();
  }

  Future<void> deactivate() async {
    _isActive = false;
    await _handler?.dispose();
    _handler = null;
    _pending.clear(); // bersihkan antrean saat user minta stop
  }

  Future<void> _connect() async {
    if (connected) {
      config.onDebugMessage('[STOMP] Already connected. Nothing to do!');
      return;
    }

    await config.beforeConnect();

    if (!_isActive) {
      config.onDebugMessage('[STOMP] Client was marked as inactive. Skip!');
      return;
    }

    _handler = StompHandler(
      config: config.copyWith(
        onConnect: (frame) {
          if (!_isActive) {
            config.onDebugMessage(
              '[STOMP] Connected while deactivated. Will disconnect.',
            );
            _handler?.dispose();
            return;
          }

          // callback user dulu (biar dia tau connect)
          config.onConnect(frame);

          // replay semua subscription
          for (final s in _savedSubs) {
            try {
              _handler?.subscribe(
                destination: s.destination,
                callback: s.callback,
                headers: s.headers,
              );
            } catch (_) {
              /* lanjut */
            }
          }

          // terakhir: flush pending SEND (setelah SUBSCRIBE siap)
          _flushPendingSends();
        },
        onWebSocketDone: () {
          // reconnect diurus Handler (sesuai revisi sebelumnya)
          config.onWebSocketDone();
        },
      ),
    );

    await _handler!.start();
  }

  StompUnsubscribe subscribe({
    required String destination,
    required StompFrameCallback callback,
    Map<String, String>? headers,
  }) {
    final handler = _handler;
    if (handler == null) {
      throw StompBadStateException(
        'The StompHandler was null. '
        'Did you forget calling activate() on the client?',
      );
    }

    final unsub = handler.subscribe(
      destination: destination,
      callback: callback,
      headers: headers,
    );

    // simpan agar bisa auto re-subscribe setelah reconnect
    _savedSubs.add(_SavedSub(destination, callback, headers));

    // bungkus unsubscribe: hapus dari daftar simpanan
    return ({Map<String, String>? unsubscribeHeaders}) {
      _savedSubs.removeWhere(
        (s) =>
            s.destination == destination &&
            identical(s.callback, callback) &&
            _mapEquals(s.headers, headers),
      );
      unsub(unsubscribeHeaders: unsubscribeHeaders);
    };
  }

  void send({
    required String destination,
    Map<String, String>? headers,
    String? body,
    Uint8List? binaryBody,
    bool queueIfDisconnected = true, // default: antrikan saat offline
  }) {
    final handler = _handler;
    if (handler == null || !connected) {
      if (!queueIfDisconnected) {
        throw StompBadStateException(
          'No active connection and queueIfDisconnected=false.',
        );
      }
      _enqueueSend(destination, headers, body, binaryBody);
      return;
    }

    handler.send(
      destination: destination,
      headers: headers,
      body: body,
      binaryBody: binaryBody,
    );
  }

  void ack({required String id, Map<String, String>? headers}) {
    final handler = _handler;
    if (handler == null) {
      throw StompBadStateException(
        'The StompHandler was null. '
        'Did you forget calling activate() on the client?',
      );
    }
    handler.ack(id: id, headers: headers);
  }

  void nack({required String id, Map<String, String>? headers}) {
    final handler = _handler;
    if (handler == null) {
      throw StompBadStateException(
        'The StompHandler was null. '
        'Did you forget calling activate() on the client?',
      );
    }
    handler.nack(id: id, headers: headers);
  }

  // ====== Pending SEND helpers ======

  void _enqueueSend(
    String destination,
    Map<String, String>? headers,
    String? body,
    Uint8List? binaryBody,
  ) {
    // purge expired dulu
    final now = DateTime.now();
    _pending.removeWhere((p) => now.difference(p.enqueuedAt) > pendingTtl);

    // jaga ukuran antrean
    if (_pending.length >= maxPendingSends) {
      // drop paling lama
      final dropped = _pending.removeAt(0);
      config.onDebugMessage(
        '[STOMP] Pending queue full. Dropping oldest to enqueue new. '
        'dropped=${dropped.destination}',
      );
    }

    _pending.add(
      _PendingSend(
        destination: destination,
        headers: headers,
        body: body,
        binaryBody: binaryBody,
        enqueuedAt: now,
      ),
    );

    config.onDebugMessage(
      '[STOMP] Queued SEND offline: $destination (q=${_pending.length})',
    );
  }

  void _flushPendingSends() {
    if (!connected || _pending.isEmpty) return;

    final now = DateTime.now();
    final toSend = <_PendingSend>[];

    // ambil yang belum kedaluwarsa (preserve order)
    for (final p in _pending) {
      if (now.difference(p.enqueuedAt) <= pendingTtl) {
        toSend.add(p);
      }
    }

    // kirim berurutan
    for (final p in toSend) {
      try {
        _handler!.send(
          destination: p.destination,
          headers: p.headers,
          body: p.body,
          binaryBody: p.binaryBody,
        );
      } catch (e) {
        // kalau gagal, berhenti flush supaya urutan tetap
        config.onDebugMessage('[STOMP] Flush SEND failed: $e');
        break;
      }
      // sukses → hapus dari antrean
      _pending.remove(p);
    }

    if (_pending.isNotEmpty) {
      config.onDebugMessage(
        '[STOMP] Pending left in queue: ${_pending.length}',
      );
    }
  }
}

class _SavedSub {
  final String destination;
  final StompFrameCallback callback;
  final Map<String, String>? headers;
  _SavedSub(this.destination, this.callback, this.headers);
}

class _PendingSend {
  final String destination;
  final Map<String, String>? headers;
  final String? body;
  final Uint8List? binaryBody;
  final DateTime enqueuedAt;
  _PendingSend({
    required this.destination,
    required this.headers,
    required this.body,
    required this.binaryBody,
    required this.enqueuedAt,
  });
}

bool _mapEquals(Map<String, String>? a, Map<String, String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
