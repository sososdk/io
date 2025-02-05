part of 'anio.dart';

abstract mixin class AsyncDispatcher {
  @protected
  var asyncDispatched = false;
  @protected
  var closed = false;

  @protected
  Future<T> dispatch<T>(Future<T> Function() f, {bool close = false}) async {
    if (closed) return Future.error(closedMessage());
    if (asyncDispatched) return Future.error(dispatchedMessage());
    if (close) closed = true;
    asyncDispatched = true;
    return f().whenComplete(() => asyncDispatched = false);
  }

  @protected
  void checkAvailable() {
    if (asyncDispatched) throw dispatchedMessage();
    if (closed) throw closedMessage();
  }

  @protected
  Object closedMessage() => StateError('closed');

  @protected
  Object dispatchedMessage() {
    return StateError('An async operation is currently pending');
  }
}

abstract interface class FileHandle implements RandomAccessFile {
  factory FileHandle(RandomAccessFile delegate) = _FileHandleImpl;

  @visibleForTesting
  int get openCount;

  @override
  Future<FileHandle> flush();

  @override
  Future<FileHandle> lock(
      [FileLock mode = FileLock.exclusive, int start = 0, int end = -1]);

  @override
  Future<FileHandle> unlock([int start = 0, int end = -1]);

  @override
  Future<FileHandle> setPosition(int position);

  @override
  Future<FileHandle> truncate(int length);

  @override
  Future<FileHandle> writeByte(int value);

  @override
  Future<FileHandle> writeFrom(List<int> buffer, [int start = 0, int? end]);

  @override
  Future<FileHandle> writeString(String string, {Encoding encoding = utf8});

  Future<int> readIntoSink(Buffer sink, int count);

  Future<int> readIntoSinkWithPosition(int position, Buffer sink, int count);

  int readIntoSinkSync(Buffer sink, int count);

  int readIntoSinkWithPositionSync(int position, Buffer sink, int count);

  Future<FileHandle> writeFromSource(Buffer source, int count);

  void writeFromSourceSync(Buffer source, int count);

  Future<FileHandle> writeFromSourceWithPosition(
      int position, Buffer source, int count);

  void writeFromSourceWithPositionSync(int position, Buffer source, int count);

  FileSource source([int position = 0]);

  FileSink sink([int position = 0]);
}

mixin FileHandleBase implements FileHandle {
  @protected
  RandomAccessFile get delegate;

  @override
  @visibleForTesting
  var openCount = 0;

  @protected
  var asyncDispatched = false;

  @protected
  Future<T> dispatch<T>(Future<T> Function() f, {bool close = false}) async {
    if (openCount < 0) return Future.error(closedMessage());
    if (asyncDispatched) return Future.error(dispatchedMessage());
    if (close) openCount--;
    asyncDispatched = true;
    return f().whenComplete(() => asyncDispatched = false);
  }

  @protected
  void checkAvailable() {
    if (asyncDispatched) throw dispatchedMessage();
    if (openCount < 0) throw closedMessage();
  }

  @protected
  Object closedMessage() {
    return FileSystemException('File closed', path);
  }

  @protected
  Object dispatchedMessage() {
    return FileSystemException('An async operation is currently pending', path);
  }

  @override
  Future<FileHandle> flush() => dispatch(() async {
        await delegate.flush();
        return this;
      });

  @override
  void flushSync() {
    checkAvailable();
    return delegate.flushSync();
  }

  @override
  Future<int> length() => dispatch(delegate.length);

  @override
  int lengthSync() {
    checkAvailable();
    return delegate.lengthSync();
  }

  @override
  Future<FileHandle> lock(
      [FileLock mode = FileLock.exclusive, int start = 0, int end = -1]) {
    return dispatch(() async {
      await delegate.lock(mode, start, end);
      return this;
    });
  }

  @override
  void lockSync(
      [FileLock mode = FileLock.exclusive, int start = 0, int end = -1]) {
    checkAvailable();
    return delegate.lockSync(mode, start, end);
  }

  @override
  Future<FileHandle> unlock([int start = 0, int end = -1]) {
    return dispatch(() async {
      await delegate.unlock(start, end);
      return this;
    });
  }

  @override
  void unlockSync([int start = 0, int end = -1]) {
    checkAvailable();
    return delegate.unlockSync(start, end);
  }

  @override
  String get path => delegate.path;

  @override
  Future<int> position() => dispatch(delegate.position);

  @override
  int positionSync() {
    checkAvailable();
    return delegate.positionSync();
  }

  @override
  Future<Uint8List> read(int count) => dispatch(() => delegate.read(count));

  @override
  Uint8List readSync(int count) {
    checkAvailable();
    return delegate.readSync(count);
  }

  @override
  Future<int> readByte() => dispatch(delegate.readByte);

  @override
  int readByteSync() {
    checkAvailable();
    return delegate.readByteSync();
  }

  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) {
    return dispatch(() => delegate.readInto(buffer, start, end));
  }

  @override
  int readIntoSync(List<int> buffer, [int start = 0, int? end]) {
    checkAvailable();
    return delegate.readIntoSync(buffer, start, end);
  }

  @override
  Future<FileHandle> setPosition(int position) => dispatch(() async {
        await delegate.setPosition(position);
        return this;
      });

  @override
  void setPositionSync(int position) {
    checkAvailable();
    return delegate.setPositionSync(position);
  }

  @override
  Future<FileHandle> truncate(int length) => dispatch(() async {
        await delegate.truncate(length);
        return this;
      });

  @override
  void truncateSync(int length) {
    checkAvailable();
    return delegate.truncateSync(length);
  }

  @override
  Future<FileHandle> writeByte(int value) => dispatch(() async {
        await delegate.writeByte(value);
        return this;
      });

  @override
  int writeByteSync(int value) {
    checkAvailable();
    return delegate.writeByteSync(value);
  }

  @override
  Future<FileHandle> writeFrom(List<int> buffer, [int start = 0, int? end]) {
    return dispatch(() async {
      await delegate.writeFrom(buffer, start, end);
      return this;
    });
  }

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {
    checkAvailable();
    return delegate.writeFromSync(buffer, start, end);
  }

  @override
  Future<FileHandle> writeString(String string, {Encoding encoding = utf8}) {
    return dispatch(() async {
      await delegate.writeString(string, encoding: encoding);
      return this;
    });
  }

  @override
  void writeStringSync(String string, {Encoding encoding = utf8}) {
    checkAvailable();
    return delegate.writeStringSync(string, encoding: encoding);
  }

  Future<int> _readIntoSink(Buffer sink, int count) async {
    var bytesRead = 0;
    while (count > bytesRead) {
      final tail = sink.writableSegment(1);
      final length = min(count - bytesRead, Segment.size - tail.limit);
      final bytes = tail.data;
      final start = tail.limit;
      final end = tail.limit + length;
      final readResult = await delegate.readInto(bytes, start, end);
      if (readResult == 0) {
        if (tail.pos == tail.limit) {
          // We allocated a tail segment, but didn't end up needing it. Recycle!
          sink.head = tail.pop();
        }
        break;
      }
      tail.limit += readResult;
      bytesRead += readResult;
      sink.length += readResult;
    }
    return bytesRead;
  }

  @override
  Future<int> readIntoSink(Buffer sink, int count) {
    checkArgument(count >= 0, 'count < 0: $count');
    return dispatch(() => _readIntoSink(sink, count));
  }

  @override
  Future<int> readIntoSinkWithPosition(int position, Buffer sink, int count) {
    checkArgument(count >= 0, 'count < 0: $count');
    return dispatch(() =>
        delegate.setPosition(position).then((e) => _readIntoSink(sink, count)));
  }

  int _readIntoSinkSync(Buffer sink, int count) {
    var bytesRead = 0;
    while (count > bytesRead) {
      final tail = sink.writableSegment(1);
      final length = min(count - bytesRead, Segment.size - tail.limit);
      final bytes = tail.data;
      final start = tail.limit;
      final end = tail.limit + length;
      final readResult = delegate.readIntoSync(bytes, start, end);
      if (readResult == 0) {
        if (tail.pos == tail.limit) {
          // We allocated a tail segment, but didn't end up needing it. Recycle!
          sink.head = tail.pop();
        }
        break;
      }
      tail.limit += readResult;
      bytesRead += readResult;
      sink.length += readResult;
    }
    return bytesRead;
  }

  @override
  int readIntoSinkSync(Buffer sink, int count) {
    checkAvailable();
    checkArgument(count >= 0, 'count < 0: $count');
    return _readIntoSinkSync(sink, count);
  }

  @override
  int readIntoSinkWithPositionSync(int position, Buffer sink, int count) {
    checkAvailable();
    checkArgument(count >= 0, 'count < 0: $count');
    setPositionSync(position);
    return _readIntoSinkSync(sink, count);
  }

  Future<void> _writeFromSource(Buffer source, int count) async {
    while (count > 0) {
      final head = source.head!;
      final toCopy = min(count, head.limit - head.pos);
      final end = head.pos + toCopy;
      await delegate.writeFrom(head.data, head.pos, end);
      head.pos += toCopy;
      count -= toCopy;
      source.length -= toCopy;
      if (head.pos == head.limit) {
        source.head = head.pop();
      }
    }
  }

  @override
  Future<FileHandle> writeFromSource(Buffer source, int count) {
    RangeError.checkValueInInterval(count, 0, source.length);
    return dispatch(() async {
      await _writeFromSource(source, count);
      return this;
    });
  }

  @override
  Future<FileHandle> writeFromSourceWithPosition(
      int position, Buffer source, int count) {
    RangeError.checkValueInInterval(count, 0, source.length);
    return dispatch(() => delegate.setPosition(position).then((e) async {
          await _writeFromSource(source, count);
          return this;
        }));
  }

  void _writeFromSourceSync(Buffer source, int count) {
    while (count > 0) {
      final head = source.head!;
      final toCopy = min(count, head.limit - head.pos);
      final end = head.pos + toCopy;
      delegate.writeFromSync(head.data, head.pos, end);
      head.pos += toCopy;
      count -= toCopy;
      source.length -= toCopy;
      if (head.pos == head.limit) {
        source.head = head.pop();
      }
    }
  }

  @override
  void writeFromSourceSync(Buffer source, int count) {
    checkAvailable();
    RangeError.checkValueInInterval(count, 0, source.length);
    _writeFromSourceSync(source, count);
  }

  @override
  void writeFromSourceWithPositionSync(int position, Buffer source, int count) {
    checkAvailable();
    RangeError.checkValueInInterval(count, 0, source.length);
    delegate.setPositionSync(position);
    _writeFromSourceSync(source, count);
  }

  @override
  FileSource source([int position = 0]) {
    checkAvailable();
    openCount++;
    return FileSource(this, position);
  }

  @override
  FileSink sink([int position = 0]) {
    checkAvailable();
    openCount++;
    return FileSink(this, position);
  }

  @override
  Future<void> close() async {
    return dispatch(() async {
      if (openCount < 0) await delegate.close();
    }, close: true);
  }

  @override
  void closeSync() {
    checkAvailable();
    openCount--;
    if (openCount < 0) delegate.closeSync();
  }
}

class _FileHandleImpl with FileHandleBase {
  @override
  final RandomAccessFile delegate;

  _FileHandleImpl(this.delegate);
}

extension FileHandleRandomAccessFileExtension on RandomAccessFile {
  FileHandle handle() => FileHandle(this);
}

extension FileHandleFileExtension on File {
  Future<FileHandle> openHandle({FileMode mode = FileMode.read}) async {
    return open(mode: mode).then((e) => e.handle());
  }

  FileHandle openHandleSync({FileMode mode = FileMode.read}) {
    return openSync(mode: mode).handle();
  }
}

extension FutureFileHandleExtension on Future<FileHandle> {
  Future<FileSource> source([int position = 0]) {
    return then((e) => e.source(position));
  }

  Future<FileSink> sink([int position = 0]) => then((e) => e.sink(position));
}

extension NullableFutureFileHandleExtension on Future<FileHandle?> {
  Future<FileSource?> source([int position = 0]) {
    return then((e) => e?.source(position));
  }

  Future<FileSink?> sink([int position = 0]) => then((e) => e?.sink(position));
}

class FileSource with AsyncDispatcher implements Source {
  FileSource(this.handle, int position) : _position = position;

  final FileHandle handle;

  int _position;

  int get position {
    checkAvailable();
    return _position;
  }

  set position(int value) {
    checkAvailable();
    _position = value;
  }

  @override
  Future<int> read(Buffer sink, int count) => dispatch(() async {
        final n = await handle.readIntoSinkWithPosition(_position, sink, count);
        _position += n;
        return n;
      });

  @override
  Future<void> close() {
    return dispatch(handle.close, close: true);
  }
}

class FileSink with AsyncDispatcher implements Sink {
  FileSink(this.handle, int position) : _position = position;

  final FileHandle handle;

  int _position;

  int get position {
    checkAvailable();
    return _position;
  }

  set position(int value) {
    checkAvailable();
    _position = value;
  }

  @override
  Future<void> write(Buffer source, int count) {
    return dispatch(() async {
      await handle.writeFromSourceWithPosition(_position, source, count);
      _position += count;
    });
  }

  @override
  Future<void> flush() {
    return dispatch(handle.flush);
  }

  @override
  Future<void> close() async {
    return dispatch(handle.close, close: true);
  }
}

extension BufferedFileSourceExtension on BufferedSource {
  int get position {
    Source source = this;
    var bufferSize = 0;
    while (source is RealBufferedSource) {
      bufferSize += source.buffer.length;
      source = source.source;
    }
    checkArgument(source is FileSource, 'source was not a $FileSource');
    source = source as FileSource;
    return source.position - bufferSize;
  }

  set position(int value) {
    Source source = this;
    var bufferSize = 0;
    while (source is RealBufferedSource) {
      bufferSize += source.buffer.length;
      source = source.source;
    }
    checkArgument(source is FileSource, 'source was not a $FileSource');
    source = source as FileSource;
    var toSkip = value - (source.position - bufferSize);
    if (0 <= toSkip && toSkip < bufferSize) {
      // The new position requires only a buffer change.
      Source temp = this;
      while (toSkip > 0 && temp is RealBufferedSource) {
        final count = min(toSkip, temp.buffer.length);
        temp.buffer.skip(count);
        toSkip -= count;
        temp = temp.source;
      }
    } else {
      // The new position doesn't share data with the current buffer.
      Source temp = this;
      while (temp is RealBufferedSource) {
        temp.buffer.clear();
        temp = temp.source;
      }
      source.position = value;
    }
  }
}

extension BufferedFileSinkExtension on BufferedSink {
  int get position {
    Sink sink = this;
    var bufferSize = 0;
    while (sink is RealBufferedSink) {
      bufferSize += sink.buffer.length;
      sink = sink.sink;
    }
    checkArgument(sink is FileSink, 'sink was not a $FileSink');
    sink = sink as FileSink;
    return sink.position + bufferSize;
  }

  set position(int value) {
    Sink sink = this;
    var bufferSize = 0;
    while (sink is RealBufferedSink) {
      bufferSize += sink.buffer.length;
      sink = sink.sink;
    }
    checkArgument(sink is FileSink, 'sink was not a $FileSink');
    if (bufferSize > 0) throw StateError('buffer not emitted');
    sink = sink as FileSink;
    sink.position = value;
  }
}
