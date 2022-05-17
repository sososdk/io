import 'dart:async';

import 'package:file_system/file_system.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart';

import 'lock.dart';
import 'logger.dart';
import 'lru_map.dart';

/// A cache that uses a bounded amount of space on a filesystem. Each cache
/// entry has a string key and a fixed number of values. Each key must match
/// the regex '^[a-z0-9_-]{1,120}$'. Values are byte sequences, accessible as
/// streams or files.
///
/// The cache stores its data in a directory on the filesystem. This directory
/// must be exclusive to the cache; the cache may delete or overwrite files from
/// its directory. It is an error for multiple processes to use the same cache
/// directory at the same time.
///
/// This cache limits the number of bytes that it will store on the filesystem.
/// When the number of stored bytes exceeds the limit, the cache will remove
/// entries in the background until the limit is satisfied. The limit is not
/// strict: the cache may temporarily exceed it while waiting for files to be
/// deleted. The limit does not include filesystem overhead or the cache journal
/// so space-sensitive applications should set a conservative limit.
///
/// Clients call [edit] to create or update the values of an entry. An entry may
/// have only one editor at one time; if a value is not available to be edited
/// then [edit] will return null.
/// * When an entry is being **created** it is necessary to supply a full set of
/// values; the empty value should be used as a placeholder if necessary.
/// * When an entry is being edited, it is not necessary to supply data for
/// every value; values default to their previous value.
///
/// Every [edit] call must be matched by a call to [Editor.commit] or
/// [Editor.abort]. Committing is atomic: a read observes the full set of values
/// as they were before or after the commit, but never a mix of values.
///
/// Clients call [get] to read a snapshot of an entry. The read will observe the
/// value at the time that [get] was called. Updates and removals after the call
/// do not impact ongoing reads.
///
/// This class is tolerant of some I/O errors. If files are missing from the
/// filesystem, the corresponding entries will be dropped from the cache. If an
/// error occurs while writing a cache value, the edit will fail silently.
class DiskLruCache {
  /// 操作的记录文件名
  static const _kJournalFile = 'journal';

  /// 操作的记录临时文件名
  static const _kJournalFileTmp = 'journal.tmp';

  /// 操作的记录备份文件名
  static const _kJournalFileBackup = 'journal.bkp';

  /// 标识
  static const _kMagic = 'so.io.DiskLruCache';

  /// 版本
  static const _kVersion = "1";

  /// 记录的操作行为符
  static const _kRead = 'READ';
  static const _kDirty = 'DIRTY';
  static const _kClean = 'CLEAN';
  static const _kRemove = 'REMOVE';

  static const _kStringKeyPattern = r'^[a-z0-9_-]{1,120}$';

  final _lock = Lock();

  final _lruEntries = LruMap<String, Entry>();

  final RegExp _legalKeyPattern = RegExp(_kStringKeyPattern);

  /// Returns the directory where this cache stores its data.
  final String directory;

  final FileSystem fileSystem;

  final int appVersion;

  final int valueCount;

  // This cache uses a journal file named "journal". A typical journal file looks like this:
  //
  //     so.io.DiskLruCache
  //     1
  //     100
  //     2
  //
  //     CLEAN 3400330d1dfc7f3f7f4b8d4d803dfcf6 832 21054
  //     DIRTY 335c4c6028171cfddfbaae1a9c313c52
  //     CLEAN 335c4c6028171cfddfbaae1a9c313c52 3934 2342
  //     REMOVE 335c4c6028171cfddfbaae1a9c313c52
  //     DIRTY 1ab96a171faeeee38496d8b330771a7a
  //     CLEAN 1ab96a171faeeee38496d8b330771a7a 1600 234
  //     READ 335c4c6028171cfddfbaae1a9c313c52
  //     READ 3400330d1dfc7f3f7f4b8d4d803dfcf6
  //
  // The first five lines of the journal form its header. They are the constant string
  // "so.io.DiskLruCache", the disk cache's version, the application's version, the value
  // count, and a blank line.
  //
  // Each of the subsequent lines in the file is a record of the state of a cache entry. Each line
  // contains space-separated values: a state, a key, and optional state-specific values.
  //
  //   o DIRTY lines track that an entry is actively being created or updated. Every successful
  //     DIRTY action should be followed by a CLEAN or REMOVE action. DIRTY lines without a matching
  //     CLEAN or REMOVE indicate that temporary files may need to be deleted.
  //
  //   o CLEAN lines track a cache entry that has been successfully published and may be read. A
  //     publish line is followed by the lengths of each of its values.
  //
  //   o READ lines track accesses for LRU.
  //
  //   o REMOVE lines track entries that have been deleted.
  //
  // The journal file is appended to as cache operations occur. The journal may occasionally be
  // compacted by dropping redundant lines. A temporary file named "journal.tmp" will be used during
  // compaction; that file should be deleted if it exists when the cache is opened.
  final String journalFile;

  final String journalFileTmp;

  final String journalFileBackup;

  int? _maxSize;

  int _size = 0;

  BufferedSink? _journalWriter;

  int _redundantOpCount = 0;
  bool _hasJournalErrors = false;
  bool _civilizedFileSystem = false;

  // Must be read and written when synchronized on 'this'.
  bool _initialized = false;
  bool _closed = false;
  bool _mostRecentTrimFailed = false;
  bool _mostRecentRebuildFailed = false;

  /// To differentiate between old and current snapshots, each entry is given a
  /// sequence number each time an edit is committed. A snapshot is stale if its
  /// sequence number is not equal to its entry's sequence number.
  int _nextSequenceNumber = 0;

  DiskLruCache(
    this.fileSystem,
    this.directory, {
    this.appVersion = 1,
    this.valueCount = 1,
    int? maxSize,
  })  : assert(valueCount > 0),
        assert(maxSize == null || maxSize > 0),
        _maxSize = maxSize,
        journalFile = join(directory, _kJournalFile),
        journalFileTmp = join(directory, _kJournalFileTmp),
        journalFileBackup = join(directory, _kJournalFileBackup);

  /// The maximum number of bytes that this cache should use to store its data.
  Future<int?> get maxSize => _lock.synchronized(() => _maxSize);

  /// Changes the maximum number of bytes the cache can store and queues a job
  /// to trim the existing store, if necessary.
  Future<void> setMaxSize(int? maxSize) => _lock.synchronized(() {
        _maxSize = maxSize;
        if (_initialized) {
          _cleanup();
        }
      });

  Future<void> _cleanup() => _lock.synchronized(() async {
        if (!_initialized || _closed) {
          return; // Nothing to do.
        }

        await _trimToSize().catchError((_) {
          _mostRecentTrimFailed = true;
        });

        try {
          if (_journalRebuildRequired()) {
            await _rebuildJournal();
            _redundantOpCount = 0;
          }
        } catch (e) {
          _mostRecentRebuildFailed = true;
          _journalWriter = BlackHoleSink().buffer();
        }
      });

  Future<void> initialize() => _lock.synchronized(() => _initialize());

  Future<void> _initialize() async {
    _assertLock();

    if (_initialized) {
      return; // Already initialized.
    }

    // If a bkp file exists, use it instead.
    if (await fileSystem.exists(journalFileBackup)) {
      // If journal file also exists just delete backup file.
      if (await fileSystem.exists(journalFile)) {
        await fileSystem.delete(journalFileBackup);
      } else {
        await fileSystem.atomicMove(journalFileBackup, journalFile);
      }
    }

    _civilizedFileSystem = await fileSystem.isCivilized(journalFileBackup);

    // Prefer to pick up where we left off.
    if (await fileSystem.exists(journalFile)) {
      try {
        await _readJournal();
        await _processJournal();
        _initialized = true;
        return;
      } catch (e, s) {
        logger.warning('DiskLruCache $directory is corrupted, removing', e, s);
      }

      // The cache is corrupted, attempt to delete the contents of the directory. This can throw and
      // we'll let that propagate out as it likely means there is a severe filesystem problem.
      await _delete();
    }

    await _rebuildJournal();
    _initialized = true;
  }

  Future<void> _readJournal() {
    _assertLock();

    return fileSystem.read(journalFile, (source) async {
      final magic = await source.readLineStrict();
      final version = await source.readLineStrict();
      final appVersionString = await source.readLineStrict();
      final valueCountString = await source.readLineStrict();
      final blank = await source.readLineStrict();
      if (_kMagic != magic ||
          _kVersion != version ||
          appVersion.toString() != appVersionString ||
          valueCount.toString() != valueCountString ||
          blank.isNotEmpty) {
        throw Exception(
            'unexpected journal header: [$magic, $version, $valueCountString, $blank]');
      }

      var lineCount = 0;
      while (true) {
        try {
          _readJournalLine(await source.readLineStrict());
          lineCount++;
        } on EOFException {
          break; // End of journal.
        }
      }
      _redundantOpCount = lineCount - _lruEntries.length;

      // If we ended on a truncated line, rebuild the journal before appending to it.
      if (!await source.exhausted()) {
        await _rebuildJournal();
      } else {
        _journalWriter = await _newJournalWriter();
      }
    });
  }

  Future<BufferedSink> _newJournalWriter() async {
    final fileSink = await fileSystem.sink(journalFile, mode: FileMode.append);
    final faultHidingSink = FaultHidingSink(fileSink, () {
      _assertLock();
      _hasJournalErrors = true;
    });
    return faultHidingSink.buffer();
  }

  void _readJournalLine(String line) {
    final firstSpace = line.indexOf(' ');
    if (firstSpace == -1) throw Exception('unexpected journal line: $line');

    final keyBegin = firstSpace + 1;
    final secondSpace = line.indexOf(' ', keyBegin);
    final String key;
    if (secondSpace == -1) {
      key = line.substring(keyBegin);
      if (firstSpace == _kRemove.length && line.startsWith(_kRemove)) {
        _lruEntries.remove(key);
        return;
      }
    } else {
      key = line.substring(keyBegin, secondSpace);
    }

    final entry = _lruEntries.putIfAbsent(key, () => Entry(key, this));
    if (secondSpace != -1 &&
        firstSpace == _kClean.length &&
        line.startsWith(_kClean)) {
      final parts = line.substring(secondSpace + 1).split(' ');
      entry.readable = true;
      entry.currentEditor = null;
      entry.setLengths(parts);
    } else if (secondSpace == -1 &&
        firstSpace == _kDirty.length &&
        line.startsWith(_kDirty)) {
      entry.currentEditor = Editor._(this, entry);
    } else if (secondSpace == -1 &&
        firstSpace == _kRead.length &&
        line.startsWith(_kRead)) {
      // This work was already done by calling _lruEntries.get().
    } else {
      throw Exception('unexpected journal line: $line');
    }
  }

  /// Computes the initial size and collects garbage as a part of opening the
  /// cache. Dirty entries are assumed to be inconsistent and will be deleted.
  Future<void> _processJournal() async {
    await fileSystem.deleteIfExists(journalFileTmp);
    final toRemove = <Entry>[];
    for (final entry in _lruEntries.values) {
      if (entry.currentEditor == null) {
        for (var t = 0; t < valueCount; t++) {
          _size += entry.lengths[t];
        }
      } else {
        entry.currentEditor = null;
        for (var t = 0; t < valueCount; t++) {
          await fileSystem.deleteIfExists(entry.getCleanFile(t));
          await fileSystem.deleteIfExists(entry.getDirtyFile(t));
        }
        toRemove.add(entry);
      }
    }
    _lruEntries.removeWhere((key, value) => toRemove.contains(value));
  }

  /// Creates a new journal that omits redundant information. This replaces the
  /// current journal if it exists.
  Future<void> _rebuildJournal() async {
    _assertLock();
    await _journalWriter?.close();
    await fileSystem.write(journalFileTmp, (sink) async {
      await sink.writeLine(_kMagic);
      await sink.writeLine(_kVersion);
      await sink.writeLine('$appVersion');
      await sink.writeLine('$valueCount');
      await sink.writeLine();
      for (final entry in _lruEntries.values) {
        if (entry.currentEditor != null) {
          await sink.writeLine('$_kDirty ${entry.key}');
        } else {
          await sink.writeLine('$_kClean ${entry.key} ${entry.getLengths()}');
        }
      }
    });

    if (await fileSystem.exists(journalFile)) {
      await fileSystem.atomicMove(journalFile, journalFileBackup);
      await fileSystem.atomicMove(journalFileTmp, journalFile);
      await fileSystem.deleteIfExists(journalFileBackup);
    } else {
      await fileSystem.atomicMove(journalFileTmp, journalFile);
    }
    _journalWriter = await _newJournalWriter();
    _hasJournalErrors = false;
    _mostRecentRebuildFailed = false;
  }

  /// Returns a snapshot of the entry named [key], or null if it doesn't  exist
  /// is not currently readable. If a value is returned, it is moved to the head
  /// of the LRU queue.
  Future<Snapshot?> get(String key) => _lock.synchronized(() async {
        await _initialize();

        _checkNotClosed();
        _validateKey(key);
        final entry = _lruEntries[key];
        if (entry == null) return null;
        final snapshot = await entry.snapshot();
        if (snapshot == null) return null;

        _redundantOpCount++;
        await _journalWriter!.writeLine('$_kRead $key');
        if (_journalRebuildRequired()) {
          _cleanup();
        }

        return snapshot;
      });

  /// Returns an editor for the entry named [key], or null if another
  /// edit is in progress.
  Future<Editor?> edit(String key, [int? expectedSequenceNumber]) =>
      _lock.synchronized(() async {
        await _initialize();

        _checkNotClosed();
        _validateKey(key);
        var entry = _lruEntries[key];
        if (expectedSequenceNumber != null &&
            (entry == null || entry.sequenceNumber != expectedSequenceNumber)) {
          return null; // Snapshot is stale.
        }

        if (entry?.currentEditor != null) {
          return null; // Another edit is in progress.
        }

        if (entry != null && entry.lockingSourceCount != 0) {
          return null; // We can't write this file because a reader is still reading it.
        }

        if (_mostRecentTrimFailed || _mostRecentRebuildFailed) {
          // The OS has become our enemy! If the trim job failed, it means we are storing more data than
          // requested by the user. Do not allow edits so we do not go over that limit any further. If
          // the journal rebuild failed, the journal writer will not be active, meaning we will not be
          // able to record the edit, causing file leaks. In both cases, we want to retry the clean up
          // so we can get out of this state!
          _cleanup();
          return null;
        }

        // Flush the journal before creating files to prevent file leaks.
        await _journalWriter!.writeLine('$_kDirty $key');
        await _journalWriter!.flush();

        if (_hasJournalErrors) {
          return null; // Don't edit; the journal can't be written.
        }

        entry = _lruEntries.putIfAbsent(key, () => Entry(key, this));
        final editor = Editor._(this, entry);
        entry.currentEditor = editor;
        return editor;
      });

  /// Returns the number of bytes currently being used to store the values in
  /// this cache. This may be greater than the max size if a background deletion
  /// is pending.
  Future<int> get size =>
      _lock.synchronized(() => _initialize().then((value) => _size));

  Future<void> _completeEdit(Editor editor, bool success) async {
    _assertLock();

    final entry = editor._entry;
    if (entry.currentEditor != editor) throw StateError('invalid editor');

    // If this edit is creating the entry for the first time, every index must have a value.
    if (success && !entry.readable) {
      for (var i = 0; i < valueCount; i++) {
        if (!editor._written![i]) {
          // Newly created entry didn't create value.
          await _completeEdit(editor, false);
          throw StateError(
              "Newly created entry didn't create value for index $i");
        }
        if (!await fileSystem.exists(entry.getDirtyFile(i))) {
          await _completeEdit(editor, false);
          return;
        }
      }
    }

    for (var i = 0; i < valueCount; i++) {
      final dirty = entry.getDirtyFile(i);
      if (success && !entry.zombie) {
        if (await fileSystem.exists(dirty)) {
          final clean = entry.getCleanFile(i);
          await fileSystem.atomicMove(dirty, clean);
          final oldLength = entry.lengths[i];
          final newLength = await fileSystem
              .stat(clean)
              .then((e) => e.type == FileSystemEntityType.file ? e.size : 0);
          entry.lengths[i] = newLength;
          _size += -oldLength + newLength;
        }
      } else {
        await fileSystem.deleteIfExists(dirty);
      }
    }

    entry.currentEditor = null;
    if (entry.zombie) {
      await _removeEntry(entry);
      return;
    }

    _redundantOpCount++;
    if (entry.readable || success) {
      entry.readable = true;
      await _journalWriter!
          .writeLine('$_kClean ${entry.key} ${entry.getLengths()}');
      if (success) {
        entry.sequenceNumber = _nextSequenceNumber++;
      }
    } else {
      _lruEntries.remove(entry.key);
      await _journalWriter!.writeLine('$_kRemove ${entry.key}');
    }
    await _journalWriter!.flush();

    if ((_maxSize != null && _size > _maxSize!) || _journalRebuildRequired()) {
      _cleanup();
    }
  }

  /// We only rebuild the journal when it will halve the size of the journal
  /// and eliminate at least 2000 ops.
  bool _journalRebuildRequired() {
    _assertLock();
    const redundantOpCompactThreshold = 2000;
    return _redundantOpCount >= redundantOpCompactThreshold &&
        _redundantOpCount >= _lruEntries.length;
  }

  /// Drops the entry for [key] if it exists and can be removed. If the entry
  /// for [key] is currently being edited, that edit will complete normally but
  /// its value will not be stored.
  Future<bool> remove(String key) => _lock.synchronized(() async {
        await _initialize();

        _checkNotClosed();
        _validateKey(key);
        final entry = _lruEntries[key];
        if (entry == null) return false;
        final removed = await _removeEntry(entry);
        if (removed) {
          _mostRecentTrimFailed = false;
        }
        return removed;
      });

  Future<bool> _removeEntry(Entry entry) async {
    _assertLock();

    // If we can't delete files that are still open, mark this entry as a zombie
    // so its files will be deleted when those files are closed.
    if (!_civilizedFileSystem) {
      if (entry.lockingSourceCount > 0) {
        // Mark this entry as 'DIRTY' so that if the process crashes this entry won't be used.
        await _journalWriter?.writeLine('$_kDirty ${entry.key}');
        await _journalWriter?.flush();
      }
      if (entry.lockingSourceCount > 0 || entry.currentEditor != null) {
        entry.zombie = true;
        return true;
      }
    }

    // Prevent the edit from completing normally.
    await entry.currentEditor?._detach();

    for (var i = 0; i < valueCount; i++) {
      await fileSystem.deleteIfExists(entry.getCleanFile(i));
      _size -= entry.lengths[i];
      entry.lengths[i] = 0;
    }

    _redundantOpCount++;
    await _journalWriter?.writeLine('$_kRemove ${entry.key}');
    _lruEntries.remove(entry.key);

    if (_journalRebuildRequired()) {
      _cleanup();
    }
    return true;
  }

  /// Force buffered operations to the filesystem.
  Future<void> flush() => _lock.synchronized(() async {
        if (!_initialized) return;

        _checkNotClosed();
        await _trimToSize();
        await _journalWriter!.flush();
      });

  /// Returns true if this cache has been closed.
  Future<bool> isClosed() => _lock.synchronized(() => _closed);

  /// Closes this cache. Stored values will remain on the filesystem.
  Future<void> close() => _lock.synchronized(() async {
        if (!_initialized || _closed) {
          _closed = true;
          return;
        }

        // Copying for concurrent iteration.
        for (final entry in _lruEntries.values) {
          // Prevent the edit from completing normally.
          await entry.currentEditor?._detach();
        }
        await _trimToSize();
        await _journalWriter!.close();
        _journalWriter = null;
        _closed = true;
      });

  Future<void> _trimToSize() async {
    _assertLock();

    while (_maxSize != null && _size > _maxSize!) {
      if (!await _removeOldestEntry()) return;
    }
    _mostRecentTrimFailed = false;
  }

  /// Returns true if an entry was removed. This will return false if all
  /// entries are zombies.
  Future<bool> _removeOldestEntry() async {
    for (final toEvict in _lruEntries.values) {
      if (!toEvict.zombie) {
        await _removeEntry(toEvict);
        return true;
      }
    }
    return false;
  }

  /// Closes the cache and deletes all of its stored values. This will delete
  /// all files in the cache directory including files that weren't created by
  /// the cache.
  Future<void> delete() =>
      _lock.synchronized(() => _delete().then((value) => _closed = true));

  Future<void> _delete() async {
    _assertLock();

    for (final entry in _lruEntries.values) {
      // Prevent the edit from completing normally.
      await entry.currentEditor?._detach();
    }
    _lruEntries.clear();

    await _journalWriter?.close();
    _journalWriter = null;

    await fileSystem.deleteIfExists(directory);

    _size = 0;
    _redundantOpCount = 0;
    _nextSequenceNumber = 0;
  }

  /// Deletes all stored values from the cache. In-flight edits will complete
  /// normally but their values will not be stored.
  Future<void> evictAll() => _lock.synchronized(() async {
        await _initialize();

        // Copying for concurrent iteration.
        for (final entry in _lruEntries.values) {
          await _removeEntry(entry);
        }
        _mostRecentTrimFailed = false;
      });

  void _assertLock() {
    assert(_lock.inLock);
  }

  void _checkNotClosed() {
    if (_closed) throw StateError('cache is closed');
  }

  void _validateKey(String key) {
    if (!_legalKeyPattern.hasMatch(key)) {
      throw ArgumentError('keys must match regex $_kStringKeyPattern: "$key"');
    }
  }

  @visibleForTesting
  Future<void> emulateWindows() =>
      initialize().then((value) => _civilizedFileSystem = false);

  @visibleForTesting
  Future<int> redundantOpCount() => _lock.synchronized(() => _redundantOpCount);

  @visibleForTesting
  Future<void> hasJournalErrors(bool hasErrors) =>
      _lock.synchronized(() => _hasJournalErrors = hasErrors);
}

/// A snapshot of the values for an entry.
class Snapshot {
  final DiskLruCache _cache;
  final String key;
  final int sequenceNumber;
  final List<Source> sources;
  final List<int> lengths;

  Snapshot._(
    this._cache,
    this.key,
    this.sequenceNumber,
    this.sources,
    this.lengths,
  );

  /// Returns an editor for this snapshot's entry, or null if either the entry
  /// has changed since this snapshot was created or if another edit is in
  /// progress.
  Future<Editor?> edit() => _cache.edit(key, sequenceNumber);

  /// Returns the unbuffered reader with the value for [index].
  Source getSource(int index) => sources[index];

  /// Returns the byte length of the value for [index].
  int getLength(int index) => lengths[index];

  Future<void> close() async {
    for (final source in sources) {
      try {
        await source.close();
      } catch (_) {}
    }
  }
}

/// Edits the values for an entry.
class Editor {
  final DiskLruCache _cache;
  final Entry _entry;
  final List<bool>? _written;
  bool _done = false;

  Editor._(this._cache, this._entry)
      : _written = _entry.readable
            ? null
            : List.filled(_cache.valueCount, false, growable: false);

  /// Prevents this editor from completing normally. This is necessary either
  /// when the edit causes an I/O error, or if the target entry is evicted while
  /// this editor is active. In either case we delete the editor's created files
  /// and prevent new files from being created. Note that once an editor has
  /// been detached it is possible for another editor to edit the entry.
  Future<void> _detach() async {
    _cache._assertLock();

    if (_entry.currentEditor == this) {
      if (_cache._civilizedFileSystem) {
        await _cache._completeEdit(this, false); // Delete it now.
      } else {
        // We can't delete it until the current edit completes.
        _entry.zombie = true;
      }
    }
  }

  /// Returns an unbuffered input stream to read the last committed value, or
  /// null if no value has been committed.
  Future<Source?> newSource(int index) {
    return _cache._lock.synchronized(() async {
      if (_done) throw StateError('editor was done');
      if (!_entry.readable || _entry.currentEditor != this || _entry.zombie) {
        return null;
      }
      try {
        return await _cache.fileSystem.source(_entry.getCleanFile(index));
      } on FileSystemException {
        return null;
      }
    });
  }

  /// Returns a new unbuffered output stream to write the value at [index]. If
  /// the underlying output stream encounters errors when writing to the
  /// filesystem, this edit will be aborted when [commit] is called.
  Future<Sink> newSink(int index) {
    return _cache._lock.synchronized(() async {
      if (_done) throw StateError('editor was done');
      if (_entry.currentEditor != this) {
        return BlackHoleSink();
      }
      if (!_entry.readable) {
        _written![index] = true;
      }
      final dirtyFile = _entry.getDirtyFile(index);
      final Sink sink;
      try {
        sink = await _cache.fileSystem.sink(dirtyFile);
      } on FileSystemException {
        return BlackHoleSink();
      }
      return FaultHidingSink(
        sink,
        () => _cache._lock.synchronized(() => _detach()),
      );
    });
  }

  /// Commits this edit so it is visible to readers. This releases the edit lock
  /// so another edit may be started on the same key.
  Future<void> commit() => _cache._lock.synchronized(() async {
        if (_done) throw StateError('editor was done');
        if (_entry.currentEditor == this) {
          try {
            await _cache._completeEdit(this, true);
          } finally {
            _done = true;
          }
        } else {
          _done = true;
        }
      });

  /// Aborts this edit. This releases the edit lock so another edit may be
  /// started on the same key.
  Future<void> abort() => _cache._lock.synchronized(() async {
        if (_done) throw StateError('editor was done');
        if (_entry.currentEditor == this) {
          try {
            await _cache._completeEdit(this, false);
          } finally {
            _done = true;
          }
        } else {
          _done = true;
        }
      });
}

/// Cache information of one file.
class Entry {
  Entry(this.key, this._cache) {
    lengths = List.generate(valueCount, (index) => 0, growable: false);
  }

  /// The key used to identify the object in the cache.
  final String key;

  final DiskLruCache _cache;

  FileSystem get fileSystem => _cache.fileSystem;

  String get directory => _cache.directory;

  int get valueCount => _cache.valueCount;

  /// True if this entry has ever been published.
  bool readable = false;

  /// True if this entry must be deleted when the current edit or read completes.
  bool zombie = false;

  /// The ongoing edit or null if this entry is not being edited.
  Editor? currentEditor;

  /// Sources currently reading this entry before a write or delete can proceed. When decrementing
  /// this to zero, the entry must be removed if it is a zombie.
  int lockingSourceCount = 0;

  /// The sequence number of the most recently committed edit to this entry.
  int sequenceNumber = 0;

  /// Lengths of this entry's files.
  late List<int> lengths;

  String getLengths() => lengths.join(' ');

  /// Set lengths using decimal numbers like "10123".
  void setLengths(List<String> strings) {
    if (strings.length != valueCount) {
      throw ArgumentError('unexpected journal line: $strings');
    }

    try {
      for (var i = 0; i < strings.length; i++) {
        lengths[i] = int.parse(strings[i]);
      }
    } on FormatException {
      throw ArgumentError('unexpected journal line: $strings');
    }
  }

  String getCleanFile(int i) => join(directory, '$key.$i');

  String getDirtyFile(int i) => join(directory, '$key.$i.tmp');

  /// Returns a snapshot of this entry. This opens all streams eagerly to
  /// guarantee that we see a single published snapshot. If we opened streams
  /// lazily then the streams could come from different edits.
  Future<Snapshot?> snapshot() async {
    _cache._assertLock();

    if (!readable) return null;
    if (!_cache._civilizedFileSystem && (currentEditor != null || zombie)) {
      return null;
    }

    final sources = <Source>[];
    final lengths = List.of(this.lengths, growable: false);
    try {
      for (var i = 0; i < valueCount; i++) {
        sources.add(await _newSource(i));
      }
      return Snapshot._(_cache, key, sequenceNumber, sources, lengths);
    } on FileSystemException {
      // A file must have been deleted manually!
      for (final source in sources) {
        try {
          await source.close();
        } catch (_) {}
      }
      // Since the entry is no longer valid, remove it so the metadata is
      // accurate (i.e. the cache size.)
      try {
        await _cache._removeEntry(this);
      } catch (_) {}
      return null;
    }
  }

  Future<Source> _newSource(int index) async {
    final source = await fileSystem.source(getCleanFile(index));
    if (_cache._civilizedFileSystem) return source;

    lockingSourceCount++;
    return _Source(
        source,
        () => _cache._lock.synchronized(() async {
              lockingSourceCount--;
              if (lockingSourceCount == 0 && zombie) {
                await _cache._removeEntry(this);
              }
            }));
  }
}

class _Source extends ForwardingSource {
  final Future<void> Function() onClose;
  bool _closed = false;

  _Source(Source delegate, this.onClose) : super(delegate);

  @override
  Future close() async {
    if (!_closed) {
      _closed = true;
      await delegate.close();
      await onClose();
    }
  }
}
