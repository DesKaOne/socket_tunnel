import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:socket_tunnel/ext/indonesia_time.dart';

import 'colors.dart'; // TermColor

class Logger {
  final String? name;
  final bool saveLog;

  // Opsi baru
  final bool useEmoji;
  final bool colorizeLevelLabel;
  final bool colorizeMessage;
  final bool includeNamePrefix;

  final Directory _logDir = Directory('logs');
  IOSink? _logFileSink;
  String _currentFileDate = '';

  Logger({
    this.name,
    this.saveLog = false,
    this.useEmoji = true,
    this.colorizeLevelLabel = true,
    this.colorizeMessage = false,
    this.includeNamePrefix = false,
  }) {
    if (saveLog) _initializeLogFile();
    if (name != null) {
      stdout.write('\x1B[2K\r');
      header(name!);
    }
  }

  void _initializeLogFile() {
    if (!_logDir.existsSync()) _logDir.createSync(recursive: true);
    _currentFileDate = DateFormat('yyyy-MM-dd').format(DateTime.now().toWib());
    final logFile = File(p.join(_logDir.path, '$_currentFileDate.log'));
    _logFileSink = logFile.openWrite(mode: FileMode.append);
  }

  void _rotateIfNeeded(String today) {
    if (!saveLog) return;
    if (today != _currentFileDate) {
      _logFileSink?.flush();
      _logFileSink?.close();
      _initializeLogFile();
    }
  }

  String _emoji(String type) {
    if (!useEmoji) return '';
    switch (type) {
      case 'ERROR':
        return '❌';
      case 'WARNING':
        return '⚠️ ';
      case 'SUCCESS':
        return '✅';
      case 'DEBUG':
        return '🐞';
      default:
        return 'ℹ️ ';
    }
  }

  String _colorLevel(String type) {
    if (!colorizeLevelLabel) return type;
    switch (type) {
      case 'ERROR':
        return TermColor.red(type, bold: true);
      case 'WARNING':
        return TermColor.yellow(type, bold: true);
      case 'SUCCESS':
        return TermColor.green(type, bold: true);
      case 'DEBUG':
        return TermColor.blue(type, bold: true);
      default:
        return TermColor.cyan(type, bold: true);
    }
  }

  String _colorMsg(String type, String msg) {
    if (!colorizeMessage) return msg;
    switch (type) {
      case 'ERROR':
        return TermColor.red(msg);
      case 'WARNING':
        return TermColor.yellow(msg);
      case 'SUCCESS':
        return TermColor.green(msg);
      case 'DEBUG':
        return TermColor.blue(msg);
      default:
        return TermColor.cyan(msg);
    }
  }

  String _rawPrefix(String time, String type) {
    final namePart = includeNamePrefix && name != null ? '[${name!}] ' : '';
    return '=> $time | $namePart${type.padRight(7)} | ';
  }

  void _write(String type, String msg, {bool bold = true, String end = '\n'}) {
    final nowWib = DateTime.now().toWib();
    final today = DateFormat('yyyy-MM-dd').format(nowWib);
    _rotateIfNeeded(today);

    final time = DateFormat("HH:mm:ss").format(nowWib);
    final prefixRaw = _rawPrefix(time, type);
    final emoji = _emoji(type);
    final levelLabel = _colorLevel(type);

    // label berwarna utk baris pertama
    final namePart = includeNamePrefix && name != null ? '[${name!}] ' : '';
    final labelColored = TermColor.white(
      '=> $time | $namePart$levelLabel',
      bold: true,
    );

    final lines = msg.trimRight().split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = _colorMsg(type, lines[i]);

      if (saveLog) _logFileSink?.writeln('$prefixRaw${lines[i]}');

      //stdout.write('\x1B[2K\r');
      if (i == 0) {
        final display = '$labelColored | $line';
        end == '\n'
            ? stdout.writeln(
                '${TermColor.white('${emoji.isNotEmpty ? '$emoji ' : ''}$display', bold: bold)}          ',
              )
            : stdout.write(
                '${TermColor.white('${emoji.isNotEmpty ? '$emoji ' : ''}$display', bold: bold)}          \r',
              );
      } else {
        final indent = ' ' * prefixRaw.length;
        final display = '$indent$line';
        end == '\n'
            ? stdout.writeln(
                '${TermColor.white(display, bold: bold)}          ',
              )
            : stdout.write(
                '${TermColor.white(display, bold: bold)}          \r',
              );
      }
    }
  }

  void info(String message, {String end = '\n'}) =>
      _write("INFO", message, end: end);
  void warning(String message, {String end = '\n'}) =>
      _write("WARNING", message, end: end, bold: true);
  void error(String message, {String end = '\n'}) =>
      _write("ERROR", message, end: end, bold: true);
  void debug(String message, {String end = '\n'}) =>
      _write("DEBUG", message, end: end);
  void success(String message, {String end = '\n'}) =>
      _write("SUCCESS", message, end: end);

  void line({bool isBold = false}) {
    final width = stdout.hasTerminal ? stdout.terminalColumns : 80;
    final char = isBold ? '=' : '-';
    stdout.write('\x1B[2K\r');
    stdout.writeln(TermColor.white(char * width, bold: isBold));
  }

  void header(String text, {bool isBold = true}) {
    final width = stdout.hasTerminal ? stdout.terminalColumns : 80;
    final border = isBold ? '=' : '-';
    final borderLine = border * width;

    stdout.writeln(TermColor.white(borderLine, bold: isBold));
    for (var line in text.trim().split('\n')) {
      final t = line.trim();
      final padLeft = ((width - t.length) / 2).floor();
      final centered = (' ' * (padLeft > 0 ? padLeft : 0)) + t;
      stdout.writeln(TermColor.white(centered.padRight(width), bold: isBold));
    }
    stdout.writeln(TermColor.white(borderLine, bold: isBold));
  }

  static void clear() => stdout.write("\x1B[2J\x1B[H");
  void reset() => stdout.write('\x1B[2K\r');

  Future<void> dispose() async {
    await _logFileSink?.flush();
    await _logFileSink?.close();
    _logFileSink = null;
  }
}

// ignore: unused_element
void _main() {
  final log = Logger(
    name: 'DesKaOne Runner',
    saveLog: true,
    useEmoji: true,
    colorizeLevelLabel: true,
    colorizeMessage: true,
    includeNamePrefix: true,
  );

  log.info('Mulai eksekusi');
  log.warning('CPU meletup-letup dikit');
  log.error('Waduh, koneksi putus');
  log.success('Berhasil recover 🎉');
}
