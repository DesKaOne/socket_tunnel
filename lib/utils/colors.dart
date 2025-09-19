import 'dart:io';
import 'package:ansicolor/ansicolor.dart';

/// Hindari tabrakan dengan Flutter's `Colors`.
class TermColor {
  TermColor._();

  // ===== enable/disable global =====
  static bool _enabled = _detectEnabled();

  static bool get enabled => _enabled;
  static void setEnabled(bool v) {
    _enabled = v;
    _cache.clear();
    // Jika paketmu punya variabel global ini, boleh aktifkan baris di bawah:
    // ansiColorDisabled = !v; // <— top-level, bukan AnsiPen.ansiColorDisabled
  }

  static bool _detectEnabled() {
    try {
      if (Platform.environment.containsKey('NO_COLOR')) return false;
      return stdout.hasTerminal && stdout.supportsAnsiEscapes;
    } catch (_) {
      return true; // default: aktif (mis. non-IO platform)
    }
  }

  // ===== cache pen utk named colors =====
  static final Map<String, AnsiPen> _cache = {};

  static AnsiPen _pen(String name, {required bool bg, required bool bold}) {
    final key = '$name|$bg|$bold';
    return _cache.putIfAbsent(key, () {
      final p = AnsiPen();
      switch (name) {
        case 'red':
          p.red(bg: bg, bold: bold);
          break;
        case 'green':
          p.green(bg: bg, bold: bold);
          break;
        case 'blue':
          p.blue(bg: bg, bold: bold);
          break;
        case 'magenta':
          p.magenta(bg: bg, bold: bold);
          break;
        case 'yellow':
          p.yellow(bg: bg, bold: bold);
          break;
        case 'cyan':
          p.cyan(bg: bg, bold: bold);
          break;
        case 'white':
          p.white(bg: bg, bold: bold);
          break;
        default:
          p.white(bg: bg, bold: bold);
      }
      return p;
    });
  }

  // ===== API kompatibel =====
  static String Function(String message, {bool bg, bool bold}) get red => _red;
  static String Function(String message, {bool bg, bool bold}) get green =>
      _green;
  static String Function(String message, {bool bg, bool bold}) get blue =>
      _blue;
  static String Function(String message, {bool bg, bool bold}) get magenta =>
      _magenta;
  static String Function(String message, {bool bg, bool bold}) get yellow =>
      _yellow;
  static String Function(String message, {bool bg, bool bold}) get cyan =>
      _cyan;
  static String Function(String message, {bool bg, bool bold}) get white =>
      _white;

  static String _red(String m, {bool bg = false, bool bold = false}) =>
      _enabled ? _pen('red', bg: bg, bold: bold)(m) : m;
  static String _green(String m, {bool bg = false, bool bold = false}) =>
      _enabled ? _pen('green', bg: bg, bold: bold)(m) : m;
  static String _blue(String m, {bool bg = false, bool bold = false}) =>
      _enabled ? _pen('blue', bg: bg, bold: bold)(m) : m;
  static String _magenta(String m, {bool bg = false, bool bold = false}) =>
      _enabled ? _pen('magenta', bg: bg, bold: bold)(m) : m;
  static String _yellow(String m, {bool bg = false, bool bold = false}) =>
      _enabled ? _pen('yellow', bg: bg, bold: bold)(m) : m;
  static String _cyan(String m, {bool bg = false, bool bold = false}) =>
      _enabled ? _pen('cyan', bg: bg, bold: bold)(m) : m;
  static String _white(String m, {bool bg = false, bool bold = false}) =>
      _enabled ? _pen('white', bg: bg, bold: bold)(m) : m;

  /// Reset ANSI yang sebenarnya.
  static String reset() => _enabled ? '\x1B[0m' : '';

  // ===== Preset tema =====
  static String info(String m, {bool bold = false}) => cyan(m, bold: bold);
  static String success(String m, {bool bold = false}) => green(m, bold: bold);
  static String warn(String m, {bool bold = false}) => yellow(m, bold: bold);
  static String error(String m, {bool bold = true}) => red(m, bold: bold);
  static String debug(String m, {bool bold = false}) => blue(m, bold: bold);
  static String note(String m, {bool bold = false}) => magenta(m, bold: bold);

  // ===== xterm-256 & truecolor (RGB) =====
  static String xterm(
    String m,
    int code, {
    bool bg = false,
    bool bold = false,
  }) {
    if (!_enabled) return m;
    if (code < 0) code = 0;
    if (code > 255) code = 255;
    final open = StringBuffer();
    if (bold) open.write('\x1B[1m');
    open.write(bg ? '\x1B[48;5;${code}m' : '\x1B[38;5;${code}m');
    return '$open$m\x1B[0m';
  }

  static String rgb(
    String m,
    int r,
    int g,
    int b, {
    bool bg = false,
    bool bold = false,
  }) {
    if (!_enabled) return m;
    r = r.clamp(0, 255);
    g = g.clamp(0, 255);
    b = b.clamp(0, 255);
    final open = StringBuffer();
    if (bold) open.write('\x1B[1m');
    open.write(bg ? '\x1B[48;2;$r;$g;${b}m' : '\x1B[38;2;$r;$g;${b}m');
    return '$open$m\x1B[0m';
  }
}

/// Gaya teks (bold/italic/underline/dim/inverse/strike)
class TermStyle {
  TermStyle._();

  static String apply(
    String m, {
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool dim = false,
    bool inverse = false,
    bool strike = false,
  }) {
    if (!TermColor.enabled) return m;
    final codes = <int>[];
    if (bold) codes.add(1);
    if (italic) codes.add(3);
    if (underline) codes.add(4);
    if (dim) codes.add(2);
    if (inverse) codes.add(7);
    if (strike) codes.add(9);
    if (codes.isEmpty) return m;
    return '\x1B[${codes.join(';')}m$m\x1B[0m';
  }
}

/// Ergonomis: panggil langsung di String.
extension Chalk on String {
  String red({bool bg = false, bool bold = false}) =>
      TermColor.red(this, bg: bg, bold: bold);
  String green({bool bg = false, bool bold = false}) =>
      TermColor.green(this, bg: bg, bold: bold);
  String blue({bool bg = false, bool bold = false}) =>
      TermColor.blue(this, bg: bg, bold: bold);
  String magenta({bool bg = false, bool bold = false}) =>
      TermColor.magenta(this, bg: bg, bold: bold);
  String yellow({bool bg = false, bool bold = false}) =>
      TermColor.yellow(this, bg: bg, bold: bold);
  String cyan({bool bg = false, bool bold = false}) =>
      TermColor.cyan(this, bg: bg, bold: bold);
  String white({bool bg = false, bool bold = false}) =>
      TermColor.white(this, bg: bg, bold: bold);

  // Preset
  String info({bool bold = false}) => TermColor.info(this, bold: bold);
  String success({bool bold = false}) => TermColor.success(this, bold: bold);
  String warn({bool bold = false}) => TermColor.warn(this, bold: bold);
  String error({bool bold = true}) => TermColor.error(this, bold: bold);
  String debug({bool bold = false}) => TermColor.debug(this, bold: bold);
  String note({bool bold = false}) => TermColor.note(this, bold: bold);

  // xterm & RGB
  String xterm(int code, {bool bg = false, bool bold = false}) =>
      TermColor.xterm(this, code, bg: bg, bold: bold);
  String rgb(int r, int g, int b, {bool bg = false, bool bold = false}) =>
      TermColor.rgb(this, r, g, b, bg: bg, bold: bold);

  // Style
  String bold() => TermStyle.apply(this, bold: true);
  String italic() => TermStyle.apply(this, italic: true);
  String underline() => TermStyle.apply(this, underline: true);
  String dim() => TermStyle.apply(this, dim: true);
  String inverse() => TermStyle.apply(this, inverse: true);
  String strike() => TermStyle.apply(this, strike: true);
}

// ignore: unused_element
void _main() {
  print('info'.info());
  print('sukses'.success(bold: true));
  print('warning'.warn());
  print('gagal'.error());
  print('Hello'.rgb(255, 105, 180)); // hotpink
  print('Blue BG'.xterm(21, bg: true)); // xterm biru
  print('underline'.underline().cyan());
  print('${TermColor.reset()}normal lagi');
}
