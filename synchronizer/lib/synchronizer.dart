library;

import 'dart:async';

abstract interface class Lock {
  factory Lock() = _Lock;

  factory Lock.reentrant() = _ReentrantLock;

  /// Executes [computation] when lock is available.
  ///
  /// Only one asynchronous block can run while the lock is retained.
  ///
  /// If [timeout] is specified, it will try to grab the lock and will not
  /// call the computation callback and throw a [TimeoutException] if the lock
  /// cannot be grabbed in the given duration.
  Future<T> synchronized<T>(FutureOr<T> Function() computation,
      {Duration? timeout, bool checkReentrant = true});
}

class _Lock implements Lock {
  /// The last running block.
  Future<dynamic>? _last;

  @override
  Future<T> synchronized<T>(
    FutureOr<T> Function() computation, {
    Duration? timeout,
    bool checkReentrant = true,
  }) async {
    if (checkReentrant && (Zone.current[this] ?? false)) {
      throw StateError('Can not reentrant.');
    }

    final prev = _last;
    final completer = Completer.sync();
    _last = completer.future;
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
      final result = runZoned(() => computation(), zoneValues: {this: true});
      if (result is Future) {
        return await result;
      } else {
        return result;
      }
    } finally {
      // Waiting for the previous task to be done in case of timeout.
      void complete() {
        // Only mark it unlocked when the last one complete.
        if (identical(_last, completer.future)) {
          _last = null;
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

class _ReentrantLock implements Lock {
  final _lock = _Lock();

  @override
  Future<T> synchronized<T>(
    FutureOr<T> Function() computation, {
    Duration? timeout,
    bool checkReentrant = true,
  }) {
    return ((Zone.current[this] as _Lock?) ?? _lock).synchronized(() async {
      final result = runZoned(() => computation(), zoneValues: {this: _Lock()});
      if (result is Future) {
        return await result;
      } else {
        return result;
      }
    }, timeout: timeout, checkReentrant: checkReentrant);
  }

  @override
  String toString() => 'ReentrantLock[${identityHashCode(this)}]';
}
