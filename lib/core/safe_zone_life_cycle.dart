import 'dart:async';
import 'dart:math';

import '../utils/utils.dart';

class SafeZoneLifeCycle {
  final AsyncAction onActions;
  final AsyncError onError;
  final AsyncVoid onCleanUp;

  // Base delay (dipakai kalau backoff dimatikan, atau sebagai start backoff).
  final Duration _baseDelay;

  // ===== Opsi Backoff =====
  final bool enableBackoff; // aktifkan exponential backoff?
  final Duration maxBackoff; // batas maksimum backoff
  final double jitterFactor; // 0..1 → variasi +/-
  final bool resetBackoffOnCleanDisconnect; // reset backoff jika putus normal?

  SafeZoneLifeCycle({
    required this.onActions,
    required this.onError,
    required this.onCleanUp,
    Duration reconnectDelay = const Duration(seconds: 10),
    this.enableBackoff = false,
    this.maxBackoff = const Duration(minutes: 1),
    this.jitterFactor = 0.2,
    this.resetBackoffOnCleanDisconnect = true,
  }) : assert(jitterFactor >= 0 && jitterFactor <= 1),
       _baseDelay = reconnectDelay;

  bool _running = true;
  bool _connecting = false;
  Completer<void>? _lifecycleC;

  final _rand = Random();
  Duration _currentBackoff = Duration.zero;

  /// Bangunkan satu siklus (mis. dari onDone/onError koneksi stream/socket).
  void signalRetry() {
    final c = _lifecycleC;
    if (c != null && !c.isCompleted) c.complete();
  }

  /// Stop loop dengan rapi.
  void cancel() {
    _running = false;
    signalRetry(); // bangunkan kalau lagi menunggu
  }

  /// Reset state backoff ke awal (opsional dipanggil dari luar).
  void resetBackoff() {
    _currentBackoff = Duration.zero;
  }

  /// Paksa reconnect secepatnya: reset backoff + bangunkan loop.
  void reconnectNow() {
    resetBackoff();
    signalRetry();
  }

  Duration _withJitter(Duration d) {
    if (!enableBackoff || jitterFactor == 0) return d;
    final ms = d.inMilliseconds.toDouble();
    final delta = ms * jitterFactor;
    final jittered = ms + _rand.nextDouble() * (2 * delta) - delta; // ±jitter
    return Duration(milliseconds: max(0, jittered.round()));
  }

  Duration _nextDelay({required bool hadError}) {
    if (!enableBackoff) return _baseDelay;

    if (!hadError && resetBackoffOnCleanDisconnect) {
      _currentBackoff = _baseDelay;
      return _withJitter(_currentBackoff);
    }

    // Kalau error → tingkatkan (atau mulai) backoff.
    if (_currentBackoff == Duration.zero || _currentBackoff < _baseDelay) {
      _currentBackoff = _baseDelay;
    } else {
      final doubled = Duration(
        milliseconds: _currentBackoff.inMilliseconds * 2,
      );
      _currentBackoff = doubled <= maxBackoff ? doubled : maxBackoff;
    }
    return _withJitter(_currentBackoff);
  }

  /// Jalankan life-cycle berulang:
  /// - onActions: set up koneksi/listener, dsb.
  /// - onError  : terima SEMUA error (sync/async) yang tak di-handle try/catch.
  /// - onCleanUp: selalu dipanggil di akhir siklus (berhasil/gagal).
  Future<void> create() async {
    while (_running) {
      if (_connecting) {
        // Anti double-run ketika masih dalam siklus aktif.
        await Future.delayed(_baseDelay);
        continue;
      }

      _connecting = true;
      _lifecycleC = Completer<void>();
      final lifecycleDone = Completer<void>();

      var hadError = false;
      var cleaned = false;

      Future<void> cleanupOnce() async {
        if (cleaned) return;
        cleaned = true;
        try {
          await onCleanUp();
        } catch (_) {
          // Jangan biarkan error cleanup menghentikan siklus.
        }
      }

      void finishOnce([Object? e, StackTrace? st]) {
        if (!lifecycleDone.isCompleted) {
          if (e == null) {
            lifecycleDone.complete();
          } else {
            lifecycleDone.completeError(e, st ?? StackTrace.current);
          }
        }
      }

      // Tangkap error yang tidak ditangani dalam zona ini.
      runZonedGuarded(
        () async {
          try {
            // 1) Jalankan aksi (mis. connect & setup listener).
            try {
              await onActions();
            } catch (e, st) {
              // Pastikan sync error juga masuk onError.
              hadError = true;
              // Jalankan handler secara async agar tidak bentrok dengan zona.
              Future.microtask(() async {
                try {
                  await onError(e, st);
                } catch (_) {}
                signalRetry(); // bangunkan lifecycle supaya masuk finally
              });
            }

            // 2) TUNGGU sampai ada yang memanggil signalRetry() (onDone/onError/destroy)
            await _lifecycleC!.future;
          } finally {
            // 3) Cleanup per-siklus (selalu dijalankan)
            try {
              await cleanupOnce();
            } finally {
              _connecting = false;
              finishOnce(); // selesaikan siklus
            }
          }
        },
        (error, stack) {
          // runZonedGuarded handler harus sinkron → pakai microtask untuk async work
          Future.microtask(() async {
            hadError = true;
            try {
              await onError(error, stack);
            } catch (_) {}
            signalRetry(); // pastikan finally jalan
          });
        },
      );

      // >>> TUNGGU sampai siklus betul-betul selesai <<<
      await lifecycleDone.future;

      if (!_running) break;

      // Jeda sebelum mencoba lagi (base/backoff).
      final delay = _nextDelay(hadError: hadError);
      await Future.delayed(delay);
    }
  }
}
