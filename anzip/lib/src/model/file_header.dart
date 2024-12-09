import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:anio/anio.dart';

import '../bit_utils.dart';
import '../cp437.dart';
import '../zip_constants.dart';
import 'abstract_file_header.dart';
import 'compression_method.dart';
import 'zip_64_extended_info.dart';

class FileHeader extends AbstractFileHeader<Zip64ExtendedInfo> {
  const FileHeader(
    this.versionMadeBy,
    super.versionNeeded,
    super.generalPurposeFlag,
    super.compressionMethod,
    super.lastModifiedTime,
    super.crc,
    super.compressedSize,
    super.uncompressedSize,
    this._diskNumberStart,
    this.internalFileAttributes,
    this.externalFileAttributes,
    this._offsetLocalHeader,
    super.name,
    super.zip64ExtendedInfo,
    super.aesExtraDataRecord,
    this.comment,
  );

  @override
  int get signature => kCensig;

  final int versionMadeBy;
  final int _diskNumberStart;
  final List<int> internalFileAttributes;
  final List<int> externalFileAttributes;
  final int _offsetLocalHeader;
  final String? comment;

  int get diskNumberStart =>
      zip64ExtendedInfo?.diskNumberStart ?? _diskNumberStart;

  int get offsetLocalHeader =>
      zip64ExtendedInfo?.offsetLocalHeader ?? _offsetLocalHeader;

  @override
  bool get isDirectory {
    // first check if DOS attributes are set (lower order bytes from external attributes). If yes, check if the 4th bit
    // which represents a directory is set. If UNIX attributes are set (higher order two bytes), check for the 6th bit
    // in 4th byte which  represents a directory flag.
    if (isBitSet(externalFileAttributes[0], 4)) {
      return true;
    } else if (isBitSet(externalFileAttributes[3], 6)) {
      return true;
    }
    return super.isDirectory;
  }

  bool get isSymbolicLink => isBitSet(externalFileAttributes[3], 5);

  FileHeader copyWith(int offsetLocalHeader) {
    return FileHeader(
      versionMadeBy,
      versionNeeded,
      generalPurposeFlag,
      compressionMethod,
      dosTime,
      crc,
      compressedSize,
      uncompressedSize,
      _diskNumberStart,
      internalFileAttributes,
      externalFileAttributes,
      offsetLocalHeader,
      name,
      zip64ExtendedInfo,
      aesExtraDataRecord,
      comment,
    );
  }

  @override
  Future<void> write(BufferedSink sink, Encoding? encoding) async {
    await sink.writeUint32(signature, Endian.little);
    await sink.writeUint16(versionMadeBy, Endian.little);
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
    final commentRaw =
        comment == null ? null : (encoding ?? cp437).encode(comment!);
    final commentLength = commentRaw?.length ?? 0;
    await sink.writeUint16(commentLength, Endian.little);
    if (isZip64Format) {
      await sink.writeUint16(kZip64numlimit, Endian.little);
    } else {
      await sink.writeUint16(_diskNumberStart, Endian.little);
    }
    await sink.writeFromBytes(internalFileAttributes);
    await sink.writeFromBytes(externalFileAttributes);
    if (isZip64Format) {
      await sink.writeUint32(kZip64sizelimit, Endian.little);
    } else {
      await sink.writeUint32(_offsetLocalHeader, Endian.little);
    }
    await sink.writeFromBytes(nameRaw);
    await sink.writeFromSource(extraBuffer);
    // ignore extra data records
    if (commentRaw != null) {
      await sink.writeFromBytes(
          commentRaw, 0, min(commentLength, kMaxCommentSize));
    }
  }
}
