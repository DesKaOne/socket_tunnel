import 'package:socket_client/socket_client.dart';

import '../socks_js/sock_js_utils.dart';
import 'stomp_frame.dart';

typedef StompFrameCallback = void Function(StompFrame);
typedef StompBeforeConnectCallback = Future<void> Function();
typedef StompDebugCallback = void Function(String);
typedef StompWebSocketErrorCallback = void Function(dynamic);
typedef StompWebSocketDoneCallback = void Function();

class StompConfig {
  // --- Endpoint ---
  final String url; // http(s)/ws(s) endpoint (tanpa /websocket untuk SockJS)
  final bool useSockJS; // kalau true, url akan diubah ke sockjs ws(s) path
  String? _connectUrl; // cache generated URL
  String get connectUrl =>
      _connectUrl ??= useSockJS ? SockJsUtils().generateTransportUrl(url) : url;

  /// Shortcut yang sudah di-parse
  Uri get wsUri => Uri.parse(connectUrl);

  // --- Proxy ---
  final bool useProxy;
  final ProxyMode proxyMode;
  final List<ProxyConfig> proxies;

  // --- WebSocket ---
  /// Header kustom saat handshake WebSocket (mis. User-Agent, Sec-WebSocket-Protocol)
  final Map<String, String>? webSocketConnectHeaders;

  /// Subprotocols yang akan dikirim kalau header ‘Sec-WebSocket-Protocol’ tidak disediakan.
  /// Urutan penting: server akan pilih pertama yang dia dukung.
  final List<String> subprotocols;

  // --- STOMP CONNECT ---
  final Map<String, String>? stompConnectHeaders;
  final String? login;
  final String? passcode;

  /// STOMP `host` header (virtual host). Default: host dari wsUri.
  final String? virtualHost;

  // --- Heartbeat & Reconnect ---
  final Duration heartbeatOutgoing; // client → server (ms)
  final Duration heartbeatIncoming; // server → client (ms)
  final Duration?
  pingInterval; // ping frame WS (opsional, beda dari STOMP heartbeat)
  final Duration reconnectDelay;
  final Duration connectionTimeout;

  // --- Hooks/Callbacks ---
  final StompBeforeConnectCallback beforeConnect;
  final StompFrameCallback onConnect;
  final StompFrameCallback onDisconnect;
  final StompFrameCallback onStompError;
  final StompFrameCallback onUnhandledFrame;
  final StompFrameCallback onUnhandledMessage;
  final StompFrameCallback onUnhandledReceipt;
  final StompWebSocketErrorCallback onWebSocketError;
  final StompWebSocketDoneCallback onWebSocketDone;
  final StompDebugCallback onDebugMessage;

  StompConfig({
    required this.url,
    this.useProxy = false,
    this.proxies = const [],
    this.proxyMode = ProxyMode.NONE,
    this.reconnectDelay = const Duration(seconds: 5),
    this.heartbeatIncoming = Duration.zero,
    this.heartbeatOutgoing = Duration.zero,
    this.pingInterval,
    this.connectionTimeout = const Duration(seconds: 15),
    this.stompConnectHeaders,
    this.webSocketConnectHeaders,
    this.beforeConnect = _noOpFuture,
    this.onConnect = _noOp,
    this.onStompError = _noOp,
    this.onDisconnect = _noOp,
    this.onUnhandledFrame = _noOp,
    this.onUnhandledMessage = _noOp,
    this.onUnhandledReceipt = _noOp,
    this.onWebSocketError = _noOp,
    this.onWebSocketDone = _noOp,
    this.onDebugMessage = _noOp,
    this.useSockJS = false,
    this.subprotocols = const ['v12.stomp', 'v11.stomp', 'v10.stomp'],
    this.login,
    this.passcode,
    this.virtualHost,
  });

  StompConfig.sockJS({
    required this.url,
    this.useProxy = false,
    this.proxies = const [],
    this.proxyMode = ProxyMode.NONE,
    this.reconnectDelay = const Duration(seconds: 5),
    this.heartbeatIncoming = Duration.zero,
    this.heartbeatOutgoing = Duration.zero,
    this.connectionTimeout = const Duration(seconds: 15),
    this.stompConnectHeaders,
    this.webSocketConnectHeaders,
    this.pingInterval,
    this.beforeConnect = _noOpFuture,
    this.onConnect = _noOp,
    this.onStompError = _noOp,
    this.onDisconnect = _noOp,
    this.onUnhandledFrame = _noOp,
    this.onUnhandledMessage = _noOp,
    this.onUnhandledReceipt = _noOp,
    this.onWebSocketError = _noOp,
    this.onWebSocketDone = _noOp,
    this.onDebugMessage = _noOp,
    this.subprotocols = const ['v12.stomp', 'v11.stomp', 'v10.stomp'],
    this.login,
    this.passcode,
    this.virtualHost,
  }) : useSockJS = true;

  /// Headers final untuk handshake WebSocket.
  /// - Kalau `webSocketConnectHeaders` tidak set `Sec-WebSocket-Protocol`, kita isi dari `subprotocols`.
  Map<String, String> buildWebSocketHeaders({
    List<String>? overrideSubprotocols,
  }) {
    final out = <String, String>{};
    if (webSocketConnectHeaders != null) {
      webSocketConnectHeaders!.forEach((k, v) {
        if (k.isNotEmpty) out[k] = v.toString();
      });
    }
    final hasProto = out.keys.any(
      (k) => k.toLowerCase() == 'sec-websocket-protocol',
    );
    if (!hasProto) {
      final protos = overrideSubprotocols ?? subprotocols;
      if (protos.isNotEmpty) {
        out['Sec-WebSocket-Protocol'] = protos.join(', ');
      }
    }
    return out;
  }

  StompConfig copyWith({
    String? url,
    bool? useProxy,
    List<ProxyConfig>? proxies,
    ProxyMode? proxyMode,
    Duration? reconnectDelay,
    Duration? heartbeatIncoming,
    Duration? heartbeatOutgoing,
    Duration? pingInterval,
    Duration? connectionTimeout,
    bool? useSockJS,
    Map<String, String>? stompConnectHeaders,
    Map<String, String>? webSocketConnectHeaders,
    StompBeforeConnectCallback? beforeConnect,
    StompFrameCallback? onConnect,
    StompFrameCallback? onStompError,
    StompFrameCallback? onDisconnect,
    StompFrameCallback? onUnhandledFrame,
    StompFrameCallback? onUnhandledMessage,
    StompFrameCallback? onUnhandledReceipt,
    StompWebSocketErrorCallback? onWebSocketError,
    StompWebSocketDoneCallback? onWebSocketDone,
    StompDebugCallback? onDebugMessage,
    List<String>? subprotocols,
    String? login,
    String? passcode,
    String? virtualHost,
    Duration? overallDeadline,
  }) {
    return StompConfig(
      url: url ?? this.url,
      useProxy: useProxy ?? this.useProxy,
      proxies: proxies ?? this.proxies,
      proxyMode: proxyMode ?? this.proxyMode,
      reconnectDelay: reconnectDelay ?? this.reconnectDelay,
      heartbeatIncoming: heartbeatIncoming ?? this.heartbeatIncoming,
      heartbeatOutgoing: heartbeatOutgoing ?? this.heartbeatOutgoing,
      pingInterval: pingInterval ?? this.pingInterval,
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      useSockJS: useSockJS ?? this.useSockJS,
      webSocketConnectHeaders:
          webSocketConnectHeaders ?? this.webSocketConnectHeaders,
      stompConnectHeaders: stompConnectHeaders ?? this.stompConnectHeaders,
      beforeConnect: beforeConnect ?? this.beforeConnect,
      onConnect: onConnect ?? this.onConnect,
      onStompError: onStompError ?? this.onStompError,
      onDisconnect: onDisconnect ?? this.onDisconnect,
      onUnhandledFrame: onUnhandledFrame ?? this.onUnhandledFrame,
      onUnhandledMessage: onUnhandledMessage ?? this.onUnhandledMessage,
      onUnhandledReceipt: onUnhandledReceipt ?? this.onUnhandledReceipt,
      onWebSocketError: onWebSocketError ?? this.onWebSocketError,
      onWebSocketDone: onWebSocketDone ?? this.onWebSocketDone,
      onDebugMessage: onDebugMessage ?? this.onDebugMessage,
      subprotocols: subprotocols ?? this.subprotocols,
      login: login ?? this.login,
      passcode: passcode ?? this.passcode,
      virtualHost: virtualHost ?? this.virtualHost,
    );
  }

  /// Reset SockJS session path (biar generate ulang /serverId/sessionId/)
  void resetSession() => _connectUrl = null;

  // no-ops
  static void _noOp([_, __]) {}
  static Future<void> _noOpFuture() => Future.value();
}
