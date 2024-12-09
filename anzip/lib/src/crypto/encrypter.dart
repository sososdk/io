import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../model/encryption_method.dart';
import '../zip_constants.dart';
import 'aes_cipher.dart';
import 'engine/zip_crypto_engine.dart';

abstract interface class Encrypter {}

class AesEncrypter with AesCipher implements Encrypter {
  AesEncrypter(this.strength, Uint8List password) : salt = strength.genSalt() {
    final derivedKey = derivePasswordBasedKey(salt, password);
    derivedPasswordVerifier = derivePasswordVerifier(derivedKey);
    engine = getEngine(derivedKey);
    mac = getMacBasedPRF(derivedKey);
  }

  @override
  final AesKeyStrength strength;
  final Uint8List salt;

  late final Uint8List derivedPasswordVerifier;
  late final AESEngine engine;
  late final HMac mac;

  static const size = kAesBlockSize;
  final iv = Uint8List(size);
  final counterBlock = Uint8List(size);
  int nonce = 1;

  int encryptData(Uint8List buff, int start, int len) {
    for (var j = start; j < (start + len); j += size) {
      final loop = (j + size <= (start + len)) ? size : ((start + len) - j);
      prepareBuffAesIVBytes(iv, nonce);
      engine.processBlock(iv, 0, counterBlock, 0);
      for (var k = 0; k < loop; k++) {
        buff[j + k] ^= counterBlock[k];
      }
      mac.update(buff, j, loop);
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

class ZipCryptoEncrypter implements Encrypter {
  final _engine = ZipCryptoEngine();

  ZipCryptoEncrypter(Uint8List password) {
    _engine.derive(password);
  }

  int encryptBytes(Uint8List bytes, [int start = 0, int? end]) {
    return _engine.encryptBytes(bytes, start, end);
  }

  Uint8List genHeaderBytes(int key) {
    final bytes = Uint8List(kStdDecHdrSize);
    final random = Random.secure();
    for (var i = 0; i < bytes.length - 1; i++) {
      bytes[i] = random.nextInt(256);
    }
    bytes[kStdDecHdrSize - 1] = key >>> 24;
    encryptBytes(bytes);
    return bytes;
  }
}
