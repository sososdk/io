library;

import 'dart:async';

import 'package:anio/anio.dart';
import 'package:file/file.dart';
import 'package:path/path.dart' as p;

export 'package:file/chroot.dart';
export 'package:file/file.dart';
export 'package:file/local.dart';
export 'package:file/memory.dart';

extension FileSystemShortcuts on FileSystem {
  /// Creates a [Sink] that writes bytes to [path] from beginning to end. If [path] already exists it
  /// will be replaced with the new data.
  Future<Sink> sink(
    String path, {
    FileMode mode = FileMode.write,
    bool recursive = false,
  }) async {
    if (mode != FileMode.write &&
        mode != FileMode.append &&
        mode != FileMode.writeOnly &&
        mode != FileMode.writeOnlyAppend) {
      throw ArgumentError('Invalid file mode for this operation');
    }
    if (recursive) {
      await directory(p.dirname(path)).create(recursive: true);
    }
    return file(path).openWrite(mode: mode).sink();
  }

  /// Creates a sink to write [path], executes [block] to write it, and then closes the sink.
  /// This is a compact way to write a file.
  Future<T> write<T>(
    String path,
    FutureOr<T> Function(BufferedSink sink) block, {
    FileMode mode = FileMode.write,
    bool recursive = false,
  }) {
    return sink(path, mode: mode, recursive: recursive)
        .buffered()
        .then((e) => () async {
              try {
                return await block(e);
              } finally {
                try {
                  await e.close();
                } catch (_) {}
              }
            }());
  }

  /// Creates a source that reads the bytes of [path] from beginning to end.
  Future<Source> source(String path, [int? start, int? end]) async {
    return file(path).openRead(start, end).source();
  }

  /// Creates a source to read [path], executes [block] to read it, and then closes the
  /// source. This is a compact way to read the contents of a file.
  Future<T> read<T>(
      String path, FutureOr<T> Function(BufferedSource source) block,
      [int? start, int? end]) {
    return source(path, start, end).buffered().then((e) async {
      try {
        return await block(e);
      } finally {
        try {
          await e.close();
        } catch (_) {}
      }
    });
  }

  /// Creates a [FileHandle] to handle [path].
  Future<FileHandle> open(
    dynamic path, {
    FileMode mode = FileMode.read,
    bool recursive = false,
  }) async {
    if (recursive) {
      await directory(p.dirname(path)).create(recursive: true);
    }
    return file(path).openHandle(mode: mode);
  }

  Future<Sink> openSink(
    dynamic path, {
    int position = 0,
    bool recursive = false,
  }) {
    return open(path, mode: FileMode.write, recursive: recursive).use((handle) {
      return handle.sink(position);
    });
  }

  Future<Sink> openAppendingSink(
    dynamic path, {
    bool recursive = false,
  }) {
    return open(path, mode: FileMode.write, recursive: recursive).use((handle) {
      return handle.appendingSink();
    });
  }

  Future<Source> openSource(dynamic path, {int position = 0}) {
    return open(path, mode: FileMode.read, recursive: false).use((handle) {
      return handle.source(position);
    });
  }

  /// Returns a reference to a [FileSystemEntity] at [path].
  Future<FileSystemEntity?> entity(String path) async {
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

  /// Synchronously returns a reference to a [FileSystemEntity] at [path].
  FileSystemEntity? entitySync(String path) {
    final type = typeSync(path, followLinks: false);
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

  /// Creates the directory if it doesn't exist.
  ///
  /// If [recursive] is false, only the last directory in the path is
  /// created. If [recursive] is true, all non-existing path components
  /// are created. If the directory already exists nothing is done.
  ///
  /// Returns a `Future<Directory>` that completes with this
  /// directory once it has been created. If the directory cannot be
  /// created the future completes with an exception.
  Future<Directory> createDirectory(dynamic path, {bool recursive = false}) {
    return directory(path).create(recursive: recursive);
  }

  /// Synchronously creates the directory if it doesn't exist.
  ///
  /// If [recursive] is false, only the last directory in the path is
  /// created. If [recursive] is true, all non-existing path components
  /// are created. If the directory already exists nothing is done.
  ///
  /// If the directory cannot be created an exception is thrown.
  void createDirectorySync({bool recursive = false}) {
    directory(path).createSync(recursive: recursive);
  }

  /// Creates a symbolic link in the file system.
  Future<Link> createLink(dynamic path, {bool recursive = false}) {
    return link(path).create(path, recursive: recursive);
  }

  /// Creates a symbolic link in the file system.
  void createLinkSync(dynamic path, {bool recursive = false}) {
    link(path).createSync(path, recursive: recursive);
  }

  /// Checks whether the file system entity with this [path] exists.
  Future<bool> exists(String path) => type(path, followLinks: false)
      .then((e) => e != FileSystemEntityType.notFound);

  /// Synchronously checks whether the file system entity with this [path]
  /// exists.
  bool existsSync(String path) =>
      typeSync(path, followLinks: false) != FileSystemEntityType.notFound;

  /// Deletes the [FileSystemEntity] reference by [path].
  Future<void> delete(String path, {bool mustExist = false}) =>
      entity(path).then((e) async {
        if (e == null) {
          if (mustExist) {
            throw FileSystemException('No such file or directory', path);
          } else {
            return;
          }
        }
        await e.delete(recursive: true);
      });

  /// Synchronously deletes the [FileSystemEntity] reference by [path].
  void deleteSync(String path, {bool mustExist = false}) {
    final e = entitySync(path);
    if (e == null) {
      if (mustExist) {
        throw FileSystemException('No such file or directory', path);
      } else {
        return;
      }
    }
    e.deleteSync(recursive: true);
  }

  /// Moves [source] to [target] in-place if the underlying file system supports it. If [target]
  /// exists, it is first removed. If `source == target`, this operation does nothing. This may be
  /// used to move a file or a directory.
  ///
  /// **Only as Atomic as the Underlying File System Supports**
  ///
  /// FAT and NTFS file systems cannot atomically move a file over an existing file. If the target
  /// file already exists, the move is performed into two steps:
  ///
  ///  1. Atomically delete the target file.
  ///  2. Atomically rename the source file to the target file.
  ///
  /// The delete step and move step are each atomic but not atomic in aggregate! If this process
  /// crashes, the host operating system crashes, or the hardware fails it is possible that the
  /// delete step will succeed and the rename will not.
  ///
  /// **Entire-file or nothing**
  ///
  /// These are the possible results of this operation:
  ///
  ///  * This operation returns normally, the source file is absent, and the target file contains the
  ///    data previously held by the source file. This is the success case.
  ///
  ///  * The operation throws an exception and the file system is unchanged. For example, this
  ///    occurs if this process lacks permissions to perform the move.
  ///
  ///  * This operation throws an exception, the target file is deleted, but the source file is
  ///    unchanged. This is the partial failure case described above and is only possible on
  ///    file systems like FAT and NTFS that do not support atomic file replacement. Typically in
  ///    such cases this operation won't return at all because the process or operating system has
  ///    also crashed.
  ///
  /// There is no failure mode where the target file holds a subset of the bytes of the source file.
  /// If the rename step cannot be performed atomically, this function will throw an [IOException]
  /// before attempting a move. Typically this occurs if the source and target files are on different
  /// physical volumes.
  ///
  /// **Non-Atomic Moves**
  ///
  /// If you need to move files across volumes, use [copy] followed by [delete], and change your
  /// application logic to recover should the copy step suffer a partial failure.
  Future<void> atomicMove(String source, String target) {
    return entity(source).then((e) async {
      if (e == null) {
        throw FileSystemException('No such file or directory', source);
      }
      await directory(p.dirname(target)).create(recursive: true);
      await e.rename(target);
    });
  }

  Future<FileSystemEntity> copy(
    String source,
    String target, {
    bool followLinks = true,
  }) {
    return entity(source).then((e) async {
      if (e is File) {
        await directory(p.dirname(target)).create(recursive: true);
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
        final stream = e.list(recursive: true, followLinks: followLinks);
        await for (final sub in stream) {
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
  }

  /// Returns true if file streams can be manipulated independently of their
  /// paths. This is typically true for systems like Mac, Unix, and Linux that
  /// use inodes in their file system interface. It is typically false on
  /// Windows.
  ///
  /// If this returns false we won't permit simultaneous reads and writes. When
  /// writes commit we need to delete the previous snapshots, and that won't
  /// succeed if the file is open. (We do permit multiple simultaneous reads.)
  Future<bool> isCivilized(String path) =>
      openSink(path, recursive: true).then((e) async {
        try {
          await delete(path);
          return true;
        } catch (_) {
        } finally {
          try {
            await e.close();
          } catch (_) {}
        }
        return false;
      }).whenComplete(() async {
        await delete(path, mustExist: false);
      });
}

extension FileSystemEntityShortcuts on FileSystemEntity {
  String get absolutePath => isAbsolute ? path : absolute.path;
}
