import 'digital_signature.dart';
import 'file_header.dart';

class CentralDirectory {
  const CentralDirectory(this.fileHeaders, this.digitalSignature);

  final List<FileHeader> fileHeaders;

  final DigitalSignature digitalSignature;
}
