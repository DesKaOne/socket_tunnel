enum FromUnits { Bytes, KB, MB, GB, TB }

class BytesConverter {
  // Label SI (1000) dan Biner (1024)
  static const List<String> _siLabels = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
  static const List<String> _binLabels = ['Bytes', 'KiB', 'MiB', 'GiB', 'TiB'];

  // Ambil slice label sesuai titik awal
  static List<String> _labelsFrom(FromUnits from, {required bool binary}) {
    final labels = binary ? _binLabels : _siLabels;
    final startIdx = switch (from) {
      FromUnits.Bytes => 0,
      FromUnits.KB => 1,
      FromUnits.MB => 2,
      FromUnits.GB => 3,
      FromUnits.TB => 4,
    };
    return labels.sublist(startIdx);
  }

  /// Mesin format umum: [value] adalah angka pada unit awal (lihat [fromUnits])
  static (double value, String unit) _format(
    double value,
    List<String> labels,
    int base,
    int fixed,
  ) {
    var size = value;
    var i = 0;
    while (size >= base && i < labels.length - 1) {
      size /= base;
      i++;
    }
    return (double.parse(size.toStringAsFixed(fixed)), labels[i]);
  }

  /// Format SI (basis 1000). [value] adalah angka pada [fromUnits].
  static (double value, String unit) formatSI(
    double value, {
    FromUnits fromUnits = FromUnits.Bytes,
    int fixed = 2,
  }) {
    return _format(value, _labelsFrom(fromUnits, binary: false), 1000, fixed);
  }

  /// Format Biner (basis 1024). [value] adalah angka pada [fromUnits].
  static (double value, String unit) formatBinary(
    double value, {
    FromUnits fromUnits = FromUnits.Bytes,
    int fixed = 2,
  }) {
    return _format(value, _labelsFrom(fromUnits, binary: true), 1024, fixed);
  }

  /// Format siap cetak, contoh: "1.23 MB" (SI) atau "1.17 MiB" (biner)
  static String formatString(
    double value, {
    bool binary = false,
    FromUnits fromUnits = FromUnits.Bytes,
    int fixed = 2,
  }) {
    final (v, u) = binary
        ? formatBinary(value, fromUnits: fromUnits, fixed: fixed)
        : formatSI(value, fromUnits: fromUnits, fixed: fixed);
    return '$v $u';
  }

  // ---- Parser ----
  // Dukungan unit (case-insensitive, singular/plural & short form)
  static const Map<String, int> _siFactor = {
    'b': 1,
    'byte': 1,
    'bytes': 1,
    'k': 1000,
    'kb': 1000,
    'm': 1000 * 1000,
    'mb': 1000 * 1000,
    'g': 1000 * 1000 * 1000,
    'gb': 1000 * 1000 * 1000,
    't': 1000 * 1000 * 1000 * 1000,
    'tb': 1000 * 1000 * 1000 * 1000,
  };

  static const Map<String, int> _binFactor = {
    'b': 1,
    'byte': 1,
    'bytes': 1,
    'k': 1024,
    'kb': 1024,
    'kib': 1024,
    'm': 1024 * 1024,
    'mb': 1024 * 1024,
    'mib': 1024 * 1024,
    'g': 1024 * 1024 * 1024,
    'gb': 1024 * 1024 * 1024,
    'gib': 1024 * 1024 * 1024,
    't': 1024 * 1024 * 1024 * 1024,
    'tb': 1024 * 1024 * 1024 * 1024,
    'tib': 1024 * 1024 * 1024 * 1024,
  };

  /// Parsing string ke bytes (double).
  /// Contoh sah: "1.5 GB", "512 KiB", "200kb", "42 bytes", "2 MiB"
  static double parseToBytes(String input, {bool binary = false}) {
    final s = input.trim().toLowerCase();
    final re = RegExp(r'^([\d]+(?:\.\d+)?)\s*([a-z]+)$');
    final m = re.firstMatch(s);
    if (m == null) {
      throw const FormatException(
        "Format tidak dikenali. Contoh: '1.5 GB' atau '512 KiB'",
      );
    }

    final numStr = m.group(1)!;
    final unitStr = m.group(2)!;

    final value = double.tryParse(numStr);
    if (value == null || value.isNaN || !value.isFinite) {
      throw FormatException("Angka tidak valid: '$numStr'");
    }

    // Normalisasi unit: buang 's' di akhir (bytes -> byte), kecuali 'kb/mb/gb/tb'
    var unit = unitStr;
    if (unit.endsWith('s') &&
        unit != 'kb' &&
        unit != 'mb' &&
        unit != 'gb' &&
        unit != 'tb') {
      unit = unit.substring(0, unit.length - 1);
    }

    final table = binary ? _binFactor : _siFactor;
    final factor = table[unit];
    if (factor == null) {
      throw FormatException("Unit tidak dikenali: '$unitStr'");
    }

    return value * factor;
  }
}
