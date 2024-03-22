import '../zip_constants.dart';
import 'zip_header.dart';

class DataDescriptor implements ZipHeader {
  const DataDescriptor(
    this.crc,
    this.compressedSize,
    this.uncompressedSize,
  );

  @override
  int get signature => extsig;

  final int crc;
  final int compressedSize;
  final int uncompressedSize;
}
