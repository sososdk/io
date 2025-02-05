import 'dart:async';
import 'dart:convert';
import 'dart:core' as core show Sink;
import 'dart:core';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';

part 'buffer.dart';
part 'io.dart';
part 'sink.dart';
part 'source.dart';

const int kLF = 10; // \n
const int kCR = 13; // \r

class EOFException implements IOException {
  const EOFException();
}

void checkState(bool value, [String? message]) {
  if (!value) throw StateError(message ?? '');
}

void checkArgument(bool value, [String? message]) {
  if (!value) throw ArgumentError(message ?? '');
}

/// Object use `close` method.
extension ClosableExtension<T extends dynamic> on T {
  Future<R> use<R>(
    FutureOr<R> Function(T closable) block, [
    FutureOr<void> Function()? close,
  ]) async {
    try {
      final result = block(this);
      if (result is Future) {
        return await result;
      } else {
        return result;
      }
    } finally {
      final result = _close(close);
      if (result is Future) await result;
    }
  }

  FutureOr<void> _close([FutureOr<void> Function()? close]) async {
    final function = close ?? this?.close;
    if (function == null) return;
    final result = function();
    if (result is Future) await result;
  }
}

extension FutureClosableExtension<T extends dynamic> on Future<T> {
  Future<R> use<R>(
    FutureOr<R> Function(T closable) block, [
    FutureOr<void> Function()? close,
  ]) async {
    return ((await this) as Object?).use((e) => block(e as T), close);
  }
}
