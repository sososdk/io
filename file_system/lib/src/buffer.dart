part of 'io.dart';

/// A collection of bytes in memory.
class Buffer implements BufferedSource, BufferedSink {
  final List<Uint8List> _chunks = [];
  int _length = 0;

  int get length => _length;

  bool get isEmpty => _length == 0;

  bool get isNotEmpty => !isEmpty;

  void clear() {
    _length = 0;
    _chunks.clear();
  }

  int operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', _length);
    var offset = 0;
    for (var chunk in _chunks) {
      if (chunk.length > index - offset) {
        return chunk[index - offset];
      } else {
        offset += chunk.length;
      }
    }
    throw StateError("No element");
  }

  @override
  Buffer get buffer => this;

  @override
  int read(Buffer sink, int count) {
    assert(count >= 0);
    if (_length == 0) return 0;
    if (count > _length) count = _length;
    sink.write(this, count);
    return count;
  }

  @override
  bool exhausted() => _length == 0;

  @override
  bool request(int count) => _length >= count;

  @override
  void require(int count) {
    if (_length < count) throw EOFException();
  }

  @override
  void skip(int count) {
    while (count > 0) {
      if (isEmpty) throw EOFException();
      final chunk = _chunks.removeAt(0);
      if (chunk.length > count) {
        _length -= count;
        _chunks.insert(0, chunk.sublist(count));
        count = 0;
      } else {
        _length -= chunk.length;
        count -= chunk.length;
      }
    }
  }

  @override
  int indexOf(int element, [int start = 0, int? end]) {
    assert(end == null || start < end);
    if (end == null) {
      end = _length;
    } else if (end > _length) {
      end = _length;
    }
    for (int i = start; i < end; i++) {
      if (this[i] == element) return i;
    }
    return -1;
  }

  @override
  FutureOr<int> readIntoSink(Sink sink) async {
    final count = _length;
    if (count > 0) {
      await sink.write(this, count);
    }
    return count;
  }

  @override
  int readIntoBytes(Uint8List sink, [int start = 0, int? end]) {
    end = RangeError.checkValidRange(start, end, sink.length);
    int read = 0;
    while (end > start) {
      if (isEmpty) return read;
      final chunk = _chunks.removeAt(0);
      if (chunk.length > end - start) {
        _length -= end - start;
        _chunks.insert(0, chunk.sublist(end - start));
        sink.setRange(start, end, chunk);
        read += end - start;
        start = end;
      } else {
        _length -= chunk.length;
        sink.setRange(start, start + chunk.length, chunk);
        read += chunk.length;
        start += chunk.length;
      }
    }
    return read;
  }

  @override
  Uint8List readBytes([int? count]) {
    assert(count == null || count >= 0);
    count ??= _length;
    final sink = Uint8List(min(count, _length));
    readIntoBytes(sink);
    return sink;
  }

  @override
  int readInt8() {
    if (isEmpty) throw EOFException();
    while (true) {
      final chunk = _chunks.removeAt(0);
      if (chunk.length > 1) {
        _chunks.insert(0, chunk.sublist(1));
        _length--;
        return chunk[0];
      } else if (chunk.length == 1) {
        _length--;
        return chunk[0];
      }
    }
  }

  @override
  int readInt16([Endian endian = Endian.big]) {
    if (_length < 2) throw EOFException();
    return readBytes(2).buffer.asByteData().getInt16(0, endian);
  }

  @override
  int readInt32([Endian endian = Endian.big]) {
    if (_length < 4) throw EOFException();
    return readBytes(4).buffer.asByteData().getInt32(0, endian);
  }

  @override
  int readInt64([Endian endian = Endian.big]) {
    if (_length < 8) throw EOFException();
    return readBytes(8).buffer.asByteData().getInt64(0, endian);
  }

  @override
  double readFloat32([Endian endian = Endian.big]) {
    if (_length < 4) throw EOFException();
    return readBytes(4).buffer.asByteData().getFloat32(0, endian);
  }

  @override
  double readFloat64([Endian endian = Endian.big]) {
    if (_length < 8) throw EOFException();
    return readBytes(8).buffer.asByteData().getFloat64(0, endian);
  }

  @override
  String readString({Encoding encoding = utf8, int? count}) {
    assert(count == null || count >= 0);
    count ??= _length;
    if (isEmpty) return '';
    final sink = Uint8List(min(_length, count));
    readIntoBytes(sink);
    return encoding.decode(sink);
  }

  @override
  String? readLine({Encoding encoding = utf8, int? newline}) {
    newline ??= indexOf(kLF);
    if (newline == -1) {
      if (_length == 0) {
        return null;
      } else {
        return readString(encoding: encoding, count: _length);
      }
    } else {
      return _readLine(encoding, newline);
    }
  }

  @override
  String readLineStrict({Encoding encoding = utf8, int? end}) {
    final newline = indexOf(kLF, 0, end);
    if (newline != -1) {
      return _readLine(encoding, newline);
    }
    throw EOFException();
  }

  String _readLine(Encoding encoding, int newline) {
    assert(newline >= 0);
    String result;
    if (newline > 0 && this[newline - 1] == kCR) {
      // Read everything until '\r\n', then skip the '\r\n'.
      result = readString(encoding: encoding, count: newline - 1);
      skip(2);
    } else {
      // Read everything until '\n', then skip the '\n'.
      result = readString(encoding: encoding, count: newline);
      skip(1);
    }
    return result;
  }

  @override
  void write(Buffer source, int count) {
    assert(source != this);
    RangeError.checkValueInInterval(count, 0, source.length);
    while (count > 0) {
      if (source.isEmpty) return;
      final chunk = source._chunks.removeAt(0);
      if (chunk.length > count) {
        _chunks.add(chunk.sublist(0, count));
        _length += count;
        source._chunks.insert(0, chunk.sublist(count));
        source._length -= count;
        count = 0;
      } else {
        _chunks.add(chunk);
        _length += chunk.length;
        source._length -= chunk.length;
        count -= chunk.length;
      }
    }
  }

  @override
  FutureOr<int> writeSource(Source source) async {
    int total = 0;
    while (true) {
      final read = await source.read(this, kBlockSize);
      if (read == 0) break;
      total += read;
    }
    return total;
  }

  @override
  void writeBytes(List<int> source, [int start = 0, int? end]) {
    end = RangeError.checkValidRange(start, end, source.length);
    if (!(start == 0 && end == source.length)) {
      source = source.sublist(start, end);
    }
    Uint8List bytes;
    if (source is Uint8List) {
      bytes = source;
    } else {
      bytes = Uint8List.fromList(source);
    }
    _chunks.add(bytes);
    _length += bytes.length;
  }

  @override
  void writeInt8(int byte) {
    writeBytes(Uint8List(1)..[0] = byte);
  }

  @override
  void writeInt16(int value, [Endian endian = Endian.big]) {
    writeBytes((ByteData(2)..setInt16(0, value, endian)).buffer.asUint8List());
  }

  @override
  void writeInt32(int value, [Endian endian = Endian.big]) {
    writeBytes((ByteData(4)..setInt32(0, value, endian)).buffer.asUint8List());
  }

  @override
  void writeInt64(int value, [Endian endian = Endian.big]) {
    writeBytes((ByteData(8)..setInt64(0, value, endian)).buffer.asUint8List());
  }

  @override
  void writeFloat32(double value, [Endian endian = Endian.big]) {
    writeBytes(
        (ByteData(4)..setFloat32(0, value, endian)).buffer.asUint8List());
  }

  @override
  void writeFloat64(double value, [Endian endian = Endian.big]) {
    writeBytes(
        (ByteData(8)..setFloat64(0, value, endian)).buffer.asUint8List());
  }

  @override
  void writeString(String string, [Encoding encoding = utf8]) {
    writeBytes(encoding.encode(string));
  }

  @override
  void writeLine([String string = '', Encoding encoding = utf8]) {
    writeString('$string\n', encoding);
  }

  @override
  void writeCharCode(int charCode) {
    writeString(String.fromCharCode(charCode));
  }

  Uint8List asBytes([int? count]) {
    assert(count == null || count >= 0);
    count ??= _length;
    if (_length == 0) return Uint8List(0);
    final sink = Uint8List(min(count, _length));
    int read = 0;
    for (var chunk in _chunks) {
      if (read + chunk.length > count) {
        sink.setRange(read, count, chunk);
        break;
      } else {
        sink.setRange(read, read + chunk.length, chunk);
        read += chunk.length;
      }
    }
    return sink;
  }

  void copyTo(Buffer buffer, [int start = 0, int? end]) {
    end = RangeError.checkValidRange(start, end, _length);
    for (var chunk in _chunks) {
      if (start + chunk.length > end) {
        buffer.writeBytes(chunk.sublist(start, end));
        break;
      } else {
        buffer.writeBytes(chunk);
        start += chunk.length;
      }
    }
  }

  @override
  void emit() {}

  @override
  void flush() {}

  @override
  void close() {}

  @override
  String toString() => asBytes().toString();
}
