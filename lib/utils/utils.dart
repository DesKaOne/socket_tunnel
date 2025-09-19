import 'dart:async';
import 'dart:typed_data';

import '../core/session.dart';

typedef AsyncAction<T> = FutureOr<T> Function();
typedef AsyncError = FutureOr<void> Function(Object error, StackTrace stack);
typedef AsyncVoid = FutureOr<void> Function();

typedef OnData = FutureOr<void> Function(Uint8List payload);
typedef OnError = FutureOr<void> Function(dynamic error, StackTrace stack);
typedef OnDone = FutureOr<void> Function();

typedef SessionCallback = FutureOr<void> Function(Session session);
