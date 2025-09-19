import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:socket_client/socket_client.dart';

import '../../exc/stomp_exception.dart';
import 'parser.dart';
import '../socks_js/sock_js_parser.dart';
import 'stomp_config.dart';
import 'stomp_frame.dart';
import 'stomp_parser.dart';

typedef StompUnsubscribe =
    void Function({Map<String, String>? unsubscribeHeaders});

class StompHandler {
  final StompConfig config;

  late Parser _parser;
  CustomWebsocket? _channel;
  bool _connected = false;
  bool _isActive = false;
  int _currentReceiptIndex = 0;
  int _currentSubscriptionIndex = 0;
  DateTime _lastServerActivity = DateTime.now();

  final _receiptWatchers = <String, StompFrameCallback>{};
  final _subscriptionWatcher = <String, StompFrameCallback>{};

  Timer? _heartbeatSender;
  Timer? _heartbeatReceiver;

  bool get connected => _connected;

  StompHandler({required this.config}) {
    {
      if (config.useSockJS) {
        // use SockJS parser
        _parser = SockJSParser(
          onStompFrame: _onFrame,
          onPingFrame: _onPing,
          onDone: _onDone,
        );
      } else {
        _parser = StompParser(_onFrame, _onPing);
      }
    }
  }

  Future<void> start() async {
    _isActive = true;

    try {
      _channel = await CustomWebsocket.connect(
        config.wsUri,
        headers: config.buildWebSocketHeaders(),
        proxyMode: config.proxyMode,
        proxies: config.proxies,
        timeout: config.connectionTimeout,
      );

      if (!_isActive) {
        await _cleanUp();
      } else {
        _channel!.listen(_onWsData, onError: _onError, onDone: _onDone);
        _connectToStomp();
      }
    } catch (err) {
      _onError(err);
      _onDone(); // _onDone akan atur reconnect bila perlu
    }
  }

  Future<void> dispose() async {
    if (connected) {
      _disconnectFromStomp();
    } else {
      await _cleanUp();
    }
  }

  StompUnsubscribe subscribe({
    required String destination,
    required StompFrameCallback callback,
    Map<String, String>? headers,
  }) {
    Map<String, String> subscriptionHeaders = {};
    if (config.useSockJS) {
      subscriptionHeaders = {
        ...?headers,
        'destination': destination,
        //'ack': 'client',
      };
    } else {
      subscriptionHeaders = {
        ...?headers,
        'destination': destination,
        'ack': 'auto',
      };
    }

    if (!subscriptionHeaders.containsKey('id')) {
      subscriptionHeaders['id'] = 'sub-${_currentSubscriptionIndex++}';
    }

    _subscriptionWatcher[subscriptionHeaders['id']!] = callback;
    _transmit(command: 'SUBSCRIBE', headers: subscriptionHeaders);

    return ({Map<String, String>? unsubscribeHeaders}) {
      if (!connected) return;
      final headers = {...?unsubscribeHeaders};
      if (!headers.containsKey('id')) {
        headers['id'] = subscriptionHeaders['id']!;
      }
      _subscriptionWatcher.remove(headers['id']);

      _transmit(command: 'UNSUBSCRIBE', headers: headers);
    };
  }

  void send({
    required String destination,
    Map<String, String>? headers,
    String? body,
    Uint8List? binaryBody,
  }) {
    _transmit(
      command: 'SEND',
      body: body,
      binaryBody: binaryBody,
      headers: {'destination': destination, ...?headers},
    );
  }

  void ack({required String id, Map<String, String>? headers}) {
    _transmit(command: 'ACK', headers: {...?headers, 'id': id});
  }

  void nack({required String id, Map<String, String>? headers}) {
    _transmit(command: 'NACK', headers: {...?headers, 'id': id});
  }

  void watchForReceipt(String receiptId, StompFrameCallback callback) {
    _receiptWatchers[receiptId] = callback;
  }

  void _connectToStomp() {
    final connectHeaders = {
      'accept-version': config.useSockJS ? '1.2,1.1,1.0' : '1.1,1.2',
      'heart-beat':
          '${config.heartbeatOutgoing.inMilliseconds},${config.heartbeatIncoming.inMilliseconds}',
      ...?config.stompConnectHeaders,
    };

    _transmit(command: 'CONNECT', headers: connectHeaders);
  }

  void _disconnectFromStomp() {
    final disconnectHeaders = {
      'receipt': 'disconnect-${_currentReceiptIndex++}',
    };

    watchForReceipt(disconnectHeaders['receipt']!, (frame) async {
      await _cleanUp();
      config.onDisconnect(frame);
    });

    _transmit(command: 'DISCONNECT', headers: disconnectHeaders);
  }

  void _transmit({
    required String command,
    required Map<String, String> headers,
    String? body,
    Uint8List? binaryBody,
  }) {
    if (_channel == null) {
      throw StompBadStateException(
        'Tidak ada koneksi aktif untuk mengirim frame.',
      );
    }

    final frame = StompFrame(
      command: command,
      headers: headers,
      body: body,
      binaryBody: binaryBody,
    );

    final serializedFrame = _parser.serializeFrame(frame);
    config.onDebugMessage('>>> $serializedFrame');

    try {
      _channel!.add(serializedFrame);
    } catch (_) {
      throw StompBadStateException('Koneksi tertutup saat mengirim frame.');
    }
  }

  void _onError(dynamic error) {
    config.onWebSocketError(error);
  }

  Future<void> _onDone() async {
    config.onWebSocketDone();
    await _cleanUp();
  }

  // ganti _onData jadi menerima dynamic & normalize:
  void _onWsData(dynamic data) {
    _lastServerActivity = DateTime.now();

    if (config.useSockJS) {
      // SockJS: parser kamu biasanya expect STRING
      final text = (data is Uint8List)
          ? data
          : utf8.decode((data as List<int>), allowMalformed: true);
      config.onDebugMessage('<<< $text');
      _parser.parseData(
        text,
      ); // pastikan SockJSParser.parseData menerima String
      return;
    }

    // Native WebSocket STOMP:
    Uint8List bytes;
    if (data is String) {
      // sebagian broker kirim text frame; kita konversi ke bytes untuk parser
      bytes = Uint8List.fromList(utf8.encode(data));
    } else if (data is List<int>) {
      bytes = Uint8List.fromList(data);
    } else {
      // bentuk lain? log & abaikan
      config.onDebugMessage('<<< [unknown WS frame type: ${data.runtimeType}]');
      return;
    }

    // Log aman (tanpa merusak biner)
    final preview = utf8.decode(bytes, allowMalformed: true);
    config.onDebugMessage('<<< $preview');

    _parser.parseData(
      bytes,
    ); // pastikan StompParser.parseData menerima Uint8List
  }

  void _onFrame(StompFrame frame) {
    switch (frame.command) {
      case 'CONNECTED':
        _onConnectFrame(frame);
        break;
      case 'MESSAGE':
        _onMessageFrame(frame);
        break;
      case 'RECEIPT':
        _onReceiptFrame(frame);
        break;
      case 'ERROR':
        _onErrorFrame(frame);
        break;
      default:
        _onUnhandledFrame(frame);
    }
  }

  void _onPing() {
    config.onDebugMessage('<<< PING');
  }

  void _onConnectFrame(StompFrame frame) {
    _connected = true;

    if (frame.headers['version'] != '1.0') {
      _parser.escapeHeaders = true;
    } else {
      _parser.escapeHeaders = false;
    }

    if (frame.headers['version'] != '1.0' &&
        frame.headers.containsKey('heart-beat')) {
      _setupHeartbeat(frame);
    }

    config.onConnect(frame);
  }

  void _onMessageFrame(StompFrame frame) {
    final subscriptionId = frame.headers['subscription'];

    if (_subscriptionWatcher.containsKey(subscriptionId)) {
      _subscriptionWatcher[subscriptionId]!(frame);
    } else {
      config.onUnhandledMessage(frame);
    }
  }

  void _onReceiptFrame(StompFrame frame) {
    final receiptId = frame.headers['receipt-id'];
    if (_receiptWatchers.containsKey(receiptId)) {
      _receiptWatchers[receiptId]!(frame);
      _receiptWatchers.remove(receiptId);
    } else {
      config.onUnhandledReceipt(frame);
    }
  }

  void _onErrorFrame(StompFrame frame) {
    config.onStompError(frame);
  }

  void _onUnhandledFrame(StompFrame frame) {
    config.onUnhandledFrame(frame);
  }

  void _setupHeartbeat(StompFrame frame) {
    final serverHeartbeats = frame.headers['heart-beat']!.split(',');
    final serverOutgoing = int.parse(serverHeartbeats[0]);
    final serverIncoming = int.parse(serverHeartbeats[1]);

    if (config.heartbeatOutgoing.inMilliseconds > 0 && serverIncoming > 0) {
      final ttl = max(config.heartbeatOutgoing.inMilliseconds, serverIncoming);
      _heartbeatSender?.cancel();
      _heartbeatSender = Timer.periodic(Duration(milliseconds: ttl), (_) {
        config.onDebugMessage('>>> PING');
        if (config.useSockJS) {
          _channel?.add('["\\n"]'); // SockJS: array-of-strings
        } else {
          _channel?.add('\n'); // native WS
        }
      });
    }

    if (config.heartbeatIncoming.inMilliseconds > 0 && serverOutgoing > 0) {
      final ttl = max(config.heartbeatIncoming.inMilliseconds, serverOutgoing);
      _heartbeatReceiver?.cancel();
      _heartbeatReceiver = Timer.periodic(Duration(milliseconds: ttl), (_) {
        final deltaMs =
            DateTime.now().millisecondsSinceEpoch -
            _lastServerActivity.millisecondsSinceEpoch;
        // The connection might be dead. Clean up.
        if (deltaMs > (ttl * 2)) {
          _cleanUp();
        }
      });
    }
  }

  Future<void> _cleanUp() async {
    _connected = false;
    _isActive = false;
    _heartbeatSender?.cancel();
    _heartbeatReceiver?.cancel();

    try {
      await _channel?.close(1000, 'Bye');
    } catch (_) {}

    _channel = null;
  }
}
