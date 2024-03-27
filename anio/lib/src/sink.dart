part of 'anio.dart';

abstract interface class Sink {
  /// Removes [count] bytes from [source] and appends them to this.
  FutureOr<void> write(Buffer source, int count);

  /// Pushes all buffered bytes to their final destination.
  FutureOr<void> flush();

  /// Pushes all buffered bytes to their final destination and releases the resources held by this
  /// sink. It is an error to write a closed sink. It is safe to close a sink more than once.
  FutureOr<void> close();
}

extension SinkBuffer on Sink {
  BufferedSink buffer() => _RealBufferedSink(this);
}

extension FutureSinkBuffer on Future<Sink> {
  Future<BufferedSink> buffer() async => _RealBufferedSink(await this);
}

abstract interface class BufferedSink implements Sink {
  Buffer get buffer;

  /// Removes all bytes from `source` and appends them to this sink. Returns the number of bytes read
  /// which will be 0 if `source` is exhausted.
  FutureOr<int> writeSource(Source source);

  /// This writes `byteCount` bytes of [source], starting at [start].
  FutureOr<void> writeBytes(Uint8List source, [int start = 0, int? end]);

  /// Writes a byte to this sink.
  FutureOr<void> writeInt8(int value);

  /// Writes a byte to this sink.
  FutureOr<void> writeUint8(int value);

  /// Writes two bytes to this sink.
  FutureOr<void> writeInt16(int value, [Endian endian = Endian.big]);

  /// Writes two bytes to this sink.
  FutureOr<void> writeUint16(int value, [Endian endian = Endian.big]);

  /// Writes four bytes to this sink.
  FutureOr<void> writeInt32(int value, [Endian endian = Endian.big]);

  /// Writes four bytes to this sink.
  FutureOr<void> writeUint32(int value, [Endian endian = Endian.big]);

  /// Writes eight bytes to this sink.
  FutureOr<void> writeInt64(int value, [Endian endian = Endian.big]);

  /// Writes eight bytes to this sink.
  FutureOr<void> writeUint64(int value, [Endian endian = Endian.big]);

  /// Writes four bytes to this sink.
  FutureOr<void> writeFloat32(double value, [Endian endian = Endian.big]);

  /// Writes eight bytes to this sink.
  FutureOr<void> writeFloat64(double value, [Endian endian = Endian.big]);

  /// Encodes [string] in [encoding] and writes it to this sink.
  FutureOr<void> writeString(String string, [Encoding encoding = utf8]);

  /// Writes [string] followed by a newline, `"\n"`.
  FutureOr<void> writeLine([String string = '', Encoding encoding = utf8]);

  /// Writes the character represented by [charCode].
  FutureOr<void> writeCharCode(int charCode);

  /// Writes all buffered data to the underlying sink, if one exists. Like [flush], but weaker. Call
  /// this before this buffered sink goes out of scope so that its data can reach its destination.
  FutureOr<void> emit();
}

class ForwardingSink implements Sink {
  final Sink delegate;

  const ForwardingSink(this.delegate);

  @override
  FutureOr<void> write(Buffer source, int count) =>
      delegate.write(source, count);

  @override
  FutureOr<void> flush() => delegate.flush();

  @override
  FutureOr<void> close() => delegate.close();
}

class BlackHoleSink implements Sink {
  BlackHoleSink();

  @override
  void write(Buffer source, int count) {}

  @override
  void flush() => Future.value();

  @override
  void close() => Future.value();
}

class FaultHidingSink extends ForwardingSink {
  final void Function() onError;
  var _hasErrors = false;

  FaultHidingSink(super.sink, this.onError);

  @override
  FutureOr<void> write(Buffer source, int count) async {
    if (_hasErrors) {
      return;
    }
    try {
      await super.write(source, count);
    } catch (e) {
      _hasErrors = true;
      onError();
    }
  }

  @override
  FutureOr<void> flush() async {
    if (_hasErrors) {
      return;
    }
    try {
      return await super.flush();
    } catch (e) {
      _hasErrors = true;
      onError();
    }
  }

  @override
  FutureOr<void> close() async {
    if (_hasErrors) {
      return;
    }
    try {
      return await super.close();
    } catch (e) {
      _hasErrors = true;
      onError();
    }
  }
}

class _RealBufferedSink implements BufferedSink {
  _RealBufferedSink(Sink sink)
      : _sink = sink,
        _buffer = Buffer();
  final Sink _sink;
  final Buffer _buffer;

  bool _closed = false;

  @override
  Buffer get buffer => _buffer;

  @override
  FutureOr<void> write(Buffer source, int count) async {
    checkState(!_closed, 'closed');
    _buffer.write(source, count);
    await emit();
  }

  @override
  FutureOr<void> writeBytes(Uint8List source, [int start = 0, int? end]) async {
    checkState(!_closed, 'closed');
    _buffer.writeBytes(source, start, end);
    await emit();
  }

  @override
  FutureOr<void> writeInt8(int value) async {
    checkState(!_closed, 'closed');
    _buffer.writeInt8(value);
    await emit();
  }

  @override
  FutureOr<void> writeUint8(int value) async {
    checkState(!_closed, 'closed');
    _buffer.writeUint8(value);
    await emit();
  }

  @override
  FutureOr<void> writeInt16(int value, [Endian endian = Endian.big]) async {
    checkState(!_closed, 'closed');
    _buffer.writeInt16(value, endian);
    await emit();
  }

  @override
  FutureOr<void> writeUint16(int value, [Endian endian = Endian.big]) async {
    checkState(!_closed, 'closed');
    _buffer.writeUint16(value, endian);
    await emit();
  }

  @override
  FutureOr<void> writeInt32(int value, [Endian endian = Endian.big]) async {
    checkState(!_closed, 'closed');
    _buffer.writeInt32(value, endian);
    await emit();
  }

  @override
  FutureOr<void> writeUint32(int value, [Endian endian = Endian.big]) async {
    checkState(!_closed, 'closed');
    _buffer.writeUint32(value, endian);
    await emit();
  }

  @override
  FutureOr<void> writeInt64(int value, [Endian endian = Endian.big]) async {
    checkState(!_closed, 'closed');
    _buffer.writeInt64(value, endian);
    await emit();
  }

  @override
  FutureOr<void> writeUint64(int value, [Endian endian = Endian.big]) async {
    checkState(!_closed, 'closed');
    _buffer.writeUint64(value, endian);
    await emit();
  }

  @override
  FutureOr<void> writeFloat32(
    double value, [
    Endian endian = Endian.big,
  ]) async {
    checkState(!_closed, 'closed');
    _buffer.writeFloat32(value, endian);
    await emit();
  }

  @override
  FutureOr<void> writeFloat64(
    double value, [
    Endian endian = Endian.big,
  ]) async {
    checkState(!_closed, 'closed');
    _buffer.writeFloat64(value, endian);
    await emit();
  }

  @override
  FutureOr<int> writeSource(Source source) async {
    checkState(!_closed, 'closed');
    int totalBytesRead = 0;
    while (true) {
      final result = await source.read(_buffer, kBlockSize);
      if (result == 0) break;
      totalBytesRead += result;
      await emit();
    }
    return totalBytesRead;
  }

  @override
  FutureOr<void> writeString(String string, [Encoding encoding = utf8]) async {
    checkState(!_closed, 'closed');
    _buffer.writeString(string, encoding);
    await emit();
  }

  @override
  FutureOr<void> writeLine([String string = '', Encoding encoding = utf8]) {
    return writeString('$string\n', encoding);
  }

  @override
  FutureOr<void> writeCharCode(int charCode) {
    return writeString(String.fromCharCode(charCode));
  }

  @override
  FutureOr<void> emit() async {
    checkState(!_closed, 'closed');
    if (_buffer.isNotEmpty) {
      await _sink.write(_buffer, _buffer.length);
    }
  }

  @override
  FutureOr<void> flush() async {
    checkState(!_closed, 'closed');
    if (_buffer.isNotEmpty) {
      await _sink.write(_buffer, _buffer.length);
    }
    return _sink.flush();
  }

  @override
  FutureOr<void> close() async {
    if (_closed) return;
    // Emit buffered data to the underlying sink. If this fails, we still need
    // to close the sink; otherwise we risk leaking resources.
    Object? thrown;
    try {
      if (_buffer.isNotEmpty) {
        await _sink.write(_buffer, _buffer.length);
      }
    } catch (e) {
      thrown = e;
    }
    try {
      await _sink.close();
    } catch (e) {
      thrown ??= e;
    }
    _closed = true;
    if (thrown != null) throw thrown;
  }
}

extension StreamSink on core.Sink<List<int>> {
  Sink sink() => _StreamSink(this);
}

class _StreamSink implements Sink {
  _StreamSink(this.sink);

  final core.Sink<List<int>> sink;

  @override
  FutureOr<void> write(Buffer source, int count) async {
    RangeError.checkValueInInterval(count, 0, source.length);
    while (count > 0) {
      if (source.isEmpty) return;
      final chunk = source._chunks.removeAt(0);
      if (chunk.length > count) {
        sink.add(chunk.sublist(0, count));
        source._chunks.insert(0, chunk.sublist(count));
        source._length -= count;
        count = 0;
      } else {
        sink.add(chunk);
        source._length -= chunk.length;
        count -= chunk.length;
      }
    }
  }

  @override
  FutureOr<void> flush() {
    if (sink is IOSink) {
      return (sink as IOSink).flush();
    }
  }

  @override
  FutureOr<void> close() async => sink.close();
}
