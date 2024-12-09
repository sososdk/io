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

abstract interface class BufferedSink implements Sink {
  Buffer get buffer;

  /// Removes all bytes from `source` and appends them to this sink. Returns the number of bytes read
  /// which will be 0 if `source` is exhausted.
  FutureOr<int> writeFromSource(Source source);

  /// This writes `byteCount` bytes of [source], starting at [start].
  FutureOr<void> writeFromBytes(List<int> source, [int start = 0, int? end]);

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

  /// Writes complete segments to the underlying sink, if one exists. Like [flush], but weaker. Use
  /// this to limit the memory held in the buffer to a single segment. Typically application code
  /// will not need to call this: it is only necessary when application code writes directly to this
  /// sink's [buffer].
  ///
  /// ```dart
  /// final BufferedSink b0 = Buffer();
  /// final BufferedSink b1 = b0.buffered();
  /// final BufferedSink b2 = b1.buffered();
  ///
  /// const length = kBlockSize * 2 + 3616;
  /// b2.buffer.writeFromBytes(Uint8List(length));
  /// expect(length, b2.buffer.length);
  /// expect(0, b1.buffer.length);
  /// expect(0, b0.buffer.length);
  ///
  /// b2.emitCompleteSegments();
  /// expect(length % kBlockSize, b2.buffer.length);
  /// expect(0, b1.buffer.length);
  /// expect((length ~/ kBlockSize) * kBlockSize, b0.buffer.length);
  /// ```
  FutureOr<void> emitCompleteSegments();
}

class RealBufferedSink implements BufferedSink {
  RealBufferedSink(Sink sink)
      : _sink = sink,
        _buffer = Buffer();
  final Sink _sink;
  final Buffer _buffer;

  bool _closed = false;

  @internal
  Sink get sink => _sink;

  @override
  Buffer get buffer => _buffer;

  @override
  Future<void> write(Buffer source, int count) async {
    checkState(!_closed, 'closed');
    _buffer.write(source, count);
    await emitCompleteSegments();
  }

  @override
  Future<void> writeFromBytes(List<int> source,
      [int start = 0, int? end]) async {
    checkState(!_closed, 'closed');
    _buffer.writeFromBytes(source, start, end);
    await emitCompleteSegments();
  }

  @override
  Future<void> writeInt8(int value) async {
    checkState(!_closed, 'closed');
    _buffer.writeInt8(value);
    await emitCompleteSegments();
  }

  @override
  Future<void> writeUint8(int value) async {
    checkState(!_closed, 'closed');
    _buffer.writeUint8(value);
    await emitCompleteSegments();
  }

  @override
  Future<void> writeInt16(int value, [Endian endian = Endian.big]) async {
    checkState(!_closed, 'closed');
    _buffer.writeInt16(value, endian);
    await emitCompleteSegments();
  }

  @override
  Future<void> writeUint16(int value, [Endian endian = Endian.big]) async {
    checkState(!_closed, 'closed');
    _buffer.writeUint16(value, endian);
    await emitCompleteSegments();
  }

  @override
  Future<void> writeInt32(int value, [Endian endian = Endian.big]) async {
    checkState(!_closed, 'closed');
    _buffer.writeInt32(value, endian);
    await emitCompleteSegments();
  }

  @override
  Future<void> writeUint32(int value, [Endian endian = Endian.big]) async {
    checkState(!_closed, 'closed');
    _buffer.writeUint32(value, endian);
    await emitCompleteSegments();
  }

  @override
  Future<void> writeInt64(int value, [Endian endian = Endian.big]) async {
    checkState(!_closed, 'closed');
    _buffer.writeInt64(value, endian);
    await emitCompleteSegments();
  }

  @override
  Future<void> writeUint64(int value, [Endian endian = Endian.big]) async {
    checkState(!_closed, 'closed');
    _buffer.writeUint64(value, endian);
    await emitCompleteSegments();
  }

  @override
  Future<void> writeFloat32(
    double value, [
    Endian endian = Endian.big,
  ]) async {
    checkState(!_closed, 'closed');
    _buffer.writeFloat32(value, endian);
    await emitCompleteSegments();
  }

  @override
  Future<void> writeFloat64(
    double value, [
    Endian endian = Endian.big,
  ]) async {
    checkState(!_closed, 'closed');
    _buffer.writeFloat64(value, endian);
    await emitCompleteSegments();
  }

  @override
  Future<int> writeFromSource(Source source) async {
    checkState(!_closed, 'closed');
    var totalBytes = 0;
    while (true) {
      final result = await source.read(_buffer, Segment.size);
      if (result == 0) break;
      totalBytes += result;
      await emitCompleteSegments();
    }
    return totalBytes;
  }

  @override
  Future<void> writeString(String string, [Encoding encoding = utf8]) async {
    checkState(!_closed, 'closed');
    _buffer.writeString(string, encoding);
    await emitCompleteSegments();
  }

  @override
  Future<void> writeLine([String string = '', Encoding encoding = utf8]) {
    return writeString('$string\n', encoding);
  }

  @override
  Future<void> writeCharCode(int charCode) {
    return writeString(String.fromCharCode(charCode));
  }

  @override
  Future<void> emitCompleteSegments() async {
    checkState(!_closed, 'closed');
    final byteCount = _buffer.completeSegmentByteCount();
    if (byteCount > 0) await _sink.write(_buffer, byteCount);
  }

  @override
  Future<void> emit() async {
    checkState(!_closed, 'closed');
    if (_buffer.isNotEmpty) {
      await _sink.write(_buffer, _buffer.length);
    }
  }

  @override
  Future<void> flush() async {
    checkState(!_closed, 'closed');
    if (_buffer.isNotEmpty) {
      await _sink.write(_buffer, _buffer.length);
    }
    await _sink.flush();
  }

  @override
  Future<void> close() async {
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

extension SinkBuffer on Sink {
  BufferedSink buffered() => RealBufferedSink(this);
}

extension FutureSinkBuffer on Future<Sink> {
  Future<BufferedSink> buffered() => then((e) => e.buffered());
}

extension NullableFutureSinkBuffer on Future<Sink?> {
  Future<BufferedSink?> buffered() => then((e) => e?.buffered());
}

mixin ForwardingSink implements Sink {
  Sink get delegate;

  @override
  Future<void> write(Buffer source, int count) async =>
      delegate.write(source, count);

  @override
  Future<void> flush() async => delegate.flush();

  @override
  Future<void> close() async => delegate.close();
}

class BlackHoleSink implements Sink {
  BlackHoleSink();

  @override
  void write(Buffer source, int count) => source.skip(count);

  @override
  void flush() => Future.value();

  @override
  void close() => Future.value();
}

class FaultHidingSink with ForwardingSink {
  final void Function() onError;
  var _hasErrors = false;

  FaultHidingSink(this.delegate, this.onError);

  @override
  final Sink delegate;

  @override
  Future<void> write(Buffer source, int count) async {
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
  Future<void> flush() async {
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
  Future<void> close() async {
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

extension OutputSinkExtension on core.Sink<List<int>> {
  Sink sink() => OutputSink(this);
}

@internal
class OutputSink implements Sink {
  OutputSink(this.sink);

  final core.Sink<List<int>> sink;

  @override
  Future<void> write(Buffer source, int count) async {
    RangeError.checkValueInInterval(count, 0, source.length);
    var remaining = count;
    while (remaining > 0) {
      final head = source.head!;
      final toCopy = min(remaining, head.limit - head.pos);
      sink.add(head.data.sublist(head.pos, head.pos + toCopy));

      head.pos += toCopy;
      remaining -= toCopy;
      source.length -= toCopy;

      if (head.pos == head.limit) {
        source.head = head.pop();
      }
    }
  }

  @override
  Future<void> flush() async {
    if (sink is IOSink) {
      return (sink as IOSink).flush();
    }
  }

  @override
  Future<void> close() async => sink.close();
}
