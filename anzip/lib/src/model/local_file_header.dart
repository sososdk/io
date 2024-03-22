import '../zip_constants.dart';
import '../zip_exception.dart';
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
    this._isDirectory,
    this.extraField,
    this.offsetStartOfData,
    this.writeCompressedSizeInZip64ExtraRecord,
    this.extendedDataUpdated = false,
  ]);

  LocalFileHeader copyWith({
    int? crc,
    int? compressedSize,
    int? uncompressedSize,
    bool? isDirectory,
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
      isDirectory ?? _isDirectory,
      extraField,
      offsetStartOfData,
      writeCompressedSizeInZip64ExtraRecord,
      true,
    );
  }

  @override
  int get signature => locsig;

  final bool? _isDirectory;
  final List<int>? extraField;
  final int? offsetStartOfData;
  final bool? writeCompressedSizeInZip64ExtraRecord;
  final bool extendedDataUpdated;

  @override
  bool get isDirectory {
    return _isDirectory ?? fileName.endsWith('/') || fileName.endsWith('\\');
  }

  @override
  int get compressedSize {
    if (dataDescriptorExists && !extendedDataUpdated) {
      throw ZipException('compressed size not updated');
    }
    return super.compressedSize;
  }
}
