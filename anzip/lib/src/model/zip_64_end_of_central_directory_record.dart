import 'dart:typed_data';

import 'package:anio/anio.dart';

import '../zip_constants.dart';
import 'zip_header.dart';

class Zip64EndOfCentralDirectoryRecord implements ZipHeader {
  Zip64EndOfCentralDirectoryRecord(
    this.versionMadeBy,
    this.versionNeeded,
    this.numberOfDisk,
    this.numberOfDiskStartOfCentralDirectory,
    this.totalNumberOfEntriesInCentralDirectoryOnDisk,
    this.totalNumberOfEntriesInCentralDirectory,
    this.sizeOfCentralDirectory,
    this.offsetOfCentralDirectory,
    this.extensibleDataSector,
  );

  @override
  List<int> get signature => kZip64censig;

  final int versionMadeBy;
  final int versionNeeded;
  final int numberOfDisk;
  final int numberOfDiskStartOfCentralDirectory;
  final int totalNumberOfEntriesInCentralDirectoryOnDisk;
  final int totalNumberOfEntriesInCentralDirectory;
  final int sizeOfCentralDirectory;
  final int offsetOfCentralDirectory;
  final List<int> extensibleDataSector;

  Future<void> write(BufferedSink sink) async {
    await sink.writeFromBytes(signature);
    await sink.writeUint64(44 + extensibleDataSector.length, Endian.little);
    await sink.writeUint16(versionMadeBy, Endian.little);
    await sink.writeUint16(versionNeeded, Endian.little);
    await sink.writeUint32(numberOfDisk, Endian.little);
    await sink.writeUint32(numberOfDiskStartOfCentralDirectory, Endian.little);
    await sink.writeUint64(
        totalNumberOfEntriesInCentralDirectoryOnDisk, Endian.little);
    await sink.writeUint64(
        totalNumberOfEntriesInCentralDirectory, Endian.little);
    await sink.writeUint64(sizeOfCentralDirectory, Endian.little);
    await sink.writeUint64(offsetOfCentralDirectory, Endian.little);
    await sink.writeFromBytes(extensibleDataSector);
  }
}
