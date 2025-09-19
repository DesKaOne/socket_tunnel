import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http_client/http_client.dart';
import 'package:pointycastle/export.dart';

import '../utils/logger.dart';

const String defaultKey =
    '381a0130d76c062f9f0219ee485ee3f2'; // 32 hex = 16 byte

class Storage {
  final bool debug;
  final Logger? logger;
  final String filePath;
  final String keyHex;

  late Map<String, dynamic> _store;
  late Uint8List _key;

  late final String _backupPath; // disamakan dengan main file

  Storage({
    this.debug = false,
    this.logger,
    this.filePath = 'secure_storage.bin',
    this.keyHex = defaultKey,
  }) {
    final prefix = _stripExt(filePath);
    _backupPath = '$prefix.backup.bin';
  }

  // ===================== init =====================

  Future<void> initialize() async {
    _key = BytesExt.fromHex(keyHex); // <- beneran bytes AES
    if (!(_key.length == 16 || _key.length == 24 || _key.length == 32)) {
      throw ArgumentError('Panjang key harus 16/24/32 byte (32/48/64 hex).');
    }

    Uint8List? blob;
    final f = File(filePath);
    if (await f.exists()) blob = await f.readAsBytes();

    if (blob != null && blob.length >= 16) {
      try {
        _store = _decryptToMap(blob);
        if (debug) await _dumpPrettyJson(_store, '${_stripExt(filePath)}.json');
        return;
      } catch (e) {
        logger?.error('[Storage] Decrypt utama gagal: $e');
        // coba backup
        final fb = File(_backupPath);
        if (await fb.exists()) {
          try {
            _store = _decryptToMap(await fb.readAsBytes());
            logger?.info('[Storage] Pulih dari backup!');
            return;
          } catch (e2) {
            logger?.error('[Storage] Backup juga gagal: $e2');
          }
        }
      }
    }

    // fallback fresh
    _store = {};
    await _saveToFile();
  }

  // ===================== getters/setters =====================

  dynamic get(String key) => _store[key];
  String? getString(String key) => _store[key] is String ? _store[key] : null;
  int? getInt(String key) => _store[key] is int ? _store[key] : null;
  double? getDouble(String key) => _store[key] is double ? _store[key] : null;
  bool getBool(String key) => _store[key] is bool ? _store[key] : false;

  Map<String, dynamic> getJson(String key) =>
      _store[key] is Map<String, dynamic> ? _store[key] : {};

  List<String> getStringList(String key) {
    final v = _store[key];
    return v is List ? v.whereType<String>().toList() : <String>[];
  }

  List<dynamic> getListData(String key) {
    final v = _store[key];
    return v is List ? List<dynamic>.from(v) : <dynamic>[];
  }

  Future<void> set(String key, dynamic value) async {
    _store[key] = value;
    await _saveToFile();
  }

  Set<String> getKeys() => _store.keys.toSet();

  Future<void> delete(String key) async {
    if (_store.remove(key) != null) {
      await _saveToFile();
    }
  }

  Future<void> clear() async {
    _store.clear();
    await _saveToFile();
  }

  Future<bool> restoreFromBackup() async {
    final fb = File(_backupPath);
    if (!await fb.exists()) return false;
    try {
      _store = _decryptToMap(await fb.readAsBytes());
      await _saveToFile();
      logger?.info('[Storage] Restore dari backup berhasil!');
      return true;
    } catch (e) {
      logger?.error('[Storage] Restore dari backup gagal: $e');
      return false;
    }
  }

  // ===================== crypto I/O =====================

  Future<void> _saveToFile() async {
    final jsonStr = jsonEncode(_store);
    if (debug) {
      await _dumpPrettyJson(_store, '${_stripExt(filePath)}.json');
    }

    final iv = _secureIv(16);
    final cipherBytes = _encrypt(jsonStr, iv);
    final full = Uint8List(iv.length + cipherBytes.length)
      ..setRange(0, iv.length, iv)
      ..setRange(iv.length, iv.length + cipherBytes.length, cipherBytes);

    final mainFile = File(filePath);
    final backupFile = File(_backupPath);

    // simpan backup lama dulu
    if (await mainFile.exists()) {
      try {
        await backupFile.writeAsBytes(
          await mainFile.readAsBytes(),
          flush: true,
        );
      } catch (e) {
        logger?.error('[Storage] Gagal membuat backup: $e');
      }
    }

    await mainFile.writeAsBytes(full, flush: true);
  }

  Map<String, dynamic> _decryptToMap(Uint8List blob) {
    final iv = blob.sublist(0, 16);
    final data = blob.sublist(16);
    final plain = _decrypt(data, iv);
    final obj = jsonDecode(plain);
    if (obj is Map<String, dynamic>) return obj;
    throw const FormatException('Format file tidak valid (bukan JSON object).');
  }

  // ==== AES-CBC + PKCS7 pakai PointyCastle PaddedBlockCipher ====

  Uint8List _encrypt(String plainText, Uint8List iv) {
    final params =
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV<KeyParameter>(KeyParameter(_key), iv),
          null,
        );
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')..init(true, params);
    return cipher.process(Uint8List.fromList(utf8.encode(plainText)));
  }

  String _decrypt(Uint8List encrypted, Uint8List iv) {
    final params =
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV<KeyParameter>(KeyParameter(_key), iv),
          null,
        );
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7')..init(false, params);
    final out = cipher.process(encrypted);
    return utf8.decode(out);
  }

  // ===================== utils =====================

  // IV acak kuat
  Uint8List _secureIv(int length) {
    final rnd = Random.secure();
    final out = Uint8List(length);
    for (var i = 0; i < out.length; i++) {
      out[i] = rnd.nextInt(256);
    }
    return out;
  }

  String _stripExt(String path) {
    final i = path.lastIndexOf('.');
    if (i <= 0) return path;
    return path.substring(0, i);
  }

  Future<void> _dumpPrettyJson(Map<String, dynamic> m, String path) async {
    final enc = const JsonEncoder.withIndent('    ');
    await File(path).writeAsString(enc.convert(m), flush: true);
  }
}
