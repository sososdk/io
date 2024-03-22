import '../bit_utils.dart';
import '../zip_constants.dart';
import 'abstract_file_header.dart';

class FileHeader extends AbstractFileHeader {
  const FileHeader(
    this.versionMadeBy,
    super.versionNeededToExtract,
    super.generalPurposeFlag,
    super.compressionMethod,
    super.lastModifiedTime,
    super.crc,
    super.compressedSize,
    super.uncompressedSize,
    super.fileNameLength,
    super.extraFieldLength,
    this.fileCommentLength,
    this._diskNumberStart,
    this.internalFileAttributes,
    this.externalFileAttributes,
    this._offsetLocalHeader,
    super.fileName,
    super.extraDataRecords,
    super.zip64ExtendedInfo,
    super.aesExtraDataRecord,
    this.fileComment,
  );

  @override
  int get signature => censig;

  final int versionMadeBy;
  final int fileCommentLength;
  final int _diskNumberStart;
  final List<int> internalFileAttributes;
  final List<int> externalFileAttributes;
  final int _offsetLocalHeader;
  final String? fileComment;

  int get diskNumberStart =>
      zip64ExtendedInfo?.diskNumberStart ?? _diskNumberStart;

  int get offsetLocalHeader =>
      zip64ExtendedInfo?.offsetLocalHeader ?? _offsetLocalHeader;

  @override
  bool get isDirectory {
    // first check if DOS attributes are set (lower order bytes from external attributes). If yes, check if the 4th bit
    // which represents a directory is set. If UNIX attributes are set (higher order two bytes), check for the 6th bit
    // in 4th byte which  represents a directory flag.
    final attributes = externalFileAttributes;
    if (attributes[0] != 0 && isBitSet(attributes[0], 4)) {
      return true;
    } else if (attributes[3] != 0 && isBitSet(attributes[3], 6)) {
      return true;
    }
    return fileName.endsWith('/') || fileName.endsWith('\\');
  }

  bool get isSymbolicLink => isBitSet(externalFileAttributes[3], 5);
}
