import 'dart:async';

import 'package:anio/anio.dart';
import 'package:test/expect.dart';

class MockSink implements Sink {
  final log = <String>[];
  final callThrows = <int, Object>{};

  void assertLog(List<String> messages) {
    expect(messages.toList(), log);
  }

  void assertLogContains(String message) {
    expect(log.contains(message), isTrue);
  }

  void scheduleThrow(int call, Object e) {
    callThrows[call] = e;
  }

  void throwIfScheduled() {
    final exception = callThrows[log.length - 1];
    if (exception != null) throw exception;
  }

  @override
  FutureOr<void> write(Buffer source, int count) {
    log.add('write($source, $count)');
    source.skip(count);
    throwIfScheduled();
  }

  @override
  FutureOr<void> flush() {
    log.add('flush()');
    throwIfScheduled();
  }

  @override
  FutureOr<void> close() {
    log.add('close()');
    throwIfScheduled();
  }
}
