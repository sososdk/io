import 'central_directory.dart';
import 'end_of_central_directory_record.dart';
import 'zip_64_end_of_central_directory_locator.dart';
import 'zip_64_end_of_central_directory_record.dart';

class ZipModel {
  const ZipModel(
    this.centralDirectory,
    this.zip64EndOfCentralDirectoryRecord,
    this.zip64EndOfCentralDirectoryLocator,
    this.endOfCentralDirectoryRecord,
  );

  final CentralDirectory centralDirectory;
  final Zip64EndOfCentralDirectoryRecord? zip64EndOfCentralDirectoryRecord;
  final Zip64EndOfCentralDirectoryLocator? zip64EndOfCentralDirectoryLocator;
  final EndOfCentralDirectoryRecord endOfCentralDirectoryRecord;

  bool get isSplitArchive => numberOfDisk > 0;

  bool get isZip64Format => zip64EndOfCentralDirectoryLocator != null;

  int get numberOfDisk {
    if (isZip64Format) {
      return zip64EndOfCentralDirectoryRecord!.numberOfDisk;
    } else {
      return endOfCentralDirectoryRecord.numberOfDisk;
    }
  }

  int get offsetOfCentralDirectory {
    if (isZip64Format) {
      return zip64EndOfCentralDirectoryRecord!.offsetOfCentralDirectory;
    } else {
      return endOfCentralDirectoryRecord.offsetOfCentralDirectory;
    }
  }

  String? get comment => endOfCentralDirectoryRecord.comment;
}
