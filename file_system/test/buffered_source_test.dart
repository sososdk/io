import 'dart:convert';
import 'dart:typed_data';

import 'package:file_system/file_system.dart';
import 'package:test/test.dart';

void main() {
  group('buffer', () {
    test('clear', () {
      final buffer = Buffer();
      buffer.writeString('hello');
      expect(buffer.length, 5);
      buffer.clear();
      expect(buffer.length, 0);
    });

    test('get', () {
      final buffer = Buffer();
      expect(() => buffer[0], throwsRangeError);
      buffer.writeInt8(0);
      expect(() => buffer[1], throwsRangeError);
      expect(buffer[0], 0);
    });

    test('read', () {
      final buffer = Buffer();
      buffer.writeInt32(1);
      buffer.writeInt64(1);
      final sink = Buffer();
      buffer.read(sink, 10);
      expect(sink.length, 10);
      buffer.read(sink, 10);
      expect(sink.length, 12);
      buffer.read(sink, 10);
      expect(sink.length, 12);
    });

    test('exhausted', () {
      final buffer = Buffer();
      buffer.writeString('hello\nhello2\r\nhello3\r');
      expect(buffer.readLineStrict(), 'hello');
      expect(buffer.readLineStrict(), 'hello2');
      expect(() => buffer.readLineStrict(), throwsA(isA<EOFException>()));
      expect(buffer.exhausted(), false);
      expect(buffer.readLine(), 'hello3\r');
      expect(buffer.exhausted(), true);
    });

    test('require', () {
      final buffer = Buffer();
      expect(() => buffer.require(1), throwsA(isA<EOFException>()));
      buffer.writeString('hello');
      expect(() => buffer.require(6), throwsA(isA<EOFException>()));
    });

    test('skip', () {
      final buffer = Buffer();
      buffer.writeBytes([1, 2, 3]);
      buffer.writeBytes([4, 5, 6]);
      buffer.skip(2);
      expect(buffer.toString(), '[3, 4, 5, 6]');
      buffer.skip(2);
      expect(buffer.toString(), '[5, 6]');
    });

    test('index of', () {
      final buffer = Buffer();
      buffer.writeBytes(List.generate(300, (i) => i));

      final byte = buffer.indexOf(10);
      expect(byte, 10);
    });

    test('read into sink', () async {
      final fileSystem = MemoryFileSystem();
      final file = fileSystem.file('/test');
      final sink = FileSink(file.openSync(mode: FileMode.write));

      final buffer = Buffer();
      buffer.writeString('hello');

      await buffer.readIntoSink(sink);
      await sink.close();
      expect(buffer.isEmpty, true);
      expect(file.readAsStringSync(), 'hello');
    });

    test('read into bytes', () {
      final sink = Uint8List(4);

      final buffer = Buffer();
      buffer.writeString('he');
      buffer.writeString('llo');

      final read = buffer.readIntoBytes(sink);
      expect(buffer.length, 1);
      expect(utf8.decode(sink.sublist(0, read)), 'hell');
    });

    test('read bytes', () {
      final buffer = Buffer();
      final ints = List.generate(300, (i) => i);
      buffer.writeBytes(ints);

      buffer.skip(1);
      final bytes = buffer.readBytes(10);
      expect(bytes.toString(), '[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]');
      buffer.readBytes(300);
      expect(buffer.length, 0);
    });

    test('as bytes', () {
      final buffer = Buffer();
      final ints = List.generate(300, (i) => i);
      buffer.writeBytes(ints);

      expect(buffer.asBytes(10).length, 10);
      expect(buffer.asBytes().length, 300);
      expect(buffer.length, 300);
    });

    test('write and read', () async {
      final buffer = Buffer();
      buffer.writeInt8(1);
      buffer.writeInt16(2, Endian.little);
      buffer.writeInt32(3);
      buffer.writeInt64(4);
      buffer.writeFloat32(5);
      buffer.writeFloat64(6, Endian.little);
      buffer.writeString('hello');
      buffer.writeCharCode('0'.codeUnitAt(0));
      final fileSystem = MemoryFileSystem();
      await fileSystem.sink('/test').buffer().then((e) async {
        await e.writeLine('hello');
        await e.writeString('hello2\r\n');
        await e.writeString('hello3\r');
        await e.close();
      });
      final source = await fileSystem.source('/test');
      await buffer.writeSource(source);

      expect(buffer.readInt8(), 1);
      expect(buffer.readInt16(Endian.little), 2);
      expect(buffer.readInt32(), 3);
      expect(buffer.readInt64(), 4);
      expect(buffer.readFloat32(), 5);
      expect(buffer.readFloat64(Endian.little), 6);
      expect(buffer.readString(count: 5), 'hello');
      expect(buffer.readString(count: 1), '0');
      expect(buffer.readLine(), 'hello');
      expect(buffer.readLineStrict(), 'hello2');
      expect(() => buffer.readLineStrict(), throwsA(isA<EOFException>()));
      expect(buffer.exhausted(), false);
      expect(buffer.readLine(), 'hello3\r');
      expect(buffer.exhausted(), true);
    });

    test('copy to', () {
      final buffer = Buffer();
      buffer.writeString('hello\nhello2\r\nhello3\r');

      final buffer2 = Buffer();
      buffer.copyTo(buffer2, 2, 6);

      expect(buffer2.readLineStrict(), 'llo');
      expect(buffer2.exhausted(), true);

      buffer.copyTo(buffer2, 14);
      expect(buffer2.readLine(), 'hello3\r');
    });
  });

  group('sink and source', () {
    test('read', () async {
      final fileSystem = MemoryFileSystem();
      await fileSystem.sink('/test').buffer().then((e) async {
        await e.writeInt8(1);
        await e.writeInt16(2, Endian.little);
        await e.writeInt32(3);
        await e.writeInt64(4);
        await e.writeFloat32(5);
        await e.writeFloat64(6, Endian.little);
        await e.writeCharCode('0'.codeUnitAt(0));
        await e.writeLine('hello');
        await e.writeString('hello2\r\n');
        await e.writeString('hello3\r');
        final buffer = Buffer();
        buffer.writeString('I am a buffer');
        await e.write(buffer, buffer.length);
        await e.close();
      });

      final source = await fileSystem.source('/test').buffer();
      expect(await source.readInt8(), 1);
      expect(await source.readInt16(Endian.little), 2);
      expect(await source.readInt32(), 3);
      expect(await source.readInt64(), 4);
      expect(await source.readFloat32(), 5);
      expect(await source.readFloat64(Endian.little), 6);
      expect(await source.readInt8(), '0'.codeUnitAt(0));
      expect(await source.readLine(), 'hello');
      expect(await source.readLine(), 'hello2');
      await expectLater(source.readLineStrict, throwsA(isA<EOFException>()));
      final bytes = Uint8List(7);
      expect(await source.readIntoBytes(bytes), 7);
      expect(String.fromCharCodes(bytes), 'hello3\r');
      final sink = Buffer();
      expect(await source.readIntoSink(sink), 13);
      expect(sink.readString(), 'I am a buffer');
    });
  });
}
