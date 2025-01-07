import 'dart:convert';
import 'dart:typed_data';

import 'package:anio/anio.dart';

import '../cp437.dart';
import '../zip_constants.dart';
import 'abstract_file_header.dart';
import 'compression_method.dart';
import 'zip_64_extended_info.dart';

/// Used to read zip Entry directly in sequence without reading zip Central Directory.
class LocalFileHeader extends AbstractFileHeader<LocalZip64ExtendedInfo> {
  const LocalFileHeader(
    super.versionNeeded,
    super.generalPurposeFlag,
    super.compressionMethod,
    super.lastModifiedTime,
    super.crc,
    super.compressedSize,
    super.uncompressedSize,
    super.name,
    super.zip64ExtendedInfo,
    super.aesExtraDataRecord,
  );

  LocalFileHeader copyWith(
    int crc,
    int compressedSize,
    int uncompressedSize,
    LocalZip64ExtendedInfo? zip64ExtendedInfo,
  ) {
    return LocalFileHeader(
      versionNeeded,
      generalPurposeFlag,
      compressionMethod,
      dosTime,
      crc,
      compressedSize,
      uncompressedSize,
      name,
      zip64ExtendedInfo,
      aesExtraDataRecord,
    );
  }

  @override
  List<int> get signature => kLocsig;

  @override
  Future<void> write(BufferedSink sink, Encoding? encoding) async {
    await sink.writeFromBytes(signature);
    await sink.writeUint16(versionNeeded, Endian.little);
    await sink.writeFromBytes(generalPurposeFlag);
    final compressionMethod = aesExtraDataRecord == null
        ? this.compressionMethod
        : const CompressionAes();
    await sink.writeUint16(compressionMethod.code, Endian.little);
    await sink.writeUint32(dosTime, Endian.little);
    await sink.writeUint32(crc, Endian.little);
    if (isZip64Format) {
      await sink.writeUint32(kZip64sizelimit, Endian.little);
      await sink.writeUint32(kZip64sizelimit, Endian.little);
    } else {
      await sink.writeUint32(compressedSize, Endian.little);
      await sink.writeUint32(uncompressedSize, Endian.little);
    }
    final nameRaw = (encoding ?? cp437).encode(name);
    final nameLength = nameRaw.length;
    if (nameLength > kMaxFilenameSize) throw StateError('Filename is too long');
    await sink.writeUint16(nameLength, Endian.little);
    final extraBuffer = Buffer();
    await zip64ExtendedInfo?.write(extraBuffer);
    await aesExtraDataRecord?.write(extraBuffer, this.compressionMethod);
    await sink.writeUint16(extraBuffer.length, Endian.little);
    await sink.writeFromBytes(nameRaw);
    await sink.writeFromSource(extraBuffer);
  }
}
