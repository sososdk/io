import 'dart:async';

extension ClosableExtension<T extends dynamic> on T {
  Future<R> use<R>(FutureOr<R> block(T closable)) async {
    try {
      return await block(this);
    } finally {
      try {
        await close();
      } catch (_) {}
    }
  }
}

extension FutureClosableExtension<T extends dynamic> on Future<T> {
  Future<R> use<R>(FutureOr<R> block(T closable)) => then((closable) async {
        try {
          return await block(closable);
        } finally {
          try {
            await closable.close();
          } catch (_) {}
        }
      });
}
