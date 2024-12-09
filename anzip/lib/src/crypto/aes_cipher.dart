import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../model/encryption_method.dart';
import '../zip_constants.dart';

mixin AesCipher {
  AesKeyStrength get strength;

  Uint8List derivePasswordBasedKey(Uint8List salt, Uint8List password) {
    if (password.isEmpty) {
      throw ArgumentError('password cannot be empty');
    }
    final int keyLength = strength.keyLength;
    final int macLength = strength.macLength;
    final int derivedKeyLength = keyLength + macLength + kAesVerifierLength;

    final params = Pbkdf2Parameters(salt, 1000, derivedKeyLength);
    final derivator = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64))..init(params);
    return derivator.process(password);
  }

  Uint8List derivePasswordVerifier(Uint8List derivedKey) {
    final int keyLength = strength.keyLength;
    final int macLength = strength.macLength;
    return derivedKey.sublist(keyLength + macLength);
  }

  AESEngine getEngine(Uint8List derivedKey) {
    return AESEngine()
      ..init(true, KeyParameter(derivedKey.sublist(0, strength.keyLength)));
  }

  HMac getMacBasedPRF(Uint8List derivedKey) {
    final macKey = derivedKey.sublist(
        strength.keyLength, strength.keyLength + strength.macLength);
    return HMac(SHA1Digest(), 64)..init(KeyParameter(macKey));
  }

  void prepareBuffAesIVBytes(Uint8List buff, int nonce) {
    buff[0] = nonce & 0xFF;
    buff[1] = (nonce >> 8) & 0xFF;
    buff[2] = (nonce >> 16) & 0xFF;
    buff[3] = (nonce >> 24) & 0xFF;

    for (int i = 4; i <= 15; ++i) {
      buff[i] = 0;
    }
  }
}
