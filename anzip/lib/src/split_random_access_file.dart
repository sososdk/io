import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'zip_exception.dart';

/// Implement the volume file reading function. For example, [a.z01, a.z02, a.z03, a.zip]
class SplitRandomAccessFile implements RandomAccessFile {
  SplitRandomAccessFile(
    this._file,
    this._mode,
    this._splitNumber,
    this._splitLength,
    this._randomAssessFile,
    this._naming,
    this._index,
  ) : assert(_mode == FileMode.read || _mode == FileMode.writeOnly);

  static Future<RandomAccessFile> openRead(
    File file,
    int splitNumber,
    int splitLength,
    SplitFileNaming naming,
  ) async {
    final first = File(p.join(file.parent.path, naming.splitName(1)));
    final randomAccessFile = await first.open(mode: FileMode.read);
    return SplitRandomAccessFile(file, FileMode.read, splitNumber, splitLength,
        randomAccessFile, naming, 0);
  }

  static Future<RandomAccessFile> openWrite(
    // a.zip
    File file,
    SplitFileNaming naming, {
    int splitLength = 1024 * 1024 * 1024,
  }) async {
    final randomAccessFile = await file.open(mode: FileMode.writeOnly);
    return SplitRandomAccessFile(
        file, FileMode.writeOnly, 0, splitLength, randomAccessFile, naming, 0);
  }

  // a.zip
  final File _file;
  final FileMode _mode;
  final SplitFileNaming _naming;

  /// The number of shards.
  ///
  /// For example, the shards number of [a.z01, a.z02, a.z03, a.zip] is 3.
  final int _splitNumber;

  /// The length of each shard.
  final int _splitLength;

  /// The index of the current operating shard.
  ///
  /// For example, in [a.z01, a.z02, a.z03, a.zip], the current operation is a.z02, then the index is 1.
  int _index;

  /// The currently operated file is associated with [_index].
  RandomAccessFile _randomAssessFile;

  int get splitNumber => _splitNumber;

  int get splitLength => _splitLength;

  File _nextFile(int index) {
    return File(p.join(_file.parent.path, _naming.splitName(index + 1)));
  }

  File _splitFile(int index) {
    if (index == _splitNumber) {
      return _file;
    } else if (index > _splitNumber) {
      throw ZipException('split file index out of range');
    }
    return _nextFile(index);
  }

  @override
  Future<void> close() => _randomAssessFile.close();

  @override
  void closeSync() => _randomAssessFile.closeSync();

  @override
  Future<RandomAccessFile> flush() => _randomAssessFile.flush();

  @override
  void flushSync() => _randomAssessFile.flushSync();

  @override
  Future<int> length() async =>
      _splitNumber * _splitLength + await _file.length();

  @override
  int lengthSync() => _splitNumber * _splitLength + _file.lengthSync();

  @override
  String get path => _file.path;

  @override
  Future<int> position() async {
    return _index * _splitLength + await _randomAssessFile.position();
  }

  @override
  int positionSync() {
    return _index * _splitLength + _randomAssessFile.positionSync();
  }

  @override
  Future<RandomAccessFile> setPosition(int position) async {
    final index = position ~/ _splitLength;
    if (index != _index) {
      await _randomAssessFile.close();
      _randomAssessFile = await _splitFile(index).open(mode: _mode);
      _index = index;
    }
    return _randomAssessFile.setPosition(position - (index * _splitLength));
  }

  @override
  void setPositionSync(int position) {
    final index = position ~/ _splitLength;
    if (index != _index) {
      _randomAssessFile.closeSync();
      _randomAssessFile = _splitFile(index).openSync(mode: _mode);
      _index = index;
    }
    return _randomAssessFile.setPositionSync(position - (index * _splitLength));
  }

  @override
  Future<int> readByte() => throw UnimplementedError();

  @override
  int readByteSync() => throw UnimplementedError();

  @override
  Future<Uint8List> read(int count) => throw UnimplementedError();

  @override
  Uint8List readSync(int count) => throw UnimplementedError();

  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) async {
    final needed = (end ?? buffer.length) - start;
    final length = await _randomAssessFile.readInto(buffer, start, end);
    if (needed < length) {
      await _randomAssessFile.close();
      final index = _index + 1;
      _randomAssessFile = await _splitFile(index).open(mode: _mode);
      _index = index;

      return length + await readInto(buffer, length, end);
    }
    return length;
  }

  @override
  int readIntoSync(List<int> buffer, [int start = 0, int? end]) {
    final needed = (end ?? buffer.length) - start;
    final length = _randomAssessFile.readIntoSync(buffer, start, end);
    if (needed < length) {
      _randomAssessFile.closeSync();
      final index = _index + 1;
      _randomAssessFile = _splitFile(index).openSync(mode: _mode);
      _index = index;

      return length + readIntoSync(buffer, length, end);
    }
    return length;
  }

  @override
  Future<RandomAccessFile> writeByte(int value) {
    throw UnimplementedError();
  }

  @override
  int writeByteSync(int value) {
    throw UnimplementedError();
  }

  /// 当前写入文件永远是 a.zip, 如果当前写入文件已经写满, 则将 a.zip 重命名为 a.z[index].
  @override
  Future<RandomAccessFile> writeFrom(List<int> buffer,
      [int start = 0, int? end]) {
    throw UnimplementedError();
  }

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {}

  @override
  Future<RandomAccessFile> writeString(String string,
      {Encoding encoding = utf8}) {
    throw UnimplementedError();
  }

  @override
  void writeStringSync(String string, {Encoding encoding = utf8}) {}

  @override
  Future<RandomAccessFile> lock(
          [FileLock mode = FileLock.exclusive, int start = 0, int end = -1]) =>
      throw UnimplementedError();

  @override
  Future<RandomAccessFile> truncate(int length) => throw UnimplementedError();

  @override
  void truncateSync(int length) => throw UnimplementedError();

  @override
  void lockSync(
          [FileLock mode = FileLock.exclusive, int start = 0, int end = -1]) =>
      throw UnimplementedError();

  @override
  Future<RandomAccessFile> unlock([int start = 0, int end = -1]) =>
      throw UnimplementedError();

  @override
  void unlockSync([int start = 0, int end = -1]) => throw UnimplementedError();
}

class SplitFileNaming {
  static const String prefix = 'z';

  SplitFileNaming(this.name) : _pattern = RegExp('^$name\\.$prefix(\\d*)\$');

  final String name;
  final RegExp _pattern;

  String splitName(int index) {
    return '$name.$prefix${index.toString().padLeft(2, '0')}';
  }

  int? index(String splitName) {
    final match = _pattern.firstMatch(splitName);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }
}
