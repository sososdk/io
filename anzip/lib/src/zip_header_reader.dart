import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:anio/anio.dart';
import 'package:collection/collection.dart';
import 'package:file_system/file_system.dart';

import 'bit_utils.dart';
import 'cp437.dart';
import 'model/aes_extra_data_record.dart';
import 'model/central_directory.dart';
import 'model/compression_method.dart';
import 'model/digital_signature.dart';
import 'model/encryption_method.dart';
import 'model/end_of_central_directory_record.dart';
import 'model/extra_data_record.dart';
import 'model/file_header.dart';
import 'model/local_file_header.dart';
import 'model/zip_64_end_of_central_directory_locator.dart';
import 'model/zip_64_end_of_central_directory_record.dart';
import 'model/zip_64_extended_info.dart';
import 'model/zip_model.dart';
import 'zip_constants.dart';
import 'zip_exception.dart';

Encoding _getEncoding(Uint8List flag, Encoding? encoding) {
  return isBitSet(flag[1], 3) ? utf8 : (encoding ?? cp437);
}

Future<String> _readString(
    BufferedSource source, int length, Encoding encoding) async {
  final bytes = await source.readBytes(length);
  try {
    return encoding.decode(bytes);
  } catch (_) {
    return String.fromCharCodes(bytes);
  }
}

Stream<ExtraDataRecord> _readExtraDataRecords(
    BufferedSource source, int extraFieldLength) async* {
  if (extraFieldLength == 0) return;
  if (extraFieldLength < 4) {
    await source.skip(extraFieldLength);
    return;
  }
  int count = 0;
  while (count < extraFieldLength) {
    final signature = await source.readBytes(2);
    final size = await source.readUint16(Endian.little);
    final data = await source.readBytes(size);
    count += 2 + 2 + size;
    yield ExtraDataRecord(signature, data);
  }
  await source.skip(extraFieldLength - count);
}

(AesExtraDataRecord, CompressionMethod)? _readAesExtraDataRecord(
    List<ExtraDataRecord> records) {
  for (final record in records) {
    if (const ListEquality().equals(record.signature, kAesextdatarec)) {
      if (record.data.length != 7) {
        throw ZipException('corrupt AES extra data records');
      }
      final buffer = Buffer.fromBytes(record.data);
      final aesVersion =
          AesVersion.fromVersionNumber(buffer.readUint16(Endian.little));
      final vendorID = buffer.readString(count: 2, encoding: cp437);
      final aesKeyStrength = AesKeyStrength.fromRawCode(buffer.readUint8());
      final compressionMethod =
          CompressionMethod.fromCode(buffer.readUint16(Endian.little));
      return (
        AesExtraDataRecord(aesVersion, vendorID, aesKeyStrength),
        compressionMethod
      );
    }
  }
  return null;
}

class FileHeaderReader {
  FileHeaderReader(this._file, [this._encoding]);

  final File _file;
  final Encoding? _encoding;

  Future<ZipModel> parse() async {
    final length = await _file.length();
    if (length < kEndhdr) {
      throw ZipException(
          'Zip file size less than size of zip headers. Probably not a zip file.');
    }
    return _file.openHandle().use((handle) async {
      final offset = await _findEocd(handle, length);
      final eocdrec = await _readEocdrec(handle, offset);
      // If file is Zip64 format, Zip64 headers have to be read before reading central directory
      final zip64eocdloc = await _readZip64Eocdloc(handle, offset);
      Zip64EndOfCentralDirectoryRecord? zip64eocdrec;
      if (zip64eocdloc != null) {
        zip64eocdrec = await _readZip64Eocdrec(handle, zip64eocdloc);
      }
      final centralDir =
          await _readCentralDirectory(handle, eocdrec, zip64eocdrec);
      return ZipModel(centralDir, zip64eocdrec, zip64eocdloc, eocdrec);
    });
  }

  Future<EndOfCentralDirectoryRecord> _readEocdrec(
      FileHandle handle, int offset) {
    return handle.source(offset + 4).buffered().use((source) async {
      return EndOfCentralDirectoryRecord(
        await source.readUint16(Endian.little),
        await source.readUint16(Endian.little),
        await source.readUint16(Endian.little),
        await source.readUint16(Endian.little),
        await source.readUint32(Endian.little),
        await source.readUint32(Endian.little),
        await () async {
          final length = await source.readUint16(Endian.little);
          if (length == 0) return null;
          return await _readString(source, length, _encoding ?? cp437);
        }(),
      );
    });
  }

  Future<int> _findEocd(FileHandle handle, int length) async {
    // Scan backwards from the end of the file looking for the END_OF_CENTRAL_DIRECTORY_SIGNATURE.
    // If this file has no comment we'll see it on the first attempt; otherwise we have to go
    // backwards byte-by-byte until we reach it. (The number of bytes scanned will equal the comment
    // size).
    var scanOffset = length - kEndhdr;
    if (scanOffset < 0) throw ZipException('not a zip: size=$length');
    final stopOffset = max(scanOffset - 65536, 0);
    while (true) {
      if (await handle
          .source(scanOffset)
          .buffered()
          .use((e) => e.startsWithBytes(kEndsig))) return scanOffset;

      scanOffset--;
      if (scanOffset < stopOffset) {
        throw ZipException(
            'not a zip: end of central directory signature not found');
      }
    }
  }

  Future<Zip64EndOfCentralDirectoryLocator?> _readZip64Eocdloc(
      FileHandle handle, int offset) {
    // Now the file pointer is at the end of signature of Central Dir Rec
    // Seek back with the following values
    // 4 -> total number of disks
    // 8 -> relative offset of the zip64 end of central directory record
    // 4 -> number of the disk with the start of the zip64 end of central directory
    // 4 -> zip64 end of central dir locator signature
    // Refer to Appnote for more information
    offset -= (4 + 8 + 4 + 4);
    if (offset <= 0) return Future.value();
    return handle.source(offset).buffered().use((source) async {
      if (await source.startsWithBytes(kZip64endsig)) {
        await source.skip(4);
        final number = await source.readUint32(Endian.little);
        final offset = await source.readUint64(Endian.little);
        final total = await source.readUint32(Endian.little);
        return Zip64EndOfCentralDirectoryLocator(number, offset, total);
      } else {
        return null;
      }
    });
  }

  // Zip64 end of central directory record
  // signature                       4 bytes  (0x06064b50)
  // size of zip64 end of central
  // directory record                8 bytes
  // version made by                 2 bytes
  // version needed to extract       2 bytes
  // number of this disk             4 bytes
  // number of the disk with the
  // start of the central directory  4 bytes
  // total number of entries in the
  // central directory on this disk  8 bytes
  // total number of entries in the
  // central directory               8 bytes
  // size of the central directory   8 bytes
  // offset of start of central
  // directory with respect to
  // the starting disk number        8 bytes
  // zip64 extensible data sector    (variable size)
  Future<Zip64EndOfCentralDirectoryRecord> _readZip64Eocdrec(
      FileHandle handle, Zip64EndOfCentralDirectoryLocator eocdloc) async {
    return handle
        .source(eocdloc.offsetZip64EndOfCentralDirectoryRecord)
        .buffered()
        .use((source) async {
      if (await source.startsWithBytes(kZip64censig)) {
        await source.skip(4);
        // size of Zip64 EndCentralDirectoryRecord
        final size = await source.readUint64(Endian.little);
        return Zip64EndOfCentralDirectoryRecord(
          await source.readUint16(Endian.little),
          await source.readUint16(Endian.little),
          await source.readUint32(Endian.little),
          await source.readUint32(Endian.little),
          await source.readUint64(Endian.little),
          await source.readUint64(Endian.little),
          await source.readUint64(Endian.little),
          await source.readUint64(Endian.little),
          await () async {
            // zip64 extensible data sector
            // 44 is the size of fixed variables in this record
            if (size - 44 > 0) {
              return await source.readBytes(size - 44);
            }
            return const <int>[];
          }(),
        );
      } else {
        throw ZipException(
            'invalid signature for zip64 end of central directory record');
      }
    });
  }

  Future<CentralDirectory> _readCentralDirectory(
      FileHandle handle,
      EndOfCentralDirectoryRecord eocdrec,
      Zip64EndOfCentralDirectoryRecord? zip64eocdrec) async {
    final offset = zip64eocdrec?.offsetOfCentralDirectory ??
        eocdrec.offsetOfCentralDirectory;
    final number = zip64eocdrec?.totalNumberOfEntriesInCentralDirectory ??
        eocdrec.totalNumberOfEntriesInCentralDirectory;
    return handle.source(offset).buffered().use((source) async {
      final headers = <FileHeader>[];
      for (var i = 0; i < number; i++) {
        if (!await source.startsWithBytes(kCensig)) {
          throw ZipException(
              'Expected central directory entry not found (#${i + 1})');
        }
        await source.skip(4);
        final versionMadeBy = await source.readUint16(Endian.little);
        final versionNeeded = await source.readUint16(Endian.little);
        final generalPurposeFlag = await source.readBytes(2);
        final compressionMethod =
            CompressionMethod.fromCode(await source.readUint16(Endian.little));
        final lastModifiedTime = await source.readUint32(Endian.little);
        final crc = await source.readUint32(Endian.little);
        final compressedSize = await source.readUint32(Endian.little);
        final uncompressedSize = await source.readUint32(Endian.little);
        final fileNameLength = await source.readUint16(Endian.little);
        final extraFieldLength = await source.readUint16(Endian.little);
        final fileCommentLength = await source.readUint16(Endian.little);
        final diskNumberStart = await source.readUint16(Endian.little);
        final internalFileAttributes = await source.readBytes(2);
        final externalFileAttributes = await source.readBytes(4);
        final offsetLocalHeader = await source.readUint32(Endian.little);
        final fileName = await () async {
          if (fileNameLength > 0) {
            return _readString(source, fileNameLength,
                _getEncoding(generalPurposeFlag, _encoding));
          } else {
            throw ZipException('Invalid entry name in file header');
          }
        }();
        final extraDataRecords =
            await _readExtraDataRecords(source, extraFieldLength).toList();
        Zip64ExtendedInfo? zip64ExtendedInfo;
        for (final record in extraDataRecords) {
          if (const ListEquality().equals(record.signature, kZip64extsig)) {
            final buffer = Buffer.fromBytes(record.data);
            final $uncompressedSize =
                buffer.request(8) && uncompressedSize == kZip64sizelimit
                    ? buffer.readUint64(Endian.little)
                    : null;
            final $compressedSize =
                buffer.request(8) && compressedSize == kZip64sizelimit
                    ? buffer.readUint64(Endian.little)
                    : null;
            final $offsetLocalHeader =
                buffer.request(8) && offsetLocalHeader == kZip64sizelimit
                    ? buffer.readUint64(Endian.little)
                    : null;
            final $diskNumberStart =
                buffer.request(4) && diskNumberStart == kZip64numlimit
                    ? buffer.readUint32(Endian.little)
                    : null;
            zip64ExtendedInfo = Zip64ExtendedInfo(
              $compressedSize,
              $uncompressedSize,
              $offsetLocalHeader,
              $diskNumberStart,
            );
            break;
          }
        }
        final aesData = _readAesExtraDataRecord(extraDataRecords);
        final fileComment = await () {
          if (fileCommentLength > 0) {
            return _readString(source, fileCommentLength,
                _getEncoding(generalPurposeFlag, _encoding));
          }
          return null;
        }();
        final header = FileHeader(
          versionMadeBy,
          versionNeeded,
          generalPurposeFlag,
          aesData?.$2 ?? compressionMethod,
          lastModifiedTime,
          crc,
          compressedSize,
          uncompressedSize,
          diskNumberStart,
          internalFileAttributes,
          externalFileAttributes,
          offsetLocalHeader,
          fileName,
          zip64ExtendedInfo,
          aesData?.$1,
          fileComment,
        );
        headers.add(header);
      }

      // read digital signature
      DigitalSignature? signature;
      if (await source.startsWithBytes(kDigsig)) {
        await source.skip(4);
        final size = await source.readUint16(Endian.little);
        final signatureData = await source.readBytes(size);
        signature = DigitalSignature(signatureData);
      }
      return CentralDirectory(headers, signature);
    });
  }
}

class LocalFileHeaderReader {
  LocalFileHeaderReader(this.source, [this.encoding]);

  final BufferedSource source;
  final Encoding? encoding;

  Future<LocalFileHeader?> parse() async {
    if (await source.startsWithBytes(kTemspmaker)) await source.skip(4);
    if (!await source.startsWithBytes(kLocsig)) return null;
    await source.skip(4);
    final versionNeeded = await source.readInt16(Endian.little);
    final generalPurposeFlag = await () async {
      final flag = await source.readBytes(2);
      if (flag.length != 2) {
        throw ZipException(
            'Could not read enough bytes for generalPurposeFlags');
      }
      return flag;
    }();
    final compressionMethod =
        CompressionMethod.fromCode(await source.readUint16(Endian.little));
    final lastModifiedTime = await source.readUint32(Endian.little);
    final crc = await source.readUint32(Endian.little);
    final compressedSize = await source.readUint32(Endian.little);
    final uncompressedSize = await source.readUint32(Endian.little);
    final fileNameLength = await source.readUint16(Endian.little);
    final extraFieldLength = await source.readUint16(Endian.little);
    final fileName = await () async {
      if (fileNameLength > 0) {
        final encoding = _getEncoding(generalPurposeFlag, this.encoding);
        return _readString(source, fileNameLength, encoding);
      } else {
        throw ZipException('Invalid entry name in local file header');
      }
    }();
    final extraDataRecords =
        await _readExtraDataRecords(source, extraFieldLength).toList();
    LocalZip64ExtendedInfo? zip64ExtendedInfo;
    for (final record in extraDataRecords) {
      if (const ListEquality().equals(record.signature, kZip64extsig)) {
        final buffer = Buffer.fromBytes(record.data);
        zip64ExtendedInfo = LocalZip64ExtendedInfo(
          buffer.readUint64(Endian.little),
          buffer.readUint64(Endian.little),
        );
        break;
      }
    }
    final aesData = _readAesExtraDataRecord(extraDataRecords);
    return LocalFileHeader(
      versionNeeded,
      generalPurposeFlag,
      aesData?.$2 ?? compressionMethod,
      lastModifiedTime,
      crc,
      compressedSize,
      uncompressedSize,
      fileName,
      zip64ExtendedInfo,
      aesData?.$1,
    );
  }
}
