extension IndonesiaTime on DateTime {
  // Konversi zona: hasilkan DateTime "lokal" (isUtc: false) pada offset tertentu
  DateTime _inOffset(int hours) {
    return toUtc().add(Duration(hours: hours));
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

  // ignore: non_constant_identifier_names
  static String _2(int n) => n.toString().padLeft(2, '0');

  String _format(DateTime dt, String zona) {
    final hari = _hari[dt.weekday - 1]; // <-- fix
    final bulan = _bulan[dt.month - 1];
    return '$hari, ${dt.day} $bulan ${dt.year}, '
        '${_2(dt.hour)}:${_2(dt.minute)}:${_2(dt.second)} $zona';
  }

  String _formatTime(DateTime dt, String zona, {bool withSeconds = true}) {
    final hhmm = '${_2(dt.hour)}:${_2(dt.minute)}';
    return withSeconds ? '$hhmm:${_2(dt.second)} $zona' : '$hhmm $zona';
  }

  String toWibString() => _format(toWib(), 'WIB');
  String toWitaString() => _format(toWita(), 'WITA');
  String toWitString() => _format(toWit(), 'WIT');

  String toWibTimeString({bool withSeconds = true}) =>
      _formatTime(toWib(), 'WIB', withSeconds: withSeconds);
  String toWitaTimeString({bool withSeconds = true}) =>
      _formatTime(toWita(), 'WITA', withSeconds: withSeconds);
  String toWitTimeString({bool withSeconds = true}) =>
      _formatTime(toWit(), 'WIT', withSeconds: withSeconds);

  // Bonus: formatter generik kalau butuh zona custom
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

  String formatTs({bool forceWIB = false}) {
    // WIB = UTC+7. Kalau mau paksa WIB, konversi dari UTC dulu.
    final d = forceWIB ? toUtc().add(const Duration(hours: 7)) : toUtc();
    String two(int n) => n < 10 ? '0$n' : '$n';
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  String pretty() {
    return toLocal()
        .toIso8601String() // 2025-09-16T17:35:17.755579
        .split('.')
        .first // 2025-09-16T17:35:17
        .replaceFirst('T', ' '); // 2025-09-16 17:35:17
  }

  DateTime pret() {
    return DateTime(year, month, day);
  }
}
