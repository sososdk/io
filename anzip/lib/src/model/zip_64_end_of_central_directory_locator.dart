import 'dart:typed_data';

import 'package:anio/anio.dart';

import '../zip_constants.dart';
import 'zip_header.dart';

class Zip64EndOfCentralDirectoryLocator implements ZipHeader {
  const Zip64EndOfCentralDirectoryLocator(
    this.numberOfDiskStartOfZip64EndOfCentralDirectoryRecord,
    this.offsetZip64EndOfCentralDirectoryRecord,
    this.totalNumberOfDisks,
  );

  @override
  List<int> get signature => kZip64endsig;

  /// number of the disk with the start of the zip64 end of central directory
  final int numberOfDiskStartOfZip64EndOfCentralDirectoryRecord;

  /// relative offset of the zip64 end of central directory record
  final int offsetZip64EndOfCentralDirectoryRecord;

  /// total number of disks
  final int totalNumberOfDisks;

  Future<void> write(BufferedSink sink) async {
    await sink.writeFromBytes(signature);
    await sink.writeUint32(
        numberOfDiskStartOfZip64EndOfCentralDirectoryRecord, Endian.little);
    await sink.writeUint64(
        offsetZip64EndOfCentralDirectoryRecord, Endian.little);
    await sink.writeUint32(totalNumberOfDisks, Endian.little);
  }
}
