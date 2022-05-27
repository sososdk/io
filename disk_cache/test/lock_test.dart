import 'dart:async';

import 'package:disk_cache/src/lock.dart';
import 'package:test/test.dart';

void main() {
  test('in lock', () async {
    final lock = Lock();

    expect(lock.inLock, false);
    lock.synchronized(() async {
      expect(lock.inLock, true);
      await Future.delayed(Duration(seconds: 1));
      print('${DateTime.now()}: 0');
      expect(lock.inLock, true);
    });

    print('${DateTime.now()}: 1');
    expect(lock.inLock, false);

    await Future.delayed(Duration(seconds: 1));

    expect(lock.inLock, false);

    await lock.synchronized(() => print('${DateTime.now()}: 2'));
  });

  test('non-reentrant', () async {
    final lock = Lock();
    Object? exception;
    await lock.synchronized(() async {
      try {
        await lock.synchronized(() {}, timeout: const Duration(seconds: 1));
      } catch (e) {
        exception = e;
      }
    });
    expect(exception, const TypeMatcher<TimeoutException>());
  });
}
