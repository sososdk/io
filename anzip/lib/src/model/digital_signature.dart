import '../zip_constants.dart';
import 'zip_header.dart';

class DigitalSignature implements ZipHeader {
  const DigitalSignature(this.size, this.signatureData);

  @override
  int get signature => digsig;

  final int? size;

  final String? signatureData;
}
