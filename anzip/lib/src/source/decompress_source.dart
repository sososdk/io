part of 'zip_entry_source.dart';

abstract class _DecompressSource implements Source {
  _DecompressSource(Source source) : source = source.buffered();

  static _DecompressSource create(Source source, LocalFileHeader header) {
    return switch (header.compressionMethod) {
      CompressionMethod.store => _StoreSource(source),
      CompressionMethod.deflate => _InflaterSource(source),
      _ => throw ZipException(
          'Entry [${header.fileName}] ${header.compressionMethod} not supported'),
    };
  }

  final BufferedSource source;

  @override
  FutureOr<void> close() => source.close();
}

class _StoreSource extends _DecompressSource {
  _StoreSource(super.source);

  @override
  FutureOr<int> read(Buffer sink, int count) => source.read(sink, count);
}

class _InflaterSource extends _DecompressSource {
  _InflaterSource(super.source);

  final _inflater = RawZLibFilter.inflateFilter(raw: true);
  final _buffer = Buffer();

  bool _finished = false;

  @override
  FutureOr<int> read(Buffer sink, int count) async {
    while (true) {
      await _inflate();
      final result = _buffer.read(sink, count);
      if (result > 0) return result;
      if (_finished) return 0;
    }
  }

  FutureOr<void> _inflate() async {
    if (!_buffer.exhausted()) return;
    if (await source.exhausted()) {
      if (_finished) return;
      _finished = true;
      while (true) {
        final out = _inflater.processed(end: true);
        if (out == null) break;
        _buffer.writeFromBytes(out);
      }
    } else {
      final bytes = source.buffer.readBytes();
      _inflater.process(bytes, 0, bytes.length);
      while (true) {
        final out = _inflater.processed(flush: false);
        if (out == null) break;
        _buffer.writeFromBytes(out);
      }
    }
  }
}
