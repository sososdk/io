import 'package:synchronized/synchronized.dart';
import 'package:test/test.dart';

void main() {
  late Lock lock;

  setUp(() {
    lock = Lock();
  });

  test('in lock', () async {
    expect(lock.inLock, false);
    await lock.synchronized(() {
      expect(lock.inLock, true);
    });
    expect(lock.inLock, false);
  });
}
