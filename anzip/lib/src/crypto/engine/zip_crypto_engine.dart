import 'dart:typed_data';

import '../crc32.dart';

class ZipCryptoEngine {
  final _keys = List.filled(3, 0);

  void derive(Uint8List password) {
    _keys[0] = 0x12345678;
    _keys[1] = 0x23456789;
    _keys[2] = 0x34567890;
    password.forEach(update);
  }

  void update(int b) {
    _keys[0] = crc32(_keys[0], b);
    _keys[1] = (_keys[1] + (_keys[0] & 0xff)) * 0x08088405 + 1;
    _keys[2] = crc32(_keys[2], _keys[1] >> 24);
  }

  int streamByte() {
    final temp = _keys[2] | 2;
    return (temp * (temp ^ 1)) >>> 8;
  }

  int encryptBytes(Uint8List bytes, [int start = 0, int? end]) {
    end = RangeError.checkValidRange(start, end, bytes.length);
    for (var i = start; i < end; i++) {
      final temp = bytes[i] ^ streamByte();
      update(bytes[i]);
      bytes[i] = temp;
    }
    return end - start;
  }

  int decryptBytes(Uint8List bytes, [int start = 0, int? end]) {
    end = RangeError.checkValidRange(start, end, bytes.length);
    for (var i = start; i < end; i++) {
      final temp = bytes[i] ^ streamByte();
      update(temp);
      bytes[i] = temp;
    }
    return end - start;
  }
}
