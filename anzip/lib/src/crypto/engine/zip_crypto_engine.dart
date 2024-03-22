import 'dart:convert';

import '../crc32.dart';

class ZipCryptoEngine {
  final _keys = List.filled(3, 0);

  void initKeys(String password, bool useUtf8Password) {
    _keys[0] = 305419896;
    _keys[1] = 591751049;
    _keys[2] = 878082192;
    List<int> bytes =
        useUtf8Password ? utf8.encode(password) : password.codeUnits;
    for (int b in bytes) {
      updateKeys(b);
    }
  }

  void updateKeys(int b) {
    _keys[0] = crc32(_keys[0], b);
    _keys[1] += _keys[0] & 0xff;
    _keys[1] = _keys[1] * 134775813 + 1;
    _keys[2] = crc32(_keys[2], _keys[1] >> 24);
  }

  int decryptByte() {
    final temp = _keys[2] | 2;
    return ((temp * (temp ^ 1)) >>> 8) & 0xff;
  }
}
