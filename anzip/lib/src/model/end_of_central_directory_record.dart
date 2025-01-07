import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:anio/anio.dart';

import '../cp437.dart';
import '../zip_constants.dart';
import 'zip_header.dart';

class EndOfCentralDirectoryRecord implements ZipHeader {
  const EndOfCentralDirectoryRecord(
    this.numberOfDisk,
    this.numberOfDiskStartOfCentralDirectory,
    this.totalNumberOfEntriesInCentralDirectoryOnDisk,
    this.totalNumberOfEntriesInCentralDirectory,
    this.sizeOfCentralDirectory,
    this.offsetOfCentralDirectory,
    this.comment,
  );

  @override
  List<int> get signature => kEndsig;

  /// number of this disk
  final int numberOfDisk;

  /// number of the disk with the start of the central directory
  final int numberOfDiskStartOfCentralDirectory;

  /// total number of entries in the central directory on this disk
  final int totalNumberOfEntriesInCentralDirectoryOnDisk;

  /// total number of entries in the central directory
  final int totalNumberOfEntriesInCentralDirectory;

  /// size of the central directory
  final int sizeOfCentralDirectory;

  /// offset of start of central directory with respect to the starting disk number
  final int offsetOfCentralDirectory;
  final String? comment;

  Future<void> write(BufferedSink sink, Encoding? encoding) async {
    await sink.writeFromBytes(signature);
    await sink.writeUint16(numberOfDisk, Endian.little);
    await sink.writeUint16(numberOfDiskStartOfCentralDirectory, Endian.little);
    await sink.writeUint16(
        totalNumberOfEntriesInCentralDirectoryOnDisk, Endian.little);
    await sink.writeUint16(
        totalNumberOfEntriesInCentralDirectory, Endian.little);
    await sink.writeUint32(sizeOfCentralDirectory, Endian.little);
    await sink.writeUint32(offsetOfCentralDirectory, Endian.little);
    final commentRaw =
        comment == null ? null : (encoding ?? cp437).encode(comment!);
    final commentLength = commentRaw?.length ?? 0;
    await sink.writeUint16(commentLength, Endian.little);
    if (commentRaw != null) {
      await sink.writeFromBytes(
          commentRaw, 0, min(commentLength, kMaxCommentSize));
    }
  }
}
