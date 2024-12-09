import 'dart:typed_data';

import 'package:anio/anio.dart';

import '../zip_constants.dart';
import 'zip_header.dart';

abstract class AbstractZip64ExtendedInfo implements ZipHeader {
  const AbstractZip64ExtendedInfo(
    this.compressedSize,
    this.uncompressedSize,
  );

  @override
  int get signature => kZip64extsig;

  final int? compressedSize;
  final int? uncompressedSize;

  Future<void> write(BufferedSink buffer);
}

class Zip64ExtendedInfo extends AbstractZip64ExtendedInfo {
  const Zip64ExtendedInfo(
    super.compressedSize,
    super.uncompressedSize,
    this.offsetLocalHeader,
    this.diskNumberStart,
  );

  final int? offsetLocalHeader;
  final int? diskNumberStart;

  @override
  Future<void> write(BufferedSink buffer) async {
    await buffer.writeUint16(signature, Endian.little);
    final temp = Buffer();
    if (uncompressedSize != null) {
      temp.writeUint64(uncompressedSize!, Endian.little);
    }
    if (compressedSize != null) {
      temp.writeUint64(compressedSize!, Endian.little);
    }
    if (offsetLocalHeader != null) {
      temp.writeUint64(offsetLocalHeader!, Endian.little);
    }
    if (diskNumberStart != null) {
      temp.writeUint32(diskNumberStart!, Endian.little);
    }
    await buffer.writeUint16(temp.length, Endian.little);
    await buffer.writeFromSource(temp);
  }
}

class LocalZip64ExtendedInfo extends AbstractZip64ExtendedInfo {
  LocalZip64ExtendedInfo(super.compressedSize, super.uncompressedSize);

  @override
  Future<void> write(BufferedSink buffer) async {
    await buffer.writeUint16(signature, Endian.little);
    final temp = Buffer();
    if (uncompressedSize != null) {
      temp.writeUint64(uncompressedSize!, Endian.little);
    }
    if (compressedSize != null) {
      temp.writeUint64(compressedSize!, Endian.little);
    }
    await buffer.writeUint16(temp.length, Endian.little);
    await buffer.writeFromSource(temp);
  }
}
