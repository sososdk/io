part of 'anio.dart';

abstract class Source {
  /// Remove [count] bytes from this and appends them to [sink]. Returns
  /// the number of bytes read.
  FutureOr<int> read(Buffer sink, int count);

  /// Closes this source and releases the resources held by this source. It is
  /// an error to read a closed source. It is safe to close a source more than
  /// once.
  FutureOr<void> close();
}

extension SourceBuffer on Source {
  BufferedSource buffer() => RealBufferedSource(this);

  /// Attempts to exhaust this, returning true if successful. This is useful when reading a complete
  /// source is helpful, such as when doing so completes a cache body or frees a socket connection for
  /// reuse.
  FutureOr<bool> discard([
    Duration timeout = const Duration(milliseconds: 100),
  ]) async {
    try {
      final skip = skipAll();
      if (skip is Future) {
        await skip.timeout(timeout);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Reads until this is exhausted.
  FutureOr<void> skipAll() async {
    final skipBuffer = Buffer();
    while (await read(skipBuffer, kBlockSize) != 0) {
      skipBuffer.clear();
    }
  }
}

extension FutureSourceBuffer on Future<Source> {
  Future<BufferedSource> buffer() async => RealBufferedSource(await this);
}

abstract class BufferedSource extends Source {
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

  /// Removes all bytes from this and appends them to `sink`. Returns the total number of bytes
  /// written to `sink` which will be 0 if this is exhausted.
  FutureOr<int> readIntoSink(Sink sink);

  /// Removes exactly `end - start` bytes from this and copies them into `sink`.
  FutureOr<int> readIntoBytes(Uint8List sink, [int start = 0, int? end]);

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
}

class ForwardingSource extends Source {
  final Source delegate;

  ForwardingSource(this.delegate);

  @override
  FutureOr<int> read(Buffer sink, int count) => delegate.read(sink, count);

  @override
  FutureOr close() => delegate.close();
}

class FileSource extends Source {
  FileSource(this.file);

  final RandomAccessFile file;
  bool _closed = false;

  @override
  Future<int> read(Buffer sink, int count) {
    assert(!_closed);
    return file.read(count).then((e) {
      if (e.isNotEmpty) sink.writeBytes(e);
      return e.length;
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await file.close();
  }
}

class StreamSource extends Source {
  StreamSource(this.stream) {
    _subscription = stream.listen(
      (event) {
        _subscription.pause();
        try {
          _receiveBuffer.writeBytes(event);
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
    assert(!_closed);
    _subscription.resume();
    while (_receiveBuffer.isEmpty) {
      if (_done) {
        return 0;
      }
      final completer = _completer = Completer();
      await completer.future;
      _completer = null;
    }
    final length = min(count, _receiveBuffer.length);
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

class RealBufferedSource extends BufferedSource {
  RealBufferedSource(Source source)
      : _source = source,
        _buffer = Buffer();

  final Source _source;
  final Buffer _buffer;

  bool _closed = false;

  @override
  Buffer get buffer => _buffer;

  @override
  FutureOr<int> read(Buffer sink, int count) async {
    assert(count > 0);
    assert(!_closed);
    int read = 0;
    while (read < count) {
      if (_buffer.isEmpty) {
        final read = await _source.read(_buffer, kBlockSize);
        if (read == 0) return read;
      }
      read += _buffer.read(sink, min(_buffer.length, count - read));
    }
    return read;
  }

  @override
  FutureOr<bool> exhausted() async {
    return _buffer.exhausted() && await _source.read(_buffer, kBlockSize) == 0;
  }

  @override
  FutureOr<bool> request(int count) async {
    assert(count >= 0);
    assert(!_closed);
    while (_buffer.length < count) {
      if (await _source.read(_buffer, kBlockSize) == 0) return false;
    }
    return true;
  }

  @override
  FutureOr<void> require(int count) async {
    if (!await request(count)) throw EOFException();
  }

  @override
  FutureOr<void> skip(int count) async {
    assert(!_closed);
    while (count > 0) {
      if (_buffer.isEmpty && await _source.read(_buffer, kBlockSize) == 0) {
        throw EOFException();
      }
      final skip = min(count, _buffer.length);
      _buffer.skip(skip);
      count -= skip;
    }
  }

  @override
  FutureOr<int> indexOf(int element, [int start = 0, int? end]) async {
    assert(!_closed);
    assert(end == null || start < end);
    while (end == null || start < end) {
      final result = _buffer.indexOf(element, start, end);
      if (result != -1) return result;

      // The byte wasn't in the buffer. Give up if we've already reached our target size or if the
      // underlying stream is exhausted.
      final lastBufferLength = buffer.length;
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
  FutureOr<Uint8List> readBytes([int? count]) async {
    if (count == null) {
      await _buffer.writeSource(_source);
      return _buffer.readBytes();
    } else {
      await require(count);
      return _buffer.readBytes(count);
    }
  }

  @override
  FutureOr<int> readInt8() async {
    await require(1);
    return _buffer.readInt8();
  }

  @override
  FutureOr<int> readUint8() async {
    await require(1);
    return _buffer.readUint8();
  }

  @override
  FutureOr<int> readInt16([Endian endian = Endian.big]) async {
    await require(2);
    return _buffer.readInt16(endian);
  }

  @override
  FutureOr<int> readUint16([Endian endian = Endian.big]) async {
    await require(2);
    return _buffer.readUint16(endian);
  }

  @override
  FutureOr<int> readInt32([Endian endian = Endian.big]) async {
    await require(4);
    return _buffer.readInt32(endian);
  }

  @override
  FutureOr<int> readUint32([Endian endian = Endian.big]) async {
    await require(4);
    return _buffer.readUint32(endian);
  }

  @override
  FutureOr<int> readInt64([Endian endian = Endian.big]) async {
    await require(8);
    return _buffer.readInt64(endian);
  }

  @override
  FutureOr<int> readUint64([Endian endian = Endian.big]) async {
    await require(8);
    return _buffer.readUint64(endian);
  }

  @override
  FutureOr<double> readFloat32([Endian endian = Endian.big]) async {
    await require(4);
    return _buffer.readFloat32(endian);
  }

  @override
  FutureOr<double> readFloat64([Endian endian = Endian.big]) async {
    await require(8);
    return _buffer.readFloat64(endian);
  }

  @override
  FutureOr<int> readIntoBytes(Uint8List sink, [int start = 0, int? end]) async {
    end = RangeError.checkValidRange(start, end, sink.length);
    int read = 0;
    while (end > start) {
      if (_buffer.isEmpty && await _source.read(_buffer, kBlockSize) == 0) {
        return read;
      }
      final count = _buffer.readIntoBytes(sink, start, end);
      read += count;
      start += count;
    }
    return read;
  }

  @override
  FutureOr<int> readIntoSink(Sink sink) async {
    int read = 0;
    while (_buffer.isNotEmpty) {
      read += _buffer.length;
      await sink.write(_buffer, _buffer.length);
      await _source.read(_buffer, kBlockSize);
    }
    return read;
  }

  @override
  FutureOr<String> readString({Encoding encoding = utf8, int? count}) async {
    if (count == null) {
      await _buffer.writeSource(_source);
      return _buffer.readString(encoding: encoding);
    } else {
      await require(count);
      return _buffer.readString(encoding: encoding, count: count);
    }
  }

  @override
  FutureOr<String?> readLine({Encoding encoding = utf8}) async {
    final newline = await indexOf(kLF);
    if (newline == -1) {
      if (_buffer.length != 0) {
        return _buffer.readString(encoding: encoding);
      } else {
        return null;
      }
    } else {
      return _buffer.readLine(encoding: encoding, newline: newline);
    }
  }

  @override
  FutureOr<String> readLineStrict({Encoding encoding = utf8, int? end}) async {
    final newline = await indexOf(kLF, 0, end);
    if (newline != -1) {
      return _buffer.readLine(encoding: encoding, newline: newline)!;
    }
    throw EOFException();
  }

  @override
  FutureOr<void> close() async {
    if (_closed) return;
    _closed = true;
    await _source.close();
    _buffer.clear();
  }

  @override
  String toString() => 'buffer($_source)';
}
