import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:pointycastle/export.dart';

import '../model/encryption_method.dart';
import '../zip_constants.dart';
import '../zip_exception.dart';
import 'aes_cipher.dart';
import 'engine/zip_crypto_engine.dart';

abstract interface class Decrypter {}

class AesDecrypter with AesCipher implements Decrypter {
  AesDecrypter(this.strength, Uint8List salt, Uint8List passwordVerifier,
      Uint8List password) {
    final derivedKey = derivePasswordBasedKey(salt, password);
    final derivedPasswordVerifier = derivePasswordVerifier(derivedKey);
    if (!const ListEquality()
        .equals(passwordVerifier, derivedPasswordVerifier)) {
      throw ZipException('password error');
    }
    engine = getEngine(derivedKey);
    mac = getMacBasedPRF(derivedKey);
  }

  @override
  final AesKeyStrength strength;

  late final AESEngine engine;
  late final HMac mac;

  static const size = kAesBlockSize;
  final iv = Uint8List(size);
  final counterBlock = Uint8List(size);
  int nonce = 1;

  int decryptData(Uint8List buff, int start, int len) {
    for (var j = start; j < (start + len); j += size) {
      final loop = (j + size <= (start + len)) ? size : ((start + len) - j);
      mac.update(buff, j, loop);
      prepareBuffAesIVBytes(iv, nonce);
      engine.processBlock(iv, 0, counterBlock, 0);
      for (var k = 0; k < loop; ++k) {
        buff[j + k] ^= counterBlock[k];
      }
      nonce++;
    }
    return len;
  }

  Uint8List doFinal() {
    final out = Uint8List(mac.macSize);
    mac.doFinal(out, 0);
    return out.sublist(0, kAesAuthLength);
  }
}

class ZipCryptoDecrypter implements Decrypter {
  final _engine = ZipCryptoEngine();

  ZipCryptoDecrypter(Uint8List password) {
    _engine.derive(password);
  }

  int decryptBytes(Uint8List bytes, [int start = 0, int? end]) {
    return _engine.decryptBytes(bytes, start, end);
  }

  void validate(Uint8List headerBytes, int crc, int dosTime) {
    decryptBytes(headerBytes);
    final code = headerBytes[kStdDecHdrSize - 1];
    if (code != (crc >> 24) & 0xff && code != (dosTime >> 8) & 0xff) {
      throw ZipException('password error');
    }
  }
}
