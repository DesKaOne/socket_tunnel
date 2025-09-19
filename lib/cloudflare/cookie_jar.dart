import 'dart:convert';

import '../core/storage_pointycastle.dart';
import '../puppeteer/puppeteer.dart';

class CookieJar {
  final Storage storage;
  final String email;
  final String userAgent;

  /// Legacy flat (boleh dipakai untuk debug / kompat lawas).
  final Map<String, String> _kv = {};

  /// domain → path → {name:value}
  final Map<String, Map<String, Map<String, String>>> _store = {};

  bool _isLogged = false;

  bool get isLogged => _isLogged;

  CookieJar({
    required this.storage,
    required this.email,
    required this.userAgent,
  });

  // ================ Public API ================

  /// Serap semua Set-Cookie dari response headers (robust).
  void absorbResponseHeaders(
    Map<String, String> headers, {
    String? domainHint,
  }) {
    final lines = _collectSetCookieLines(headers);
    if (lines.isEmpty) return;

    for (final line in _splitSetCookieSafe(lines)) {
      final parsed = _parseOneSetCookie(line);
      if (parsed == null) continue;

      final name = parsed.name;
      final value = parsed.value;
      final d = parsed.domain ?? domainHint; // kalau server tak kirim Domain
      final p = parsed.path ?? '/';

      // Simpan ke store domain/path (utama)
      if (d != null && d.isNotEmpty) {
        put(d, name, value, path: p);
      }
      // Simpan juga ke flat (opsional; buat debug/kompat)
      _kv[name] = value;
    }

    // Persist setelah absorb (biar selalu up to date)
    saveToStorage();
  }

  /// Serap string "Cookie:" (bukan Set-Cookie) — mis. dari puppeteer.
  void absorbCookieHeader(
    String cookieHeader, {
    required String domain,
    String path = "/",
  }) {
    if (cookieHeader.trim().isEmpty) return;

    // Simpan mentah juga (biar bisa dilihat/diambil sewaktu-waktu)
    storage.set(storageKey(), {
      'cookieHeader': cookieHeader,
      'userAgent': userAgent,
      'jar': jsonEncode(_store),
    });

    for (final seg in cookieHeader.split(RegExp(r';\s*'))) {
      if (seg.isEmpty) continue;
      final m = RegExp(r'^([^=;\s]+)=([^;]*)$').firstMatch(seg);
      if (m == null) continue;
      final name = m.group(1)!;
      final value = m.group(2)!;
      put(domain, name, value, path: path);
      _kv[name] = value;
    }
    saveToStorage();
  }

  /// Buat header Cookie untuk URL tertentu (domain+path aware).
  String headerFor(Uri uri) {
    final domain = uri.host.toLowerCase();
    final path = uri.path.isEmpty ? "/" : uri.path;

    final out = <String, String>{};

    // exact domain
    if (_store.containsKey(domain)) {
      _store[domain]!.forEach((p, kv) {
        if (path.startsWith(p)) out.addAll(kv);
      });
    }
    // domain leading-dot (e.g., .example.com)
    for (final d in _store.keys) {
      if (d.startsWith('.') &&
          (domain == d.substring(1) || domain.endsWith(d))) {
        _store[d]!.forEach((p, kv) {
          if (path.startsWith(p)) out.addAll(kv);
        });
      }
    }
    if (out.isEmpty) return '';
    return out.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Header Cookie gabungan (flat) – hanya untuk kompat lama / debug.
  String header() => _kv.entries.map((e) => '${e.key}=${e.value}').join('; ');

  String? get(String name) => _kv[name];
  void set(String name, String value) {
    _kv[name] = value;
    saveToStorage();
  }

  void setIsLogged(bool value) {
    _isLogged = value;
  }

  /// Simpan 1 cookie domain/path-aware.
  void put(String domain, String name, String value, {String path = "/"}) {
    final d = domain.toLowerCase();
    final p = path.isEmpty ? "/" : path;
    _store.putIfAbsent(d, () => <String, Map<String, String>>{});
    _store[d]!.putIfAbsent(p, () => <String, String>{});
    _store[d]![p]![name] = value;
  }

  // ================ Persistence ================

  /// Muat dari storage (jika ada).
  /// Mengembalikan true jika sukses load.
  bool loadFromStorage() {
    final raw = storage.get(storageKey());
    if (raw is Map) {
      // restore store
      final jarJson = raw['jar'];
      if (jarJson is String && jarJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(jarJson);
          if (decoded is Map<String, dynamic>) {
            _store.clear();
            decoded.forEach((dom, paths) {
              final Map<String, Map<String, String>> byPath = {};
              if (paths is Map<String, dynamic>) {
                paths.forEach((p, kv) {
                  final Map<String, String> map = {};
                  if (kv is Map<String, dynamic>) {
                    kv.forEach((k, v) {
                      if (v is String) map[k] = v;
                    });
                  }
                  byPath[p] = map;
                });
              }
              _store[dom] = byPath;
            });

            // isi flat dari _store (simple merge)
            _kv.clear();
            _store.forEach((_, paths) {
              paths.forEach((__, kv) => _kv.addAll(kv));
            });
          }
        } catch (_) {}
      }

      // kalau ada cookieHeader mentah, boleh dipakai juga (opsional)
      final ch = raw['cookieHeader'];
      if (ch is String && ch.isNotEmpty) {
        // jangan overwrite _store, karena sudah di-restore dari jar
        // ini sekadar biar gampang diakses jika butuh mentahnya
      }
      _isLogged = raw['isLogged'];
      return true;
    }
    return false;
  }

  /// Simpan ke storage.
  void saveToStorage() {
    // simpan _store saja (lebih akurat domain/path)
    storage.set(storageKey(), {
      'userAgent': userAgent,
      'jar': jsonEncode(_store),
      'isLogged': _isLogged,
    });
  }

  Future<void> deleteStorage() async {
    await storage.delete(storageKey());
  }

  String storageKey() => 'cookies::$email';

  // ================ Internal helpers ================

  /// Kumpulkan semua “Set-Cookie” (case-insensitive).
  /// Banyak HTTP lib nge-flatten, jadi ambil semua kunci yg equals-ignore-case.
  List<String> _collectSetCookieLines(Map<String, String> headers) {
    final out = <String>[];
    headers.forEach((k, v) {
      if (k.toLowerCase() == 'set-cookie') {
        // Beberapa lib memuat hanya 1 string (satu header).
        // Tapi server bisa kirim multipel; di sini anggap satu baris = satu cookie.
        // Kalau digabung, _splitSetCookieSafe akan mengurai.
        out.add(v);
      }
    });
    return out;
  }

  /// Split aman untuk gabungan Set-Cookie yang mengandung “Expires=…GMT” (ada koma).
  /// Strategi: pecah manual dengan state kecil: kalau sedang di dalam atribut Expires,
  /// jangan split pada koma sampai ketemu ';' / akhir.
  List<String> _splitSetCookieSafe(List<String> rawLines) {
    // Jika server kirim satu cookie per header (case umum), tinggal return apa adanya.
    if (rawLines.length == 1 && !rawLines.first.contains(',')) {
      return rawLines;
    }

    final out = <String>[];
    for (final line in rawLines) {
      // Jika line jelas satu cookie saja, dorong langsung.
      if (!line.contains(',')) {
        out.add(line.trim());
        continue;
      }

      final buf = StringBuffer();
      var i = 0;
      var inExpires = false;

      while (i < line.length) {
        final ch = line[i];

        // deteksi “expires=”
        if (!inExpires &&
            (i + 8 <= line.length) &&
            line.substring(i, i + 8).toLowerCase() == 'expires=') {
          inExpires = true;
          buf.write('expires=');
          i += 8;
          continue;
        }

        if (inExpires) {
          // di dalam expires, tulis apa adanya sampai ; (atau EOL)
          if (ch == ';') {
            inExpires = false;
            buf.write(';');
            i++;
          } else {
            buf.write(ch);
            i++;
          }
          continue;
        }

        // di luar expires: koma memisah antar cookie
        if (ch == ',') {
          final piece = buf.toString().trim();
          if (piece.isNotEmpty) out.add(piece);
          buf.clear();
          i++;
          // buang spasi setelah koma
          while (i < line.length && line[i] == ' ') i++;
          continue;
        }

        buf.write(ch);
        i++;
      }

      final last = buf.toString().trim();
      if (last.isNotEmpty) out.add(last);
    }

    return out;
  }

  /// Parse satu baris Set-Cookie → (name, value, domain?, path?)
  _ParsedCookie? _parseOneSetCookie(String line) {
    final semi = line.split(';');
    if (semi.isEmpty) return null;

    final first = semi.first.trim();
    final eq = first.indexOf('=');
    if (eq <= 0) return null;

    final name = first.substring(0, eq).trim();
    final value = first.substring(eq + 1).trim();

    String? domain;
    String? path;

    for (var i = 1; i < semi.length; i++) {
      final av = semi[i].trim();
      final idx = av.indexOf('=');
      final aName = (idx < 0 ? av : av.substring(0, idx)).trim().toLowerCase();
      final aVal = (idx < 0 ? '' : av.substring(idx + 1).trim());

      if (aName == 'domain' && aVal.isNotEmpty) domain = aVal.toLowerCase();
      if (aName == 'path' && aVal.isNotEmpty) path = aVal;
    }

    return _ParsedCookie(name, value, domain: domain, path: path);
  }

  List<CookieParam> getCookies() {
    List<CookieParam> addCookie = [];
    final listCookies = header().split('; ');
    for (var cookies in listCookies) {
      final s = cookies.split('=');
      addCookie.add(CookieParam(name: s[0], value: s[1]));
    }
    return addCookie;
  }
}

class _ParsedCookie {
  final String name;
  final String value;
  final String? domain;
  final String? path;
  _ParsedCookie(this.name, this.value, {this.domain, this.path});
}
