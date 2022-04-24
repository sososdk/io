import 'dart:convert';
import 'dart:typed_data';

import 'package:file_system/file_system.dart';

const int _kLF = 10;
const int _kCR = 13;

class StrictLineReader {
  final Source source;
  final Encoding encoding;
  final int capacity;

  late Uint8List _buf;
  int _pos = 0;
  int _end = 0;

  StrictLineReader(this.source, {this.capacity = 8192, this.encoding = utf8});

  Future<String> readLine() async {
    // Read more data if we are at the end of the buffered data.
    if (_pos >= _end) {
      await _fill();
    }
    // Try to find LF in the buffered data and return the line if successful.
    for (var i = _pos; i != _end; ++i) {
      if (_buf[i] == _kLF) {
        final lineEnd = (i != _pos && _buf[i - 1] == _kCR) ? i - 1 : i;
        final res = encoding.decode(_buf.sublist(_pos, lineEnd));
        _pos = i + 1;
        return res;
      }
    }

    final builder = BytesBuilder(copy: false);
    while (true) {
      builder.add(_buf.sublist(_pos, _end));
      // Mark unterminated line in case fillBuf throws EOFException.
      _end = -1;
      await _fill();
      // Try to find LF in the buffered data and return the line if successful.
      for (var i = _pos; i != _end; ++i) {
        if (_buf[i] == _kLF) {
          if (i != _pos) {
            builder.add(_buf.sublist(_pos, i));
          }
          _pos = i + 1;
          return encoding.decode(builder.takeBytes());
        }
      }
    }
  }

  bool get hasUnterminatedLine => _end == -1;

  Future<void> _fill() async {
    final result = await source.read(capacity);
    if (result.isEmpty) {
      throw EOFException();
    } else {
      _buf = result;
    }
    _pos = 0;
    _end = result.length;
  }
}

class EOFException implements Exception {}
