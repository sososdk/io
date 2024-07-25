import 'dart:async';

import 'package:synchronizer/synchronizer.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  group('Lock', () {
    run(() => Lock());
  });
  group('ReentrantLock', () {
    run(() => Lock.reentrant());

    group('reentrant', () {
      // only for reentrant-lock
      test('nested', () async {
        final lock = Lock.reentrant();

        final list = <int>[];
        final future1 = lock.synchronized(() async {
          list.add(1);
          await lock.synchronized(() async {
            await sleep(10);
            list.add(2);
          });
          list.add(3);
        });
        final future2 = lock.synchronized(() {
          list.add(4);
        });
        await Future.wait([future1, future2]);
        expect(list, [1, 2, 3, 4]);
      });

      test('inner_value', () async {
        final lock = Lock.reentrant();

        expect(
            await lock.synchronized(() async {
              expect(
                  await lock.synchronized(() {
                    return 'inner';
                  }),
                  'inner');
              return 'outer';
            }),
            'outer');
      });

      test('inner_vs_outer', () async {
        final lock = Lock.reentrant();

        final list = <int>[];
        // ignore: unawaited_futures
        lock.synchronized(() async {
          await sleep(1);
          list.add(1);

          // This one should execute before
          return lock.synchronized(() async {
            await sleep(1);
            list.add(2);
          });
        });
        await lock.synchronized(() async {
          list.add(3);
        });
        expect(list, [1, 2, 3]);
      });

      test('inner_no_wait', () async {
        final lock = Lock.reentrant();
        final list = <int>[];
        // ignore: unawaited_futures
        lock.synchronized(() {
          list.add(1);
          return lock.synchronized(() async {
            await sleep(1);
            list.add(3);
          });
        });
        list.add(2);
        await lock.synchronized(() async {
          list.add(4);
        });
        expect(list, [1, 2, 3, 4]);
      });

      test('two_locks', () async {
        final lock1 = Lock.reentrant();
        final lock2 = Lock.reentrant();

        expect(Zone.current[lock1], isNull);

        bool? ok;
        await lock1.synchronized(() async {
          expect(Zone.current[lock1], isNotNull);
          expect(Zone.current[lock2], isNull);
          await lock2.synchronized(() async {
            expect(Zone.current[lock2], isNotNull);
            expect(Zone.current[lock1], isNotNull);

            ok = true;
          });
        });
        expect(ok, isTrue);
      });

      test('late', () async {
        final lock = Lock.reentrant();
        final completer = Completer<void>();
        await lock.synchronized(() {
          sleep(1).then((_) async {
            try {
              await lock.synchronized(() {});
            } finally {
              completer.complete();
            }
          });
        });
        await completer.future;
      });
    });

    group('error', () {
      test('inner_throw', () async {
        final lock = Lock.reentrant();
        try {
          await lock.synchronized(() async {
            await lock.synchronized(() {
              throw 'throwing';
            });
          });
          fail('should throw'); // ignore: dead_code
        } catch (e) {
          expect(e is TestFailure, isFalse);
        }

        await lock.synchronized(() {});
      });

      test('inner_throw_async', () async {
        final lock = Lock.reentrant();
        try {
          await lock.synchronized(() async {
            await lock.synchronized(() async {
              throw 'throwing';
            });
          });
          fail('should throw'); // ignore: dead_code
        } catch (e) {
          expect(e is TestFailure, isFalse);
        }
        await sleep(1);
      });
    });
  });
}

void run(Lock Function() newLock) {
  group('base lock', () {
    test('two_locks', () async {
      final lock1 = Lock();
      final lock2 = Lock();

      bool? ok;
      await lock1.synchronized(() async {
        await lock2.synchronized(() async {
          ok = true;
        });
      });
      expect(ok, isTrue);
    });

    test('order', () async {
      final lock = Lock();
      final list = <int>[];
      final future1 = lock.synchronized(() async {
        list.add(1);
      });
      final future2 = lock.synchronized(() async {
        await sleep(10);
        list.add(2);
        return 'text';
      });
      final future3 = lock.synchronized(() {
        list.add(3);
        return 1234;
      });
      expect(list, [1]);
      await Future.wait([future1, future2, future3]);
      expect(await future1, isNull);
      expect(await future2, 'text');
      expect(await future3, 1234);
      expect(list, [1, 2, 3]);
    });

    test('queued_value', () async {
      final lock = Lock();
      final value1 = lock.synchronized(() async {
        await sleep(1);
        return 'value1';
      });
      expect(await lock.synchronized(() => 'value2'), 'value2');
      expect(await value1, 'value1');
    });
  });

  group('perf', () {
    const operationCount = 10000;

    test('$operationCount operations', () async {
      const count = operationCount;
      int j;

      final sw1 = Stopwatch();
      j = 0;
      sw1.start();
      for (var i = 0; i < count; i++) {
        j += i;
      }
      sw1.stop();
      expect(j, count * (count - 1) / 2);

      final sw2 = Stopwatch();
      j = 0;
      sw2.start();
      for (var i = 0; i < count; i++) {
        await () async {
          j += i;
        }();
      }
      sw2.stop();
      expect(j, count * (count - 1) / 2);

      final lock = Lock();
      final sw3 = Stopwatch();
      j = 0;
      sw3.start();
      for (var i = 0; i < count; i++) {
        // ignore: unawaited_futures
        lock.synchronized(() {
          j += i;
        });
      }
      // final wait
      await lock.synchronized(() => {});
      sw3.stop();
      expect(j, count * (count - 1) / 2);

      final sw4 = Stopwatch();
      j = 0;
      sw4.start();
      for (var i = 0; i < count; i++) {
        await lock.synchronized(() async {
          await Future<void>.value();
          j += i;
        });
      }
      // final wait
      sw4.stop();
      expect(j, count * (count - 1) / 2);

      print('  none ${sw1.elapsed}');
      print(' await ${sw2.elapsed}');
      print(' syncd ${sw3.elapsed}');
      print('asyncd ${sw4.elapsed}');
    });
  });

  group('timeout', () {
    test('1_ms', () async {
      final lock = Lock();
      final completer = Completer<void>();
      final future = lock.synchronized(() async {
        await completer.future;
      });
      try {
        await lock.synchronized(() {},
            timeout: const Duration(milliseconds: 1));
        fail('should fail');
      } on TimeoutException catch (_) {}
      completer.complete();
      await future;
    });

    test('100_ms', () async {
      // var isNewTiming = await isDart2AsyncTiming();
      // hoping timint is ok...
      final lock = Lock();

      var ran1 = false;
      var ran2 = false;
      var ran3 = false;
      var ran4 = false;
      // hold for 5ms
      // ignore: unawaited_futures
      lock.synchronized(() async {
        await sleep(1000);
      });

      try {
        await lock.synchronized(() {
          ran1 = true;
        }, timeout: const Duration(milliseconds: 1));
      } on TimeoutException catch (_) {}

      try {
        await lock.synchronized(() async {
          await sleep(5000);
          ran2 = true;
        }, timeout: const Duration(milliseconds: 1));
        // fail('should fail');
      } on TimeoutException catch (_) {}

      try {
        // ignore: unawaited_futures
        lock.synchronized(() {
          ran4 = true;
        }, timeout: const Duration(milliseconds: 2000));
      } on TimeoutException catch (_) {}

      // waiting long enough
      await lock.synchronized(() {
        ran3 = true;
      }, timeout: const Duration(milliseconds: 2000));

      expect(ran1, isFalse, reason: 'ran1 should be false');
      expect(ran2, isFalse, reason: 'ran2 should be false');
      expect(ran3, isTrue, reason: 'ran3 should be true');
      expect(ran4, isTrue, reason: 'ran4 should be true');
    });

    test('1_ms_with_error', () async {
      var ok = false;
      var okTimeout = false;
      try {
        final lock = Lock();
        final completer = Completer<void>();
        unawaited(lock.synchronized(() async {
          await completer.future;
        }).catchError((e) {}));
        try {
          await lock.synchronized(() {},
              timeout: const Duration(milliseconds: 1));
          fail('should fail');
        } on TimeoutException catch (_) {}
        completer.completeError('error');
        // await future;
        // await lock.synchronized(null, timeout: Duration(milliseconds: 1000));

        // Make sure these block ran
        await lock.synchronized(() {
          ok = true;
        });
        await lock.synchronized(() {
          okTimeout = true;
        }, timeout: const Duration(milliseconds: 1000));
      } catch (_) {}
      expect(ok, isTrue);
      expect(okTimeout, isTrue);
    });
  });

  group('error', () {
    test('throw', () async {
      final lock = Lock();
      try {
        await lock.synchronized(() {
          throw 'throwing';
        });
        fail('should throw'); // ignore: dead_code
      } catch (e) {
        expect(e is TestFailure, isFalse);
      }

      var ok = false;
      await lock.synchronized(() {
        ok = true;
      });
      expect(ok, isTrue);
    });

    test('queued_throw', () async {
      final lock = Lock();

      // delay so that it is queued
      // ignore: unawaited_futures
      lock.synchronized(() {
        return sleep(1);
      });
      try {
        await lock.synchronized(() async {
          throw 'throwing';
        });
        fail('should throw'); // ignore: dead_code
      } catch (e) {
        expect(e is TestFailure, isFalse);
      }

      var ok = false;
      await lock.synchronized(() {
        ok = true;
      });
      expect(ok, isTrue);
    });

    test('throw_async', () async {
      final lock = Lock();
      try {
        await lock.synchronized(() async {
          throw 'throwing';
        });
        fail('should throw'); // ignore: dead_code
      } catch (e) {
        expect(e is TestFailure, isFalse);
      }
    });
  });

  group('immediacity', () {
    test('sync', () async {
      final lock = Lock();
      int? value;
      final future = lock.synchronized(() {
        value = 1;
        return Future<void>.value().then((_) {
          value = 2;
        });
      });
      // A sync method is executed right away!
      expect(value, 1);
      await future;
      expect(value, 2);
    });

    test('async', () async {
      final lock = Lock();
      int? value;
      final future = lock.synchronized(() async {
        value = 1;
        return Future<void>.value().then((_) {
          value = 2;
        });
      });
      // A sync method is executed right away!
      expect(value, 1);
      await future;
      expect(value, 2);
    });
  });
}
