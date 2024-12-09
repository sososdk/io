import 'dart:convert';

import 'package:anio/anio.dart';

import '../bit_utils.dart';
import '../zip_constants.dart';
import '../zip_utils.dart';
import 'aes_extra_data_record.dart';
import 'compression_method.dart';
import 'encryption_method.dart';
import 'zip_64_extended_info.dart';
import 'zip_header.dart';

abstract class AbstractFileHeader<T extends AbstractZip64ExtendedInfo>
    implements ZipHeader {
  const AbstractFileHeader(
    this.versionNeeded,
    this.generalPurposeFlag,
    this.compressionMethod,
    this._lastModifiedTime,
    this.crc,
    this._compressedSize,
    this._uncompressedSize,
    this.name,
    this.zip64ExtendedInfo,
    this.aesExtraDataRecord,
  );

  final int versionNeeded;
  final List<int> generalPurposeFlag;
  final CompressionMethod compressionMethod;
  final int _lastModifiedTime;
  final int crc;
  final int _compressedSize;
  final int _uncompressedSize;
  final String name;
  final T? zip64ExtendedInfo;
  final AesExtraDataRecord? aesExtraDataRecord;

  int get compressedSize =>
      (zip64ExtendedInfo?.compressedSize ?? _compressedSize);

  int get uncompressedSize =>
      zip64ExtendedInfo?.uncompressedSize ?? _uncompressedSize;

  bool get isEncrypted => isBitSet(generalPurposeFlag[0], 0);

  bool get useDataDescriptor => isBitSet(generalPurposeFlag[0], 3);

  bool get fileNameUtf8Encoded => isBitSet(generalPurposeFlag[1], 3);

  int get encryptionHeaderSize {
    if (!isEncrypted) return 0;

    return switch (encryptionMethod) {
      EncryptionZipCrypto() => kStdDecHdrSize,
      EncryptionAes() => kAesAuthLength +
          kAesVerifierLength +
          aesExtraDataRecord!.aesKeyStrength.saltLength,
      _ => 0
    };
  }

  EncryptionMethod get encryptionMethod {
    if (aesExtraDataRecord != null) {
      return aesExtraDataRecord!;
    } else if (isEncrypted) {
      return const EncryptionZipCrypto();
    } else {
      return const EncryptionNone();
    }
  }

  bool get isDirectory => name.endsWith('/') || name.endsWith('\\');

  int get dosTime => _lastModifiedTime;

  DateTime get epochTime => dosToEpochTime(dosTime);

  bool get isZip64Format => zip64ExtendedInfo != null;

  int get encryptionKey {
    return useDataDescriptor ? (dosTime & 0xffff) << 16 : crc;
  }

  Future<void> write(BufferedSink sink, Encoding? encoding);

  @override
  String toString() => name;
}
