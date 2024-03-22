import '../zip_constants.dart';
import 'zip_header.dart';

class EndOfCentralDirectoryRecord implements ZipHeader {
  const EndOfCentralDirectoryRecord(
    this.numberOfThisDisk,
    this.numberOfThisDiskStartOfCentralDirectory,
    this.totalNumberOfEntriesInCentralDirectoryOnThisDisk,
    this.totalNumberOfEntriesInCentralDirectory,
    this.sizeOfCentralDirectory,
    this.offsetStartOfCentralDirectory,
    this.offsetEndOfCentralDirectory,
    this.comment,
  );

  @override
  int get signature => endsig;

  final int numberOfThisDisk;
  final int numberOfThisDiskStartOfCentralDirectory;
  final int totalNumberOfEntriesInCentralDirectoryOnThisDisk;
  final int totalNumberOfEntriesInCentralDirectory;
  final int sizeOfCentralDirectory;
  final int offsetStartOfCentralDirectory;
  final int offsetEndOfCentralDirectory;
  final String? comment;
}
