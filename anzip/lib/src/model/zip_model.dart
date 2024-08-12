import 'central_directory.dart';
import 'end_of_central_directory_record.dart';
import 'zip_64_end_of_central_directory_locator.dart';
import 'zip_64_end_of_central_directory_record.dart';

class ZipModel {
  const ZipModel(
    this.endOfCentralDirectoryRecord,
    this.zip64EndOfCentralDirectoryLocator,
    this.zip64EndOfCentralDirectoryRecord,
    this.centralDirectory,
  );

  final EndOfCentralDirectoryRecord endOfCentralDirectoryRecord;
  final Zip64EndOfCentralDirectoryLocator? zip64EndOfCentralDirectoryLocator;
  final Zip64EndOfCentralDirectoryRecord? zip64EndOfCentralDirectoryRecord;
  final CentralDirectory? centralDirectory;

  bool get isZip64Format => zip64EndOfCentralDirectoryLocator != null;

  bool get splitArchive => numberOfThisDisk > 0;

  int get numberOfThisDisk {
    if (isZip64Format) {
      return zip64EndOfCentralDirectoryRecord!.numberOfThisDisk;
    } else {
      return endOfCentralDirectoryRecord.numberOfThisDisk;
    }
  }
}
