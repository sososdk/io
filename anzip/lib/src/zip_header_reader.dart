import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anio/anio.dart';

import 'bit_utils.dart';
import 'compression_method.dart';
import 'model/aes_extra_data_record.dart';
import 'model/aes_key_strength.dart';
import 'model/aes_version.dart';
import 'model/central_directory.dart';
import 'model/digital_signature.dart';
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
  return isBitSet(flag[1], 3) ? utf8 : encoding ?? latin1;
}

Future<String> _readFileName(
    BufferedSource source, int nameLength, Encoding encoding) async {
  if (nameLength > 0) {
    return source.readString(count: nameLength, encoding: encoding);
  } else {
    throw ZipException('Invalid entry name in file header');
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
    final header = await source.readUint16(Endian.little);
    final size = await source.readUint16(Endian.little);
    final data = await source.readBytes(size);
    count += 2 + 2 + size;
    yield ExtraDataRecord(header, size, data);
  }
  await source.skip(extraFieldLength - count);
}

Future<Zip64ExtendedInfo?> _readZip64ExtendedInfo(BufferedSource source,
    List<ExtraDataRecord> records, int compressedSize, int uncompressedSize,
    [int? diskNumberStart, int? offsetLocalHeader]) async {
  for (final record in records) {
    if (record.header == zip64extsig) {
      if (record.size == 0) return null;
      int count = 0;
      final buffer = Buffer()..writeFromBytes(Uint8List.fromList(record.data));
      int? newUncompressedSize;
      if (count < record.size && uncompressedSize == zip64sizelimit) {
        newUncompressedSize = buffer.readUint64(Endian.little);
        count += 8;
      }
      int? newCompressedSize;
      if (count < record.size && compressedSize == zip64sizelimit) {
        newCompressedSize = buffer.readUint64(Endian.little);
        count += 8;
      }
      int? newOffsetLocalHeader;
      if (count < record.size && offsetLocalHeader == zip64sizelimit) {
        newOffsetLocalHeader = buffer.readUint64(Endian.little);
        count += 8;
      }
      int? newDiskNumberStart;
      if (count < record.size && diskNumberStart == zip64numlimit) {
        newDiskNumberStart = buffer.readUint32(Endian.little);
      }
      return Zip64ExtendedInfo(newCompressedSize, newUncompressedSize,
          newOffsetLocalHeader, newDiskNumberStart);
    }
  }
  return null;
}

Future<AESExtraDataRecord?> _readAesExtraDataRecord(
    BufferedSource source, List<ExtraDataRecord> records) async {
  for (final record in records) {
    if (record.header == aesextdatarec) {
      if (record.size != 7) {
        throw ZipException('corrupt AES extra data records');
      }
      final buffer = Buffer()..writeFromBytes(Uint8List.fromList(record.data));
      final aesVersion =
          AesVersion.fromVersionNumber(buffer.readUint16(Endian.little));
      final vendorID = buffer.readString(count: 2);
      final aesKeyStrength = AesKeyStrength.fromRawCode(buffer.readUint8());
      final compressionMethod =
          CompressionMethod.fromCode(buffer.readUint16(Endian.little));
      return AESExtraDataRecord(
          record.size, aesVersion, vendorID, aesKeyStrength, compressionMethod);
    }
  }
  return null;
}

class FileHeaderReader {
  const FileHeaderReader(this._handle, [this._encoding = utf8]);

  final FileHandle _handle;
  final Encoding _encoding;

  Future<ZipModel> parse() async {
    final length = await _handle.length();
    if (length < endhdr) {
      throw ZipException(
          'Zip file size less than size of zip headers. Probably not a zip file.');
    }

    final eocdrec = await _readEndOfCentralDirectoryRecord();
    Zip64EndOfCentralDirectoryLocator? zip64eocdloc;
    Zip64EndOfCentralDirectoryRecord? zip64eocdrec;
    CentralDirectory? centralDirectory;
    if (eocdrec.totalNumberOfEntriesInCentralDirectory == 0) {
      // no entries
    } else {
      // If file is Zip64 format, Zip64 headers have to be read before reading central directory
      zip64eocdloc = await _readZip64EndOfCentralDirectoryLocator(
          eocdrec.offsetEndOfCentralDirectory);
      if (zip64eocdloc != null) {
        zip64eocdrec = await _readZip64EndCentralDirectoryRecord(zip64eocdloc);
      }
      final int offsetStartOfCentralDirectory;
      final int numberOfEntriesInCentralDirectory;
      if (zip64eocdrec != null) {
        offsetStartOfCentralDirectory =
            zip64eocdrec.offsetStartCentralDirectoryWRTStartDiskNumber;
        numberOfEntriesInCentralDirectory =
            zip64eocdrec.totalNumberOfEntriesInCentralDirectory;
      } else {
        offsetStartOfCentralDirectory = eocdrec.offsetStartOfCentralDirectory;
        numberOfEntriesInCentralDirectory =
            eocdrec.totalNumberOfEntriesInCentralDirectory;
      }
      centralDirectory = await _readCentralDirectory(
          offsetStartOfCentralDirectory, numberOfEntriesInCentralDirectory);
    }
    return ZipModel(eocdrec, zip64eocdloc, zip64eocdrec, centralDirectory);
  }

  Future<EndOfCentralDirectoryRecord> _readEndOfCentralDirectoryRecord() async {
    final offset = await _locateOffsetOfEndOfCentralDirectory();
    return _handle.source(offset + 4).buffered().use((e) async {
      return EndOfCentralDirectoryRecord(
        await e.readUint16(Endian.little),
        await e.readUint16(Endian.little),
        await e.readUint16(Endian.little),
        await e.readUint16(Endian.little),
        await e.readUint32(Endian.little),
        await e.readUint32(Endian.little),
        offset,
        await () async {
          final length = await e.readUint16(Endian.little);
          if (length == 0) return null;
          try {
            return await e.readString(count: length);
          } catch (_) {
            // Ignore any exception and set comment to null if comment cannot be read
            return null;
          }
        }(),
      );
    });
  }

  Future<int> _locateOffsetOfEndOfCentralDirectory() async {
    final length = await _handle.length();
    final sig = await _handle
        .source(length - endhdr)
        .buffered()
        .use((e) => e.readInt32(Endian.little));
    if (sig == endsig) {
      return length - endhdr;
    } else {
      var currentFilePointer = length - endhdr;
      var numberOfBytesToRead =
          length < maxCommentSize ? length : maxCommentSize;
      while (numberOfBytesToRead > 0 && currentFilePointer > 0) {
        final sig = await _handle
            .source(--currentFilePointer)
            .buffered()
            .use((e) => e.readInt32(Endian.little));
        if (sig == endsig) {
          return currentFilePointer;
        }
        numberOfBytesToRead--;
      }
      throw ZipException('Zip headers not found. Probably not a zip file');
    }
  }

  Future<Zip64EndOfCentralDirectoryLocator?>
      _readZip64EndOfCentralDirectoryLocator(int offsetEndOfCentralDirectory) {
    // Now the file pointer is at the end of signature of Central Dir Rec
    // Seek back with the following values
    // 4 -> total number of disks
    // 8 -> relative offset of the zip64 end of central directory record
    // 4 -> number of the disk with the start of the zip64 end of central directory
    // 4 -> zip64 end of central dir locator signature
    // Refer to Appnote for more information
    return _handle
        .source(offsetEndOfCentralDirectory - 4 - 8 - 4 - 4)
        .buffered()
        .use((closable) async {
      final sig = await closable.readUint32(Endian.little);
      if (sig == zip64endsig) {
        final number = await closable.readUint32(Endian.little);
        final offset = await closable.readUint64(Endian.little);
        final total = await closable.readUint32(Endian.little);
        return Zip64EndOfCentralDirectoryLocator(number, offset, total);
      } else {
        return null;
      }
    });
  }

  Future<void> close() => _handle.close();

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
  Future<Zip64EndOfCentralDirectoryRecord> _readZip64EndCentralDirectoryRecord(
      Zip64EndOfCentralDirectoryLocator eocdloc) async {
    final offsetStartOfZip64CentralDirectory =
        eocdloc.offsetZip64EndOfCentralDirectoryRecord;
    return _handle
        .source(offsetStartOfZip64CentralDirectory)
        .buffered()
        .use((closable) async {
      final sig = await closable.readUint32(Endian.little);
      if (sig == zip64censig) {
        final sizeOfZip64EndCentralDirectoryRecord =
            await closable.readUint64(Endian.little);
        return Zip64EndOfCentralDirectoryRecord(
          sizeOfZip64EndCentralDirectoryRecord,
          await closable.readUint16(Endian.little),
          await closable.readUint16(Endian.little),
          await closable.readUint32(Endian.little),
          await closable.readUint32(Endian.little),
          await closable.readUint64(Endian.little),
          await closable.readUint64(Endian.little),
          await closable.readUint64(Endian.little),
          await closable.readUint64(Endian.little),
          await () async {
            // zip64 extensible data sector
            // 44 is the size of fixed variables in this record
            // not needed for now!!!

            // final size = sizeOfZip64EndCentralDirectoryRecord -44;
            // if (size > 0) {
            //   return await closable.readBytes(size);
            // }
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
      int offsetStartOfCentralDirectory,
      int numberOfEntriesInCentralDirectory) async {
    return _handle
        .source(offsetStartOfCentralDirectory)
        .buffered()
        .use((closable) async {
      final headers = <FileHeader>[];
      for (var i = 0; i < numberOfEntriesInCentralDirectory; i++) {
        final sig = await closable.readUint32(Endian.little);
        if (sig != censig) {
          throw ZipException(
              'Expected central directory entry not found (#${i + 1})');
        }
        final Uint8List generalPurposeFlag;
        final int compressedSize, uncompressedSize, diskNumberStart;
        final int offsetLocalHeader;
        final int fileNameLength, extraFieldLength, fileCommentLength;
        final List<ExtraDataRecord> extraDataRecords;

        final header = FileHeader(
          // versionMadeBy
          await closable.readUint16(Endian.little),
          // versionNeededToExtract
          await closable.readUint16(Endian.little),
          // generalPurposeFlag
          generalPurposeFlag = await closable.readBytes(2),
          // compressionMethod
          CompressionMethod.fromCode(await closable.readUint16(Endian.little)),
          // lastModifiedTime
          await closable.readUint32(Endian.little),
          // crc
          await closable.readUint32(Endian.little),
          // compressedSize
          compressedSize = await closable.readUint32(Endian.little),
          // uncompressedSize
          uncompressedSize = await closable.readUint32(Endian.little),
          // fileNameLength
          fileNameLength = await closable.readUint16(Endian.little),
          // extraFieldLength
          extraFieldLength = await closable.readUint16(Endian.little),
          // fileCommentLength
          fileCommentLength = await closable.readUint16(Endian.little),
          // diskNumberStart
          diskNumberStart = await closable.readUint16(Endian.little),
          // internalFileAttributes
          await closable.readBytes(2),
          // externalFileAttributes
          await closable.readBytes(4),
          // offsetLocalHeader
          offsetLocalHeader = await closable.readUint32(Endian.little),
          // fileName
          await _readFileName(closable, fileNameLength,
              _getEncoding(generalPurposeFlag, _encoding)),
          // extraDataRecords
          extraDataRecords =
              await _readExtraDataRecords(closable, extraFieldLength).toList(),
          // zip64ExtendedInfo
          await _readZip64ExtendedInfo(
              closable,
              extraDataRecords,
              compressedSize,
              uncompressedSize,
              diskNumberStart,
              offsetLocalHeader),
          // aesExtraDataRecord
          await _readAesExtraDataRecord(closable, extraDataRecords),
          // fileComment
          await () {
            if (fileCommentLength > 0) {
              return closable.readString(
                  count: fileCommentLength,
                  encoding: _getEncoding(generalPurposeFlag, _encoding));
            }
            return null;
          }(),
        );
        headers.add(header);
      }

      // read digital signature
      final sig = await closable.readUint32(Endian.little);
      int? digsigSize;
      String? digsigSignatureData;
      if (sig == digsig) {
        digsigSize = await closable.readUint16(Endian.little);
        if (digsigSize > 0) {
          digsigSignatureData = await closable.readString(count: digsigSize);
        }
      }
      final signature = DigitalSignature(digsigSize, digsigSignatureData);
      return CentralDirectory(headers, signature);
    });
  }
}

class LocalFileHeaderReader {
  LocalFileHeaderReader(this._source, [this._encoding = utf8]);

  final BufferedSource _source;
  final Encoding _encoding;

  Future<LocalFileHeader?> parse() async {
    var sig = await _source.readUint32(Endian.little);
    if (sig == temspmaker) {
      sig = await _source.readUint32(Endian.little);
    }
    if (sig != locsig) return null;
    final Uint8List generalPurposeFlag;
    final int compressedSize, uncompressedSize;
    final int fileNameLength, extraFieldLength;
    final List<ExtraDataRecord> extraDataRecords;
    return LocalFileHeader(
      // versionNeededToExtract
      await _source.readInt16(Endian.little),
      // generalPurposeFlag
      generalPurposeFlag = await () async {
        final flag = await _source.readBytes(2);
        if (flag.length != 2) {
          throw ZipException(
              'Could not read enough bytes for generalPurposeFlags');
        }
        return flag;
      }(),
      // compressionMethod
      CompressionMethod.fromCode(await _source.readUint16(Endian.little)),
      // lastModifiedTime
      await _source.readUint32(Endian.little),
      // crc
      await _source.readUint32(Endian.little),
      // compressedSize
      compressedSize = await _source.readUint32(Endian.little),
      // uncompressedSize
      uncompressedSize = await _source.readUint32(Endian.little),
      // fileNameLength
      fileNameLength = await _source.readUint16(Endian.little),
      // extraFieldLength
      extraFieldLength = await _source.readUint16(Endian.little),
      // fileName
      await _readFileName(
          _source, fileNameLength, _getEncoding(generalPurposeFlag, _encoding)),
      // extraDataRecords
      extraDataRecords =
          await _readExtraDataRecords(_source, extraFieldLength).toList(),
      // zip64ExtendedInfo
      await _readZip64ExtendedInfo(
          _source, extraDataRecords, compressedSize, uncompressedSize),
      // aesExtraDataRecord
      await _readAesExtraDataRecord(_source, extraDataRecords),
    );
  }
}
