import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:path/path.dart' as p;

import 'source.dart';

export 'package:file/file.dart';

extension FileSystemShortcuts on FileSystem {
  Future<IOSink> sink(
    String path, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
  }) =>
      file(path)
          .create(recursive: true)
          .then((e) => e.openWrite(mode: mode, encoding: encoding));

  Future<T> write<T>(String path, FutureOr<T> Function(IOSink sink) block,
          {Encoding encoding = utf8}) =>
      sink(path, mode: FileMode.write, encoding: encoding).then((e) async {
        try {
          return await block(e);
        } finally {
          await e.close().catchError((_) {});
        }
      });

  Future<Source> source(String path) => file(path).source();

  Future<T> read<T>(String path, FutureOr<T> Function(Source source) block) =>
      source(path).then((e) async {
        try {
          return await block(e);
        } finally {
          await e.close().catchError((_) {});
        }
      });

  Future<bool> exists(String path) => type(path, followLinks: false)
      .then((value) => value != FileSystemEntityType.notFound);

  bool existsSync(String path) =>
      typeSync(path, followLinks: false) != FileSystemEntityType.notFound;

  Future<FileSystemEntity?> getEntity(String path) async {
    final type = await this.type(path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      return file(path);
    } else if (type == FileSystemEntityType.directory) {
      return directory(path);
    } else if (type == FileSystemEntityType.link) {
      return link(path);
    } else {
      return null;
    }
  }

  Future<void> delete(String path, {bool mustExist = true}) =>
      getEntity(path).then((e) async {
        if (e == null) {
          if (mustExist) {
            throw FileSystemException('No such file or directory', path);
          } else {
            return;
          }
        }
        await e.delete(recursive: true);
      });

  Future<void> deleteIfExists(String path) => delete(path, mustExist: false);

  Future<void> atomicMove(String source, String target) =>
      getEntity(source).then((e) async {
        if (e == null) {
          throw FileSystemException('No such file or directory', source);
        }
        await directory(p.dirname(target)).create(recursive: true);
        await e.rename(target);
      });

  Future<FileSystemEntity> copy(String source, String target) =>
      getEntity(source).then((e) async {
        if (e is File) {
          return e.copy(target);
        } else if (e is Directory) {
          if (p.canonicalize(source) == p.canonicalize(target)) {
            return e;
          }
          if (p.isWithin(source, target)) {
            throw ArgumentError('Cannot copy $source to $target');
          }
          final dir = directory(target);
          await dir.create(recursive: true);
          await for (final sub in e.list(recursive: true, followLinks: false)) {
            final copyTo = p.join(target, p.relative(sub.path, from: source));
            if (sub is Directory) {
              await directory(copyTo).create(recursive: true);
            } else if (sub is File) {
              await file(sub.path).copy(copyTo);
            } else if (sub is Link) {
              await link(copyTo).create(await sub.target(), recursive: true);
            }
          }
          return dir;
        } else if (e is Link) {
          return link(target).create(await e.target(), recursive: true);
        } else {
          throw FileSystemException('No such file or directory', source);
        }
      });

  /// Returns true if file streams can be manipulated independently of their
  /// paths. This is typically true for systems like Mac, Unix, and Linux that
  /// use inodes in their file system interface. It is typically false on
  /// Windows.
  ///
  /// If this returns false we won't permit simultaneous reads and writes. When
  /// writes commit we need to delete the previous snapshots, and that won't
  /// succeed if the file is open. (We do permit multiple simultaneous reads.)
  Future<bool> isCivilized(String path) => sink(path).then((e) async {
        try {
          await delete(path);
          return true;
        } catch (_) {
        } finally {
          await e.close().catchError((_) {});
        }
        return false;
      }).whenComplete(() async {
        await delete(path, mustExist: false);
      });
}

extension FileSystemEntityShortcuts on FileSystemEntity {
  String get absolutePath => isAbsolute ? path : absolute.path;
}

extension FileShortcuts on File {
  Future<Source> source() => open().then((value) => _FileSource(value));
}

class _FileSource extends Source {
  final RandomAccessFile file;

  _FileSource(this.file);

  @override
  Future<Uint8List> read(int count) => file.read(count);

  @override
  Future close() => file.close();
}
