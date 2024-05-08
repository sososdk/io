import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:anio/anio.dart';
import 'package:collection/collection.dart';

import '../compression_method.dart';
import '../crypto/crc32.dart';
import '../crypto/decrypter.dart';
import '../encryption_method.dart';
import '../model/aes_version.dart';
import '../model/data_descriptor.dart';
import '../model/local_file_header.dart';
import '../zip_constants.dart';
import '../zip_exception.dart';

part 'cipher_source.dart';
part 'decompress_source.dart';

FutureOr<Source> createZipEntrySource(
  BufferedSource source,
  LocalFileHeader header,
  String? password,
) async {
  final entrySource = _ZipEntrySource(source, header);
  final cipherSource =
      await _CipherSource.create(source, entrySource, header, password);
  final decompressSource = _DecompressSource.create(cipherSource, header);
  return _CrcCheckSource(source, header, decompressSource);
}

class _CrcCheckSource extends ForwardingSource {
  _CrcCheckSource(this.source, this.header, super.delegate);

  final BufferedSource source;
  final LocalFileHeader header;

  final _crc32 = Crc32();

  bool _verified = false;

  @override
  Future<int> read(Buffer sink, int count) async {
    final buffer = Buffer();
    final result = await super.read(buffer, count);
    if (buffer.isNotEmpty) {
      final bytes = buffer.readBytes();
      _crc32.update(bytes);
      sink.writeFromBytes(bytes);
    } else {
      await _verify();
    }
    return result;
  }

  Future<void> _verify() async {
    if (_verified) return;
    _verified = true;
    DataDescriptor? descriptor;
    if (header.dataDescriptorExists && !header.extendedDataUpdated) {
      final sigOrCrc = await source.readUint32(Endian.little);
      final int crc, compressedSize, uncompressedSize;
      //According to zip specification, presence of extra data record header signature is optional.
      //If this signature is present, read it and read the next 4 bytes for crc
      //If signature not present, assign the read 4 bytes for crc
      if (sigOrCrc == extsig) {
        crc = await source.readUint32(Endian.little);
      } else {
        crc = sigOrCrc;
      }
      if (header.isZip64Format) {
        compressedSize = await source.readUint64(Endian.little);
        uncompressedSize = await source.readUint64(Endian.little);
      } else {
        compressedSize = await source.readUint32(Endian.little);
        uncompressedSize = await source.readUint32(Endian.little);
      }
      descriptor = DataDescriptor(crc, compressedSize, uncompressedSize);
    }

    if (header.encryptionMethod == EncryptionMethod.aes &&
        header.aesExtraDataRecord?.aesVersion == AesVersion.two) {
      // Verification will be done in this case by AesCipherSource
      return;
    }
    if ((descriptor?.crc ?? header.crc) != _crc32.crc) {
      if (header.encryptionMethod == EncryptionMethod.standard) {
        // password not match?
      }
      throw ZipException('Reached end of entry, but crc verification failed');
    }
  }
}

class _ZipEntrySource implements Source {
  _ZipEntrySource(this.source, this.header);

  final BufferedSource source;
  final LocalFileHeader header;

  final crc32 = Crc32();

  int get length => header.compressedSize - header.encryptionHeaderSize;

  int bytesReceived = 0;

  @override
  FutureOr<int> read(Buffer sink, int count) async {
    if (bytesReceived >= length) return 0;

    count = min(count, length - bytesReceived);
    final result = await source.read(sink, count);
    bytesReceived += result;
    return result;
  }

  @override
  FutureOr<void> close() => source.close();
}
