import '../compression_method.dart';
import '../zip_constants.dart';
import 'aes_key_strength.dart';
import 'aes_version.dart';
import 'zip_header.dart';

class AESExtraDataRecord implements ZipHeader {
  const AESExtraDataRecord(
    this.size,
    this.aesVersion,
    this.vendorID,
    this.aesKeyStrength,
    this.compressionMethod,
  );

  @override
  int get signature => aesextdatarec;

  final int size;
  final AesVersion aesVersion;
  final String vendorID;
  final AesKeyStrength aesKeyStrength;
  final CompressionMethod compressionMethod;
}
