import 'dart:convert';

import 'package:anio/anio.dart';

import 'digital_signature.dart';
import 'file_header.dart';

class CentralDirectory {
  const CentralDirectory(this.fileHeaders, this.digitalSignature);

  final List<FileHeader> fileHeaders;

  final DigitalSignature? digitalSignature;

  Future<void> write(BufferedSink sink, [Encoding? encoding]) async {
    for (var e in fileHeaders) {
      await e.write(sink, encoding);
    }
  }
}
