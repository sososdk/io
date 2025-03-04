import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:anio/anio.dart';
import 'package:convert/convert.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:test/test.dart';

import 'mock_sink.dart';

const kSegmentSize = Segment.size;

void main() {
  group('buffer', () {
    test('read And Write', () {
      final buffer = Buffer();
      buffer.writeString('ab');
      expect(buffer.length, equals(2));
      buffer.writeString('cdef');
      expect(buffer.length, equals(6));
      expect(buffer.readString(count: 4), equals('abcd'));
      expect(buffer.length, equals(2));
      expect(buffer.readString(count: 2), equals('ef'));
      expect(buffer.length, equals(0));
      expect(() => buffer.readString(count: 1), throwsA(isA<EOFException>()));
    });

    test('buffer to string', () {
      expect('[]', Buffer().toString());
      expect(
        '[97, 13, 10, 98, 10, 99, 13, 100, 92, 101]',
        Buffer.fromString('a\r\nb\nc\rd\\e').toString(),
      );
      expect(
        '[84, 121, 114, 97, 110, 110, 111, 115, 97, 117, 114]',
        Buffer.fromString('Tyrannosaur').toString(),
      );
      expect(
        '[116, 201, 153, 203, 136, 114, 97, 110, 201, 153, 203, 140, 115, 195, 180, 114]',
        Buffer.fromBytes(hex.decode('74c999cb8872616ec999cb8c73c3b472'))
            .toString(),
      );
      expect(
        '[${List.filled(64, '0').join(', ')}]',
        Buffer.fromBytes(Int8List(64)).toString(),
      );
    });

    test('multiple segment buffers', () {
      final buffer = Buffer();
      buffer.writeString('a' * (1000));
      buffer.writeString('b' * (2500));
      buffer.writeString('c' * (5000));
      buffer.writeString('d' * (10000));
      buffer.writeString('e' * (25000));
      buffer.writeString('f' * (50000));
      expect('a' * (999), buffer.readString(count: 999)); // a...a
      // ab...bc
      expect('a${'b' * (2500)}c', buffer.readString(count: 2502));
      expect('c' * (4998), buffer.readString(count: 4998)); // c...c
      // cd...de
      expect('c${'d' * (10000)}e', buffer.readString(count: 10002));
      expect('e' * (24998), buffer.readString(count: 24998)); // e...e
      expect('e${'f' * (50000)}', buffer.readString(count: 50001)); // ef...f
      expect(0, buffer.length);
    });

    test('move bytes between buffers share segment', () async {
      const size = kSegmentSize ~/ 2 - 1;
      final sizes = await moveBytesBetweenBuffers(['a' * (size), 'b' * (size)]);
      expect([size * 2], sizes);
    });

    test('move bytes between buffers reassign segment', () async {
      const size = kSegmentSize ~/ 2 + 1;
      final sizes = await moveBytesBetweenBuffers(['a' * (size), 'b' * (size)]);
      expect([size, size], sizes);
    });

    test('move bytes between buffers multiple segments', () async {
      const size = kSegmentSize * 3 + 1;
      final sizes = await moveBytesBetweenBuffers(['a' * (size), 'b' * (size)]);
      expect([
        kSegmentSize,
        kSegmentSize,
        kSegmentSize,
        1,
        kSegmentSize,
        kSegmentSize,
        kSegmentSize,
        1,
      ], sizes);
    });

    /** The big part of source's first segment is being moved.  */
    test('write split source buffer left', () {
      const writeSize = kSegmentSize ~/ 2 + 1;
      final sink = Buffer();
      sink.writeString('b' * (kSegmentSize - 10));
      final source = Buffer();
      source.writeString('a' * (kSegmentSize * 2));
      sink.write(source, writeSize);
      expect([kSegmentSize - 10, writeSize], segmentSizes(sink));
      expect([kSegmentSize - writeSize, kSegmentSize], segmentSizes(source));
    });

    /** The big part of source's first segment is staying put.  */
    test('write prefix doesnt split', () {
      final sink = Buffer();
      sink.writeString('b' * (10));
      final source = Buffer();
      source.writeString('a' * (kSegmentSize * 2));
      sink.write(source, 20);
      expect([30], segmentSizes(sink));
      expect([kSegmentSize - 20, kSegmentSize], segmentSizes(source));
      expect(30, sink.length);
      expect((kSegmentSize * 2 - 20), source.length);
    });

    test('write prefix doesnt split but requires compact', () {
      final sink = Buffer();
      sink.writeString('b' * (kSegmentSize - 10)); // limit = size - 10
      sink.readString(count: (kSegmentSize - 20)); // pos = size = 20
      final source = Buffer();
      source.writeString('a' * (kSegmentSize * 2));
      sink.write(source, 20);
      expect([30], segmentSizes(sink));
      expect([kSegmentSize - 20, kSegmentSize], segmentSizes(source));
      expect(30, sink.length);
      expect((kSegmentSize * 2 - 20), source.length);
    });

    test('as bytes spanning segments', () {
      final source = Buffer();
      source.writeString('a' * (kSegmentSize * 2));
      source.writeString('b' * (kSegmentSize * 2));
      final out = source.asBytes(10, (kSegmentSize * 3));
      expect(
        'a' * (kSegmentSize * 2 - 10) + 'b' * (kSegmentSize),
        utf8.decode(out),
      );
      expect(
        'a' * (kSegmentSize * 2) + 'b' * (kSegmentSize * 2),
        source.readString(count: (kSegmentSize * 4)),
      );
    });

    test('as bytes', () {
      final buffer = Buffer.fromString('hello, world!');
      final out = buffer.asBytes();
      final outString = utf8.decode(out);
      expect('hello, world!', outString);
      expect('hello, world!', buffer.readString());
    });

    test('read spanning segments', () {
      final buffer = Buffer();
      buffer.writeString('a' * (kSegmentSize * 2));
      buffer.writeString('b' * (kSegmentSize * 2));
      buffer.skip(10);
      final out = Buffer();
      buffer.read(out, (kSegmentSize * 3));
      expect(
        'a' * (kSegmentSize * 2 - 10) + 'b' * (kSegmentSize + 10),
        out.readString(),
      );
      expect('b' * (kSegmentSize - 10), buffer.readString());
    });

    test('read into sink', () {
      final buffer = Buffer.fromString('hello, world!');
      final out = Buffer();
      buffer.readIntoSink(out);
      final outString = out.readString();
      expect('hello, world!', outString);
      expect(0, buffer.length);
    });

    test('read from does not leave empty tail segment', () {
      final buffer = Buffer();
      buffer.writeFromBytes(Uint8List(kSegmentSize));
      assertNoEmptySegments(buffer);
    });

    test('move all requested bytes with read', () {
      final sink = Buffer();
      sink.writeString('a' * (10));
      final source = Buffer();
      source.writeString('b' * (15));
      expect(10, source.read(sink, 10));
      expect(20, sink.length);
      expect(5, source.length);
      expect('a' * (10) + 'b' * (10), sink.readString(count: 20));
    });

    test('move fewer than requested bytes with read', () {
      final sink = Buffer();
      sink.writeString('a' * (10));
      final source = Buffer();
      source.writeString('b' * (20));
      expect(20, source.read(sink, 25));
      expect(30, sink.length);
      expect(0, source.length);
      expect('a' * (10) + 'b' * (20), sink.readString(count: 30));
    });

    test('index of with offset', () {
      final buffer = Buffer();
      const halfSegment = kSegmentSize ~/ 2;
      buffer.writeString('a' * (halfSegment));
      buffer.writeString('b' * (halfSegment));
      buffer.writeString('c' * (halfSegment));
      buffer.writeString('d' * (halfSegment));
      expect(0, buffer.indexOf('a'.codeUnitAt(0), 0));
      expect((halfSegment - 1),
          buffer.indexOf('a'.codeUnitAt(0), (halfSegment - 1)));
      expect(halfSegment, buffer.indexOf('b'.codeUnitAt(0), (halfSegment - 1)));
      expect((halfSegment * 2),
          buffer.indexOf('c'.codeUnitAt(0), (halfSegment - 1)));
      expect((halfSegment * 3),
          buffer.indexOf('d'.codeUnitAt(0), (halfSegment - 1)));
      expect((halfSegment * 3),
          buffer.indexOf('d'.codeUnitAt(0), (halfSegment * 2)));
      expect((halfSegment * 3),
          buffer.indexOf('d'.codeUnitAt(0), (halfSegment * 3)));
      expect((halfSegment * 4 - 1),
          buffer.indexOf('d'.codeUnitAt(0), (halfSegment * 4 - 1)));
    });

    test('byte at', () {
      final buffer = Buffer();
      buffer.writeString('a');
      buffer.writeString('b' * (kSegmentSize));
      buffer.writeString('c');
      expect('a'.codeUnitAt(0), buffer[0]);
      expect('a'.codeUnitAt(0), buffer[0]); // getByte doesn't mutate!
      expect('c'.codeUnitAt(0), buffer[buffer.length - 1]);
      expect('b'.codeUnitAt(0), buffer[buffer.length - 2]);
      expect('b'.codeUnitAt(0), buffer[buffer.length - 3]);
    });

    test('get byte of empty buffer', () {
      final buffer = Buffer();
      expect(() => buffer[0], throwsA(isA<IndexError>()));
    });

    test('write prefix to empty buffer', () {
      final sink = Buffer();
      final source = Buffer();
      source.writeString('abcd');
      sink.write(source, 2);
      expect('ab', sink.readString(count: 2));
    });

    test('copy does not observe writes to original', () {
      final original = Buffer();
      final clone = original.copy();
      original.writeString('abc');
      expect(0, clone.length);
    });

    test('copy does not observe reads from original', () {
      final original = Buffer();
      original.writeString('abc');
      final clone = original.copy();
      expect('abc', original.readString(count: 3));
      expect(3, clone.length);
      expect('ab', clone.readString(count: 2));
    });

    test('original does not observe writes to clone', () {
      final original = Buffer();
      final clone = original.copy();
      clone.writeString('abc');
      expect(0, original.length);
    });

    test('original does not observe reads from clone', () {
      final original = Buffer();
      original.writeString('abc');
      final clone = original.copy();
      expect('abc', clone.readString(count: 3));
      expect(3, original.length);
      expect('ab', original.readString(count: 2));
    });

    test('clone multiple segments', () {
      final original = Buffer();
      original.writeString('a' * (kSegmentSize * 3));
      final clone = original.copy();
      original.writeString('b' * (kSegmentSize * 3));
      clone.writeString('c' * (kSegmentSize * 3));
      expect(
        'a' * (kSegmentSize * 3) + 'b' * (kSegmentSize * 3),
        original.readString(count: (kSegmentSize * 6)),
      );
      expect(
        'a' * (kSegmentSize * 3) + 'c' * (kSegmentSize * 3),
        clone.readString(count: (kSegmentSize * 6)),
      );
    });

    test('equals and hash code empty', () {
      final a = Buffer();
      final b = Buffer();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('equals and hash code', () {
      final a = Buffer.fromString('dog');
      final b = Buffer.fromString('hotdog');
      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));
      b.readString(count: 3); // Leaves b containing 'dog'.
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('equals and hash code spanning segments', () {
      final dice = Random(0);
      final data = Uint8List.fromList(
          List.generate(1024 * 1024, (_) => dice.nextInt(0xff)));
      final a = bufferWithRandomSegmentLayout(dice, data);
      final b = bufferWithRandomSegmentLayout(dice, data);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      data[data.length ~/ 2]++; // Change a single byte.
      final c = bufferWithRandomSegmentLayout(dice, data);
      expect(a, isNot(equals(c)));
      expect(a.hashCode, isNot(equals(c.hashCode)));
    });

    test('read all writes all segments at once', () async {
      final write1 = Buffer()
        ..writeString(
          "${"a" * (kSegmentSize)}${"b" * (kSegmentSize)}${"c" * (kSegmentSize)}",
        );
      final source = Buffer()
        ..writeString(
          "${"a" * (kSegmentSize)}${"b" * (kSegmentSize)}${"c" * (kSegmentSize)}",
        );
      final mockSink = MockSink();
      final result = await source.readIntoSink(mockSink);
      expect((kSegmentSize * 3), result);
      expect(0, source.length);
      mockSink.assertLog(['write($write1, ${write1.length})']);
    });

    test('write all multiple segments', () async {
      final source = Buffer.fromString('a' * (kSegmentSize * 3));
      final sink = Buffer();
      expect((kSegmentSize * 3), await sink.writeFromSource(source));
      expect(0, source.length);
      expect('a' * (kSegmentSize * 3), sink.readString());
    });

    test('copy to', () {
      final source = Buffer();
      source.writeString('party');
      final target = Buffer();
      source.copyTo(target, 1, 4);
      expect('art', target.readString());
      expect('party', source.readString());
    });

    test('copy to on segment boundary', () {
      final as = 'a' * (kSegmentSize);
      final bs = 'b' * (kSegmentSize);
      final cs = 'c' * (kSegmentSize);
      final ds = 'd' * (kSegmentSize);
      final source = Buffer();
      source.writeString(as);
      source.writeString(bs);
      source.writeString(cs);
      final target = Buffer();
      target.writeString(ds);
      source.copyTo(target, as.length, (as.length + bs.length + cs.length));
      expect(ds + bs + cs, target.readString());
    });

    test('copy to off segment boundary', () {
      final as = 'a' * (kSegmentSize - 1);
      final bs = 'b' * (kSegmentSize + 2);
      final cs = 'c' * (kSegmentSize - 4);
      final ds = 'd' * (kSegmentSize + 8);
      final source = Buffer();
      source.writeString(as);
      source.writeString(bs);
      source.writeString(cs);
      final target = Buffer();
      target.writeString(ds);
      source.copyTo(target, as.length, (as.length + bs.length + cs.length));
      expect(ds + bs + cs, target.readString());
    });

    test('copy to source and target can be the same', () {
      final as = 'a' * (kSegmentSize);
      final bs = 'b' * (kSegmentSize);
      final source = Buffer();
      source.writeString(as);
      source.writeString(bs);
      source.copyTo(source, 0, source.length);
      expect(as + bs + as + bs, source.readString());
    });

    test('copy to empty source', () {
      final source = Buffer();
      final target = Buffer.fromString('aaa');
      source.copyTo(target, 0, 0);
      expect('', source.readString());
      expect('aaa', target.readString());
    });

    test('copy to empty target', () {
      final source = Buffer.fromString('aaa');
      final target = Buffer();
      source.copyTo(target, 0, 3);
      expect('aaa', source.readString());
      expect('aaa', target.readString());
    });

    test('copy to reports accurate size', () {
      final buf = Buffer.fromBytes([0, 1, 2, 3]);
      final buffer = Buffer();
      buf.copyTo(buffer, 0, 1);
      expect(4, buf.length);
      expect(1, buffer.length);
    });

    test('starts with', () {
      final source = Buffer()
        ..writeString('a' * (kSegmentSize - 1))
        ..writeString('bcd');

      expect(true, source.startsWith('a'.codeUnits[0]));
      expect(false, source.startsWith('a'.codeUnits[0], kSegmentSize - 1));
      expect(true, source.startsWith('a'.codeUnits[0], kSegmentSize - 2));
      expect(true, source.startsWith('b'.codeUnits[0], kSegmentSize - 1));
      expect(true, source.startsWith('c'.codeUnits[0], kSegmentSize));
      expect(false, source.startsWith('d'.codeUnits[0], kSegmentSize));

      expect(false, source.startsWithBytes('abcd'.codeUnits, kSegmentSize - 1));
      expect(true, source.startsWithBytes('bcd'.codeUnits, kSegmentSize - 1));
      expect(true, source.startsWithBytes('cd'.codeUnits, kSegmentSize));
      expect(true, source.startsWithBytes('d'.codeUnits, kSegmentSize + 1));
      expect(false, source.startsWithBytes('d'.codeUnits, kSegmentSize));
    });

    test('index of bytes at segment boundary', () {
      final source = Buffer()
        ..writeString('a' * (kSegmentSize - 1))
        ..writeString('bcd');
      expect(kSegmentSize - 3,
          source.indexOfBytes('aabc'.codeUnits, kSegmentSize - 4));
      expect(kSegmentSize - 3,
          source.indexOfBytes('aabc'.codeUnits, kSegmentSize - 3));
      expect(kSegmentSize - 2,
          source.indexOfBytes('abcd'.codeUnits, kSegmentSize - 2));
      expect(kSegmentSize - 2,
          source.indexOfBytes('abc'.codeUnits, kSegmentSize - 2));
      expect(kSegmentSize - 2,
          source.indexOfBytes('abc'.codeUnits, kSegmentSize - 2));
      expect(kSegmentSize - 2,
          source.indexOfBytes('ab'.codeUnits, kSegmentSize - 2));
      expect(kSegmentSize - 2,
          source.indexOfBytes('a'.codeUnits, kSegmentSize - 2));
      expect(kSegmentSize - 1,
          source.indexOfBytes('bc'.codeUnits, kSegmentSize - 2));
      expect(kSegmentSize - 1,
          source.indexOfBytes('b'.codeUnits, kSegmentSize - 2));
      expect(
          kSegmentSize, source.indexOfBytes('c'.codeUnits, kSegmentSize - 2));
      expect(kSegmentSize, source.indexOfBytes('c'.codeUnits, kSegmentSize));
      expect(kSegmentSize + 1,
          source.indexOfBytes('d'.codeUnits, kSegmentSize - 2));
      expect(kSegmentSize + 1,
          source.indexOfBytes('d'.codeUnits, kSegmentSize + 1));
    });

    test('index of bytes does not wrap around', () {
      final source = Buffer()
        ..writeString('a' * (kSegmentSize - 1))
        ..writeString('bcd');
      expect(-1, source.indexOfBytes('abcda'.codeUnits, kSegmentSize - 3));
    });

    test('index of bytes with offset', () {
      final source = Buffer();
      expect(-1, source.indexOfBytes('flop'.codeUnits));
      source.writeString('flop flip flop');
      source.emit();
      expect(10, source.indexOfBytes('flop'.codeUnits, 1));
      source.skipAll(); // Clear stream

      // Make sure we backtrack and resume searching after partial match.
      source.writeString('hi hi hi hi hey');
      expect(6, source.indexOfBytes('hi hi hey'.codeUnits, 1));
    });

    test('index of bytes with from index', () {
      final source = Buffer.fromString('aaa');
      expect(0, source.indexOfBytes('a'.codeUnits));
      expect(0, source.indexOfBytes('a'.codeUnits, 0));
      expect(1, source.indexOfBytes('a'.codeUnits, 1));
      expect(2, source.indexOfBytes('a'.codeUnits, 2));
    });
  });

  group('sink', () {
    test('emit complete segments', () {
      final BufferedSink b0 = Buffer();
      final BufferedSink b1 = b0.buffered();
      final BufferedSink b2 = b1.buffered();

      const length = kSegmentSize * 2 + 3616;
      b2.buffer.writeFromBytes(Uint8List(length));
      expect(length, b2.buffer.length);
      expect(0, b1.buffer.length);
      expect(0, b0.buffer.length);

      b2.emitCompleteSegments();
      expect(length % kSegmentSize, b2.buffer.length);
      expect(0, b1.buffer.length);
      expect((length ~/ kSegmentSize) * kSegmentSize, b0.buffer.length);
    });
  });

  group('source', () {});

  group('file handle', () {
    late FileSystem system;

    setUp(() => system = MemoryFileSystem());

    test('file handle write and read', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().buffered().use((sink) async {
          await sink.writeString('abcdefghijklmnop');
        });
        await e.source().buffered().use((source) async {
          expect(await source.readString(count: 5), 'abcde');
          expect(await source.readString(), 'fghijklmnop');
        });
      });
    });

    test('file handle write and overwrite', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().buffered().use((sink) async {
          await sink.writeString('abcdefghij');
        });

        final length = await e.length();
        await e.sink(length - 3).buffered().use((e) async {
          await e.writeString('HIJKLMNOP');
        });
        await e.source().buffered().use((source) async {
          expect('abcdefgHIJKLMNOP', await source.readString());
        });
      });
    });

    test('file handle write beyond end', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink(10).buffered().use((sink) async {
          await sink.writeString('klmnop');
        });

        await e.source().buffered().use((source) async {
          expect(Uint8List(10), (await source.readBytes(10)));
          expect('klmnop', await source.readString());
        });
      });
    });

    test('file handle resize smaller', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().buffered().use((sink) async {
          await sink.writeString('abcdefghijklmnop');
        });

        await e.truncate(10);

        await e.source().buffered().use((source) async {
          expect('abcdefghij', await source.readString());
        });
      });
    });

    test('file handle resize larger', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().buffered().use((sink) async {
          await sink.writeString('abcde');
        });

        await e.truncate(15);

        await e.source().buffered().use((source) async {
          expect('abcde', await source.readString(count: 5));
          expect(Uint8List(10), (await source.readBytes()));
        });
      });
    });

    test('file handle flush', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().buffered().use((sink) async {
          await sink.writeString('abcde');
        });
        await e.flush();

        await system.file('temp').openHandle().use((e) async {
          await e.source().buffered().use((source) async {
            expect('abcde', await source.readString());
          });
        });
      });
    });

    test('file handle large buffered write and read', () async {
      final data = randomBytes(1024 * 1024 * 8);
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().buffered().use((sink) async {
          await sink.writeFromBytes(data);
        });
      });
      await system.file('temp').openHandle(mode: FileMode.read).use((e) async {
        await e.source().buffered().use((source) async {
          final uint8list = await source.readBytes();
          expect(data, uint8list);
        });
      });
    });

    test('file handle sink position', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().use((sink) async {
          await sink.write(Buffer.fromString('abcde'), 5);
          expect(5, sink.position);
          await sink.write(Buffer.fromString('fghijklmno'), 10);
          expect(15, sink.position);
        });
        await e.sink(200).use((sink) async {
          await sink.write(Buffer.fromString('abcde'), 5);
          expect(205, sink.position);
          await sink.write(Buffer.fromString('fghijklmno'), 10);
          expect(215, sink.position);
        });
        await e.source().buffered().use((sink) async {
          expect('abcdefghijklmno', await sink.readString(count: 15));
          expect(Uint8List(200 - 15), await sink.readBytes(200 - 15));
          expect('abcdefghijklmno', await sink.readString());
        });
      });
    });

    test('file handle buffered sink position', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().buffered().use((sink) async {
          await sink.write(Buffer.fromString('abcde'), 5);
          expect(5, sink.position);
          await sink.write(Buffer.fromString('fghijklmno'), 10);
          expect(15, sink.position);
        });
        await e.sink(200).buffered().use((sink) async {
          await sink.write(Buffer.fromString('abcde'), 5);
          expect(205, sink.position);
          await sink.write(Buffer.fromString('fghijklmno'), 10);
          expect(215, sink.position);
        });
        await e.source().buffered().use((sink) async {
          expect('abcdefghijklmno', await sink.readString(count: 15));
          expect(Uint8List(200 - 15), await sink.readBytes(200 - 15));
          expect('abcdefghijklmno', await sink.readString());
        });
      });
    });

    test('file handle sink reposition', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().use((sink) async {
          await sink.write(Buffer.fromString('abcdefghij'), 10);
          sink.position = 5;
          expect(5, sink.position);
          await sink.write(Buffer.fromString('KLM'), 3);
          expect(8, sink.position);

          sink.position = 200;
          await sink.write(Buffer.fromString('ABCDEFGHIJ'), 10);
          sink.position = 205;
          expect(205, sink.position);
          await sink.write(Buffer.fromString('klm'), 3);
          expect(208, sink.position);
        });

        {
          final buffer = Buffer();
          await e.readIntoSinkWithPosition(0, buffer, 10);
          expect('abcdeKLMij', buffer.readString());
        }

        {
          final buffer = Buffer();
          await e.readIntoSinkWithPosition(200, buffer, 15);
          expect('ABCDEklmIJ', buffer.readString());
        }
      });
    });

    test('file handle buffered sink reposition', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().buffered().use((sink) async {
          await sink.write(Buffer.fromString('abcdefghij'), 10);
          await sink.emit();
          sink.position = 5;
          expect(5, sink.position);
          await sink.write(Buffer.fromString('KLM'), 3);
          expect(8, sink.position);

          await sink.emit();
          sink.position = 200;
          await sink.write(Buffer.fromString('ABCDEFGHIJ'), 10);
          await sink.emit();
          sink.position = 205;
          expect(205, sink.position);
          await sink.write(Buffer.fromString('klm'), 3);
          expect(208, sink.position);
        });

        {
          final buffer = Buffer();
          await e.readIntoSinkWithPosition(0, buffer, 10);
          expect('abcdeKLMij', buffer.readString());
        }

        {
          final buffer = Buffer();
          await e.readIntoSinkWithPosition(200, buffer, 15);
          expect('ABCDEklmIJ', buffer.readString());
        }
      });
    });

    test('file handle source happy path', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().buffered().use((sink) async {
          await sink.writeString('abcdefghijklmnop');
        });
      });
      await system.file('temp').openHandle(mode: FileMode.read).use((e) async {
        expect(16, await e.length());
        final buffer = Buffer();

        await e.source().use((source) async {
          expect(0, source.position);
          expect(4, await source.read(buffer, 4));
          expect('abcd', buffer.readString());
          expect(4, source.position);
        });

        await e.source(8).use((source) async {
          expect(8, source.position);
          expect(4, await source.read(buffer, 4));
          expect('ijkl', buffer.readString());
          expect(12, source.position);
        });

        await e.source(16).use((source) async {
          expect(16, source.position);
          expect(0, await source.read(buffer, 4));
          expect('', buffer.readString());
          expect(16, source.position);
        });
      });
    });

    test('file handle source reposition', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().buffered().use((sink) async {
          await sink.writeString('abcdefghijklmnop');
        });
      });
      await system.file('temp').openHandle(mode: FileMode.read).use((e) async {
        expect(16, await e.length());
        final buffer = Buffer();

        await e.source().use((source) async {
          source.position = 12;
          expect(12, source.position);
          expect(4, await source.read(buffer, 4));
          expect('mnop', buffer.readString());
          expect(0, await source.read(buffer, 4));
          expect('', buffer.readString());
          expect(16, source.position);

          source.position = 0;
          expect(0, source.position);
          expect(4, await source.read(buffer, 4));
          expect('abcd', buffer.readString());
          expect(4, source.position);

          source.position = 8;
          expect(8, source.position);
          expect(4, await source.read(buffer, 4));
          expect('ijkl', buffer.readString());
          expect(12, source.position);

          source.position = 16;
          expect(16, source.position);
          expect(0, await source.read(buffer, 4));
          expect('', buffer.readString());
          expect(16, source.position);
        });
      });
    });

    test('file handle buffered source reposition', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().buffered().use((sink) async {
          await sink.writeString('abcdefghijklmnop');
        });
      });
      await system.file('temp').openHandle(mode: FileMode.read).use((e) async {
        expect(16, await e.length());
        final buffer = Buffer();

        await e.source().buffered().buffered().buffered().use((source) async {
          expect(0, source.buffer.length);
          source.position = 12;
          expect(12, source.position);
          expect(4, await source.read(buffer, 4));
          expect(0, source.buffer.length);
          expect('mnop', buffer.readString());
          expect(0, await source.read(buffer, 4));
          expect('', buffer.readString());
          expect(16, source.position);

          source.position = 0;
          expect(0, source.buffer.length);
          expect(0, source.position);
          expect(4, await source.read(buffer, 4));
          expect(12, source.buffer.length);
          expect('abcd', buffer.readString());
          expect(4, source.position);

          source.position = 8;
          expect(8, source.buffer.length);
          expect(8, source.position);
          expect(4, await source.read(buffer, 4));
          expect(4, source.buffer.length);
          expect('ijkl', buffer.readString());
          expect(12, source.position);

          source.position = 16;
          expect(0, source.buffer.length);
          expect(16, source.position);
          expect(0, await source.read(buffer, 4));
          expect(0, source.buffer.length);
          expect('', buffer.readString());
          expect(16, source.position);
        });
      });
    });

    test('file handle source seek backwards', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().buffered().use((sink) async {
          await sink.writeString('abcdefghijklmnop');
        });
      });
      await system.file('temp').openHandle(mode: FileMode.read).use((e) async {
        expect(16, await e.length());

        final buffer = Buffer();
        await e.source().use((source) async {
          expect(0, source.position);
          expect(16, await source.read(buffer, 16));
          expect('abcdefghijklmnop', buffer.readString());
          expect(16, source.position);
        });
        await e.source(0).use((source) async {
          expect(0, source.position);
          expect(16, await source.read(buffer, 16));
          expect('abcdefghijklmnop', buffer.readString());
          expect(16, source.position);
        });
      });
    });

    test('buffered file handle source happy path', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().buffered().use((sink) async {
          await sink.writeString('abcdefghijklmnop');
        });
      });
      await system.file('temp').openHandle(mode: FileMode.read).use((e) async {
        expect(16, await e.length());

        final buffer = Buffer();
        await e.source().buffered().use((source) async {
          expect(0, source.position);
          expect(4, await source.read(buffer, 4));
          expect('abcd', buffer.readString());
          expect(4, source.position);
        });
        await e.source(8).buffered().use((source) async {
          expect(8, source.position);
          expect(4, await source.read(buffer, 4));
          expect('ijkl', buffer.readString());
          expect(12, source.position);
        });
        await e.source(16).buffered().use((source) async {
          expect(16, source.position);
          expect(0, await source.read(buffer, 4));
          expect('', buffer.readString());
          expect(16, source.position);
        });
      });
    });

    test('buffered file handle source seek backwards', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        await e.sink().buffered().use((sink) async {
          await sink.writeString('abcdefghijklmnop');
        });
      });
      await system.file('temp').openHandle(mode: FileMode.read).use((e) async {
        expect(16, await e.length());

        final buffer = Buffer();
        await e.source().buffered().use((source) async {
          expect(0, source.position);
          expect(16, await source.read(buffer, 16));
          expect('abcdefghijklmnop', buffer.readString());
          expect(16, source.position);
        });
        await e.source(0).buffered().use((source) async {
          expect(0, source.position);
          expect(16, await source.read(buffer, 16));
          expect('abcdefghijklmnop', buffer.readString());
          expect(16, source.position);
        });
      });
    });

    test('sink position fails after close', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        final sink = e.sink();
        await sink.close();
        expect(() => sink.position, throwsA(isA<StateError>()));
        expect(
          () => sink.buffered().buffered().buffered().position,
          throwsA(isA<StateError>()),
        );
      });
    });

    test('sink reposition fails after close', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        final sink = e.sink();
        await sink.close();
        expect(() => sink.position = 1, throwsA(isA<StateError>()));
        expect(
          () => sink.buffered().buffered().buffered().position = 1,
          throwsA(isA<StateError>()),
        );
      });
    });

    test('source position fails after close', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        final source = e.source();
        await source.close();
        expect(() => source.position, throwsA(isA<StateError>()));
        expect(
          () => source.buffered().buffered().buffered().position,
          throwsA(isA<StateError>()),
        );
      });
    });

    test('source reposition fails after close', () async {
      await system.file('temp').openHandle(mode: FileMode.write).use((e) async {
        final source = e.source();
        await source.close();
        expect(() => source.position = 1, throwsA(isA<StateError>()));
        expect(
          () => source.buffered().buffered().buffered().position = 1,
          throwsA(isA<StateError>()),
        );
      });
    });
  });

  group('peek', () {
    test('peek', () async {
      final buffer = Buffer.fromString('abcdefghi');
      expect('abc', buffer.readString(count: 3));
      final peek = buffer.peek();
      expect('def', await peek.readString(count: 3));
      expect('ghi', await peek.readString(count: 3));
      expect(await peek.request(1), false);
      expect('def', buffer.readString(count: 3));
    });

    test('peek multiple', () async {
      final buffer = Buffer.fromString('abcdefghi');
      expect('abc', buffer.readString(count: 3));
      final peek1 = buffer.peek();
      final peek2 = buffer.peek();
      expect('def', await peek1.readString(count: 3));
      expect('def', await peek2.readString(count: 3));
      expect('ghi', await peek2.readString(count: 3));
      expect(await peek2.request(1), false);
      expect('ghi', await peek1.readString(count: 3));
      expect(await peek1.request(1), false);
      expect('def', buffer.readString(count: 3));
    });

    test('peek large', () async {
      final buffer = Buffer.fromString('abcdef');
      buffer.writeString('g' * 2 * kSegmentSize);
      buffer.writeString('hij');
      expect('abc', buffer.readString(count: 3));
      final peek = buffer.peek();
      expect('def', await peek.readString(count: 3));
      await peek.skip(2 * kSegmentSize);
      expect('hij', await peek.readString(count: 3));
      expect(await peek.request(1), false);
      expect('def', buffer.readString(count: 3));
      buffer.skip(2 * kSegmentSize);
      expect('hij', buffer.readString(count: 3));
    });

    test('peek invalid', () async {
      final buffer = Buffer.fromString('abcdefghi');
      expect('abc', buffer.readString(count: 3));
      final peek = buffer.peek();
      expect('def', await peek.readString(count: 3));
      expect('ghi', await peek.readString(count: 3));
      expect(await peek.request(1), false);
      expect('def', buffer.readString(count: 3));
      try {
        await peek.readString();
        fail('should fail');
      } on StateError catch (e) {
        expect('Peek source is invalid because upstream source was used',
            e.message);
      }
    });

    test('peek segment then invalid', () async {
      final buffer = Buffer.fromString('abc');
      buffer.writeString('d' * 2 * kSegmentSize);
      expect('abc', buffer.readString(count: 3));

      // Peek a little data and skip the rest of the upstream source
      final peek = buffer.peek();
      expect('ddd', await peek.readString(count: 3));
      buffer.clear();

      // Skip the rest of the buffered data
      await peek.skip(peek.buffer.length);
      try {
        await peek.readInt8();
        fail('should fail');
      } on StateError catch (e) {
        expect('Peek source is invalid because upstream source was used',
            e.message);
      }
    });

    test('peek doesnt read too much', () async {
      // 6 bytes in source's buffer plus 3 bytes upstream.
      final buffer = Buffer.fromString('abcdef');
      buffer.require(6);
      buffer.writeString('ghi');
      final peek = buffer.peek();

      // Read 3 bytes. This reads some of the buffered data.
      expect(await peek.request(3), true);
      expect('abc', await peek.readString(count: 3));

      // Read 3 more bytes. This exhausts the buffered data.
      expect(await peek.request(3), true);
      expect('def', await peek.readString(count: 3));

      // Read 3 more bytes. This draws new bytes.
      expect(await peek.request(3), true);
      expect(9, buffer.buffer.length);
      expect(3, peek.buffer.length);
      expect('ghi', await peek.readString(count: 3));
    });
  });
}

Future<List<int>> moveBytesBetweenBuffers(List<String> contents) async {
  final expected = StringBuffer();
  final buffer = Buffer();
  for (var s in contents) {
    final source = Buffer.fromString(s);
    await buffer.writeFromSource(source);
    expected.write(s);
  }
  final sizes = segmentSizes(buffer);
  expect(
    expected.toString(),
    buffer.readString(count: expected.length),
  );
  return sizes;
}

List<int> segmentSizes(Buffer buffer) {
  var segment = buffer.head;
  if (segment == null) return const [];

  final sizes = [segment.limit - segment.pos];
  segment = segment.next;
  while (!identical(segment, buffer.head)) {
    sizes.add(segment!.limit - segment.pos);
    segment = segment.next;
  }
  return sizes;
}

void assertNoEmptySegments(Buffer buffer) => expect(
      segmentSizes(buffer).every((e) => e != 0),
      isTrue,
      reason: 'Expected all segments to be non-empty',
    );

Buffer bufferWithRandomSegmentLayout(Random dice, Uint8List data) {
  final result = Buffer();

  // Writing to result directly will yield packed segments. Instead, write to
  // other buffers, then write those buffers to result.
  var pos = 0;
  int byteCount;
  while (pos < data.length) {
    byteCount = kSegmentSize ~/ 2 + dice.nextInt(kSegmentSize ~/ 2);
    if (byteCount > data.length - pos) byteCount = data.length - pos;
    final offset = dice.nextInt(kSegmentSize - byteCount);

    final segment = Buffer();
    segment.writeFromBytes(Uint8List(offset));
    segment.writeFromBytes(data, pos, pos + byteCount);
    segment.skip(offset);

    result.write(segment, byteCount);
    pos += byteCount;
  }

  return result;
}

Uint8List randomBytes(int length, [int? seed]) {
  final dice = Random(seed);
  return Uint8List.fromList(
      List.generate(1024 * 1024, (_) => dice.nextInt(0xff)));
}
