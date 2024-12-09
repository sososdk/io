import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:anio/anio.dart';

import '../anzip.dart';
import 'io/sink/zip_entry_sink.dart';
import 'io/sink/zip_file_sink.dart';
import 'model/central_directory.dart';
import 'model/data_descriptor.dart';
import 'model/end_of_central_directory_record.dart';
import 'model/local_file_header.dart';
import 'model/zip_64_end_of_central_directory_locator.dart';
import 'model/zip_64_end_of_central_directory_record.dart';
import 'model/zip_64_extended_info.dart';
import 'model/zip_model.dart';
import 'zip_constants.dart';
import 'zip_utils.dart';

Future<FileHeader> writeEntry(ZipFileSink fileSink, FileEntry entry,
    int versionMadeBy, Encoding? encoding) async {
  final sink = fileSink.buffered();
  // write local file header
  final diskNumberStart = fileSink.index();
  final offsetLocalHeader = await fileSink.position();
  final versionNeeded = await determineVersionNeeded(entry);
  final generalPurposeFlag = determineGeneralPurposeBitFlag(entry, encoding);
  final isZip64Format = await entry.isZip64Format();
  var header = LocalFileHeader(
    versionNeeded,
    generalPurposeFlag,
    entry.compressionMethod,
    await entry.dosTime(),
    await entry.maybeCrc(),
    0,
    0,
    entry.name,
    isZip64Format ? LocalZip64ExtendedInfo(0, 0) : null,
    entry.aesExtraDataRecord(),
  );
  await header.write(sink, encoding);
  var crc = 0;
  var compressedSize = 0;
  var uncompressedSize = 0;
  // write data (The actual data of the file, which may or may not be compressed)
  final entrySink = await createZipEntrySink(sink, header, entry.password);
  await entry.write(entrySink, encoding);
  await entrySink.close();
  crc = entrySink.crc;
  compressedSize = entrySink.compressedSize;
  uncompressedSize = entrySink.uncompressedSize;
  if (!isZip64Format && compressedSize > kZip64sizelimit) {
    throw ZipException('Poor compression resulted in unexpectedly large entry');
  }
  if (header.useDataDescriptor) {
    final descriptor = DataDescriptor(crc, compressedSize, uncompressedSize);
    await descriptor.write(sink, isZip64Format);
  }
  // update header
  header = header.copyWith(
    crc,
    compressedSize,
    uncompressedSize,
    isZip64Format
        ? LocalZip64ExtendedInfo(compressedSize, uncompressedSize)
        : null,
  );
  await sink.emit();
  final temp = Buffer();
  await header.write(temp, encoding);
  await fileSink.update(diskNumberStart, offsetLocalHeader, temp, temp.length);
  // add file header
  final zip64ExtendedInfo = isZip64Format
      ? Zip64ExtendedInfo(
          header.zip64ExtendedInfo!.compressedSize,
          header.zip64ExtendedInfo!.uncompressedSize,
          offsetLocalHeader,
          diskNumberStart,
        )
      : null;
  return FileHeader(
    versionMadeBy,
    versionNeeded,
    generalPurposeFlag,
    header.compressionMethod,
    header.dosTime,
    header.crc,
    header.compressedSize,
    header.uncompressedSize,
    diskNumberStart,
    [0, 0],
    entry.attributes,
    offsetLocalHeader,
    header.name,
    zip64ExtendedInfo,
    header.aesExtraDataRecord,
    entry.comment,
  );
}

Future<ZipModel> finalize(
  ZipFileSink fileSink,
  List<FileHeader> fileHeaders,
  int versionMadeBy,
  Encoding? encoding,
  String? comment,
) async {
  final sink = fileSink.buffered();
  // process header data
  final numberOfEntries = fileHeaders.length;
  final numberOfDisk = fileSink.index();
  final offsetOfCentralDirectory = await fileSink.position();
  // central directory file header
  final centralDir = CentralDirectory(fileHeaders, null);
  await centralDir.write(sink, encoding);
  await sink.emit();
  final sizeOfCentralDirectory =
      await fileSink.position() - offsetOfCentralDirectory;
  final isZip64Format = fileHeaders.any((e) => e.isZip64Format) ||
      numberOfEntries > kZip64numlimit ||
      numberOfDisk > kZip64numlimit ||
      sizeOfCentralDirectory > kZip64sizelimit ||
      offsetOfCentralDirectory > kZip64sizelimit;
  // end of central directory record
  final totalNumberOfEntriesInCentralDirectoryOnDisk =
      fileHeaders.where((e) => e.diskNumberStart == numberOfDisk).length;
  final eocdrec = EndOfCentralDirectoryRecord(
    min(numberOfDisk, kZip64numlimit),
    min(numberOfDisk, kZip64numlimit),
    min(totalNumberOfEntriesInCentralDirectoryOnDisk, kZip64numlimit),
    min(numberOfEntries, kZip64numlimit),
    min(sizeOfCentralDirectory, kZip64sizelimit),
    min(offsetOfCentralDirectory, kZip64sizelimit),
    comment,
  );
  final versionNeeded =
      fileHeaders.map((e) => e.versionNeeded).reduce((v, e) => max(v, e));
  final zip64eocdrec = isZip64Format
      ? Zip64EndOfCentralDirectoryRecord(
          versionMadeBy,
          versionNeeded,
          numberOfDisk,
          numberOfDisk,
          totalNumberOfEntriesInCentralDirectoryOnDisk,
          numberOfEntries,
          sizeOfCentralDirectory,
          offsetOfCentralDirectory,
          const [],
        )
      : null;
  await zip64eocdrec?.write(sink);
  final zip64eocdloc = isZip64Format
      ? Zip64EndOfCentralDirectoryLocator(
          numberOfDisk,
          offsetOfCentralDirectory + sizeOfCentralDirectory,
          numberOfDisk + 1,
        )
      : null;
  await zip64eocdloc?.write(sink);
  await eocdrec.write(sink, encoding);
  await sink.emit();
  // end of central directory record
  return ZipModel(centralDir, zip64eocdrec, zip64eocdloc, eocdrec);
}
