import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:anio/anio.dart';
import 'package:anzip/anzip.dart';
import 'package:file_system/file_system.dart';
import 'package:test/test.dart';

const compressMethods = [CompressionStore(), CompressionDeflate()];
const encryptionMethods = [
  EncryptionNone(),
  EncryptionZipCrypto(),
  EncryptionAes(AesVersion.one, AesKeyStrength.keyStrength128),
  EncryptionAes(AesVersion.one, AesKeyStrength.keyStrength192),
  EncryptionAes(AesVersion.one, AesKeyStrength.keyStrength256),
  EncryptionAes(AesVersion.two, AesKeyStrength.keyStrength128),
  EncryptionAes(AesVersion.two, AesKeyStrength.keyStrength192),
  EncryptionAes(AesVersion.two, AesKeyStrength.keyStrength256),
];

const resources = 'test/resources/archives';

void main() {
  final fileSystem = LocalFileSystem();
  late Directory tempDir;
  late File generatedFile;
  late Directory extraDir;

  cleanTempDir() async {
    await for (var entity in tempDir.list()) {
      await entity.delete(recursive: true);
    }
  }

  setUp(() async {
    tempDir = await fileSystem.systemTempDirectory.createTemp('anzip');
    generatedFile = tempDir.childFile('output.zip');
    extraDir = tempDir.childDirectory('output');
    await cleanTempDir();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('compression and encryption enum', () {
    for (final compressMethod in compressMethods) {
      for (final encryptionMethod in encryptionMethods) {
        test('${compressMethod.name}_${encryptionMethod.name}', () async {
          final fileComment = '0' * 0xffff;
          final entry1Data = Uint8List(4);
          const entry1Name = '00001';
          final entry1Comment = '1' * 0xffff;
          final entry1Password = Uint8List.fromList('password1'.codeUnits);
          final entry1Time = DateTime(1970);
          final entry2Data = Uint8List(4);
          const entry2Name = '00002';
          final entry2Comment = '2' * 0xffff;
          final entry2Password = Uint8List.fromList('password2'.codeUnits);
          final entry2Time = DateTime(1970);

          FileEntry entry1() {
            return createEntry(
              ZeroSource(4),
              name: entry1Name,
              comment: entry1Comment,
              modifyTime: entry1Time,
              password: encryptionMethod.isEncrypted ? entry1Password : null,
              compressMethod: compressMethod,
              encryptionMethod: encryptionMethod,
            );
          }

          FileEntry entry2() {
            return createEntry(
              Buffer()..writeFromBytes(Uint8List(4)),
              name: entry2Name,
              comment: entry2Comment,
              modifyTime: entry2Time,
              password: encryptionMethod.isEncrypted ? entry2Password : null,
              compressMethod: compressMethod,
              encryptionMethod: encryptionMethod,
            );
          }

          final zipFile = ZipFile(generatedFile);
          await zipFile.add([entry1()]);
          await zipFile.add([entry2()]);
          await zipFile.setComment(fileComment);
          await checkZipFile(zipFile, false, false, fileComment);

          if (!encryptionMethod.isEncrypted) {
            final file2 = tempDir.childFile('output2.zip');
            final zipFile2 = ZipFile(file2);
            await zipFile2.add([entry1(), entry2()], fileComment);
            expect(
                await generatedFile.readAsBytes(), await file2.readAsBytes());
          }

          final header1 = zipFile.fileHeaders[0];
          final header2 = zipFile.fileHeaders[1];

          final zippedFile = await ZipFile.parse(generatedFile);
          await checkZipFile(zippedFile, zipFile.isSplitArchive,
              zipFile.isZip64Format, zipFile.comment);
          await checkEntry(
            zippedFile,
            entry1Name,
            header1.isZip64Format,
            header1.crc,
            header1.uncompressedSize,
            header1.epochTime,
            header1.comment,
            data: entry1Data,
            password: entry1Password,
            compressMethodType: header1.compressionMethod.runtimeType,
            encryptionMethodType: header1.encryptionMethod.runtimeType,
          );

          await checkEntry(
            zippedFile,
            entry2Name,
            header2.isZip64Format,
            header2.crc,
            header2.uncompressedSize,
            header2.epochTime,
            header2.comment,
            data: entry2Data,
            password: entry2Password,
            compressMethodType: header1.compressionMethod.runtimeType,
            encryptionMethodType: header1.encryptionMethod.runtimeType,
          );
        });
      }
    }
  });

  group('remove', () {
    test('add and remove', () async {
      const encryption = EncryptionZipCrypto();
      final password = Uint8List.fromList('password'.codeUnits);
      final zipFile = ZipFile(generatedFile);
      await zipFile.add([
        createEntry(ZeroSource(8),
            name: '0', encryptionMethod: encryption, password: password),
        createEntry(ZeroSource(8),
            name: '1', encryptionMethod: encryption, password: password),
        createEntry(ZeroSource(8),
            name: '2', encryptionMethod: encryption, password: password),
        createEntry(ZeroSource(8),
            name: '3', encryptionMethod: encryption, password: password),
      ]);

      await zipFile.removeWhere((header) => header.name == '0');
      expect(zipFile.fileHeaders.length, 3);
      expect(
          await ZipFile.parse(generatedFile).then((e) => e.fileHeaders.length),
          3);
      await zipFile.removeWhere((header) => header.name == '3');
      expect(zipFile.fileHeaders.length, 2);
      expect(
          await ZipFile.parse(generatedFile).then((e) => e.fileHeaders.length),
          2);

      final zippedFile = await ZipFile.parse(generatedFile);
      await checkZipFile(zippedFile, zipFile.isSplitArchive,
          zipFile.isZip64Format, zipFile.comment);
      await checkEntry(
        zippedFile,
        zipFile.fileHeaders[0].name,
        zipFile.fileHeaders[0].isZip64Format,
        zipFile.fileHeaders[0].crc,
        zipFile.fileHeaders[0].uncompressedSize,
        zipFile.fileHeaders[0].epochTime,
        zipFile.fileHeaders[0].comment,
        data: Uint8List(8),
        password: password,
        encryptionMethodType: EncryptionZipCrypto,
      );
      await checkEntry(
        zippedFile,
        zipFile.fileHeaders[1].name,
        zipFile.fileHeaders[1].isZip64Format,
        zipFile.fileHeaders[1].crc,
        zipFile.fileHeaders[1].uncompressedSize,
        zipFile.fileHeaders[1].epochTime,
        zipFile.fileHeaders[1].comment,
        data: Uint8List(8),
        password: password,
        encryptionMethodType: EncryptionZipCrypto,
      );
    });
  });

  group('split zip file', () {
    test('sample', () async {
      await ZipFile.create(
          generatedFile,
          [
            createEntry(ZeroSource(960), name: '960_0.txt'),
            createEntry(ZeroSource(960), name: '960_1.txt'),
            createEntry(ZeroSource(0xffff), name: '00003'),
          ],
          diskSize: 1024);

      await extra(generatedFile, extraDir);
      expect(
          await extraDir.childFile('960_0.txt').readAsBytes(), Uint8List(960));
      expect(
          await extraDir.childFile('960_1.txt').readAsBytes(), Uint8List(960));
      expect(
          await extraDir.childFile('00003').readAsBytes(), Uint8List(0xffff));
    });
  });

  group('zip 64', () {
    final entryData = Uint8List(4);
    const entryName = '00000';

    test('force zip 64', () async {
      final zipFile = ZipFile(generatedFile);
      await zipFile.add([
        FileEntry(Buffer()..writeFromBytes(Uint8List(4)),
            name: entryName, forceZip64Format: true),
      ]);
      await checkZipFile(zipFile, false, true, null);
      final header = zipFile.fileHeaders.first;

      final zippedFile = await ZipFile.parse(generatedFile);
      await checkZipFile(zippedFile, zipFile.isSplitArchive,
          zipFile.isZip64Format, zipFile.comment);
      await checkEntry(
        zippedFile,
        entryName,
        true,
        header.crc,
        header.uncompressedSize,
        header.epochTime,
        header.comment,
        data: entryData,
        compressMethodType: header.compressionMethod.runtimeType,
        encryptionMethodType: header.encryptionMethod.runtimeType,
      );
    });

    test('large file', () async {
      final zipFile = ZipFile(generatedFile);
      await zipFile.add([
        FileEntry(Buffer()..writeFromBytes(Uint8List(0xffffffff + 1)),
            name: entryName),
      ]);
      await checkZipFile(zipFile, false, true, null);
      final header = zipFile.fileHeaders.first;

      final zippedFile = await ZipFile.parse(generatedFile);
      await checkZipFile(zippedFile, zipFile.isSplitArchive,
          zipFile.isZip64Format, zipFile.comment);
      await checkEntry(
        zippedFile,
        entryName,
        true,
        header.crc,
        header.uncompressedSize,
        header.epochTime,
        header.comment,
        compressMethodType: header.compressionMethod.runtimeType,
        encryptionMethodType: header.encryptionMethod.runtimeType,
      );
    }, timeout: Timeout(Duration(minutes: 3)));

    test('large file 0xffffffff with encryption throw zip exception', () async {
      final zipFile = ZipFile(generatedFile);
      expect(
          zipFile.add([
            FileEntry(
              ZeroBuffer(0xffffffff),
              // Buffer()..writeFromBytes(Uint8List(0xffffffff)),
              name: entryName,
              password: Uint8List.fromList('password'.codeUnits),
              encryptionMethod: const EncryptionZipCrypto(),
            ),
          ]),
          throwsA(isA<ZipException>()));
    }, timeout: Timeout(Duration(minutes: 3)));

    test('large source 0xffffffff with encryption throw zip exception', () {
      final zipFile = ZipFile(generatedFile);
      expect(
          zipFile.add([
            FileEntry(
              ZeroSource(0xffffffff),
              name: entryName,
              password: Uint8List.fromList('password'.codeUnits),
              encryptionMethod: const EncryptionZipCrypto(),
            ),
          ]),
          throwsA(isA<ZipException>()));
    }, timeout: Timeout(Duration(minutes: 3)));

    test('large source 0xffffffff with encryption need force zip 64', () async {
      final zipFile = ZipFile(generatedFile);
      await zipFile.add([
        FileEntry(
          ZeroSource(0xffffffff),
          name: entryName,
          password: Uint8List.fromList('password'.codeUnits),
          encryptionMethod: const EncryptionZipCrypto(),
          forceZip64Format: true,
        ),
      ]);
      await checkZipFile(zipFile, false, true, null);
    }, timeout: Timeout(Duration(minutes: 3)));

    test('large source 0xffffffff + 1 for zip 64', () async {
      final zipFile = ZipFile(generatedFile);
      await zipFile.add([
        FileEntry(
          ZeroSource(0xffffffff + 1),
          name: entryName,
          password: Uint8List.fromList('password'.codeUnits),
          encryptionMethod: const EncryptionZipCrypto(),
          forceZip64Format: true,
        ),
      ]);
      await checkZipFile(zipFile, false, true, null);
    }, timeout: Timeout(Duration(minutes: 3)));
  });

  group('misc', () {});
}

Future<void> extra(File file, Directory extraDir, [Uint8List? password]) async {
  await extraDir.create(recursive: true);
  final zip = await ZipFile.parse(file);
  await zip.open().use((handle) async {
    for (final header in zip.fileHeaders) {
      if (header.isDirectory) {
        await extraDir.childDirectory(header.name).create(recursive: true);
      } else if (header.isSymbolicLink) {
        final target = await zip
            .getZipEntrySource(handle, header, password)
            .use((source) => source.buffered().readString());
        await extraDir.childLink(header.name).create(target, recursive: true);
      } else {
        await zip.getZipEntrySource(handle, header, password).use((source) =>
            extraDir
                .childFile(header.name)
                .openWrite()
                .sink()
                .buffered()
                .use((sink) => sink.writeFromSource(source)));
      }
    }
  });
}

class ZeroSource implements Source {
  final int length;

  ZeroSource(this.length);

  int bytesReceived = 0;

  @override
  int read(Buffer sink, int count) {
    if (bytesReceived >= length) return 0;
    count = min(count, length - bytesReceived);
    sink.writeFromBytes(Uint8List(count));
    bytesReceived += count;
    return count;
  }

  @override
  FutureOr<void> close() {}
}

class ZeroBuffer extends Buffer {
  ZeroBuffer(this._length);

  final int _length;

  int bytesReceived = 0;

  @override
  int get length => _length - bytesReceived;

  @override
  int operator [](int index) {
    throw UnimplementedError();
  }

  @override
  Uint8List asBytes([int start = 0, int? end]) {
    throw UnimplementedError();
  }

  @override
  Buffer get buffer => throw UnimplementedError();

  @override
  void clear() {
    throw UnimplementedError();
  }

  @override
  void close() {
    throw UnimplementedError();
  }

  @override
  int completeSegmentByteCount() {
    throw UnimplementedError();
  }

  @override
  Buffer copy() {
    throw UnimplementedError();
  }

  @override
  void copyTo(Buffer buffer, [int start = 0, int? end]) {
    throw UnimplementedError();
  }

  @override
  void emit() {
    throw UnimplementedError();
  }

  @override
  void emitCompleteSegments() {
    throw UnimplementedError();
  }

  @override
  bool exhausted() {
    throw UnimplementedError();
  }

  @override
  void flush() {
    throw UnimplementedError();
  }

  @override
  int indexOf(int element, [int start = 0, int? end]) {
    throw UnimplementedError();
  }

  @override
  int indexOfBytes(Uint8List bytes, [int start = 0, int? end]) {
    throw UnimplementedError();
  }

  @override
  bool get isEmpty => throw UnimplementedError();

  @override
  bool get isNotEmpty => throw UnimplementedError();

  @override
  BufferedSource peek() {
    return ZeroSource(length).buffered();
  }

  @override
  bool rangeEquals(int offset, List<int> bytes, [int start = 0, int? end]) {
    throw UnimplementedError();
  }

  @override
  int read(Buffer sink, int count) {
    throw UnimplementedError();
  }

  @override
  Uint8List readBytes([int? count]) {
    if (count != null && count > length) throw StateError('not enough');
    count = min(count ?? 0, length);
    bytesReceived -= count;
    return Uint8List(count);
  }

  @override
  double readFloat32([Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  double readFloat64([Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  int readInt16([Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  int readInt32([Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  int readInt64([Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  int readInt8() {
    throw UnimplementedError();
  }

  @override
  int readIntoBytes(List<int> sink, [int start = 0, int? end]) {
    throw UnimplementedError();
  }

  @override
  Future<int> readIntoSink(Sink sink) async {
    final count = length;
    if (count > 0) {
      final write = sink.write(this, count);
      if (write is Future<void>) await write;
    }
    return count;
  }

  @override
  String? readLine({Encoding encoding = utf8, int? newline}) {
    throw UnimplementedError();
  }

  @override
  String readLineStrict({Encoding encoding = utf8, int? end}) {
    throw UnimplementedError();
  }

  @override
  String readString({Encoding encoding = utf8, int? count}) {
    throw UnimplementedError();
  }

  @override
  int readUint16([Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  int readUint32([Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  int readUint64([Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  int readUint8() {
    throw UnimplementedError();
  }

  @override
  bool request(int count) {
    throw UnimplementedError();
  }

  @override
  void require(int count) {
    throw UnimplementedError();
  }

  @override
  (Segment, int)? seek(int index) {
    throw UnimplementedError();
  }

  @override
  void skip(int count) {
    throw UnimplementedError();
  }

  @override
  Segment writableSegment(int minimumCapacity) {
    throw UnimplementedError();
  }

  @override
  void write(Buffer source, int count) {
    throw UnimplementedError();
  }

  @override
  void writeCharCode(int charCode) {
    throw UnimplementedError();
  }

  @override
  void writeFloat32(double value, [Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  void writeFloat64(double value, [Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  void writeFromBytes(List<int> source, [int start = 0, int? end]) {
    throw UnimplementedError();
  }

  @override
  Future<int> writeFromSource(Source source) {
    throw UnimplementedError();
  }

  @override
  void writeInt16(int value, [Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  void writeInt32(int value, [Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  void writeInt64(int value, [Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  void writeInt8(int value) {
    throw UnimplementedError();
  }

  @override
  void writeLine([String string = '', Encoding encoding = utf8]) {
    throw UnimplementedError();
  }

  @override
  void writeString(String string, [Encoding encoding = utf8]) {
    throw UnimplementedError();
  }

  @override
  void writeUint16(int value, [Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  void writeUint32(int value, [Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  void writeUint64(int value, [Endian endian = Endian.big]) {
    throw UnimplementedError();
  }

  @override
  void writeUint8(int value) {
    throw UnimplementedError();
  }
}

FileEntry createEntry(
  Object entity, {
  String? name,
  Uint8List? password,
  CompressionMethod compressMethod = const CompressionStore(),
  EncryptionMethod encryptionMethod = const EncryptionNone(),
  bool forceZip64Format = false,
  DateTime? modifyTime,
  int? crc,
  int? length,
  String? comment,
}) {
  return FileEntry(
    entity,
    name: name,
    password: password,
    compressionMethod: compressMethod,
    encryptionMethod: encryptionMethod,
    forceZip64Format: forceZip64Format,
    modifyTime: modifyTime,
    crc: crc,
    length: length,
    comment: comment,
  );
}

Future<void> checkEntry(
  ZipFile zip,
  String name,
  bool isZip64Format,
  int crc,
  int length,
  DateTime modifyTime,
  String? comment, {
  Uint8List? data,
  Uint8List? password,
  Type compressMethodType = CompressionStore,
  Type encryptionMethodType = EncryptionNone,
}) async {
  final header = zip.getEntry(name)!;
  expect(header.isZip64Format, isZip64Format);
  expect(header.epochTime, modifyTime);
  expect(header.crc, crc);
  expect(header.uncompressedSize, length);
  expect(header.comment, comment);
  expect(header.compressionMethod.runtimeType, compressMethodType);
  expect(header.encryptionMethod.runtimeType, encryptionMethodType);
  if (data != null) expect(await zip.readBytes(header, password), data);
}

Future<void> checkZipFile(ZipFile zipFile, bool isSplitArchive,
    bool isZip64Format, String? comment) async {
  expect(zipFile.isSplitArchive, isSplitArchive);
  expect(zipFile.isZip64Format, isZip64Format);
  expect(zipFile.comment, comment);
}

extension ZipFileExtension on ZipFile {
  Future<String?> readString(
    FileHeader header, {
    Encoding encoding = utf8,
    Uint8List? password,
  }) {
    return getEntrySource(header, password)
        .buffered()
        .then((e) => e.readString(encoding: encoding));
  }

  Future<Uint8List?> readBytes(FileHeader header, [Uint8List? password]) {
    return getEntrySource(header, password)
        .buffered()
        .then((e) => e.readBytes());
  }
}
