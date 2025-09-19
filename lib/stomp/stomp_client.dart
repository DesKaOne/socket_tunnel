import 'dart:async';
import 'dart:typed_data';

import '../exc/stomp_exception.dart';
import 'component/stomp_config.dart';
import 'component/stomp_handler.dart';

class StompClient {
  final StompConfig config;

  StompHandler? _handler;
  bool _isActive = false;
  Timer? _reconnectTimer;

  bool get connected => _handler?.connected ?? false;
  bool get isActive => _isActive;

  StompClient({required this.config});

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
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _handler?.dispose();
    _handler = null;
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
              '[STOMP] Client connected while deactivated. Will disconnect.',
            );
            _handler?.dispose();
            return;
          }

          // panggil callback user
          config.onConnect(frame);
        },
        onWebSocketDone: () {
          // handler yang urus reconnect; kita forward event ke user saja
          config.onWebSocketDone();
          if (_isActive) {
            _scheduleReconnect();
          }
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

    return handler.subscribe(
      destination: destination,
      callback: callback,
      headers: headers,
    );
  }

  void send({
    required String destination,
    Map<String, String>? headers,
    String? body,
    Uint8List? binaryBody,
  }) {
    final handler = _handler;
    if (handler == null) {
      throw StompBadStateException(
        'The StompHandler was null. '
        'Did you forget calling activate() on the client?',
      );
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

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (config.reconnectDelay.inMilliseconds > 0) {
      _reconnectTimer = Timer(
        config.reconnectDelay,
        () async => await _connect(),
      );
    }
  }
}
