part of 'anio.dart';

abstract interface class Source {
  /// Removes at least 1, and up to [count] bytes from this and appends them to [sink]. Returns
  /// the number of bytes read, or 0 if this source is exhausted.
  FutureOr<int> read(Buffer sink, int count);

  /// Closes this source and releases the resources held by this source. It is
  /// an error to read a closed source. It is safe to close a source more than
  /// once.
  FutureOr<void> close();
}

abstract interface class BufferedSource implements Source {
  /// This source's internal buffer.
  Buffer get buffer;

  /// Returns true if there are no more bytes in this source.
  FutureOr<bool> exhausted();

  /// Returns true when the buffer contains at least [count] bytes, expanding it as
  /// necessary. Returns false if the source is exhausted before the requested bytes can be read.
  FutureOr<bool> request(int count);

  /// Returns when the buffer contains at least [count] bytes. Throws an
  /// [EOFException] if the source is exhausted before the required bytes can be read.
  FutureOr<void> require(int count);

  /// Reads and discards [count] bytes from this source. Throws an [EOFException] if the
  /// source is exhausted before the requested bytes can be skipped.
  FutureOr<void> skip(int count);

  /// Returns the index of [element] if it is found in the range of [start] inclusive to [end]
  /// exclusive. If [element] isn't found, or if `start == end`, then -1 is returned.
  ///
  /// The scan terminates at either [end] or the end of the buffer, whichever comes first. The
  /// maximum number of bytes scanned is `start - end`.
  FutureOr<int> indexOf(int element, [int start = 0, int? end]);

  /// Returns the index of the first match for [bytes] in the range of [start] inclusive to [end]
  /// exclusive. This expands the buffer as necessary until [bytes] is found. This reads an unbounded number of
  /// bytes into the buffer. Returns -1 if the stream is exhausted before the requested bytes are
  /// found.
  ///
  /// ```dart
  /// var MOVE = utf8.encode("move");
  ///
  /// Buffer buffer = new Buffer();
  /// buffer.writeString("Don't move! He can't see us if we don't move.");
  ///
  /// expect(6,  buffer.indexOfBytes(MOVE));
  /// expect(40, buffer.indexOfBytes(MOVE, 12));
  /// ```
  FutureOr<int> indexOfBytes(Uint8List bytes, [int start = 0, int? end]);

  /// Removes all bytes from this and appends them to `sink`. Returns the total number of bytes
  /// written to `sink` which will be 0 if this is exhausted.
  FutureOr<int> readIntoSink(Sink sink);

  /// Removes exactly `end - start` bytes from this and copies them into `sink`.
  FutureOr<int> readIntoBytes(List<int> sink, [int start = 0, int? end]);

  /// Removes bytes (all bytes if [count] is null) from this and returns them as a list of bytes.
  FutureOr<Uint8List> readBytes([int? count]);

  /// Removes a byte from this source.
  ///
  /// The return value will be between -128 and 127, inclusive.
  FutureOr<int> readInt8();

  /// Removes a byte from this source.
  ///
  /// The return value will be between 0 and 255, inclusive.
  FutureOr<int> readUint8();

  /// Removes two bytes from this source.
  ///
  /// The return value will be between -2<sup>15</sup> and 2<sup>15</sup> - 1,
  /// inclusive.
  FutureOr<int> readInt16([Endian endian = Endian.big]);

  /// Removes two bytes from this source.
  ///
  /// The return value will be between 0 and  2<sup>16</sup> - 1, inclusive.
  FutureOr<int> readUint16([Endian endian = Endian.big]);

  /// Removes four bytes from this source.
  ///
  /// The return value will be between -2<sup>31</sup> and 2<sup>31</sup> - 1,
  /// inclusive.
  FutureOr<int> readInt32([Endian endian = Endian.big]);

  /// Removes four bytes from this source.
  ///
  /// The return value will be between 0 and  2<sup>32</sup> - 1, inclusive.
  FutureOr<int> readUint32([Endian endian = Endian.big]);

  /// Removes eight bytes from this source.
  ///
  /// The return value will be between -2<sup>63</sup> and 2<sup>63</sup> - 1,
  /// inclusive.
  FutureOr<int> readInt64([Endian endian = Endian.big]);

  /// Removes eight bytes from this source.
  ///
  /// The return value will be between 0 and  2<sup>64</sup> - 1, inclusive.
  ///
  /// If you need 64-bit unsigned numbers, you need to use `BigInt`:
  /// ```dart
  /// BigInt.from(readUint64()).toUnsigned(64)
  /// ```
  FutureOr<int> readUint64([Endian endian = Endian.big]);

  /// Removes four bytes from this source.
  ///
  /// The return value will be between -2<sup>128</sup> and 2<sup>128</sup> - 1,
  /// inclusive.
  FutureOr<double> readFloat32([Endian endian = Endian.big]);

  /// Removes eight bytes from this source.
  ///
  /// The return value will be between -2<sup>1024</sup> and 2<sup>1024</sup> - 1,
  /// inclusive.
  FutureOr<double> readFloat64([Endian endian = Endian.big]);

  /// Removes bytes (all bytes if [count] is null) from this and returns the string.
  /// Returns the empty string if this source is empty.
  FutureOr<String> readString({Encoding encoding = utf8, int? count});

  /// Removes and returns characters up to but not including the next line break. A line break is
  /// either `"\n"` or `"\r\n"`; these characters are not included in the result.
  ///
  /// **On the end of the stream this method returns null,** If
  /// the source doesn't end with a line break then an implicit line break is assumed. Null is
  /// returned once the source is exhausted. Use this for human-generated data, where a trailing
  /// line break is optional.
  FutureOr<String?> readLine({Encoding encoding = utf8});

  /// Removes and returns characters up to but not including the next line break. A line break is
  /// either `"\n"` or `"\r\n"`; these characters are not included in the result.
  ///
  /// **On the end of the stream this method throws.** Every call must consume either
  /// '\r\n' or '\n'. If these characters are absent in the stream, an [EOFException]
  /// is thrown. Use this for machine-generated data where a missing line break implies truncated
  /// input.
  FutureOr<String> readLineStrict({Encoding encoding = utf8, int? end});

  /// Returns true if `end` - `start` bytes at `offset` in this source equal [bytes] at [start].
  /// This expands the buffer as necessary until a byte does not match, all bytes are matched, or if
  /// the stream is exhausted before enough bytes could determine a match.
  FutureOr<bool> rangeEquals(int offset, List<int> bytes,
      [int start = 0, int? end]);

  /// Returns a new `BufferedSource` that can read data from this `BufferedSource` without consuming
  /// it. The returned source becomes invalid once this source is next read or closed.
  ///
  /// For example, we can use `peek()` to lookahead and read the same data multiple times.
  ///
  /// ```dart
  /// final buffer = Buffer()
  /// buffer.writeString("abcdefghi")
  ///
  /// buffer.readString(3) // returns "abc", buffer contains "defghi"
  ///
  /// final peek = buffer.peek()
  /// peek.readString(3) // returns "def", buffer contains "defghi"
  /// peek.readString(3) // returns "ghi", buffer contains "defghi"
  ///
  /// buffer.readString(3) // returns "def", buffer contains "ghi"
  /// ```
  FutureOr<BufferedSource> peek();
}

class RealBufferedSource implements BufferedSource {
  RealBufferedSource(Source source)
      : _source = source,
        _buffer = Buffer();

  final Source _source;
  final Buffer _buffer;

  bool _closed = false;

  @override
  Buffer get buffer => _buffer;

  @override
  Future<int> read(Buffer sink, int count) async {
    checkArgument(count >= 0, 'byteCount < 0: $count');
    checkState(!_closed, 'closed');

    if (_buffer.isEmpty) {
      final result = await _source.read(_buffer, kBlockSize);
      if (result == 0) return 0;
    }

    return _buffer.read(sink, min(count, _buffer._length));
  }

  @override
  Future<bool> exhausted() async {
    checkState(!_closed, 'closed');
    return _buffer.exhausted() && await _source.read(_buffer, kBlockSize) == 0;
  }

  @override
  Future<bool> request(int count) async {
    checkArgument(count >= 0, 'byteCount < 0: $count');
    checkState(!_closed, 'closed');
    while (_buffer._length < count) {
      if (await _source.read(_buffer, kBlockSize) == 0) return false;
    }
    return true;
  }

  @override
  Future<void> require(int count) async {
    if (!await request(count)) throw const EOFException();
  }

  @override
  Future<void> skip(int count) async {
    checkState(!_closed, 'closed');
    while (count > 0) {
      if (_buffer.isEmpty && await _source.read(_buffer, kBlockSize) == 0) {
        throw const EOFException();
      }
      final skip = min(count, _buffer._length);
      _buffer.skip(skip);
      count -= skip;
    }
  }

  @override
  Future<int> indexOf(int element, [int start = 0, int? end]) async {
    checkArgument(start >= 0 && (end == null || start < end));
    checkState(!_closed, 'closed');
    while (end == null || start < end) {
      final result = _buffer.indexOf(element, start, end);
      if (result != -1) return result;

      // The byte wasn't in the buffer. Give up if we've already reached our target size or if the
      // underlying stream is exhausted.
      final lastBufferLength = _buffer._length;
      if ((end != null && lastBufferLength >= end) ||
          await _source.read(_buffer, kBlockSize) == 0) {
        return -1;
      }

      // Continue the search from where we left off.
      start = max(start, lastBufferLength);
    }
    return -1;
  }

  @override
  Future<int> indexOfBytes(Uint8List bytes, [int start = 0, int? end]) async {
    checkState(!_closed, 'closed');
    while (true) {
      final result = _buffer.indexOfBytes(bytes, start, end);
      if (result != -1) return result;

      final lastBufferSize = _buffer._length;
      if (await _source.read(_buffer, kBlockSize) == 0) return -1;

      // Keep searching, picking up from where we left off.
      start = max(start, lastBufferSize - bytes.length + 1);
    }
  }

  @override
  Future<Uint8List> readBytes([int? count]) async {
    if (count == null) {
      await _buffer.writeFromSource(_source);
      return _buffer.readBytes();
    } else {
      await require(count);
      return _buffer.readBytes(count);
    }
  }

  @override
  Future<int> readInt8() async {
    await require(1);
    return _buffer.readInt8();
  }

  @override
  Future<int> readUint8() async {
    await require(1);
    return _buffer.readUint8();
  }

  @override
  Future<int> readInt16([Endian endian = Endian.big]) async {
    await require(2);
    return _buffer.readInt16(endian);
  }

  @override
  Future<int> readUint16([Endian endian = Endian.big]) async {
    await require(2);
    return _buffer.readUint16(endian);
  }

  @override
  Future<int> readInt32([Endian endian = Endian.big]) async {
    await require(4);
    return _buffer.readInt32(endian);
  }

  @override
  Future<int> readUint32([Endian endian = Endian.big]) async {
    await require(4);
    return _buffer.readUint32(endian);
  }

  @override
  Future<int> readInt64([Endian endian = Endian.big]) async {
    await require(8);
    return _buffer.readInt64(endian);
  }

  @override
  Future<int> readUint64([Endian endian = Endian.big]) async {
    await require(8);
    return _buffer.readUint64(endian);
  }

  @override
  Future<double> readFloat32([Endian endian = Endian.big]) async {
    await require(4);
    return _buffer.readFloat32(endian);
  }

  @override
  Future<double> readFloat64([Endian endian = Endian.big]) async {
    await require(8);
    return _buffer.readFloat64(endian);
  }

  @override
  Future<int> readIntoBytes(List<int> sink, [int start = 0, int? end]) async {
    end = RangeError.checkValidRange(start, end, sink.length);
    int totalBytes = 0;
    while (end > start) {
      if (_buffer.isEmpty && await _source.read(_buffer, kBlockSize) == 0) {
        return totalBytes;
      }
      final count = _buffer.readIntoBytes(sink, start, end);
      totalBytes += count;
      start += count;
    }
    return totalBytes;
  }

  @override
  Future<int> readIntoSink(Sink sink) async {
    var totalBytes = 0;
    while (_source.read(_buffer, kBlockSize) != 0) {
      final emitCount = buffer.completeSegmentByteCount();
      if (emitCount > 0) {
        totalBytes += emitCount;
        sink.write(buffer, emitCount);
      }
    }
    if (buffer.isNotEmpty) {
      totalBytes += buffer._length;
      sink.write(buffer, buffer._length);
    }
    return totalBytes;
  }

  @override
  Future<String> readString({Encoding encoding = utf8, int? count}) async {
    if (count == null) {
      await _buffer.writeFromSource(_source);
      return _buffer.readString(encoding: encoding);
    } else {
      await require(count);
      return _buffer.readString(encoding: encoding, count: count);
    }
  }

  @override
  Future<String?> readLine({Encoding encoding = utf8}) async {
    final newline = await indexOf(kLF);
    if (newline == -1) {
      if (_buffer.isNotEmpty) {
        return _buffer.readString(encoding: encoding);
      } else {
        return null;
      }
    } else {
      return _buffer.readLine(encoding: encoding, newline: newline);
    }
  }

  @override
  Future<String> readLineStrict({Encoding encoding = utf8, int? end}) async {
    checkArgument(end == null || end > 0);
    final newline = await indexOf(kLF, 0, end);
    if (newline != -1) {
      return _buffer._readLine(encoding, newline);
    }
    if (end != null &&
        (await request(end) && _buffer[end - 1] == kCR) &&
        (await request(end + 1) && _buffer[end] == kLF)) {
      // The line was 'limit' UTF-8 bytes followed by \r\n.
      return _buffer._readLine(encoding, end);
    }
    throw const EOFException();
  }

  @override
  FutureOr<BufferedSource> peek() => (PeekSource(this) as Source).buffered();

  @override
  Future<bool> rangeEquals(int offset, List<int> bytes,
      [int start = 0, int? end]) async {
    checkState(!_closed, 'closed');
    checkArgument(offset >= 0);
    end = RangeError.checkValidRange(start, end, bytes.length);
    for (var i = start; i < end; i++) {
      final bufferOffset = offset + i - start;
      if (!await request(bufferOffset + 1)) return false;
      if (buffer[bufferOffset] != bytes[i]) return false;
    }
    return true;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _source.close();
    _buffer.clear();
  }

  @override
  String toString() => 'buffer($_source)';
}

extension SourceBuffer on Source {
  RealBufferedSource buffered() => RealBufferedSource(this);

  /// Attempts to exhaust this, returning true if successful. This is useful when reading a complete
  /// source is helpful, such as when doing so completes a cache body or frees a socket connection for
  /// reuse.
  Future<bool> discard([
    Duration timeout = const Duration(milliseconds: 100),
  ]) async {
    try {
      await skipAll().timeout(timeout);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Reads until this is exhausted.
  Future<void> skipAll() async {
    final skipBuffer = Buffer();
    while (await read(skipBuffer, kBlockSize) != 0) {
      skipBuffer.clear();
    }
  }
}

extension FutureSourceBuffer on Future<Source> {
  Future<RealBufferedSource> buffered() async => RealBufferedSource(await this);
}

class ForwardingSource implements Source {
  final Source delegate;

  const ForwardingSource(this.delegate);

  @override
  Future<int> read(Buffer sink, int count) async => delegate.read(sink, count);

  @override
  Future close() async => delegate.close();
}

extension InputSourceExtension on Stream<List<int>> {
  Source source() => InputSource(this);
}

@internal
class InputSource implements Source {
  InputSource(this.stream) {
    _subscription = stream.listen(
      (event) {
        _subscription.pause();
        try {
          _receiveBuffer.writeFromBytes(event);
          _completer?.complete();
        } catch (error, stackTrace) {
          _subscription
              .cancel()
              .whenComplete(() => _completer?.completeError(error, stackTrace));
        }
      },
      onError: (error, stackTrace) {
        _completer?.completeError(error, stackTrace);
      },
      onDone: () {
        _done = true;
        _completer?.complete();
      },
      cancelOnError: true,
    );
  }

  final _receiveBuffer = Buffer();
  final Stream<List<int>> stream;
  late StreamSubscription<List<int>> _subscription;
  Completer? _completer;
  bool _done = false;
  bool _closed = false;

  @override
  Future<int> read(Buffer sink, int count) async {
    if (count == 0) return 0;
    checkArgument(count >= 0, 'count < 0: $count');
    checkState(!_closed, 'closed');
    _subscription.resume();
    while (_receiveBuffer.isEmpty) {
      if (_done) return 0;
      final completer = _completer = Completer();
      await completer.future;
      _completer = null;
    }
    final length = min(count, _receiveBuffer._length);
    sink.write(_receiveBuffer, length);
    return length;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    try {
      _completer?.completeError('StreamSource closed.');
    } catch (_) {}
  }
}

@internal
class PeekSource implements Source {
  PeekSource(this.upstream)
      : buffer = upstream.buffer,
        expectedSegment = upstream.buffer.head,
        expectedPos = upstream.buffer.head?.pos;

  final BufferedSource upstream;
  final Buffer buffer;
  Segment? expectedSegment;
  int? expectedPos;

  var _closed = false;
  var _pos = 0;

  @override
  Future<int> read(Buffer sink, int count) async {
    checkArgument(count >= 0, 'byteCount < 0: $count');
    checkState(!_closed, 'closed');
    // Source becomes invalid if there is an expected Segment and it and the expected position
    // do not match the current head and head position of the upstream buffer
    checkState(
      expectedSegment == null ||
          identical(expectedSegment, buffer.head) &&
              expectedPos == buffer.head!.pos,
      'Peek source is invalid because upstream source was used',
    );
    if (count == 0) return 0;
    if (!await upstream.request(_pos + 1)) return -1;
    if (expectedSegment == null && buffer.head != null) {
      // Only once the buffer actually holds data should an expected Segment and position be
      // recorded. This allows reads from the peek source to repeatedly return -1 and for data to be
      // added later. Unit tests depend on this behavior.
      expectedSegment = buffer.head;
      expectedPos = buffer.head!.pos;
    }
    final toCopy = min(count, buffer._length - _pos);
    buffer.copyTo(sink, _pos, toCopy);
    _pos += toCopy;
    return toCopy;
  }

  @override
  void close() => _closed = true;
}
