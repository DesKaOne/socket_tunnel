import 'dart:math';

import '../utils/bytes_converter.dart';
import '../utils/secrets.dart';

class Session<E> {
  final E session;
  int upBytes;
  int downBytes;

  int get totBytes => upBytes + downBytes;

  Session({required this.session, this.upBytes = 0, this.downBytes = 0});

  @override
  String toString() =>
      'session=$session, up=$upBytes, down=$downBytes, total=$totBytes';
}

class LogSession<E> extends Session<E> {
  final int connected;

  LogSession({
    required super.session,
    required this.connected,
    super.upBytes,
    super.downBytes,
  });

  @override
  String toString() {
    final conn = connected.toString().padLeft(3, '0');
    final id = _shortId(session);
    final human = BytesConverter.formatString(
      totBytes.toDouble(),
      binary: true,
    );
    return '[$conn] Session: $id, Traffic: $totBytes, +$human';
  }

  String _shortId(E s) {
    if (s is String) {
      final clean = s.replaceAll('-', '');
      final take = min(8, clean.length);
      return clean
          .substring(0, take)
          .padRight(8, '0'); // jaga panjang konsisten
    }
    if (s is int) {
      // Asumsi Secrets tersedia di proyekmu
      final id = Secrets.createId(s.toString());
      return id.substring(0, min(8, id.length));
    }
    // Fallback generik: pakai toString() lalu potong
    final t = Secrets.createId(s.toString());
    return t.substring(0, min(8, t.length));
  }
}
