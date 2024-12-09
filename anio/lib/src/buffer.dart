part of 'anio.dart';

/// A collection of bytes in memory.
class Buffer implements BufferedSource, BufferedSink {
  @internal
  Segment? head;

  int _length = 0;

  int get length => _length;

  @internal
  set length(int value) => _length = value;

  bool get isEmpty => _length == 0;

  bool get isNotEmpty => !isEmpty;

  void clear() => skip(_length);

  int operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', _length);
    final (s, offset) = seek(index)!;
    return s.data[s.pos + index - offset];
  }

  @override
  Buffer get buffer => this;

  @override
  int read(Buffer sink, int count) {
    checkArgument(count >= 0, 'count < 0: $count');
    if (isEmpty) return 0;
    if (count > _length) count = _length;
    sink.write(this, count);
    return count;
  }

  @override
  bool exhausted() => isEmpty;

  @override
  bool request(int count) => _length >= count;

  @override
  void require(int count) {
    if (_length < count) throw const EOFException();
  }

  @override
  void skip(int count) {
    while (count > 0) {
      final head = this.head;
      if (head == null) throw const EOFException();

      final toSkip = min(count, head.limit - head.pos);
      _length -= toSkip;
      count -= toSkip;
      head.pos += toSkip;

      if (head.pos == head.limit) {
        this.head = head.pop();
      }
    }
  }

  @override
  int indexOf(int element, [int start = 0, int? end]) {
    end = RangeError.checkValidRange(start, end, _length);
    if (start == end) return -1;
    if (head == null) return -1;
    var (s, offset) = seek(start)!;
    // Scan through the segments, searching for element.
    while (offset < end) {
      final data = s.data;
      final limit = min(s.limit, s.pos + end - offset);
      var pos = s.pos + start - offset;
      while (pos < limit) {
        if (data[pos] == element) {
          return pos - s.pos + offset;
        }
        pos++;
      }
      // Not in this segment. Try the next one.
      offset += s.limit - s.pos;
      start = offset;
      s = s.next;
    }
    return -1;
  }

  @override
  int indexOfBytes(Uint8List bytes, [int start = 0, int? end]) {
    checkArgument(bytes.isNotEmpty, 'bytes is empty');
    end = RangeError.checkValidRange(start, end, _length);
    if (end - start < bytes.length) return -1;
    if (head == null) return -1;
    var (s, offset) = seek(start)!;
    // Scan through the segments, searching for the lead byte. Each time that is found, delegate
    // to rangeEquals() to check for a complete match.
    final b0 = bytes[0];
    final bytesSize = bytes.length;
    final resultLimit = _length - bytesSize + 1;
    while (offset < resultLimit) {
      // Scan through the current segment.
      final data = s.data;
      final segmentLimit = min(s.limit, s.pos + resultLimit - offset);
      for (var pos = s.pos + start - offset; pos < segmentLimit; pos++) {
        if (data[pos] == b0 && s.rangeEquals(pos + 1, bytes, 1, bytesSize)) {
          return pos - s.pos + offset;
        }
      }

      // Not in this segment. Try the next one.
      offset += s.limit - s.pos;
      start = offset;
      s = s.next;
    }
    return -1;
  }

  @override
  Future<int> readIntoSink(Sink sink) async {
    final count = _length;
    if (count > 0) {
      final write = sink.write(this, count);
      if (write is Future<void>) await write;
    }
    return count;
  }

  @override
  int readIntoBytes(List<int> sink, [int start = 0, int? end]) {
    end = RangeError.checkValidRange(start, end, sink.length);
    var offset = start;
    while (end - offset > 0) {
      final s = head;
      if (s == null) return offset - start;
      final toCopy = min(end - offset, s.limit - s.pos);
      sink.setRange(offset, offset + toCopy, s.data, s.pos);
      offset += toCopy;
      s.pos += toCopy;
      _length -= toCopy;
      if (s.pos == s.limit) head = s.pop();
    }
    return offset - start;
  }

  @override
  Uint8List readBytes([int? count]) {
    checkArgument(count == null || count >= 0, 'count < 0: $count');
    if (count != null) require(count);
    count ??= _length;
    final sink = Uint8List(min(count, _length));
    readIntoBytes(sink);
    return sink;
  }

  @override
  int readInt8() {
    require(1);

    final segment = head!;
    var pos = segment.pos;
    final limit = segment.limit;

    final data = segment.data;
    final b = data[pos++];
    _length -= 1;

    if (pos == limit) {
      head = segment.pop();
    } else {
      segment.pos = pos;
    }

    return b;
  }

  @override
  int readUint8() => readInt8().toUnsigned(8);

  @override
  int readInt16([Endian endian = Endian.big]) {
    return readBytes(2).buffer.asByteData().getInt16(0, endian);
  }

  @override
  int readUint16([Endian endian = Endian.big]) {
    return readBytes(2).buffer.asByteData().getUint16(0, endian);
  }

  @override
  int readInt32([Endian endian = Endian.big]) {
    return readBytes(4).buffer.asByteData().getInt32(0, endian);
  }

  @override
  int readUint32([Endian endian = Endian.big]) {
    return readBytes(4).buffer.asByteData().getUint32(0, endian);
  }

  @override
  int readInt64([Endian endian = Endian.big]) {
    return readBytes(8).buffer.asByteData().getInt64(0, endian);
  }

  @override
  int readUint64([Endian endian = Endian.big]) {
    return readBytes(8).buffer.asByteData().getUint64(0, endian);
  }

  @override
  double readFloat32([Endian endian = Endian.big]) {
    return readBytes(4).buffer.asByteData().getFloat32(0, endian);
  }

  @override
  double readFloat64([Endian endian = Endian.big]) {
    return readBytes(8).buffer.asByteData().getFloat64(0, endian);
  }

  @override
  String readString({Encoding encoding = utf8, int? count}) {
    return encoding.decode(readBytes(count));
  }

  @override
  String? readLine({Encoding encoding = utf8, int? newline}) {
    newline ??= indexOf(kLF);
    if (newline == -1) {
      if (isEmpty) {
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
    if ((end != null && end < _length) &&
        this[end - 1] == kCR &&
        this[end] == kLF) {
      return _readLine(encoding, end);
    }
    throw const EOFException();
  }

  String _readLine(Encoding encoding, int newline) {
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
  bool rangeEquals(int offset, List<int> bytes, [int start = 0, int? end]) {
    checkArgument(offset >= 0);
    end = RangeError.checkValidRange(start, end, bytes.length);
    for (var i = start; i < end; i++) {
      if (this[offset + i - start] != bytes[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  BufferedSource peek() => PeekSource(this).buffered();

  @override
  void write(Buffer source, int count) {
    checkArgument(source != this, 'source == this');
    RangeError.checkValueInInterval(count, 0, source._length);
    while (count > 0) {
      // Is a prefix of the source's head segment all that we need to move?
      if (count < source.head!.limit - source.head!.pos) {
        final tail = head?.prev;
        if (tail != null &&
            tail.owner &&
            count + tail.limit - (tail.shared ? 0 : tail.pos) <= Segment.size) {
          // Our existing segments are sufficient. Move bytes from source's head to our tail.
          source.head!.writeTo(tail, count.toInt());
          source._length -= count;
          _length += count;
          return;
        } else {
          // We're going to need another segment. Split the source's head
          // segment in two, then move the first of those two to this buffer.
          source.head = source.head!.split(count.toInt());
        }
      }

      // Remove the source's head segment and append it to our tail.
      final segmentToMove = source.head;
      final movedCount = segmentToMove!.limit - segmentToMove.pos;
      source.head = segmentToMove.pop();
      if (head == null) {
        head = segmentToMove;
        segmentToMove.prev = segmentToMove;
        segmentToMove.next = segmentToMove.prev;
      } else {
        var tail = head!.prev;
        tail = tail.push(segmentToMove);
        tail.compact();
      }
      source._length -= movedCount;
      _length += movedCount;
      count -= movedCount;
    }
  }

  @override
  Future<int> writeFromSource(Source source) async {
    int totalBytes = 0;
    while (true) {
      final int result;
      final read = source.read(this, Segment.size);
      if (read is Future<int>) {
        result = await read;
      } else {
        result = read;
      }
      if (result == 0) break;
      totalBytes += result;
    }
    return totalBytes;
  }

  @override
  void writeFromBytes(List<int> source, [int start = 0, int? end]) {
    end = RangeError.checkValidRange(start, end, source.length);
    var offset = start;
    while (end - offset > 0) {
      final tail = writableSegment(1);
      final toCopy = min(end - offset, Segment.size - tail.limit);
      tail.data.setRange(tail.limit, tail.limit + toCopy, source, offset);

      offset += toCopy;
      tail.limit += toCopy;
    }
    _length += end - start;
  }

  @override
  void writeInt8(int value) {
    writeFromBytes((ByteData(1)..setInt8(0, value)).buffer.asUint8List());
  }

  @override
  void writeUint8(int value) {
    writeFromBytes((ByteData(1)..setUint8(0, value)).buffer.asUint8List());
  }

  @override
  void writeInt16(int value, [Endian endian = Endian.big]) {
    writeFromBytes(
        (ByteData(2)..setInt16(0, value, endian)).buffer.asUint8List());
  }

  @override
  void writeUint16(int value, [Endian endian = Endian.big]) {
    writeFromBytes(
        (ByteData(2)..setUint16(0, value, endian)).buffer.asUint8List());
  }

  @override
  void writeInt32(int value, [Endian endian = Endian.big]) {
    writeFromBytes(
        (ByteData(4)..setInt32(0, value, endian)).buffer.asUint8List());
  }

  @override
  void writeUint32(int value, [Endian endian = Endian.big]) {
    writeFromBytes(
        (ByteData(4)..setUint32(0, value, endian)).buffer.asUint8List());
  }

  @override
  void writeInt64(int value, [Endian endian = Endian.big]) {
    writeFromBytes(
        (ByteData(8)..setInt64(0, value, endian)).buffer.asUint8List());
  }

  @override
  void writeUint64(int value, [Endian endian = Endian.big]) {
    writeFromBytes(
        (ByteData(8)..setUint64(0, value, endian)).buffer.asUint8List());
  }

  @override
  void writeFloat32(double value, [Endian endian = Endian.big]) {
    writeFromBytes(
        (ByteData(4)..setFloat32(0, value, endian)).buffer.asUint8List());
  }

  @override
  void writeFloat64(double value, [Endian endian = Endian.big]) {
    writeFromBytes(
        (ByteData(8)..setFloat64(0, value, endian)).buffer.asUint8List());
  }

  @override
  void writeString(String string, [Encoding encoding = utf8]) {
    writeFromBytes(encoding.encode(string));
  }

  @override
  void writeLine([String string = '', Encoding encoding = utf8]) {
    writeString('$string\n', encoding);
  }

  @override
  void writeCharCode(int charCode) {
    writeString(String.fromCharCode(charCode));
  }

  Uint8List asBytes([int start = 0, int? end]) {
    end = RangeError.checkValidRange(start, end, _length);
    if (isEmpty) return Uint8List(0);

    final sink = Uint8List(end - start);
    var position = 0;
    var (s, offset) = seek(start)!;
    while (offset < end) {
      final limit = min(s.limit, s.pos + end - offset);
      final pos = s.pos + start - offset;
      sink.setRange(position, position + limit - pos, s.data, pos);
      position += limit - pos;
      offset += s.limit - s.pos;
      start = offset;
      s = s.next;
    }
    return sink;
  }

  void copyTo(Buffer buffer, [int start = 0, int? end]) {
    end = RangeError.checkValidRange(start, end, _length);
    if (start == end) return;
    var offset = start;
    var count = end - start;
    buffer._length += count;
    // Skip segments that we aren't copying from.
    var s = head!;
    while (offset >= s.limit - s.pos) {
      offset -= s.limit - s.pos;
      s = s.next;
    }
    // Copy one segment at a time.
    while (count > 0) {
      final copy = s.sharedCopy();
      copy.pos += offset;
      copy.limit = min(copy.limit, copy.pos + count);
      if (buffer.head == null) {
        copy.prev = copy;
        copy.next = copy.prev;
        buffer.head = copy.next;
      } else {
        buffer.head!.prev.push(copy);
      }
      count -= copy.limit - copy.pos;
      offset = 0;
      s = s.next;
    }
  }

  @internal
  Segment writableSegment(int minimumCapacity) {
    checkArgument(minimumCapacity >= 1 && minimumCapacity <= Segment.size,
        'unexpected capacity');

    if (head == null) {
      return head = Segment();
    }

    var tail = head!.prev;
    if (tail.limit + minimumCapacity > Segment.size || !tail.owner) {
      // Append a new empty segment to fill up.
      tail = tail.push(Segment());
    }
    return tail;
  }

  /// Searches from the front or the back depending on what's closer to [index].
  @internal
  (Segment, int)? seek(int index) {
    var s = head;
    if (s == null) return null;

    if (_length - index < index) {
      // We're scanning in the back half of this buffer. Find the segment starting at the back.
      var offset = _length;
      while (offset > index) {
        s = s!.prev;
        offset -= s.limit - s.pos;
      }
      return (s!, offset);
    } else {
      // We're scanning in the front half of this buffer. Find the segment starting at the front.
      var offset = 0;
      while (true) {
        final nextOffset = offset + (s!.limit - s.pos);
        if (nextOffset > index) break;
        s = s.next;
        offset = nextOffset;
      }
      return (s, offset);
    }
  }

  /// Returns the number of bytes in segments that are not writable. This is the number of bytes that
  /// can be flushed immediately to an underlying sink without harming throughput.
  @internal
  int completeSegmentByteCount() {
    var result = _length;
    if (result == 0) return 0;

    // Omit the tail if it's still writable.
    final tail = head!.prev;
    if (tail.limit < Segment.size && tail.owner) {
      result -= tail.limit - tail.pos;
    }

    return result;
  }

  Buffer copy() {
    final result = Buffer();
    if (isEmpty) return result;

    final head = this.head!;
    final headCopy = head.sharedCopy();

    result.head = headCopy;
    headCopy.prev = result.head!;
    headCopy.next = headCopy.prev;

    var s = head.next;
    while (!identical(s, head)) {
      headCopy.prev.push(s.sharedCopy());
      s = s.next;
    }

    result._length = _length;
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Buffer) return false;
    if (_length != other._length) return false;
    if (isEmpty) return true; // Both buffers are empty.

    var sa = head!;
    var sb = other.head!;
    var posA = sa.pos;
    var posB = sb.pos;

    var pos = 0;
    int count;
    while (pos < _length) {
      count = min(sa.limit - posA, sb.limit - posB);

      for (var i = 0; i < count; i++) {
        if (sa.data[posA++] != sb.data[posB++]) return false;
      }

      if (posA == sa.limit) {
        sa = sa.next;
        posA = sa.pos;
      }

      if (posB == sb.limit) {
        sb = sb.next;
        posB = sb.pos;
      }
      pos += count;
    }

    return true;
  }

  @override
  int get hashCode {
    var s = head;
    if (s == null) return 0;
    var result = 1;
    do {
      var pos = s!.pos;
      final limit = s.limit;
      while (pos < limit) {
        result = 31 * result + s.data[pos];
        pos++;
      }
      s = s.next;
    } while (!identical(s, head));
    return result;
  }

  @override
  void emit() {}

  @override
  void emitCompleteSegments() {}

  @override
  void flush() {}

  @override
  void close() {}

  @override
  String toString() => asBytes().toString();
}

class Segment {
  /// The size of all segments in bytes.
  static const int size = 8192;

  /// Segments will be shared when doing so avoids `arraycopy()` of this many bytes.
  static const int shareMinimum = 1024;

  final Uint8List data;

  /// The next byte of application data byte to read in this segment.
  int pos;

  /// The first byte of available data ready to be written to.
  ///
  /// If the segment is free and linked in the segment pool, the field contains total
  /// byte count of this and next segments.
  int limit;

  /// True if other segments or byte strings use the same byte array.
  bool shared;

  /// True if this segment owns the byte array and can append to it, extending `limit`.
  bool owner;

  /// Next segment in a linked or circularly-linked list.
  late Segment next;

  /// Previous segment in a circularly-linked list.
  late Segment prev;

  Segment({
    Uint8List? data,
    this.pos = 0,
    this.limit = 0,
    this.shared = false,
    this.owner = true,
  }) : data = data ?? Uint8List(size) {
    prev = this;
    next = this;
  }

  /// Returns a new segment that shares the underlying byte array with this. Adjusting pos and limit
  /// are safe but writes are forbidden. This also marks the current segment as shared, which
  /// prevents it from being pooled.
  Segment sharedCopy() {
    shared = true;
    return Segment(
        data: data, pos: pos, limit: limit, shared: true, owner: false);
  }

  /// Returns a new segment that its own private copy of the underlying byte array.
  Segment unsharedCopy() => Segment(
      data: Uint8List.fromList(data),
      pos: pos,
      limit: limit,
      shared: false,
      owner: true);

  /// Removes this segment of a circularly-linked list and returns its successor.
  /// Returns null if the list is now empty.
  Segment? pop() {
    final result = identical(next, this) ? null : next;
    prev.next = next;
    next.prev = prev;
    return result;
  }

  /// Appends `segment` after this segment in the circularly-linked list. Returns the pushed segment.
  Segment push(Segment segment) {
    segment.prev = this;
    segment.next = next;
    next.prev = segment;
    next = segment;
    return segment;
  }

  /// Splits this head of a circularly-linked list into two segments. The first segment contains the
  /// data in `[pos..pos+count)`. The second segment contains the data in
  /// `[pos+count..limit)`. This can be useful when moving partial segments from one buffer to
  /// another.
  ///
  /// Returns the new head of the circularly-linked list.
  Segment split(int count) {
    checkArgument(count > 0 && count <= limit - pos, 'count out of range');
    Segment prefix;

    // We have two competing performance goals:
    //  - Avoid copying data. We accomplish this by sharing segments.
    //  - Avoid short shared segments. These are bad for performance because they are readonly and
    //    may lead to long chains of short segments.
    // To balance these goals we only share segments when the copy will be large.
    if (count >= shareMinimum) {
      prefix = sharedCopy();
    } else {
      prefix = Segment();
      prefix.data.setRange(0, count, data, pos);
    }

    prefix.limit = prefix.pos + count;
    pos += count;
    prev.push(prefix);
    return prefix;
  }

  /// Call this when the tail and its predecessor may both be less than half full. This will copy
  /// data so that segments can be recycled.
  void compact() {
    checkArgument(!identical(prev, this), 'cannot compact');
    if (!prev.owner) return; // Cannot compact: prev isn't writable.
    final count = limit - pos;
    final availableCount = size - prev.limit + (prev.shared ? 0 : prev.pos);
    // Cannot compact: not enough writable space.
    if (count > availableCount) return;
    writeTo(prev, count);
    pop();
  }

  /// Moves [count] bytes from this segment to `sink`.
  void writeTo(Segment sink, int count) {
    checkArgument(sink.owner, 'only owner can write');
    if (sink.limit + count > size) {
      // We can't fit count bytes at the sink's current position. Shift sink first.
      if (sink.shared) throw ArgumentError();
      if (sink.limit + count - sink.pos > size) throw ArgumentError();
      sink.data.setRange(0, sink.limit - sink.pos, sink.data, sink.pos);
      sink.limit -= sink.pos;
      sink.pos = 0;
    }
    sink.data.setRange(sink.limit, sink.limit + count, data, pos);
    sink.limit += count;
    pos += count;
  }

  @internal
  bool rangeEquals(int pos, Uint8List bytes, [int start = 0, int? end]) {
    end = RangeError.checkValidRange(start, end, bytes.length);
    var segment = this;
    var limit = this.limit;
    var data = this.data;

    var i = start;
    while (i < end) {
      if (pos == limit) {
        segment = segment.next;
        limit = segment.limit;
        data = segment.data;
        pos = segment.pos;
      }

      if (data[pos] != bytes[i]) {
        return false;
      }

      pos++;
      i++;
    }

    return true;
  }

  @override
  String toString() => '{Segment@${hashCode.toRadixString(16)}}';
}
