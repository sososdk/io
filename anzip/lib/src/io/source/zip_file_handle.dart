import 'dart:async';

import 'package:anio/anio.dart';
import 'package:file_system/file_system.dart';
import 'package:path/path.dart' as p;
import 'package:synchronizer/synchronizer.dart';

import '../../model/file_header.dart';
import '../index_random_access_file.dart';
import '../split_file_naming.dart';

// ignore_for_file: invalid_use_of_internal_member

class ZipFileHandle {
  final File file;
  final int diskNumber;
  final SplitFileNaming naming;

  ZipFileHandle(this.file, this.diskNumber)
      : assert(diskNumber >= 0),
        naming = SplitFileNaming(p.basenameWithoutExtension(file.path));

  final _lock = Lock();

  IndexRandomAccessFile? __raf;

  var _closed = false;
  var _openCount = 0;

  Source entrySource(FileHeader header) {
    return source(header.diskNumberStart, header.offsetLocalHeader);
  }

  Source source([int index = 0, int position = 0]) {
    if (_closed) throw StateError('closed');
    _openCount++;
    return ZipFileHandleSource(this, index, position);
  }

  Future<IndexRandomAccessFile> _raf([int index = 0]) async {
    if (__raf == null || __raf!.index != index) {
      await __raf?.close();
      if (index == diskNumber) {
        __raf = IndexRandomAccessFile(index, await file.open());
      } else {
        final temp = file.parent.childFile(naming.indexName(index + 1));
        __raf = IndexRandomAccessFile(index, await temp.open());
      }
    }
    return __raf!;
  }

  Future<(int, int, int)> readInto(
      int index, int position, Buffer sink, int count) {
    return _lock.synchronized(() async {
      var raf = await _raf(index);
      await raf.setPosition(position);

      var bytesRead = 0;
      while (bytesRead < count) {
        final readResult = await raf.readIntoSink(sink, count - bytesRead);
        if (readResult == 0) {
          final index = raf.index + 1;
          if (index > diskNumber) break;

          raf = await _raf(index);
        } else {
          bytesRead += readResult;
        }
      }
      return (raf.index, await raf.position(), bytesRead);
    });
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_openCount != 0) return;
    return _lock.synchronized(() => __raf?.close());
  }

  Future<void> _closeOpened() async {
    _openCount--;
    if (_openCount != 0 || !_closed) return;
    return _lock.synchronized(() => __raf?.close());
  }
}

class ZipFileHandleSource implements Source {
  ZipFileHandleSource(this.fileHandle, [int index = 0, int position = 0])
      : _index = index,
        _position = position;

  final ZipFileHandle fileHandle;
  int _index;
  int _position;

  var _closed = false;

  @override
  Future<int> read(Buffer sink, int count) async {
    if (_closed) throw StateError('closed');
    final result = await fileHandle.readInto(_index, _position, sink, count);
    _index = result.$1;
    _position = result.$2;
    return result.$3;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    return fileHandle._closeOpened();
  }
}
