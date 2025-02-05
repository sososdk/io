import 'dart:async';
import 'dart:math';

import 'package:anio/anio.dart';
import 'package:file_system/file_system.dart';
import 'package:path/path.dart' as p;

import '../index_random_access_file.dart';
import '../split_file_naming.dart';

class ZipFileSink implements Sink {
  ZipFileSink(File file, [int? diskSize])
      : _handle = _ZipFileHandle(_ZipRandomAccessFile(file, diskSize));

  final _ZipFileHandle _handle;

  @override
  Future<void> write(Buffer source, int count) async {
    await _handle.writeFromSource(source, count);
  }

  Future<void> update(int index, int position, Buffer source, int count) {
    return _handle.update(index, position, source, count);
  }

  int index() => _handle.index();

  Future<int> position() => _handle.position();

  Future<void> setPosition(int position) => _handle.setPosition(position);

  Future<void> truncate(int length) => _handle.truncate(length);

  Future<void> startFinalize() => _handle.finalize();

  @override
  Future<void> flush() => _handle.flush();

  @override
  Future<void> close() => _handle.close();
}

class _ZipFileHandle with FileHandleBase {
  @override
  final _ZipRandomAccessFile delegate;

  _ZipFileHandle(this.delegate);

  int index() => delegate.index();

  Future<void> update(int index, int position, Buffer source, int count) {
    return delegate.update(index, position, source, count);
  }

  Future<void> finalize() => delegate.finalize();

  @override
  FileSink sink([int position = 0]) {
    // TODO: implement sink
    return super.sink(position);
  }
}

class _ZipRandomAccessFile with ForwardingRandomAccessFile {
  final File file;
  final int? diskSize;
  final SplitFileNaming naming;

  _ZipRandomAccessFile(this.file, this.diskSize)
      : naming = SplitFileNaming(p.basenameWithoutExtension(file.path));

  IndexFileHandle? __handle;
  var _finalize = false;

  Future<void> finalize() async {
    _finalize = true;
    await _nextSink();
  }

  @override
  RandomAccessFile get delegate => throw UnimplementedError();

  Future<IndexFileHandle> _handle() async {
    if (__handle == null) {
      final raf = await file.open(mode: FileMode.append);
      __handle = IndexFileHandle(0, raf);
    }
    return __handle!;
  }

  Future<IndexFileHandle> _nextSink() async {
    final index = __handle!.index + 1;
    await __handle!.close();
    await file.rename(file.parent.childFile(naming.indexName(index)).path);
    final raf = await file.open(mode: FileMode.write);
    return __handle = IndexFileHandle(index, raf);
  }

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    end = RangeError.checkValidRange(start, end, buffer.length);
    if (diskSize == null || _finalize) {
      final raf = await _handle();
      await raf.writeFrom(buffer, start, end);
    } else {
      var raf = await _handle();
      while (end - start > 0) {
        if (diskSize! <= await raf.length()) {
          raf = await _nextSink();
        }

        final size = min(diskSize! - await raf.length(), end - start);
        await raf.writeFrom(buffer, start, start + size);
        start += size;
      }
    }
    return this;
  }

  Future<void> update(int index, int position, Buffer source, int count) async {
    RangeError.checkValueInInterval(count, 0, source.length);
    var raf = await _handle();
    final currentIndex = raf.index;
    final currentPosition = await raf.position();
    if (currentIndex == index) {
      await raf.setPosition(position);
      await raf.writeFromSource(source, count);
      await raf.setPosition(currentPosition);
      return;
    } else {
      try {
        final delegate = await file.parent
            .childFile(naming.indexName(index + 1))
            .open(mode: FileMode.append)
            .then((e) => e.setPosition(position));
        raf = IndexFileHandle(index, delegate);
        while (count > 0) {
          if (await raf.length() <= await raf.position()) {
            await raf.close();
            final index = raf.index + 1;
            if (index == currentIndex) {
              await __handle!.setPosition(0);
              await __handle!.writeFromSource(source, count);
              await __handle!.setPosition(currentPosition);
              return;
            } else {
              final delegate = await file.parent
                  .childFile(naming.indexName(index + 1))
                  .open(mode: FileMode.append)
                  .then((e) => e.setPosition(0));
              raf = IndexFileHandle(index, delegate);
            }
          }
          final size = min(await raf.length() - await raf.position(), count);
          await raf.writeFromSource(source, size);
          count -= size;
        }
      } finally {
        // await raf.close();
      }
    }
  }

  int index() => __handle?.index ?? 0;

  @override
  Future<int> position() => _handle().then((e) => e.position());

  @override
  Future<RandomAccessFile> setPosition(int position) {
    return _handle().then((e) => e.setPosition(position));
  }

  @override
  Future<RandomAccessFile> truncate(int length) async {
    return _handle().then((e) => e.truncate(length));
  }

  @override
  Future<RandomAccessFile> flush() async {
    await __handle?.flush();
    return this;
  }

  @override
  Future<void> close() async => __handle?.close();
}
