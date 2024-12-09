import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:anio/anio.dart';

import '../../crypto/crc32.dart';
import '../../crypto/encrypter.dart';
import '../../model/compression_method.dart';
import '../../model/encryption_method.dart';
import '../../model/local_file_header.dart';
import '../../zip_constants.dart';
import '../../zip_exception.dart';

part 'cipher_sink.dart';
part 'compress_sink.dart';

Future<ZipEntrySink> createZipEntrySink(
  BufferedSink original,
  LocalFileHeader header,
  Uint8List? password,
) async {
  final sink = _OriginalSink(original);
  final cipherSink = await _CipherSink.create(sink, header, password);
  final compressSink = _CompressSink.create(cipherSink, header);
  return ZipEntrySink._(compressSink);
}

class _OriginalSink with ForwardingSink {
  _OriginalSink(this.delegate);

  @override
  final Sink delegate;

  var _writtenSize = 0;

  int get writtenSize => _writtenSize;

  @override
  Future<void> write(Buffer source, int count) {
    _writtenSize += count;
    return super.write(source, count);
  }

  @override
  Future<void> close() async {
    // Do nothing
  }
}

class ZipEntrySink implements Sink {
  ZipEntrySink._(this._sink) : bufferedSink = _sink.buffered();

  final _CompressSink _sink;
  final BufferedSink bufferedSink;
  final _crc32 = Crc32();

  int _uncompressedSize = 0;

  int get crc => _crc32.crc;

  int get uncompressedSize => _uncompressedSize;

  int get compressedSize => _sink.compressedSize;

  @override
  FutureOr<void> write(Buffer source, int count) {
    final bytes = source.readBytes(count);
    _crc32.update(bytes);
    _uncompressedSize += bytes.length;
    return bufferedSink.writeFromBytes(bytes);
  }

  @override
  FutureOr<void> flush() => bufferedSink.flush();

  @override
  FutureOr<void> close() => bufferedSink.close();
}
