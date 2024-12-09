part of 'anio.dart';

extension RandomAccessFileExtension on RandomAccessFile {
  Future<int> readIntoSink(Buffer sink, int count) async {
    checkArgument(count >= 0, 'count < 0: $count');
    var bytesRead = 0;
    while (count > bytesRead) {
      final tail = sink.writableSegment(1);
      final length = min(count - bytesRead, Segment.size - tail.limit);
      final bytes = tail.data;
      final start = tail.limit;
      final end = tail.limit + length;
      final readResult = await readInto(bytes, start, end);
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

  Future<void> writeFromSource(Buffer source, int count) async {
    RangeError.checkValueInInterval(count, 0, source.length);
    while (count > 0) {
      final head = source.head!;
      final toCopy = min(count, head.limit - head.pos);
      final end = head.pos + toCopy;
      await writeFrom(head.data, head.pos, end);
      head.pos += toCopy;
      count -= toCopy;
      source.length -= toCopy;
      if (head.pos == head.limit) {
        source.head = head.pop();
      }
    }
  }

  Source source() => FileSource(this);

  Sink sink() => FileSink(this);
}

extension FutureRandomAccessFileExtension on Future<RandomAccessFile> {
  Future<FileHandle> handle() => then((e) => e.handle());

  Future<Source> source() async => FileSource(await this);

  Future<Sink> sink() async => FileSink(await this);
}

@internal
class FileSource implements Source {
  final RandomAccessFile randomAccessFile;

  const FileSource(this.randomAccessFile);

  @override
  Future<int> read(Buffer sink, int count) {
    return randomAccessFile.readIntoSink(sink, count);
  }

  @override
  Future<void> close() {
    return randomAccessFile.close();
  }
}

class FileSink implements Sink {
  final RandomAccessFile randomAccessFile;

  const FileSink(this.randomAccessFile);

  @override
  Future<void> write(Buffer source, int count) {
    return randomAccessFile.writeFromSource(source, count);
  }

  @override
  Future<void> flush() {
    return randomAccessFile.flush();
  }

  @override
  Future<void> close() {
    return randomAccessFile.close();
  }
}

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

extension NullableFutureFileHandleExtension on Future<FileHandle?> {
  Future<Sink?> sink([int position = 0]) => then((e) => e?.sink(position));

  Future<Source?> source([int position = 0]) {
    return then((e) => e?.source(position));
  }
}

class FileHandle {
  FileHandle._(this.randomAccessFile);

  final RandomAccessFile randomAccessFile;

  final _lock = Lock();

  var _closed = false;
  var _openCount = 0;

  Source source([int position = 0]) {
    checkState(!_closed, 'closed');
    _openCount++;
    return FileHandleSource(this, position);
  }

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

  int positionSource(Source source) {
    var bufferSize = 0;

    if (source is RealBufferedSource) {
      bufferSize = source.buffer.length;
      source = source.source;
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
      var fileHandleSource = source.source;
      checkArgument(
        fileHandleSource is FileHandleSource &&
            identical(fileHandleSource.fileHandle, this),
        'source was not created by this FileHandle',
      );
      fileHandleSource = fileHandleSource as FileHandleSource;
      checkState(!fileHandleSource._closed, 'closed');

      final bufferSize = source.buffer.length;
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

  int positionSink(Sink sink) {
    var bufferSize = 0;

    if (sink is RealBufferedSink) {
      bufferSize = sink.buffer.length;
      sink = sink.sink;
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
      var fileHandleSink = sink.sink;
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

  Future<int> read(int position, Buffer sink, int count) async {
    checkState(!_closed, 'closed');
    return readInto(position, sink, count);
  }

  Future<void> write(int position, Buffer source, int count) {
    checkState(!_closed, 'closed');
    return writeFrom(position, source, count);
  }

  @internal
  Future<int> readInto(int position, Buffer sink, int count) {
    return _lock.synchronized(() async {
      await randomAccessFile.setPosition(position);
      return randomAccessFile.readIntoSink(sink, count);
    });
  }

  @internal
  Future<void> writeFrom(int position, Buffer source, int count) {
    return _lock.synchronized(() async {
      await randomAccessFile.setPosition(position);
      await randomAccessFile.writeFromSource(source, count);
    });
  }

  Future<int> position() {
    checkState(!_closed, 'closed');
    return _lock.synchronized(() => randomAccessFile.position());
  }

  Future<void> truncate(int length) {
    checkState(!_closed, 'closed');
    return _lock.synchronized(() => randomAccessFile.truncate(length));
  }

  Future<int> length() {
    checkState(!_closed, 'closed');
    return _lock.synchronized(() => randomAccessFile.length());
  }

  Future<void> flush() {
    checkState(!_closed, 'closed');
    return _lock.synchronized(() => randomAccessFile.flush());
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_openCount != 0) return;
    return _lock.synchronized(() => randomAccessFile.close());
  }

  Future<void> _closeOpened() async {
    _openCount--;
    if (_openCount != 0 || !_closed) return;
    return _lock.synchronized(() => randomAccessFile.close());
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
    final result = await fileHandle.readInto(_position, sink, count);
    _position += result;
    return result;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    return fileHandle._closeOpened();
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
    await fileHandle.writeFrom(_position, source, count);
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
