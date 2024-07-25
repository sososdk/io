import '../bit_utils.dart';
import '../compression_method.dart';
import '../encryption_method.dart';
import '../zip_constants.dart';
import '../zip_exception.dart';
import 'aes_extra_data_record.dart';
import 'extra_data_record.dart';
import 'zip_64_extended_info.dart';
import 'zip_header.dart';

abstract class AbstractFileHeader implements ZipHeader {
  const AbstractFileHeader(
    this.versionNeededToExtract,
    this.generalPurposeFlag,
    this._compressionMethod,
    this._lastModifiedTime,
    this.crc,
    this._compressedSize,
    this._uncompressedSize,
    this.fileNameLength,
    this.extraFieldLength,
    this.fileName,
    this.extraDataRecords,
    this.zip64ExtendedInfo,
    this.aesExtraDataRecord,
  );

  final int versionNeededToExtract;
  final List<int> generalPurposeFlag;
  final CompressionMethod _compressionMethod;
  final int _lastModifiedTime;
  final int crc;
  final int _compressedSize;
  final int _uncompressedSize;
  final int fileNameLength;
  final int extraFieldLength;
  final String fileName;
  final List<ExtraDataRecord> extraDataRecords;
  final Zip64ExtendedInfo? zip64ExtendedInfo;
  final AESExtraDataRecord? aesExtraDataRecord;

  int get compressedSize =>
      (zip64ExtendedInfo?.compressedSize ?? _compressedSize);

  int get uncompressedSize =>
      zip64ExtendedInfo?.uncompressedSize ?? _uncompressedSize;

  bool get isEncrypted => isBitSet(generalPurposeFlag[0], 0);

  int get encryptionHeaderSize {
    if (!isEncrypted) return 0;

    if (encryptionMethod == EncryptionMethod.aes) {
      return aesEncryptionHeaderSize;
    } else if (encryptionMethod == EncryptionMethod.standard) {
      return stdDecHdrSize;
    } else {
      return 0;
    }
  }

  int get aesEncryptionHeaderSize {
    final keyStrength = aesExtraDataRecord?.aesKeyStrength;
    if (keyStrength == null) {
      throw ZipException('invalid for Aes encrypted entry');
    }
    return aesAuthLength + aesVerifierLength + keyStrength.saltLength;
  }

  bool get dataDescriptorExists => isBitSet(generalPurposeFlag[0], 3);

  bool get fileNameUTF8Encoded => isBitSet(generalPurposeFlag[1], 3);

  EncryptionMethod get encryptionMethod {
    if (aesExtraDataRecord != null) {
      return EncryptionMethod.aes;
    } else if (isEncrypted) {
      if (isBitSet(generalPurposeFlag[0], 6)) {
        return EncryptionMethod.standardVariantStrong;
      } else {
        return EncryptionMethod.standard;
      }
    } else {
      return EncryptionMethod.none;
    }
  }

  CompressionMethod get compressionMethod {
    if (_compressionMethod == CompressionMethod.aes) {
      final method = aesExtraDataRecord?.compressionMethod;
      if (method == null) {
        throw ZipException('AES extra data record not present in header');
      }
      return method;
    }
    return _compressionMethod;
  }

  bool get isDirectory;

  int get rawLastModifiedTime => _lastModifiedTime;

  DateTime get lastModifiedTime {
    final sec = (_lastModifiedTime << 1) & 0x3e;
    final min = (_lastModifiedTime >> 5) & 0x3f;
    final hrs = (_lastModifiedTime >> 11) & 0x1f;
    final day = (_lastModifiedTime >> 16) & 0x1f;
    final mon = ((_lastModifiedTime >> 21) & 0xf) - 1;
    final year = ((_lastModifiedTime >> 25) & 0x7f) + 1980;
    final dosToEpochTime =
        DateTime.utc(year, mon, day, hrs, min, sec).millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(
        dosToEpochTime + (_lastModifiedTime >> 32));
  }

  bool get isZip64Format =>
      extraDataRecords.any((e) => e.header == zip64extsig);

  @override
  String toString() => fileName;
}
