import 'dart:convert';
import 'dart:typed_data';

import 'package:http_client/ext/bytes_ext.dart';

typedef StompPingFrameCallback = void Function();

class StompFrame {
  final String command;
  final Map<String, String> headers;
  final String? body; // kalau text
  final Uint8List? binaryBody; // kalau binary

  StompFrame({
    required this.command,
    this.headers = const {},
    this.body,
    this.binaryBody,
  }) : assert(
         body == null || binaryBody == null,
         'Pakai salah satu: body (text) ATAU binaryBody (bytes)',
       );

  factory StompFrame.fromText(
    String command, {
    Map<String, String> headers = const {},
    String body = '',
  }) => StompFrame(command: command, headers: headers, body: body);

  factory StompFrame.fromBinary(
    String command, {
    Map<String, String> headers = const {},
    required Uint8List body,
  }) => StompFrame(command: command, headers: headers, binaryBody: body);

  Map<String, dynamic> toJson() => {
    'command': command,
    'headers': headers,
    'body': body,
    'binaryBody': binaryBody,
  };

  /// Simpan sebagai JSON (binary di-hex)
  String toSave() => jsonEncode({
    'command': command,
    'headers': headers,
    'body': body,
    'binaryBody': binaryBody?.hex(),
  });

  @override
  String toString() => jsonEncode(toJson());

  /// Encode ke wire STOMP: COMMAND\n headers...\n\n body \0
  Uint8List toBytes() {
    final sb = StringBuffer()..writeln(command);

    // Escape header STOMP 1.2
    headers.forEach((k, v) {
      sb.writeln('${_escapeHdr(k)}:${_escapeHdr(v)}');
    });

    sb.writeln(); // header-body separator (CRLF optional di spec, \n cukup)

    Uint8List bodyBytes = BytesExt.fromInt(0);
    final mapLower = {
      for (final e in headers.entries) e.key.toLowerCase(): e.value,
    };

    if (binaryBody != null) {
      bodyBytes = binaryBody!;
      // wajib content-length untuk binary agar tidak ambigu dengan \0 di payload
      if (!mapLower.containsKey('content-length')) {
        sb.write(
          '',
        ); // header sudah selesai; content-length harus di header sebelumnya
        // NOTE: kalau mau enforce, bisa throw bila header belum diset.
      }
    } else if (body != null) {
      bodyBytes = body!.toUtf8Bytes;
    }

    // Jika header sudah mencantumkan content-length, hormati; kalau tidak & binaryBody ada, lebih aman set di luar (opsional).
    // ignore: unused_local_variable
    final hasContentLength = mapLower.containsKey('content-length');
    final headStr = sb.toString();
    final headBytes = headStr.toUtf8Bytes;

    // Rakit frame: head + body + NUL
    final totalLen = headBytes.length + bodyBytes.length + 1;
    final out = Uint8List(totalLen);
    out.setRange(0, headBytes.length, headBytes);
    out.setRange(
      headBytes.length,
      headBytes.length + bodyBytes.length,
      bodyBytes,
    );
    out[totalLen - 1] = 0x00; // NUL terminator

    // Catatan: spes STOMP 1.2 membolehkan pakai content-length (octet count) → kita tidak menambahkan \0 di tengah body.
    // NUL tetap dipakai sebagai terminator frame, bukan bagian body.

    return out;
  }

  // ==== STOMP 1.2 header escaping ====
  // Escape: \n => \\n, : => \\c, \ => \\\\
  String _escapeHdr(String s) =>
      s.replaceAll('\\', r'\\').replaceAll('\n', r'\n').replaceAll(':', r'\c');
}
