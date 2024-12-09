part of 'zip_entry_sink.dart';

abstract class _CompressSink implements Sink {
  _CompressSink(this.sink) : bufferedSink = sink.buffered();

  static _CompressSink create(_CipherSink sink, LocalFileHeader header) {
    final compressionMethod = header.compressionMethod;
    return switch (compressionMethod) {
      CompressionStore() => _StoreSink(sink),
      CompressionDeflate() => _DeflaterSink(sink, compressionMethod.level),
      _ => throw ZipException(
          'Entry [${header.name}] ${header.compressionMethod} not supported'),
    };
  }

  final _CipherSink sink;

  final BufferedSink bufferedSink;

  int get compressedSize => sink.compressedSize;

  @override
  FutureOr<void> flush() => bufferedSink.flush();

  @override
  FutureOr<void> close() => bufferedSink.close();
}

class _StoreSink extends _CompressSink {
  _StoreSink(super.sink);

  @override
  FutureOr<void> write(Buffer source, int count) =>
      bufferedSink.write(source, count);
}

class _DeflaterSink extends _CompressSink {
  _DeflaterSink(super.sink, int level)
      : _deflater = RawZLibFilter.deflateFilter(level: level, raw: true);

  final RawZLibFilter _deflater;

  @override
  FutureOr<void> write(Buffer source, int count) async {
    final bytes = source.readBytes(count);
    _deflater.process(bytes, 0, bytes.length);
    while (true) {
      final out = _deflater.processed(flush: false);
      if (out == null) break;
      await bufferedSink.writeFromBytes(out);
    }
  }

  @override
  FutureOr<void> close() async {
    while (true) {
      final out = _deflater.processed(end: true);
      if (out == null) break;
      await bufferedSink.writeFromBytes(out);
    }
    return super.close();
  }
}
