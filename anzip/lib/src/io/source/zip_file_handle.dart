import 'dart:async';

import 'package:anio/anio.dart';
import 'package:file_system/file_system.dart';
import 'package:path/path.dart' as p;

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

  IndexFileHandle? __handle;

  var _openCount = 0;
  var _asyncDispatched = false;

  Future<T> _dispatch<T>(Future<T> Function() f, {bool close = false}) async {
    if (_openCount < 0) return Future.error(_closedMessage());
    if (_asyncDispatched) return Future.error(_dispatchedMessage());
    if (close) _openCount--;
    _asyncDispatched = true;
    return f().whenComplete(() => _asyncDispatched = false);
  }

  void _checkAvailable() {
    if (_asyncDispatched) throw _dispatchedMessage();
    if (_openCount < 0) throw _closedMessage();
  }

  Object _closedMessage() {
    return FileSystemException('File closed', file.path);
  }

  Object _dispatchedMessage() {
    return FileSystemException(
        'An async operation is currently pending', file.path);
  }

  Future<IndexFileHandle> _handle([int index = 0]) async {
    if (__handle == null || __handle!.index != index) {
      await __handle?.close();
      if (index == diskNumber) {
        __handle = IndexFileHandle(index, await file.open());
      } else {
        final temp = file.parent.childFile(naming.indexName(index + 1));
        __handle = IndexFileHandle(index, await temp.open());
      }
    }
    return __handle!;
  }

  Future<(int, int, int)> readInto(
      int index, int position, Buffer sink, int count) {
    return _dispatch(() async {
      var handle = await _handle(index);
      await handle.setPosition(position);

      var bytesRead = 0;
      while (bytesRead < count) {
        final readResult = await handle.readIntoSink(sink, count - bytesRead);
        if (readResult == 0) {
          final index = handle.index + 1;
          if (index > diskNumber) break;

          handle = await _handle(index);
        } else {
          bytesRead += readResult;
        }
      }
      return (handle.index, await handle.position(), bytesRead);
    });
  }

  Source entrySource(FileHeader header) {
    return source(header.diskNumberStart, header.offsetLocalHeader);
  }

  Source source([int index = 0, int position = 0]) {
    _checkAvailable();
    _openCount++;
    return ZipFileHandleSource(this, index, position);
  }

  Future<void> close() async {
    return _dispatch(() async {
      if (_openCount < 0) await __handle?.close();
    }, close: true);
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
    return fileHandle.close();
  }
}
