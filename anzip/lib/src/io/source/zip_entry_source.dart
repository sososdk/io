import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anio/anio.dart';
import 'package:collection/collection.dart';

import '../../crypto/crc32.dart';
import '../../crypto/decrypter.dart';
import '../../model/compression_method.dart';
import '../../model/data_descriptor.dart';
import '../../model/encryption_method.dart';
import '../../model/file_header.dart';
import '../../model/local_file_header.dart';
import '../../zip_constants.dart';
import '../../zip_exception.dart';
import '../../zip_header_reader.dart';

part 'cipher_source.dart';
part 'decompress_source.dart';

Future<ZipEntrySource> createZipEntrySource(
  BufferedSource original,
  FileHeader fileHeader,
  Uint8List? password,
  Encoding? encoding,
) async {
  var header = await LocalFileHeaderReader(original, encoding).parse();
  if (header == null) {
    throw ZipException(
        'Could not read corresponding local file header for file header: ${fileHeader.name}');
  }
  if (fileHeader.name != header.name) {
    throw ZipException('File header and local file header mismatch');
  }
  header = header.copyWith(
    fileHeader.crc,
    fileHeader.compressedSize,
    fileHeader.uncompressedSize,
    header.zip64ExtendedInfo,
  );
  final source = original
      .limited(header.compressedSize - header.encryptionHeaderSize)
      .buffered();
  final cipherSource =
      await _CipherSource.create(original, source, header, password).buffered();
  final decompressSource = _DecompressSource.create(cipherSource, header);
  return ZipEntrySource(original, header, decompressSource);
}

class ZipEntrySource with ForwardingSource {
  ZipEntrySource(this.source, this.header, this.delegate);

  @override
  final Source delegate;
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
    if (header.useDataDescriptor) {
      final int crc, compressedSize, uncompressedSize;
      // According to zip specification, presence of extra data record header signature is optional.
      // If this signature is present, read it and read the next 4 bytes for crc
      // If signature not present, assign the read 4 bytes for crc
      if (await source.startsWithBytes(kExtsig)) {
        await source.skip(4);
        crc = await source.readUint32(Endian.little);
      } else {
        crc = await source.readUint32(Endian.little);
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

    if (header.aesExtraDataRecord?.aesVersion == AesVersion.two) {
      // Verification will be done in this case by AesCipherSource
      return;
    }
    if ((descriptor?.crc ?? header.crc) != _crc32.crc) {
      if (header.encryptionMethod case EncryptionZipCrypto()) {
        // password not match?
      }
      throw ZipException('Reached end of entry, but crc verification failed');
    }
  }
}
