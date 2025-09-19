extension IndonesiaTime on DateTime {
  // --- Core: konversi ke "lokal" dengan offset jam tertentu (isUtc: false) ---
  DateTime _inOffset(int hours) {
    final utc = toUtc();
    final ms =
        utc.millisecondsSinceEpoch + Duration(hours: hours).inMilliseconds;
    // penting: bikin DateTime non-UTC
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: false);
  }

  DateTime toWib() => _inOffset(7);
  DateTime toWita() => _inOffset(8);
  DateTime toWit() => _inOffset(9);

  static const List<String> _bulan = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  static const List<String> _hari = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  static String _2(int n) => n.toString().padLeft(2, '0');

  String _format(DateTime dt, String zona) {
    final hari =
        _hari[dt.weekday - 1]; // Monday=1..Sunday=7 → list di atas sudah pas
    final bulan = _bulan[dt.month - 1];
    return '$hari, ${dt.day} $bulan ${dt.year}, '
        '${_2(dt.hour)}:${_2(dt.minute)}:${_2(dt.second)} $zona';
  }

  String _formatTime(DateTime dt, String zona, {bool withSeconds = true}) {
    final hhmm = '${_2(dt.hour)}:${_2(dt.minute)}';
    return withSeconds ? '$hhmm:${_2(dt.second)} $zona' : '$hhmm $zona';
  }

  // --- Full datetime (ID) ---
  String toWibString() => _format(toWib(), 'WIB');
  String toWitaString() => _format(toWita(), 'WITA');
  String toWitString() => _format(toWit(), 'WIT');

  // --- Time-only (ID) ---
  String toWibTimeString({bool withSeconds = true}) =>
      _formatTime(toWib(), 'WIB', withSeconds: withSeconds);
  String toWitaTimeString({bool withSeconds = true}) =>
      _formatTime(toWita(), 'WITA', withSeconds: withSeconds);
  String toWitTimeString({bool withSeconds = true}) =>
      _formatTime(toWit(), 'WIT', withSeconds: withSeconds);

  // Formatter generik untuk zona custom
  String toIndonesiaStringWithOffset(
    int hours,
    String label, {
    bool timeOnly = false,
    bool withSeconds = true,
  }) {
    final dt = _inOffset(hours);
    return timeOnly
        ? _formatTime(dt, label, withSeconds: withSeconds)
        : _format(dt, label);
  }

  /// Timestamp simpel "YYYY-MM-DD HH:mm:ss".
  /// - forceWIB=true → pakai WIB
  /// - forceWIB=false → pakai UTC (biar konsisten untuk logging/DB)
  String formatTs({bool forceWIB = false}) {
    final d = forceWIB ? toWib() : toUtc();
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  /// Cantik: "YYYY-MM-DD HH:mm:ss" pakai waktu lokal device.
  String pretty() {
    return toLocal().toIso8601String().split('.').first.replaceFirst('T', ' ');
  }

  /// Truncate ke tanggal (00:00:00) di zona objek ini.
  DateTime pret() => DateTime(year, month, day);
}
