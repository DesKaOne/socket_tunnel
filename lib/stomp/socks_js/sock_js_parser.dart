import 'dart:convert';
import 'dart:typed_data';

import 'package:http_client/ext/bytes_ext.dart';

import '../component/parser.dart';
import '../component/stomp_frame.dart';
import '../component/stomp_parser.dart';

class SockJSParser implements Parser {
  SockJSParser({
    required Function(StompFrame) onStompFrame,
    required this.onDone,
    this.onPingFrame,
    this.maxFrameBytes = 8 * 1024 * 1024, // 8 MB guard
  }) {
    _stompParser = StompParser(onStompFrame, onPingFrame);
  }

  late final StompParser _stompParser;
  final void Function() onDone;
  final StompPingFrameCallback? onPingFrame;

  /// Guard ukuran maksimal pesan (set 0 untuk menonaktifkan).
  final int maxFrameBytes;

  @override
  bool get escapeHeaders => _stompParser.escapeHeaders;

  @override
  set escapeHeaders(bool v) => _stompParser.escapeHeaders = v;

  @override
  void parseData(dynamic data) {
    // SockJS WS transport: TEXT; tetap toleran untuk bytes.
    final Uint8List byteList = switch (data) {
      String s => s.toUtf8Bytes,
      Uint8List u => u,
      List<int> l => l.asUint8View,
      _ => throw UnsupportedError(
        'Input data type unsupported ${data.runtimeType}',
      ),
    };

    if (byteList.isEmpty) return;
    if (maxFrameBytes > 0 && byteList.length > maxFrameBytes) {
      // drop silently atau lempar — di sini kita drop saja.
      return;
    }

    final msg = utf8.decode(byteList, allowMalformed: true);
    if (msg.isEmpty) return;

    final type = msg[0];
    final content = msg.length > 1 ? msg.substring(1) : '';

    // Frame tanpa payload
    switch (type) {
      case 'o': // Open
        return;
      case 'h': // Heartbeat
        onPingFrame?.call();
        return;
      case 'n': // No-op (kadang dipakai pada transport lain; safe to ignore)
        return;
    }

    if (content.isEmpty) return;

    dynamic payload;
    try {
      payload = json.decode(content);
    } catch (_) {
      return; // payload bukan JSON valid → abaikan
    }

    switch (type) {
      case 'a': // array of messages
        if (payload is List) {
          for (final item in payload) {
            if (item is String) {
              _stompParser.parseData(item);
            }
          }
        }
        break;

      case 'm': // single message
        if (payload is String) {
          _stompParser.parseData(payload);
        }
        break;

      case 'c': // close frame: payload = [code, reason]
        // (opsional) bisa di-log kalau perlu:
        // if (payload is List && payload.length >= 2) {
        //   final code = payload[0];
        //   final reason = payload[1];
        //   // log('$code $reason');
        // }
        onDone();
        break;

      default:
        // tipe lain: abaikan
        break;
    }
  }

  @override
  dynamic serializeFrame(StompFrame frame) {
    // SockJS WS hanya dukung TEXT. Jangan kirim biner mentah.
    if (frame.binaryBody != null) {
      throw UnsupportedError(
        'SockJS transport hanya mendukung frame teks; binaryBody tidak didukung. '
        'Gunakan WS native atau encode (mis. base64) dengan dukungan server.',
      );
    }

    final dynamic stompWire = _stompParser.serializeFrame(frame);
    if (stompWire is! String) {
      throw StateError('STOMP serializer tidak menghasilkan String.');
    }

    return _encapsulateFrame(stompWire);
  }

  String _encapsulateFrame(String frame) {
    // Client → Server SockJS: kirim JSON array of strings
    // Contoh: ["CONNECT\naccept-version:1.2\n\n\u0000"]
    final payload = json.encode(frame);
    return '[$payload]';
  }
}
