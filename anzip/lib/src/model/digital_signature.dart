import 'dart:typed_data';

import '../zip_constants.dart';
import 'zip_header.dart';

class DigitalSignature implements ZipHeader {
  const DigitalSignature(this.signatureData);

  @override
  int get signature => kDigsig;

  final Uint8List signatureData;
}
