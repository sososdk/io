import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anio/anio.dart';
import 'package:file/memory.dart';
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

      expect(10, buffer.indexOf(10));
      expect(-1, buffer.indexOf(256));
    });

    test('read into sink', () async {
      final fileSystem = MemoryFileSystem();
      final file = fileSystem.file('/test');
      final sink = file.openWrite().sink();

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
      await fileSystem
          .file('/test')
          .create(recursive: true)
          .then((e) => e.openWrite().sink())
          .buffer()
          .then((e) async {
        await e.writeLine('hello');
        await e.writeString('hello2\r\n');
        await e.writeString('hello3\r');
        await e.close();
      });
      final source = fileSystem.file('/test').openRead().source();
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

    test('copy to 2', () {
      final buffer = Buffer();
      buffer.writeBytes(List.generate(4, (index) => 0 + index));
      buffer.writeBytes(List.generate(4, (index) => 4 + index));
      buffer.writeBytes(List.generate(4, (index) => 8 + index));
      buffer.writeBytes(List.generate(4, (index) => 12 + index));
      buffer.writeBytes(List.generate(4, (index) => 16 + index));
      buffer.writeBytes(List.generate(4, (index) => 20 + index));
      buffer.writeBytes(List.generate(4, (index) => 24 + index));

      final buffer2 = Buffer();
      buffer.copyTo(buffer2, 0, 0);
      expect(buffer2.readBytes().toString(), '[]');
      buffer.copyTo(buffer2, 0, 1);
      expect(buffer2.readBytes().toString(), '[0]');
      buffer.copyTo(buffer2, 0, 2);
      expect(buffer2.readBytes().toString(), '[0, 1]');
      buffer.copyTo(buffer2, 0, 3);
      expect(buffer2.readBytes().toString(), '[0, 1, 2]');
      buffer.copyTo(buffer2, 0, 4);
      expect(buffer2.readBytes().toString(), '[0, 1, 2, 3]');
      buffer.copyTo(buffer2, 0, 5);
      expect(buffer2.readBytes().toString(), '[0, 1, 2, 3, 4]');

      buffer.copyTo(buffer2, 2, 2);
      expect(buffer2.readBytes().toString(), '[]');
      buffer.copyTo(buffer2, 2, 3);
      expect(buffer2.readBytes().toString(), '[2]');
      buffer.copyTo(buffer2, 2, 4);
      expect(buffer2.readBytes().toString(), '[2, 3]');
      buffer.copyTo(buffer2, 2, 5);
      expect(buffer2.readBytes().toString(), '[2, 3, 4]');
      buffer.copyTo(buffer2, 2, 6);
      expect(buffer2.readBytes().toString(), '[2, 3, 4, 5]');
      buffer.copyTo(buffer2, 2, 7);
      expect(buffer2.readBytes().toString(), '[2, 3, 4, 5, 6]');

      buffer.copyTo(buffer2, 3, 3);
      expect(buffer2.readBytes().toString(), '[]');
      buffer.copyTo(buffer2, 3, 4);
      expect(buffer2.readBytes().toString(), '[3]');
      buffer.copyTo(buffer2, 3, 5);
      expect(buffer2.readBytes().toString(), '[3, 4]');
      buffer.copyTo(buffer2, 3, 6);
      expect(buffer2.readBytes().toString(), '[3, 4, 5]');
      buffer.copyTo(buffer2, 3, 7);
      expect(buffer2.readBytes().toString(), '[3, 4, 5, 6]');
      buffer.copyTo(buffer2, 3, 8);
      expect(buffer2.readBytes().toString(), '[3, 4, 5, 6, 7]');

      buffer.copyTo(buffer2, 4, 4);
      expect(buffer2.readBytes().toString(), '[]');
      buffer.copyTo(buffer2, 4, 5);
      expect(buffer2.readBytes().toString(), '[4]');
      buffer.copyTo(buffer2, 4, 6);
      expect(buffer2.readBytes().toString(), '[4, 5]');
      buffer.copyTo(buffer2, 4, 7);
      expect(buffer2.readBytes().toString(), '[4, 5, 6]');
      buffer.copyTo(buffer2, 4, 8);
      expect(buffer2.readBytes().toString(), '[4, 5, 6, 7]');
      buffer.copyTo(buffer2, 4, 9);
      expect(buffer2.readBytes().toString(), '[4, 5, 6, 7, 8]');
      buffer.copyTo(buffer2, 4, 10);
      expect(buffer2.readBytes().toString(), '[4, 5, 6, 7, 8, 9]');

      buffer.copyTo(buffer2, 5, 5);
      expect(buffer2.readBytes().toString(), '[]');
      buffer.copyTo(buffer2, 5, 6);
      expect(buffer2.readBytes().toString(), '[5]');
      buffer.copyTo(buffer2, 5, 7);
      expect(buffer2.readBytes().toString(), '[5, 6]');
      buffer.copyTo(buffer2, 5, 8);
      expect(buffer2.readBytes().toString(), '[5, 6, 7]');
      buffer.copyTo(buffer2, 5, 9);
      expect(buffer2.readBytes().toString(), '[5, 6, 7, 8]');
      buffer.copyTo(buffer2, 5, 10);
      expect(buffer2.readBytes().toString(), '[5, 6, 7, 8, 9]');

      buffer.copyTo(buffer2, 6, 6);
      expect(buffer2.readBytes().toString(), '[]');
      buffer.copyTo(buffer2, 6, 7);
      expect(buffer2.readBytes().toString(), '[6]');
      buffer.copyTo(buffer2, 6, 8);
      expect(buffer2.readBytes().toString(), '[6, 7]');
      buffer.copyTo(buffer2, 6, 9);
      expect(buffer2.readBytes().toString(), '[6, 7, 8]');
      buffer.copyTo(buffer2, 6, 10);
      expect(buffer2.readBytes().toString(), '[6, 7, 8, 9]');
      buffer.copyTo(buffer2, 6, 11);
      expect(buffer2.readBytes().toString(), '[6, 7, 8, 9, 10]');

      buffer.copyTo(buffer2, 5, 17);
      expect(buffer2.readBytes().toString(),
          '[5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]');

      buffer.copyTo(buffer2, 15);
      expect(buffer2.readBytes().toString(),
          '[15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27]');
    });
  });

  group('BufferedSource', () {
    late int total;
    late Buffer buffer;
    late BufferedSource source;

    setUp(() {
      total = kBlockSize * 2;
      buffer = Buffer()..writeBytes(List.generate(total, (i) => i));
      source = (buffer as Source).buffer();
    });

    test('read', () async {
      final sink = Buffer();

      expect(await source.read(sink, 2), 2);
      expect(await source.read(sink, 100), 100);
      expect(await source.read(sink, total), kBlockSize - 100 - 2);
      expect(await source.read(sink, 1), 1);

      expect(buffer.length, 0);
      expect(sink.length, kBlockSize + 1);
    });

    test('exhausted', () async {
      expect(await source.exhausted(), isFalse);
      await source.readBytes();
      expect(await source.exhausted(), isTrue);
    });

    test('request', () async {
      expect(await source.request(0), isTrue);
      expect(await source.request(30), isTrue);
      expect(await source.request(20), isTrue);
      expect(await source.request(total), isTrue);
      expect(await source.request(total + 1), isFalse);
    });

    test('require', () async {
      expect(() => source.require(total + 1), throwsA(isA<EOFException>()));
    });

    test('indexOf', () async {
      expect(await source.indexOf(12), 12);
      expect(await source.indexOf(255), 255);
      expect(await source.indexOf(256), -1);
    });

    test('indexOf', () async {
      expect(await source.indexOf(12), 12);
      expect(await source.indexOf(255), 255);
      expect(await source.indexOf(256), -1);
    });

    test('readBytes', () async {
      expect(await source.readBytes(2), [0, 1]);
      await source.skip(total - 4);
      expect(await source.readBytes(2), [(total - 2) % 256, (total - 1) % 256]);
      expect(() => source.readBytes(2), throwsA(isA<EOFException>()));
    });

    test('read num', () async {
      buffer.clear();
      buffer.writeInt8(0);
      buffer.writeUint8(1);
      buffer.writeInt16(2);
      buffer.writeUint16(3);
      buffer.writeInt32(4);
      buffer.writeUint32(5);
      buffer.writeInt64(6);
      buffer.writeUint64(7);
      buffer.writeFloat32(8);
      buffer.writeFloat64(9);
      expect(await source.readInt8(), 0);
      expect(await source.readUint8(), 1);
      expect(await source.readInt16(), 2);
      expect(await source.readUint16(), 3);
      expect(await source.readInt32(), 4);
      expect(await source.readUint32(), 5);
      expect(await source.readInt64(), 6);
      expect(await source.readUint64(), 7);
      expect(await source.readFloat32(), 8);
      expect(await source.readFloat64(), 9);
    });

    test('readIntoBytes', () async {
      final sink = Uint8List(2);
      var count = await source.readIntoBytes(sink);
      expect(count, 2);
      expect(sink, [0, 1]);

      count = await source.readIntoBytes(sink, 1, 2);
      expect(count, 1);
      expect(sink, [0, 2]);

      await source.skip(total - 5);

      count = await source.readIntoBytes(sink);
      expect(count, 2);
      expect(sink, [(total - 2) % 256, (total - 1) % 256]);

      count = await source.readIntoBytes(sink);
      expect(count, 0);
      expect(sink, [(total - 2) % 256, (total - 1) % 256]);
    });

    test('readIntoSink', () async {
      final sink = Buffer();

      final count = await source.readIntoSink(sink);
      expect(count, total);
      expect(sink.length, total);
    });

    test('read string', () async {
      buffer = Buffer()..writeString('''
中国

Line 1
Line 2
Line 3''');
      source = (buffer as Source).buffer();

      expect(await source.readString(count: 6), '中国');
      expect(await source.readLine(), '');
      expect(await source.readLine(), '');
      expect(await source.readLine(), 'Line 1');
      expect(await source.readLineStrict(), 'Line 2');
      expect(() => source.readLineStrict(), throwsA(isA<EOFException>()));
    });
  });

  group('file sink and source', () {
    test('write and read', () async {
      final fileSystem = MemoryFileSystem();
      await fileSystem
          .file('/test')
          .create(recursive: true)
          .then((e) => e.openWrite().sink())
          .buffer()
          .then((e) async {
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

      final source = fileSystem.file('/test').openRead().source().buffer();
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

  group('file handle', () {
    test('write and read and append', () async {
      final path = '/test';
      final bytes = Uint8List(7);
      final buffer = Buffer();

      final fileSystem = MemoryFileSystem();
      final handle =
          FileHandle(await fileSystem.file(path).open(mode: FileMode.write));
      final sink = await handle.sink().buffer();
      final source = await handle.source().buffer();
      await handle.close();

      // write
      await sink.writeInt8(1);
      await sink.writeInt16(2, Endian.little);
      await sink.writeInt32(3);
      await sink.writeInt64(4);
      await sink.writeFloat32(5);
      await sink.writeFloat64(6, Endian.little);
      await sink.writeCharCode('0'.codeUnitAt(0));
      await sink.writeLine('hello');
      await sink.writeString('hello2\r\n');
      await sink.writeString('hello3\r');
      buffer.writeString('I am a buffer');
      await sink.write(buffer, buffer.length);
      await sink.close();

      // read
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
      expect(await source.readIntoBytes(bytes), 7);
      expect(String.fromCharCodes(bytes), 'hello3\r');
      expect(await source.readIntoSink(buffer), 13);
      expect(buffer.readString(), 'I am a buffer');
      await source.close();

      // append
      final appendHandle =
          FileHandle(await fileSystem.file(path).open(mode: FileMode.append));
      final appendSink = await appendHandle.sink().buffer();
      final appendSource = await appendHandle.source(0).buffer();
      await appendHandle.close();

      await appendSink.writeString('appended');
      await appendSink.close();

      expect(await appendSource.readInt8(), 1);
      expect(await appendSource.readInt16(Endian.little), 2);
      expect(await appendSource.readInt32(), 3);
      expect(await appendSource.readInt64(), 4);
      expect(await appendSource.readFloat32(), 5);
      expect(await appendSource.readFloat64(Endian.little), 6);
      expect(await appendSource.readInt8(), '0'.codeUnitAt(0));
      expect(await appendSource.readLine(), 'hello');
      expect(await appendSource.readLine(), 'hello2');
      await expectLater(
          appendSource.readLineStrict, throwsA(isA<EOFException>()));
      expect(await appendSource.readIntoBytes(bytes), 7);
      expect(String.fromCharCodes(bytes), 'hello3\r');
      expect(await appendSource.readIntoSink(buffer), 13 + 8);
      expect(buffer.readString(), 'I am a bufferappended');
      appendSource.close();
    });
  });
}
