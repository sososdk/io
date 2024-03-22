import '../zip_constants.dart';
import 'zip_header.dart';

class Zip64EndOfCentralDirectoryLocator implements ZipHeader {
  const Zip64EndOfCentralDirectoryLocator(
    this.numberOfDiskStartOfZip64EndOfCentralDirectoryRecord,
    this.offsetZip64EndOfCentralDirectoryRecord,
    this.totalNumberOfDiscs,
  );

  @override
  int get signature => zip64endsig;

  final int numberOfDiskStartOfZip64EndOfCentralDirectoryRecord;
  final int offsetZip64EndOfCentralDirectoryRecord;
  final int totalNumberOfDiscs;
}
