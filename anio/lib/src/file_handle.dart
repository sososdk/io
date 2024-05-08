part of 'anio.dart';

extension FileHandleFileExtension on File {
  Future<FileHandle> openHandle({FileMode mode = FileMode.read}) async {
    return FileHandle._(await open(mode: mode));
  }

  FileHandle openHandleSync({FileMode mode = FileMode.read}) {
    return FileHandle._(openSync(mode: mode));
  }
}

extension FileHandleRandomAccessFileExtension on RandomAccessFile {
  FileHandle handle() => FileHandle._(this);
}

extension FutureFileHandleExtension on Future<FileHandle> {
  Future<Sink> sink([int position = 0]) => then((e) => e.sink(position));

  Future<Source> source([int position = 0]) => then((e) => e.source(position));
}

class FileHandle {
  FileHandle._(this.file);

  final RandomAccessFile file;

  final _lock = Lock();

  var _closed = false;
  var _openCount = 0;

  Sink sink([int position = 0]) {
    checkState(!_closed, 'closed');
    _openCount++;
    return FileHandleSink(this, position);
  }

  Future<Sink> appendingSink() async {
    checkState(!_closed, 'closed');
    _openCount++;
    return FileHandleSink(this, await length());
  }

  Future<void> write(int position, Buffer source, int count) {
    checkState(!_closed, 'closed');
    return writeNoCloseCheck(position, source, count);
  }

  @internal
  Future<void> writeNoCloseCheck(int position, Buffer source, int count) async {
    RangeError.checkValueInInterval(count, 0, source._length);
    var currentOffset = position;
    final targetOffset = position + count;
    while (currentOffset < targetOffset) {
      final head = source.head!;
      final toCopy = min(targetOffset - currentOffset, head.limit - head.pos);
      final end = head.pos + toCopy;
      await protectedWrite(currentOffset, head.data, head.pos, end);
      head.pos += toCopy;
      currentOffset += toCopy;
      source._length -= toCopy;
      if (head.pos == head.limit) {
        source.head = head.pop();
      }
    }
  }

  @internal
  Future<void> protectedWrite(
      int position, List<int> bytes, int start, int end) {
    return _lock.synchronized(() async {
      await file.setPosition(position);
      await file.writeFrom(bytes, start, end);
    });
  }

  Source source([int position = 0]) {
    checkState(!_closed, 'closed');
    _openCount++;
    return FileHandleSource(this, position);
  }

  Future<int> read(int position, Buffer sink, int count) {
    checkState(!_closed, 'closed');
    return readNoCloseCheck(position, sink, count);
  }

  @internal
  Future<int> readNoCloseCheck(int position, Buffer sink, int count) async {
    checkArgument(count >= 0, 'count < 0: $count');
    var currentOffset = position;
    final targetOffset = position + count;
    while (currentOffset < targetOffset) {
      final tail = sink.writableSegment(1);
      final length = min(targetOffset - currentOffset, kBlockSize - tail.limit);
      final readCount = await protectedRead(
          currentOffset, tail.data, tail.limit, tail.limit + length);
      if (readCount == 0) {
        if (tail.pos == tail.limit) {
          // We allocated a tail segment, but didn't end up needing it. Recycle!
          sink.head = tail.pop();
        }
        // We wanted bytes but didn't return any.
        if (position == currentOffset) return 0;
        break;
      }
      tail.limit += readCount;
      currentOffset += readCount;
      sink._length += readCount;
    }
    return currentOffset - position;
  }

  @internal
  Future<int> protectedRead(int position, List<int> bytes, int start, int end) {
    return _lock.synchronized(() async {
      await file.setPosition(position);
      var bytesRead = 0;
      while (bytesRead < end - start) {
        final readResult = await file.readInto(bytes, start + bytesRead, end);
        if (readResult == 0) break;
        bytesRead += readResult;
      }
      return bytesRead;
    });
  }

  int positionSink(Sink sink) {
    var bufferSize = 0;

    if (sink is RealBufferedSink) {
      bufferSize = sink.buffer._length;
      sink = sink._sink;
    }

    checkArgument(
      sink is FileHandleSink && identical(sink.fileHandle, this),
      'sink was not created by this FileHandle',
    );
    sink = sink as FileHandleSink;
    checkState(!sink._closed, 'closed');

    return sink._position + bufferSize;
  }

  /// Change the position of [sink] in the file to [position]. The argument [sink] must be either a
  /// sink produced by this file handle, or a [BufferedSink] that directly wraps such a sink. If the
  /// parameter is a [BufferedSink], it emits for buffered bytes.
  Future<void> repositionSink(Sink sink, int position) async {
    if (sink is RealBufferedSink) {
      var fileHandleSink = sink._sink;
      checkArgument(
        fileHandleSink is FileHandleSink &&
            identical(fileHandleSink.fileHandle, this),
        'sink was not created by this FileHandle',
      );
      fileHandleSink = fileHandleSink as FileHandleSink;
      checkState(!fileHandleSink._closed, 'closed');

      await sink.emit();
      fileHandleSink._position = position;
    } else {
      checkArgument(sink is FileHandleSink && identical(sink.fileHandle, this),
          'sink was not created by this FileHandle');
      sink = sink as FileHandleSink;
      checkState(!sink._closed, 'closed');
      sink._position = position;
    }
  }

  int positionSource(Source source) {
    var bufferSize = 0;

    if (source is RealBufferedSource) {
      bufferSize = source.buffer._length;
      source = source._source;
    }

    checkArgument(
      source is FileHandleSource && identical(source.fileHandle, this),
      'source was not created by this FileHandle',
    );
    source = source as FileHandleSource;
    checkState(!source._closed, 'closed');

    return source._position - bufferSize;
  }

  /// Change the position of [source] in the file to [position]. The argument [source] must be either
  /// a source produced by this file handle, or a [BufferedSource] that directly wraps such a source.
  /// If the parameter is a [BufferedSource], it will skip or clear buffered bytes.
  Future<void> repositionSource(Source source, int position) async {
    if (source is RealBufferedSource) {
      var fileHandleSource = source._source;
      checkArgument(
        fileHandleSource is FileHandleSource &&
            identical(fileHandleSource.fileHandle, this),
        'source was not created by this FileHandle',
      );
      fileHandleSource = fileHandleSource as FileHandleSource;
      checkState(!fileHandleSource._closed, 'closed');

      final bufferSize = source.buffer._length;
      final toSkip = position - (fileHandleSource._position - bufferSize);
      if (0 <= toSkip && toSkip < bufferSize) {
        // The new position requires only a buffer change.
        source.buffer.skip(toSkip);
      } else {
        // The new position doesn't share data with the current buffer.
        source.buffer.clear();
        fileHandleSource._position = position;
      }
    } else {
      checkArgument(
        source is FileHandleSource && identical(source.fileHandle, this),
        'source was not created by this FileHandle',
      );
      source = source as FileHandleSource;
      checkState(!source._closed, 'closed');
      source._position = position;
    }
  }

  Future<int> position() {
    checkState(!_closed, 'closed');
    return _lock.synchronized(() => file.position());
  }

  Future<void> truncate(int length) {
    checkState(!_closed, 'closed');
    return _lock.synchronized(() => file.truncate(length));
  }

  Future<int> length() {
    checkState(!_closed, 'closed');
    return _lock.synchronized(() => file.length());
  }

  Future<void> flush() {
    checkState(!_closed, 'closed');
    return _lock.synchronized(() => file.flush());
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_openCount != 0) return;
    return _lock.synchronized(() => file.close());
  }

  Future<void> _closeOpened() async {
    _openCount--;
    if (_openCount != 0 || !_closed) return;
    return _lock.synchronized(() => file.close());
  }
}

@internal
class FileHandleSink implements Sink {
  FileHandleSink(this.fileHandle, int position) : _position = position;

  final FileHandle fileHandle;

  int _position;

  var _closed = false;

  @override
  Future<void> write(Buffer source, int count) async {
    checkState(!_closed, 'closed');
    await fileHandle.writeNoCloseCheck(_position, source, count);
    _position += count;
  }

  @override
  Future<void> flush() {
    checkState(!_closed, 'closed');
    return fileHandle.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    return fileHandle._closeOpened();
  }
}

@internal
class FileHandleSource implements Source {
  FileHandleSource(this.fileHandle, int position) : _position = position;

  final FileHandle fileHandle;

  int _position;

  var _closed = false;

  @override
  Future<int> read(Buffer sink, int count) async {
    checkState(!_closed, 'closed');
    final result = await fileHandle.readNoCloseCheck(_position, sink, count);
    if (result != 0) _position += result;
    return result;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    return fileHandle._closeOpened();
  }
}
