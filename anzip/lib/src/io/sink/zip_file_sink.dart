import 'dart:async';
import 'dart:math';

import 'package:anio/anio.dart';
import 'package:file_system/file_system.dart';
import 'package:path/path.dart' as p;

import '../index_random_access_file.dart';
import '../split_file_naming.dart';

class ZipFileSink implements Sink {
  ZipFileSink(File file, [int? diskSize])
      : _raf = _ZipRandomAccessFile(file, diskSize);

  final _ZipRandomAccessFile _raf;

  @override
  Future<void> write(Buffer source, int count) async {
    await _raf.writeFromSource(source, count);
  }

  Future<void> update(int index, int position, Buffer source, int count) {
    return _raf.update(index, position, source, count);
  }

  int index() => _raf.index();

  Future<int> position() => _raf.position();

  Future<void> setPosition(int position) => _raf.setPosition(position);

  Future<void> truncate(int length) => _raf.truncate(length);

  Future<void> startFinalize() => _raf.finalize();

  @override
  Future<void> flush() => _raf.flush();

  @override
  Future<void> close() => _raf.close();
}

class _ZipRandomAccessFile with ForwardingRandomAccessFile {
  final File file;
  final int? diskSize;
  final SplitFileNaming naming;

  _ZipRandomAccessFile(this.file, this.diskSize)
      : naming = SplitFileNaming(p.basenameWithoutExtension(file.path));

  IndexRandomAccessFile? __raf;
  var _finalize = false;

  Future<void> finalize() async {
    _finalize = true;
    await _nextSink();
  }

  @override
  RandomAccessFile get delegate => throw UnimplementedError();

  Future<IndexRandomAccessFile> _raf() async {
    if (__raf == null) {
      final raf = await file.open(mode: FileMode.append);
      __raf = IndexRandomAccessFile(0, raf);
    }
    return __raf!;
  }

  Future<IndexRandomAccessFile> _nextSink() async {
    final index = __raf!.index + 1;
    await __raf!.close();
    await file.rename(file.parent.childFile(naming.indexName(index)).path);
    final raf = await file.open(mode: FileMode.write);
    return __raf = IndexRandomAccessFile(index, raf);
  }

  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async {
    end = RangeError.checkValidRange(start, end, buffer.length);
    if (diskSize == null || _finalize) {
      final raf = await _raf();
      await raf.writeFrom(buffer, start, end);
    } else {
      var raf = await _raf();
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
    var raf = await _raf();
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
        raf = IndexRandomAccessFile(index, delegate);
        while (count > 0) {
          if (await raf.length() <= await raf.position()) {
            await raf.close();
            final index = raf.index + 1;
            if (index == currentIndex) {
              await __raf!.setPosition(0);
              await __raf!.writeFromSource(source, count);
              await __raf!.setPosition(currentPosition);
              return;
            } else {
              final delegate = await file.parent
                  .childFile(naming.indexName(index + 1))
                  .open(mode: FileMode.append)
                  .then((e) => e.setPosition(0));
              raf = IndexRandomAccessFile(index, delegate);
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

  int index() => __raf?.index ?? 0;

  @override
  Future<int> position() => _raf().then((e) => e.position());

  @override
  Future<RandomAccessFile> setPosition(int position) {
    return _raf().then((e) => e.setPosition(position));
  }

  @override
  Future<RandomAccessFile> truncate(int length) async {
    return _raf().then((e) => e.truncate(length));
  }

  @override
  Future<RandomAccessFile> flush() async {
    await __raf?.flush();
    return this;
  }

  @override
  Future<void> close() async => __raf?.close();
}
