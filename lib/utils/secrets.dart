import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

class Secrets {
  Secrets._();

  // RNG + flag apakah benar-benar secure
  static late final bool _secure;
  static final Random _rng = _initRng();

  static Random _initRng() {
    try {
      final r =
          Random.secure(); // akan throw UnsupportedError jika platform tak dukung
      _secure = true;
      return r;
    } on UnsupportedError {
      _secure = false;
      return Random();
    } catch (_) {
      _secure = false;
      return Random();
    }
  }

  static bool get isSecureRandom => _secure;

  /// Generate N byte acak.
  /// Set [requireSecure] = true untuk memaksa Random.secure() (throw jika tidak tersedia).
  static Uint8List tokenBytes(int length, {bool requireSecure = false}) {
    if (length <= 0) {
      throw ArgumentError.value(length, 'length', 'Harus > 0');
    }
    if (requireSecure && !_secure) {
      throw StateError('Random.secure() tidak tersedia pada platform ini.');
    }
    final b = Uint8List(length);
    fillBytes(b);
    return b;
  }

  /// Isi buffer [out] dengan byte acak (hemat alloc).
  static void fillBytes(Uint8List out) {
    for (var i = 0; i < out.length; i++) {
      out[i] = _rng.nextInt(256);
    }
  }

  /// Hex dari N byte acak (hasil string panjang = 2 * length).
  static String tokenHex(int length, {bool requireSecure = false}) {
    final b = tokenBytes(length, requireSecure: requireSecure);
    return _toHex(b);
  }

  /// Hex dengan panjang karakter tepat [hexChars] (ceil(n/2) byte, lalu dipotong).
  static String tokenHexChars(int hexChars, {bool requireSecure = false}) {
    if (hexChars <= 0) {
      throw ArgumentError.value(hexChars, 'hexChars', 'Harus > 0');
    }
    final bytesNeeded = (hexChars + 1) >> 1; // ceil(n/2)
    final h = tokenHex(bytesNeeded, requireSecure: requireSecure);
    return h.substring(0, hexChars);
  }

  /// Base64URL (tanpa '=' padding) dari N byte acak.
  static String tokenBase64Url(int length, {bool requireSecure = false}) {
    final b = tokenBytes(length, requireSecure: requireSecure);
    return _b64urlNoPad(b);
  }

  /// Base64URL TANPA padding dengan panjang karakter target [chars].
  /// Menghitung byte yang diperlukan supaya output minimal [chars], lalu dipotong.
  static String tokenBase64UrlChars(int chars, {bool requireSecure = false}) {
    if (chars <= 0) {
      throw ArgumentError.value(chars, 'chars', 'Harus > 0');
    }
    // base64url tanpa padding: tiap 3 byte → 4 char. Jadi ~ 4/3 char/byte.
    // Cari n byte sehingga ceil(4*n/3) >= chars → n >= ceil(3*chars/4)
    final n = ((3 * chars) + 3) >> 2; // ceil(3*chars/4)
    final s = tokenBase64Url(n, requireSecure: requireSecure);
    return s.length >= chars ? s.substring(0, chars) : s; // jaga-jaga
  }

  /// UUID v4 (random) tanpa paket eksternal.
  static String uuidV4({bool requireSecure = false}) {
    final b = tokenBytes(16, requireSecure: requireSecure);
    // version 4
    b[6] = (b[6] & 0x0F) | 0x40;
    // variant RFC 4122
    b[8] = (b[8] & 0x3F) | 0x80;
    final h = _toHex(b);
    return '${h.substring(0, 8)}-'
        '${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-'
        '${h.substring(20)}';
  }

  /// ID hash dari string (UTF-8). Default SHA-256 (rekomendasi).
  static String idSha256(String message) =>
      crypto.sha256.convert(utf8.encode(message)).toString();

  /// MD5 kalau memang perlu kompatibilitas lama (TIDAK untuk keamanan).
  static String idMd5(String message) =>
      crypto.md5.convert(utf8.encode(message)).toString();

  /// HMAC-SHA256 untuk ID terikat rahasia (mis. dedup + anti-tabrak).
  static String idHmacSha256(String secret, String message) => crypto.Hmac(
    crypto.sha256,
    utf8.encode(secret),
  ).convert(utf8.encode(message)).toString();

  /// Jika message null/kosong → pakai UUID v4; kalau ada → SHA-256(message).
  static String createId(String? message, {bool requireSecure = false}) {
    return (message == null || message.isEmpty)
        ? uuidV4(requireSecure: requireSecure)
        : idSha256(message);
  }

  /// Hash SHA-256 dari bytes (sering kepakai).
  static String bytesSha256(Uint8List bytes) =>
      crypto.sha256.convert(bytes).toString();

  /// HMAC-SHA256 dari bytes.
  static String bytesHmacSha256(Uint8List key, Uint8List message) =>
      crypto.Hmac(crypto.sha256, key).convert(message).toString();

  // ===== helpers =====

  static String _toHex(Uint8List b) {
    const hexdigits = '0123456789abcdef';
    final out = StringBuffer();
    for (final v in b) {
      out
        ..write(hexdigits[v >> 4])
        ..write(hexdigits[v & 0x0F]);
    }
    return out.toString();
  }

  static String _b64urlNoPad(Uint8List b) =>
      base64Url.encode(b).replaceAll('=', '');
}
