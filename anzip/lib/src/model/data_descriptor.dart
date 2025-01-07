import 'dart:typed_data';

import 'package:anio/anio.dart';

import '../zip_constants.dart';
import 'zip_header.dart';

class DataDescriptor implements ZipHeader {
  const DataDescriptor(
    this.crc,
    this.compressedSize,
    this.uncompressedSize,
  );

  @override
  List<int> get signature => kExtsig;

  final int crc;
  final int compressedSize;
  final int uncompressedSize;

  Future<void> write(BufferedSink sink, bool isZip64Format) async {
    await sink.writeFromBytes(signature);
    await sink.writeInt32(crc, Endian.little);
    if (isZip64Format) {
      await sink.writeInt64(compressedSize, Endian.little);
      await sink.writeInt64(uncompressedSize, Endian.little);
    } else {
      await sink.writeInt32(compressedSize, Endian.little);
      await sink.writeInt32(uncompressedSize, Endian.little);
    }
  }
}
