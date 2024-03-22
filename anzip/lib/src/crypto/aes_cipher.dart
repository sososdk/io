import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../model/aes_key_strength.dart';
import '../zip_constants.dart';

mixin AesCipher {
  AesKeyStrength get strength;

  Uint8List derivePasswordBasedKey(
      Uint8List salt, String password, bool useUtf8Password) {
    if (password.isEmpty) {
      throw ArgumentError('password cannot be empty');
    }
    final int keyLength = strength.keyLength;
    final int macLength = strength.macLength;
    final int derivedKeyLength = keyLength + macLength + aesVerifierLength;

    final passwordBytes = useUtf8Password
        ? utf8.encode(password)
        : Uint8List.fromList(password.codeUnits);
    final params = Pbkdf2Parameters(salt, 1000, derivedKeyLength);
    final derivator = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64))..init(params);
    return derivator.process(passwordBytes);
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

  void prepareBuffAESIVBytes(Uint8List buff, int nonce) {
    buff[0] = nonce & 0xFF;
    buff[1] = (nonce >> 8) & 0xFF;
    buff[2] = (nonce >> 16) & 0xFF;
    buff[3] = (nonce >> 24) & 0xFF;

    for (int i = 4; i <= 15; ++i) {
      buff[i] = 0;
    }
  }
}
