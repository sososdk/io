import '../zip_constants.dart';
import 'zip_header.dart';

class Zip64EndOfCentralDirectoryRecord implements ZipHeader {
  Zip64EndOfCentralDirectoryRecord(
    this.sizeOfZip64EndCentralDirectoryRecord,
    this.versionMadeBy,
    this.versionNeededToExtract,
    this.numberOfThisDisk,
    this.numberOfThisDiskStartOfCentralDirectory,
    this.totalNumberOfEntriesInCentralDirectoryOnThisDisk,
    this.totalNumberOfEntriesInCentralDirectory,
    this.sizeOfCentralDirectory,
    this.offsetStartCentralDirectoryWRTStartDiskNumber,
    this.extensibleDataSector,
  );

  @override
  int get signature => zip64censig;

  final int sizeOfZip64EndCentralDirectoryRecord;
  final int versionMadeBy;
  final int versionNeededToExtract;
  final int numberOfThisDisk;
  final int numberOfThisDiskStartOfCentralDirectory;
  final int totalNumberOfEntriesInCentralDirectoryOnThisDisk;
  final int totalNumberOfEntriesInCentralDirectory;
  final int sizeOfCentralDirectory;
  final int offsetStartCentralDirectoryWRTStartDiskNumber;
  final List<int> extensibleDataSector;
}
