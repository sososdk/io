part of 'anio.dart';

class FileHandle {
  FileHandle(this.randomAccessFile);

  final RandomAccessFile randomAccessFile;

  final _lock = Lock();

  var _closed = false;
  var _openCount = 0;

  Future<Sink> sink([int? position]) async {
    checkState(!_closed, 'closed');
    position ??= await randomAccessFile.position();
    _openCount++;
    return _FileHandleSink(this, position);
  }

  Sink sinkSync([int? position]) {
    checkState(!_closed, 'closed');
    position ??= randomAccessFile.positionSync();
    _openCount++;
    return _FileHandleSink(this, position);
  }

  Future<void> write(int position, List<int> buffer,
      [int start = 0, int? end]) {
    checkState(!_closed, 'closed');
    return _writeNoCloseCheck(position, buffer, start, end);
  }

  Future<void> _writeNoCloseCheck(int position, List<int> buffer,
      [int start = 0, int? end]) {
    return _lock.synchronized(() => randomAccessFile
        .setPosition(position)
        .then((e) => e.writeFrom(buffer, start, end)));
  }

  Future<Source> source([int? position]) async {
    checkState(!_closed, 'closed');
    position ??= await randomAccessFile.position();
    _openCount++;
    return _FileHandleSource(this, position);
  }

  Source sourceSync([int? position]) {
    checkState(!_closed, 'closed');
    position ??= randomAccessFile.positionSync();
    _openCount++;
    return _FileHandleSource(this, position);
  }

  Future<int> read(int position, List<int> buffer, [int start = 0, int? end]) {
    checkState(!_closed, 'closed');
    return _readNoCloseCheck(position, buffer, start, end);
  }

  Future<int> _readNoCloseCheck(int position, List<int> buffer,
      [int start = 0, int? end]) {
    return _lock.synchronized(() => randomAccessFile
        .setPosition(position)
        .then((e) => e.readInto(buffer, start, end)));
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

class _FileHandleSink implements Sink {
  _FileHandleSink(this.fileHandle, int position) : _position = position;

  final FileHandle fileHandle;

  int _position;

  var _closed = false;

  @override
  FutureOr<void> write(Buffer source, int count) async {
    checkState(!_closed, 'closed');
    while (count > 0) {
      if (source.isEmpty) return;
      final chunk = source._chunks.removeAt(0);
      if (chunk.length > count) {
        await fileHandle._writeNoCloseCheck(_position, chunk, 0, count);
        _position += count;
        source._chunks.insert(0, chunk.sublist(count));
        source._length -= count;
        count = 0;
      } else {
        await fileHandle._writeNoCloseCheck(_position, chunk);
        _position += chunk.length;
        source._length -= chunk.length;
        count -= chunk.length;
      }
    }
  }

  @override
  FutureOr<void> flush() {
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

class _FileHandleSource implements Source {
  _FileHandleSource(this.fileHandle, int position) : _position = position;

  final FileHandle fileHandle;

  int _position;

  var _closed = false;

  @override
  FutureOr<int> read(Buffer sink, int count) async {
    checkState(!_closed, 'closed');
    final buffer = Uint8List(kBlockSize);
    int totalBytesRead = 0;
    while (totalBytesRead < count) {
      final result = await fileHandle._readNoCloseCheck(
          _position, buffer, 0, min(kBlockSize, count - totalBytesRead));
      if (result == 0) return totalBytesRead;
      _position += result;
      totalBytesRead += result;
      sink.writeBytes(buffer, 0, result);
    }
    return totalBytesRead;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    return fileHandle._closeOpened();
  }
}
