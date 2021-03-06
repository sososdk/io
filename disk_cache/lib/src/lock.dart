import 'dart:async';

/// Object providing the implicit lock.
class Lock {
  /// The last running block.
  Future<dynamic>? last;

  /// returns true if the lock is currently locked.
  bool get locked => last != null;

  /// Test whether we are currently in the synchronized section.
  bool get inLock => Zone.current[this] ?? false;

  /// Executes [computation] when lock is available.
  ///
  /// Only one asynchronous block can run while the lock is retained. if
  /// [timeout] is not null, it will timeout after the specified duration.
  Future<T> synchronized<T>(
    FutureOr<T> Function() computation, {
    Duration? timeout,
  }) async {
    final prev = last;
    final completer = Completer.sync();
    last = completer.future;
    try {
      // If there is a previous running block, wait for it.
      if (prev != null) {
        if (timeout != null) {
          // This could throw a timeout error.
          await prev.timeout(timeout);
        } else {
          await prev;
        }
      }

      // Run the function and return the result.
      return await runZoned(() => computation(), zoneValues: {this: true});
    } finally {
      // Cleanup.
      // waiting for the previous task to be done in case of timeout.
      void complete() {
        // Only mark it unlocked when the last one complete.
        if (identical(last, completer.future)) {
          last = null;
        }
        completer.complete();
      }

      // In case of timeout, wait for the previous one to complete too
      // before marking this task as complete.

      if (prev != null && timeout != null) {
        // But we still returns immediately.
        unawaited(prev.then((_) => complete()));
      } else {
        complete();
      }
    }
  }

  @override
  String toString() => 'Lock[${identityHashCode(this)}]';
}
