import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:pointycastle/export.dart';

import '../model/aes_key_strength.dart';
import '../zip_constants.dart';
import '../zip_exception.dart';
import 'aes_cipher.dart';
import 'engine/zip_crypto_engine.dart';

abstract interface class Decrypter {}

class AESDecrypter with AesCipher implements Decrypter {
  AESDecrypter(this.strength, Uint8List salt, Uint8List passwordVerifier,
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

  static const size = aesBlockSize;
  final iv = Uint8List(size);
  final counterBlock = Uint8List(size);
  int nonce = 1;

  int decryptData(Uint8List buff, int start, int len) {
    for (int j = start; j < (start + len); j += size) {
      final loopCount =
          (j + size <= (start + len)) ? size : ((start + len) - j);
      mac.update(buff, j, loopCount);
      prepareBuffAESIVBytes(iv, nonce);
      engine.processBlock(iv, 0, counterBlock, 0);
      for (int k = 0; k < loopCount; ++k) {
        buff[j + k] ^= counterBlock[k];
      }
      nonce++;
    }
    return len;
  }

  Uint8List doFinal() {
    final out = Uint8List(mac.macSize);
    mac.doFinal(out, 0);
    return out.sublist(0, aesAuthLength);
  }
}

class StandardDecrypter implements Decrypter {
  StandardDecrypter(
      Uint8List headerBytes, int time, int crc, Uint8List password) {
    _engine.initKeys(password);

    var result = headerBytes[0];
    for (var i = 0; i < stdDecHdrSize; i++) {
      if (i + 1 == stdDecHdrSize) {
        final code = result ^ _engine.decryptByte();
        if (code != (crc >> 24) & 0xFF && code != (time >> 8) & 0xFF) {
          throw ZipException('password error');
        }
      }

      _engine.updateKeys(result ^ _engine.decryptByte());

      if (i + 1 != stdDecHdrSize) {
        result = headerBytes[i + 1];
      }
    }
  }

  final _engine = ZipCryptoEngine();

  int decryptData(Uint8List buff, int start, int len) {
    for (var i = start; i < start + len; i++) {
      final temp = buff[i] ^ _engine.decryptByte();
      _engine.updateKeys(temp);
      buff[i] = temp;
    }
    return len;
  }
}
