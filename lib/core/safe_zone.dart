import 'dart:async';

import '../utils/utils.dart';

class SafeZone {
  final AsyncAction onActions;
  final AsyncError? onError;
  final AsyncVoid? onCleanUp;

  SafeZone({required this.onActions, this.onError, this.onCleanUp});

  Future<void> create() {
    final completer = Completer<void>();
    var cleaned = false;
    var errorHandled = false;

    Future<void> cleanupOnce() async {
      if (!cleaned) {
        cleaned = true;
        if (onCleanUp != null) {
          try {
            await onCleanUp!();
          } catch (_) {
            // sengaja diabaikan agar cleanup gak mengganggu alur error utama
          }
        }
      }
    }

    Future<void> handleErrorOnce(Object e, StackTrace st) async {
      if (!errorHandled) {
        errorHandled = true;
        if (onError != null) {
          try {
            await onError!(e, st);
          } catch (_) {
            // kalau handler error sendiri error, yaudah jangan ganggu alur
          }
        }
      }
    }

    runZonedGuarded(
      () async {
        try {
          await onActions();
          // sukses
          if (!completer.isCompleted) completer.complete();
        } catch (e, st) {
          // error dalam task utama
          // kita proses handler secara async di microtask
          Future.microtask(() async {
            await handleErrorOnce(e, st);
            await cleanupOnce();
            if (!completer.isCompleted) completer.completeError(e, st);
          });
        } finally {
          // kalau tidak ada error, tetap cleanup
          // (kalau ada error, branch di atas sudah handle cleanup)
          Future.microtask(() async {
            await cleanupOnce();
          });
        }
      },
      (e, st) {
        // Handler runZonedGuarded TIDAK async → pakai microtask
        Future.microtask(() async {
          await handleErrorOnce(e, st);
          await cleanupOnce();
          if (!completer.isCompleted) completer.completeError(e, st);
        });
      },
    );

    return completer.future;
  }
}
