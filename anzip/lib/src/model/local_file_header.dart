import '../zip_constants.dart';
import 'abstract_file_header.dart';

/// Used to read zip Entry directly in sequence without reading zip Central Directory.
class LocalFileHeader extends AbstractFileHeader {
  const LocalFileHeader(
    super.versionNeededToExtract,
    super.generalPurposeFlag,
    super.compressionMethod,
    super.lastModifiedTime,
    super.crc,
    super.compressedSize,
    super.uncompressedSize,
    super.fileNameLength,
    super.extraFieldLength,
    super.fileName,
    super.extraDataRecords,
    super.zip64ExtendedInfo,
    super.aesExtraDataRecord, [
    this.extraField,
  ]);

  LocalFileHeader copyWith({
    int? crc,
    int? compressedSize,
    int? uncompressedSize,
  }) {
    return LocalFileHeader(
      versionNeededToExtract,
      generalPurposeFlag,
      compressionMethod,
      rawLastModifiedTime,
      crc ?? this.crc,
      compressedSize ?? this.compressedSize,
      uncompressedSize ?? this.uncompressedSize,
      fileNameLength,
      extraFieldLength,
      fileName,
      extraDataRecords,
      zip64ExtendedInfo,
      aesExtraDataRecord,
      extraField,
    );
  }

  @override
  int get signature => locsig;

  final List<int>? extraField;

  @override
  bool get isDirectory => false;

  bool get isZip64Format =>
      compressedSize >= zip64sizelimit || uncompressedSize >= zip64sizelimit;
}
