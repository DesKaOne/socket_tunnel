import 'dart:math';

class SockJsUtils {
  static final SockJsUtils _instance = SockJsUtils._internal();
  factory SockJsUtils() => _instance;
  SockJsUtils._internal();

  // Prefer secure RNG (kalau gak tersedia di platform tertentu, ganti ke Random())
  final Random _rng = _trySecure() ?? Random();

  static Random? _trySecure() {
    try {
      return Random.secure();
    } catch (_) {
      return null;
    }
  }

  /// Bangun URL transport WebSocket untuk SockJS:
  ///  http(s)://host/base  ->  ws(s)://host/base/{serverId}/{sessionId}/websocket
  ///
  /// [serverId] default "000".."999" (3 digit).
  /// [sessionId] default 8 char [a-z0-9].
  /// [keepQuery] kalau true, pertahankan query string (default: false).
  String generateTransportUrl(
    String url, {
    String? serverId,
    String? sessionId,
    bool keepQuery = false,
  }) {
    var uri = Uri.parse(url);

    final sch = uri.scheme.toLowerCase();
    if (sch != 'http' && sch != 'https' && sch != 'ws' && sch != 'wss') {
      throw ArgumentError(
        'Skema harus http/https (atau ws/wss). Diterima: $sch',
      );
    }

    // Normalisasi skema target: http→ws, https→wss, ws→ws, wss→wss
    final targetScheme = (sch == 'https' || sch == 'wss') ? 'wss' : 'ws';

    // Ambil path segments yang ada
    final baseSegs = <String>[
      for (final s in uri.pathSegments)
        if (s.isNotEmpty) s,
    ];

    // Tambah segmen serverId / sessionId / websocket
    baseSegs.add(serverId ?? _generateServerId());
    baseSegs.add(sessionId ?? _generateSessionId());
    baseSegs.add('websocket');

    // Build Uri baru
    final built = uri.replace(
      scheme: targetScheme,
      // host & port tetap
      pathSegments: baseSegs,
      // SockJS umumnya gak butuh fragment; query opsional
      query: keepQuery ? uri.query : null,
      fragment: null,
    );

    return built.toString();
  }

  /// 000..999
  String _generateServerId() {
    final n = _rng.nextInt(1000); // 0..999
    if (n >= 100) return '$n';
    if (n >= 10) return '0$n';
    return '00$n';
  }

  /// 8 chars dari [a-z0-9]
  String _generateSessionId([int length = 8]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final sb = StringBuffer();
    for (var i = 0; i < length; i++) {
      sb.write(chars[_rng.nextInt(chars.length)]);
    }
    return sb.toString();
  }
}

void main() {
  // ignore: unused_local_variable
  final u = SockJsUtils().generateTransportUrl(
    'https://example.com/sockjs',
    // keepQuery: true,        // kalau mau pertahankan ?q=a
    // serverId: '123',        // bisa di-set manual
    // sessionId: 'abc123xy',  // bisa di-set manual
  );
  // -> wss://example.com/sockjs/123/abc123xy/websocket  (serverId & sessionId acak kalau gak diisi)
}
