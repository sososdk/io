import 'dart:typed_data';

import 'package:anio/anio.dart';

import '../../anzip.dart';
import '../cp437.dart';
import '../zip_constants.dart';
import 'zip_header.dart';

class AesExtraDataRecord extends EncryptionAes implements ZipHeader {
  AesExtraDataRecord(
    super.aesVersion,
    String vendorID,
    super.aesKeyStrength,
  ) : super(vendorID: vendorID);

  factory AesExtraDataRecord.from(EncryptionAes aes) {
    return AesExtraDataRecord(aes.aesVersion, aes.vendorID, aes.aesKeyStrength);
  }

  @override
  List<int> get signature => kAesextdatarec;

  Future<void> write(
      BufferedSink sink, CompressionMethod compressionMethod) async {
    await sink.writeFromBytes(signature);
    await sink.writeUint16(7, Endian.little);
    await sink.writeUint16(aesVersion.versionNumber, Endian.little);
    await sink.writeString(vendorID, cp437);
    await sink.writeUint8(aesKeyStrength.code);
    await sink.writeUint16(compressionMethod.code, Endian.little);
  }
}
