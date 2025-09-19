// tunnel2_server.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'custom_event_emitter.dart';

class OnFromClient {
  final String requestId;
  final Uint8List data;
  OnFromClient({required this.requestId, required this.data});
}

class OnClose {
  final String requestId;
  final String reason;
  final int bytes;
  OnClose({required this.requestId, required this.reason, required this.bytes});
}

typedef LogFn = void Function(String msg);

class Tunnel2Server {
  final CustomEventEmitter emitter = CustomEventEmitter();

  // ===== server state =====
  late final InternetAddress _bind;
  final int port;
  final Duration idleTimeout;
  late final LogFn _log;

  ServerSocket? _server;

  // 🔑 clientId -> connection
  final Map<String, _Conn> _byClient = {};
  final Map<String, int> _onBytes = {};

  final Set<_Conn> _all = {};
  Timer? _pingTimer;

  // waiters per clientId (tanpa polling)
  final Map<String, List<Completer<bool>>> _waiters = {};

  Tunnel2Server({
    InternetAddress? bind,
    required this.port,
    this.idleTimeout = const Duration(minutes: 2),
    LogFn? log,
  }) {
    _bind = bind ?? InternetAddress.anyIPv4;
    _log = log ?? print;
  }

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    _server = await ServerSocket.bind(_bind, port);
    _log('[T2S] listening on ${_server!.address.address}:$port');

    _server!.listen(_accept, onError: (e) => _log('[T2S] server error: $e'));

    // PING tiap 30s + tendang koneksi idle (tanpa RX lama)
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final now = DateTime.now();
      for (final c in _all.toList()) {
        // tendang jika idle terlalu lama
        if (now.difference(c.lastSeen) > idleTimeout) {
          _log('[T2S] drop idle client ${c.clientId ?? c.hashCode}');
          await c.close();
          continue;
        }
        await c.sendJson({"type": "PING"});
      }
    });
  }

  Future<void> stop() async {
    _pingTimer?.cancel();
    _pingTimer = null;

    for (final c in _all.toList()) {
      await c.close();
    }
    _all.clear();
    _byClient.clear();
    _onBytes.clear();

    // fail semua waiter yang belum complete
    for (final list in _waiters.values) {
      for (final w in list) {
        if (!w.isCompleted) w.complete(false);
      }
    }
    _waiters.clear();

    await _server?.close();
    _server = null;
  }

  // ====== API buat “STOMP side” ======

  /// Tunggu sampai ClientTCP (dengan clientId) sudah HELLO dan terikat.
  Future<bool> waitClient(
    String clientId, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    if (_byClient.containsKey(clientId)) return Future.value(true);
    final c = Completer<bool>();
    final timers = <Timer>[];

    void complete(bool v) {
      if (!c.isCompleted) c.complete(v);
      for (final t in timers) {
        try {
          t.cancel();
        } catch (_) {}
      }
      _waiters[clientId]?.remove(c);
      if (_waiters[clientId]?.isEmpty ?? true) _waiters.remove(clientId);
    }

    final list = _waiters.putIfAbsent(clientId, () => <Completer<bool>>[]);
    list.add(c);
    timers.add(Timer(timeout, () => complete(false)));

    return c.future;
  }

  /// CONNECT (ClientHello untuk 1 request) ke clientId tertentu
  Future<bool> sendConnectTo({
    required String clientId,
    required String requestId,
    required String host,
    required int port,
    required Uint8List payload, // boleh kosong
  }) async {
    final c = _byClient[clientId];
    if (c == null) return false;
    _onBytes[requestId] = (_onBytes[requestId] ?? 0) + payload.length;
    await c.sendJson({
      "type": "CONNECT",
      "clientId": clientId,
      "requestId": requestId,
      "host": host,
      "port": port,
      "payload": base64.encode(payload),
    });
    return true;
  }

  /// Kirim data lanjutan untuk requestId tertentu
  Future<bool> sendRequestTo({
    required String clientId,
    required String requestId,
    required Uint8List payload,
  }) async {
    final c = _byClient[clientId];
    if (c == null) return false;
    _onBytes[requestId] = (_onBytes[requestId] ?? 0) + payload.length;
    await c.sendJson({
      "type": "REQUEST",
      "clientId": clientId,
      "requestId": requestId,
      "payload": base64.encode(payload),
    });
    return true;
  }

  void _accept(Socket s) {
    s.setOption(SocketOption.tcpNoDelay, true);

    late _Conn conn;
    conn = _Conn(
      s,
      log: _log,
      idleTimeout: idleTimeout,
      onControl: (msg) async {
        final type = (msg['type'] ?? msg['t']) as String?;
        switch (type) {
          case 'HELLO':
            {
              final clientId = (msg['clientId'] as String?)?.trim();
              if (clientId == null || clientId.isEmpty) {
                await conn.sendJson({
                  "type": "ACK",
                  "ok": false,
                  "err": "no clientId",
                });
                return;
              }
              conn.clientId = clientId;

              // rebind: putuskan koneksi lama
              final old = _byClient[clientId];
              if (old != null && old != conn) {
                await old.sendJson({
                  "type": "ACK",
                  "ok": false,
                  "err": "rebind",
                });
                await old.close();
              }
              _byClient[clientId] = conn;

              // bangunkan waiters
              final ws = _waiters.remove(clientId);
              if (ws != null) {
                for (final w in ws) {
                  if (!w.isCompleted) w.complete(true);
                }
              }
              await conn.sendJson({
                "type": "ACK",
                "ok": true,
                "clientId": clientId,
              });
              break;
            }

          case 'PONG':
          case 'PING':
            // liveness updated di _Conn._onBytes (lastSeen)
            break;

          case 'RESPONSE':
            {
              final req = (msg['requestId'] as String?)?.trim();
              final p64 = msg['payload'] as String?;
              if (req == null || p64 == null) return;
              try {
                final data = base64.decode(p64);
                _onBytes[req] = (_onBytes[req] ?? 0) + data.length;
                emitter.emit(
                  'RESPONSE',
                  this,
                  OnFromClient(requestId: req, data: Uint8List.fromList(data)),
                );
              } catch (_) {
                /* ignore */
              }
              break;
            }

          case 'CLOSE':
            {
              final rid = (msg['requestId'] as String?)?.trim();
              final reason = (msg['reason'] as String?) ?? '';
              int total = 0;
              final b = msg['bytes'];
              if (b is num) total = b.toInt();

              if (rid != null && rid.isNotEmpty) {
                final length = _onBytes.remove(rid); // cleanup counter di sini
                emitter.emit(
                  'CLOSE',
                  this,
                  OnClose(
                    requestId: rid,
                    reason: reason,
                    bytes: length ?? total,
                  ),
                );
              }
              break;
            }

          case 'ACK':
            // optional: log
            break;

          default:
            _log('[T2S] unknown control: $msg');
        }
      },
      onClose: (c) {
        _all.remove(c);
        if (c.clientId != null && _byClient[c.clientId!] == c) {
          _byClient.remove(c.clientId!);
        }
      },
    );

    _all.add(conn);
    conn.start();
  }
}

// ===== koneksi per-client =====

class _Conn {
  final Socket s;
  final LogFn log;
  final void Function(Map<String, dynamic> msg) onControl;
  final void Function(_Conn) onClose;
  final Duration idleTimeout;

  String? clientId;
  bool _closed = false;

  DateTime lastSeen = DateTime.now();

  final BytesBuilder _lineBuf = BytesBuilder();
  static const int _kMaxLine = 256 * 1024; // 256KB guard

  _Conn(
    this.s, {
    required this.log,
    required this.onControl,
    required this.onClose,
    required this.idleTimeout,
  });

  void start() {
    // gunakan stream timeout yang BALIKAN-nya dipakai:
    s
        .timeout(idleTimeout)
        .listen(
          _onBytes,
          onError: (e) {
            log('[T2S] conn error: $e');
            close();
          },
          onDone: () => close(),
          cancelOnError: true,
        );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      s.destroy();
    } catch (_) {}
    onClose(this);
  }

  Future<void> sendJson(Map<String, dynamic> obj) async {
    final line = '${jsonEncode(obj)}\n';
    s.add(utf8.encode(line));
    // await s.flush(); // optional, add() biasanya cukup
  }

  void _onBytes(List<int> chunk) {
    lastSeen = DateTime.now();

    // frame: newline-delimited JSON
    var data = Uint8List.fromList(chunk);
    while (data.isNotEmpty && !_closed) {
      final nl = data.indexOf(10); // '\n'
      if (nl != -1) {
        if (_lineBuf.length + nl > _kMaxLine) {
          log('[T2S] line too long');
          close();
          return;
        }
        _lineBuf.add(data.sublist(0, nl));
        data = data.sublist(nl + 1);

        final lineBytes = _lineBuf.toBytes();
        _lineBuf.clear();

        if (lineBytes.isEmpty) continue;
        String line;
        try {
          line = utf8.decode(lineBytes);
        } catch (e) {
          log('[T2S] bad utf8: $e');
          continue;
        }
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;

        try {
          final msg = jsonDecode(trimmed);
          if (msg is Map<String, dynamic>) {
            onControl(msg);
          } else {
            log('[T2S] unexpected json type: ${msg.runtimeType}');
          }
        } catch (e) {
          log('[T2S] bad json: $e');
        }
        continue;
      }

      // no newline, buffer-kan
      if (_lineBuf.length + data.length > _kMaxLine) {
        log('[T2S] line too long (partial)');
        close();
        return;
      }
      _lineBuf.add(data);
      data = Uint8List(0);
    }
  }
}
