import 'dart:async';
import 'dart:convert';
import 'dart:core' as core show Sink;
import 'dart:core';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:synchronizer/synchronizer.dart';

part 'buffer.dart';
part 'file_handle.dart';
part 'sink.dart';
part 'source.dart';

const int kLF = 10; // \n
const int kCR = 13; // \r
/// The size of all segments in bytes.
@visibleForTesting
const int kBlockSize = 8192;

/// Segments will be shared when doing so avoids `arraycopy()` of this many bytes.
@visibleForTesting
const int kShareMinimum = 1024;

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
      final result = safeClose(close);
      if (result is Future) await result;
    }
  }

  FutureOr<void> safeClose([FutureOr<void> Function()? close]) async {
    try {
      final function = close ?? this?.close;
      if (function == null) return;
      final result = function();
      if (result is Future) await result;
    } catch (_) {}
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
