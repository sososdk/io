import 'dart:typed_data';

import 'package:anzip/src/crypto/decrypter.dart';
import 'package:anzip/src/crypto/encrypter.dart';
import 'package:test/test.dart';

void main() {
  test('zip crypto', () {
    final password = Uint8List.fromList('password'.codeUnits);
    final encrypter = ZipCryptoEncrypter(password);
    final decrypter = ZipCryptoDecrypter(password);
    final bytes = Uint8List(12);
    encrypter.encryptBytes(bytes);
    decrypter.decryptBytes(bytes);
    expect(bytes, Uint8List(12));
  });
}
