import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:anio/anio.dart';
import 'package:disk_cache/disk_cache.dart';
import 'package:file_system/file_system.dart';
import 'package:test/test.dart';

Future<void> main() async {
  const magic = 'so.io.DiskCache';
  const version = 1;
  const appVersion = 1;
  const valueCount = 2;
  const cacheDir = 'build/cache';
  const journalFile = 'build/cache/journal';
  const journalBkpFile = 'build/cache/journal.bkp';
  final fileSystem = FaultyFileSystem(const LocalFileSystem());
  final toClose = ListQueue<DiskCache>();
  late DiskCache cache;

  Future<void> createNewCacheWithSize(int? maxSize) async {
    cache = DiskCache(fileSystem, cacheDir,
        appVersion: appVersion, valueCount: valueCount, maxSize: maxSize);
    await cache.initialize();
    toClose.add(cache);
  }

  Future<void> createNewCache() {
    createNewCacheWithSize(null);
    return cache.initialize();
  }

  Future<List<String>> readJournalLines() {
    return fileSystem.read(journalFile, (source) async {
      return const LineSplitter().convert(await source.readString());
    });
  }

  Future<void> assertJournalEquals(
      [List<String> expectedBodyLines = const []]) async {
    final expectedLines = [];
    expectedLines.add(magic);
    expectedLines.add('$version');
    expectedLines.add('$appVersion');
    expectedLines.add('$valueCount');
    expectedLines.add('');
    expectedLines.addAll(expectedBodyLines);
    expect(await readJournalLines(), expectedLines);
  }

  Future<void> createJournalWithHeader(
    String magic,
    String version,
    String appVersion,
    String valueCount,
    String blank,
    List<String> bodyLines,
  ) {
    return fileSystem.write(journalFile, (sink) async {
      await sink.writeLine(magic);
      await sink.writeLine(version);
      await sink.writeLine(appVersion);
      await sink.writeLine(valueCount);
      await sink.writeLine(blank);
      for (final line in bodyLines) {
        await sink.writeLine(line);
      }
    });
  }

  Future<void> createJournal(List<String> bodyLines) {
    return createJournalWithHeader(
        magic, '$version', '$appVersion', '$valueCount', '', bodyLines);
  }

  String getCleanFile(String key, int index) => '$cacheDir/$key.$index';

  String getDirtyFile(String key, int index) => '$cacheDir/$key.$index.tmp';

  Future<String> readFile(String path) =>
      fileSystem.read(path, (source) => source.readString());

  Future<String?> readFileOrNull(String path) => fileSystem
      .read<String?>(path, (source) => source.readString())
      .catchError((e) => null);

  Future<void> writeFile(String path, String content) =>
      fileSystem.write(path, (sink) => sink.writeString(content));

  Future<void> generateSomeGarbageFiles() async {
    const dir1 = '$cacheDir/dir1';
    const dir2 = '$dir1/dir2';
    await writeFile(getCleanFile('g1', 0), 'A');
    await writeFile(getCleanFile('g1', 1), 'B');
    await writeFile(getCleanFile('g2', 0), 'C');
    await writeFile(getCleanFile('g2', 1), 'D');
    await writeFile('$cacheDir/otherFile0', 'E');
    await writeFile('$dir2/otherFile1', 'F');
  }

  Future<void> assertGarbageFilesAllDeleted() async {
    expect(await fileSystem.exists(getCleanFile('g1', 0)), isFalse);
    expect(await fileSystem.exists(getCleanFile('g1', 1)), isFalse);
    expect(await fileSystem.exists(getCleanFile('g2', 0)), isFalse);
    expect(await fileSystem.exists(getCleanFile('g2', 1)), isFalse);
    expect(await fileSystem.exists('$cacheDir/otherFile0'), isFalse);
    expect(await fileSystem.exists('$cacheDir/dir1'), isFalse);
  }

  Future<void> set(String key, String value0, String value1) {
    return cache.edit(key).then((value) => value!).then((editor) async {
      await editor.setString(0, value0);
      await editor.setString(1, value1);
      await editor.commit();
    });
  }

  Future<void> assertAbsent(String key) async {
    await cache.get(key).then((snapshot) async {
      if (snapshot != null) {
        await snapshot.close();
        expect(0, 1);
      }
    });
    expect(await fileSystem.exists(getCleanFile(key, 0)), isFalse);
    expect(await fileSystem.exists(getCleanFile(key, 1)), isFalse);
    expect(await fileSystem.exists(getDirtyFile(key, 0)), isFalse);
    expect(await fileSystem.exists(getDirtyFile(key, 1)), isFalse);
  }

  Future<void> assertValue(String key, String value0, String value1) async {
    final snapshot = await cache.get(key).then((value) => value!);
    await snapshot.assertValue(0, value0);
    await snapshot.assertValue(1, value1);
    expect(await fileSystem.exists(getCleanFile(key, 0)), isTrue);
    expect(await fileSystem.exists(getCleanFile(key, 1)), isTrue);
  }

  Future<void> addOp2000() async {
    // Cause the rebuild action to fail.
    fileSystem.setFaulty(journalFile, true);
    while (await cache.redundantOpCount() < 2000) {
      await set('a', 'a', 'a');
      await set('b', 'b', 'b');
    }
  }

  setUp(() async {
    await createNewCache();
  });

  tearDown(() async {
    while (toClose.isNotEmpty) {
      final cache = toClose.removeFirst();
      await cache.delete();
    }
  });

  test('empty cache', () async {
    await cache.close();
    await assertJournalEquals();
  });

  test('recover from initialization failure', () async {
    // Add an uncommitted entry. This will get detected on initialization, and the cache will
    // attempt to delete the file. Do not explicitly close the cache here so the entry is left as
    // incomplete.
    final creator = await cache.edit('k1').then((value) => value!);
    await creator
        .newSink(0)
        .buffered()
        .then((value) => value.writeString('Hello'));

    // Simulate a severe Filesystem failure on the first initialization.
    fileSystem.setFaulty('$cacheDir/k1.0.tmp', true);
    fileSystem.setFaulty(cacheDir, true);
    cache = DiskCache(fileSystem, cacheDir,
        appVersion: appVersion, valueCount: valueCount);

    await cache.get('k1').catchError((e) => null);

    // Now let it operate normally.
    fileSystem.setFaulty('$cacheDir/k1.0.tmp', false);
    fileSystem.setFaulty(cacheDir, false);
    final snapshot = await cache.get('k1');
    expect(snapshot, isNull);
  });

  test('validate key', () async {
    String? key;
    key = 'has_space ';
    await expectLater(() => cache.edit(key!), throwsArgumentError);
    key = 'has_CR\r';
    await expectLater(() => cache.edit(key!), throwsArgumentError);
    key = 'has_LF\n';
    await expectLater(() => cache.edit(key!), throwsArgumentError);
    key = 'has_invalid/';
    await expectLater(() => cache.edit(key!), throwsArgumentError);
    key = 'has_invalid☃';
    await expectLater(() => cache.edit(key!), throwsArgumentError);
    key =
        'this_is_way_too_long_this_is_way_too_long_this_is_way_too_long_this_is_way_too_long_this_is_way_too_long_this_is_way_too_long';
    await expectLater(() => cache.edit(key!), throwsArgumentError);

    // Test valid cases.
    // Exactly 120.
    key =
        '012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789';
    await cache.edit(key).then((value) => value?.abort());
    // Contains all valid characters.
    key = 'abcdefghijklmnopqrstuvwxyz_0123456789';
    await cache.edit(key).then((value) => value?.abort());
    // Contains dash.
    key = '-20384573948576';
    await cache.edit(key).then((value) => value?.abort());
  });

  test('write and read entry', () async {
    final creator = await cache.edit('k1').then((value) => value!);
    await creator.setString(0, 'ABC');
    await creator.setString(1, 'DE');
    expect(await creator.newSource(0), isNull);
    expect(await creator.newSource(1), isNull);
    await creator.commit();
    final snapshot = await cache.get('k1').then((value) => value!);
    await snapshot.assertValue(0, 'ABC');
    await snapshot.assertValue(1, 'DE');
    await snapshot.close();
  });

  test('read and write entry across cache open and close', () async {
    final creator = await cache.edit('k1').then((value) => value!);
    await creator.setString(0, 'A');
    await creator.setString(1, 'B');
    await creator.commit();
    await cache.close();
    await createNewCache();
    final snapshot = await cache.get('k1').then((value) => value!);
    await snapshot.assertValue(0, 'A');
    await snapshot.assertValue(1, 'B');
    await snapshot.close();
  });

  test('read and write entry without proper close', () async {
    final creator = await cache.edit('k1').then((value) => value!);
    await creator.setString(0, 'A');
    await creator.setString(1, 'B');
    await creator.commit();

    // Simulate a dirty close of 'cache' by opening the cache directory again.
    await createNewCache();
    final snapshot = await cache.get('k1').then((value) => value!);
    await snapshot.assertValue(0, 'A');
    await snapshot.assertValue(1, 'B');
    await snapshot.close();
  });

  test('journal with edit and publish', () async {
    final creator = await cache.edit('k1').then((value) => value!);
    await assertJournalEquals(['DIRTY k1']); // DIRTY must always be flushed.
    await creator.setString(0, 'AB');
    await creator.setString(1, 'C');
    await creator.commit();
    await cache.close();
    await assertJournalEquals(['DIRTY k1', 'CLEAN k1 2 1']);
  });

  test('reverted new file is remove in journal', () async {
    final creator = await cache.edit('k1').then((value) => value!);
    await assertJournalEquals(['DIRTY k1']); // DIRTY must always be flushed.
    await creator.setString(0, 'AB');
    await creator.setString(1, 'C');
    await creator.abort();
    await cache.close();
    await assertJournalEquals(['DIRTY k1', 'REMOVE k1']);
  });

  test('unterminated edit is reverted on cache close', () async {
    final creator = await cache.edit('k1').then((value) => value!);
    await creator.setString(0, 'AB');
    await creator.setString(1, 'C');
    await cache.close();
    final expected = ['DIRTY k1', 'REMOVE k1'];
    await assertJournalEquals(expected);
    await creator.commit();
    // 'REMOVE k1' not written because journal is closed.
    await assertJournalEquals(expected);
  });

  test('unterminated edit is reverted on cache close on windows', () async {
    await cache.emulateWindows();
    final creator = await cache.edit('k1').then((value) => value!);
    await creator.setString(0, 'AB');
    await creator.setString(1, 'C');
    await cache.close();
    final expected = ['DIRTY k1'];
    await assertJournalEquals(expected);
    await creator.commit();
    // 'REMOVE k1' not written because journal is closed.
    await assertJournalEquals(expected);
  });

  test('journal does not include read of yet unpublished value', () async {
    final creator = await cache.edit('k1').then((value) => value!);
    expect(await cache.get('k1'), isNull);
    await creator.setString(0, 'A');
    await creator.setString(1, 'BC');
    await creator.commit();
    await cache.close();
    await assertJournalEquals(['DIRTY k1', 'CLEAN k1 1 2']);
  });

  test('journal with edit and publish and read', () async {
    final k1Creator = await cache.edit('k1').then((value) => value!);
    await k1Creator.setString(0, 'AB');
    await k1Creator.setString(1, 'C');
    await k1Creator.commit();
    final k2Creator = await cache.edit('k2').then((value) => value!);
    await k2Creator.setString(0, 'DEF');
    await k2Creator.setString(1, 'G');
    await k2Creator.commit();
    final k1Snapshot = await cache.get('k1').then((value) => value!);
    await k1Snapshot.close();
    await cache.close();
    await assertJournalEquals(
        ['DIRTY k1', 'CLEAN k1 2 1', 'DIRTY k2', 'CLEAN k2 3 1', 'READ k1']);
  });

  test('cannot operate on edit after publish', () async {
    final creator = await cache.edit('k1').then((value) => value!);
    await creator.setString(0, 'A');
    await creator.setString(1, 'B');
    await creator.commit();
    await creator.assertInoperable();
  });

  test('cannot operate on edit after revert', () async {
    final creator = await cache.edit('k1').then((value) => value!);
    await creator.setString(0, 'A');
    await creator.setString(1, 'B');
    await creator.abort();
    await creator.assertInoperable();
  });

  test('explicit remove applied to disk immediately', () async {
    final creator = await cache.edit('k1').then((value) => value!);
    await creator.setString(0, 'ABC');
    await creator.setString(1, 'D');
    await creator.commit();
    final k1 = getCleanFile('k1', 0);
    expect(await readFile(k1), 'ABC');
    await cache.remove('k1');
    expect(await fileSystem.exists(k1), isFalse);
  });

  test('remove prevents active edit from storing a value', () async {
    await set('a', 'a', 'a');
    final a = await cache.edit('a').then((value) => value!);
    await a.setString(0, 'a1');
    expect(await cache.remove('a'), isTrue);
    await a.setString(1, 'a1');
    await a.commit();
    await assertAbsent('a');
  });

  /// Each read sees a snapshot of the file at the time read was called. This
  /// means that two reads of the same key can see different data.
  test('read and write overlaps maintain consistency', () async {
    final v1Creator = await cache.edit('k1').then((value) => value!);
    await v1Creator.setString(0, 'AAaa');
    await v1Creator.setString(1, 'BBbb');
    await v1Creator.commit();

    final snapshot1 = await cache.get('k1').then((value) => value!);
    final inV1 = snapshot1.getSource(0).buffered();
    expect(await inV1.readInt8(), 'A'.codeUnitAt(0));
    expect(await inV1.readInt8(), 'A'.codeUnitAt(0));

    final v1Updater = await cache.edit('k1').then((value) => value!);
    await v1Updater.setString(0, 'CCcc');
    await v1Updater.setString(1, 'DDdd');
    await v1Updater.commit();

    final snapshot2 = await cache.get('k1').then((value) => value!);
    await snapshot2.assertValue(0, 'CCcc');
    await snapshot2.assertValue(1, 'DDdd');
    await snapshot2.close();

    expect(await inV1.readInt8(), 'a'.codeUnitAt(0));
    expect(await inV1.readInt8(), 'a'.codeUnitAt(0));
    await snapshot1.close();
  });

  test('open with dirty key deletes all files for that key', () async {
    await cache.close();
    final cleanFile0 = getCleanFile('k1', 0);
    final cleanFile1 = getCleanFile('k1', 1);
    final dirtyFile0 = getDirtyFile('k1', 0);
    final dirtyFile1 = getDirtyFile('k1', 1);
    await writeFile(cleanFile0, 'A');
    await writeFile(cleanFile1, 'B');
    await writeFile(dirtyFile0, 'C');
    await writeFile(dirtyFile1, 'D');
    await createJournal(['CLEAN k1 1 1', 'DIRTY k1']);
    await createNewCache();
    expect(await fileSystem.exists(cleanFile0), isFalse);
    expect(await fileSystem.exists(cleanFile1), isFalse);
    expect(await fileSystem.exists(dirtyFile0), isFalse);
    expect(await fileSystem.exists(dirtyFile1), isFalse);
    expect(await cache.get('k1'), isNull);
  });

  test('open with invalid version clears directory', () async {
    await cache.close();
    await generateSomeGarbageFiles();
    await createJournalWithHeader(
        magic, '$version', '101', '$valueCount', '', []);
    await createNewCache();
    await assertGarbageFilesAllDeleted();
  });

  test('open with invalid value count clears directory', () async {
    await cache.close();
    await generateSomeGarbageFiles();
    await createJournalWithHeader(
        magic, '$version', '$appVersion', '1', '', []);
    await createNewCache();
    await assertGarbageFilesAllDeleted();
  });

  test('open with invalid blank line clears directory', () async {
    await cache.close();
    await generateSomeGarbageFiles();
    await createJournalWithHeader(
        magic, '$version', '$appVersion', '$valueCount', 'x', []);
    await createNewCache();
    await assertGarbageFilesAllDeleted();
  });

  test('open with invalid journal line clears directory', () async {
    await cache.close();
    await generateSomeGarbageFiles();
    await createJournal(['CLEAN k1 1 1', 'BOGUS']);
    await createNewCache();
    await assertGarbageFilesAllDeleted();
    expect(await cache.get('k1'), isNull);
  });

  test('open with invalid file size clears directory', () async {
    await cache.close();
    await generateSomeGarbageFiles();
    await createJournal(['CLEAN k1 0000x001 1']);
    await createNewCache();
    await assertGarbageFilesAllDeleted();
    expect(await cache.get('k1'), isNull);
  });

  test('open with truncated line discards thatLine', () async {
    await cache.close();
    await writeFile(getCleanFile('k1', 0), 'A');
    await writeFile(getCleanFile('k1', 1), 'B');
    await fileSystem.write(journalFile, (sink) async {
      await sink.writeLine(magic);
      await sink.writeLine('$version');
      await sink.writeLine('$appVersion');
      await sink.writeLine('$valueCount');
      await sink.writeLine();
      await sink.writeString('CLEAN k1 1 1');
    });
    await createNewCache();
    expect(await cache.get('k1'), isNull);

    // The journal is not corrupt when editing after a truncated line.
    await set('k1', 'C', 'D');
    await cache.close();
    await createNewCache();
    await assertValue('k1', 'C', 'D');
  });

  test('open with too many file sizes clears directory', () async {
    await cache.close();
    await generateSomeGarbageFiles();
    await createJournal(['CLEAN k1 1 1 1']);
    await createNewCache();
    await assertGarbageFilesAllDeleted();
    expect(await cache.get('k1'), isNull);
  });

  test('create new entry with too few values fails', () async {
    final creator = await cache.edit('k1').then((value) => value!);
    await creator.setString(1, 'A');
    await expectLater(creator.commit, throwsStateError);
    expect(await fileSystem.exists(getCleanFile('k1', 0)), isFalse);
    expect(await fileSystem.exists(getCleanFile('k1', 1)), isFalse);
    expect(await fileSystem.exists(getDirtyFile('k1', 0)), isFalse);
    expect(await fileSystem.exists(getDirtyFile('k1', 1)), isFalse);
    expect(await cache.get('k1'), isNull);
    final creator2 = await cache.edit('k1').then((value) => value!);
    await creator2.setString(0, 'B');
    await creator2.setString(1, 'C');
    await creator2.commit();
  });

  test('revert with too few values', () async {
    final creator = await cache.edit('k1').then((value) => value!);
    await creator.setString(0, 'A');
    await creator.abort();
    expect(await fileSystem.exists(getCleanFile('k1', 0)), isFalse);
    expect(await fileSystem.exists(getCleanFile('k1', 1)), isFalse);
    expect(await fileSystem.exists(getDirtyFile('k1', 0)), isFalse);
    expect(await fileSystem.exists(getDirtyFile('k1', 1)), isFalse);
    expect(await cache.get('k1'), isNull);
  });

  test('update existing entry with too few values reuses previous values',
      () async {
    final creator = await cache.edit('k1').then((value) => value!);
    await creator.setString(0, 'A');
    await creator.setString(1, 'B');
    await creator.commit();
    final updater = await cache.edit('k1').then((value) => value!);
    await updater.setString(0, 'C');
    await updater.commit();
    final snapshot = await cache.get('k1').then((value) => value!);
    await snapshot.assertValue(0, 'C');
    await snapshot.assertValue(1, 'B');
    await snapshot.close();
  });

  test('grow max size', () async {
    await cache.close();
    await createNewCacheWithSize(10);
    await set('a', 'a', 'aaa'); // size 4
    await set('b', 'bb', 'bbbb'); // size 6
    await cache.setMaxSize(20);
    await set('c', 'c', 'c'); // size 2
    expect(await cache.size, 12);
  });

  test('shrink max size evicts', () async {
    await cache.close();
    await createNewCacheWithSize(20);
    await set('a', 'a', 'aaa'); // size 4
    await set('b', 'bb', 'bbbb'); // size 6
    await set('c', 'c', 'c'); // size 2
    await cache.setMaxSize(10);
    expect(await cache.size, 8);
  });

  test('evict on insert', () async {
    await cache.close();
    await createNewCacheWithSize(10);
    await set('a', 'a', 'aaa'); // size 4
    await set('b', 'bb', 'bbbb'); // size 6
    expect(await cache.size, 10);

    // Cause the size to grow to 12 should evict 'A'.
    await set('c', 'c', 'c'); // size 2
    // await cache.flush();
    expect(await cache.size, 8);
    await assertAbsent('a');
    await assertValue('b', 'bb', 'bbbb');
    await assertValue('c', 'c', 'c');

    // Causing the size to grow to 10 should evict nothing.
    await set('d', 'd', 'd'); // size 2
    // await cache.flush();
    expect(await cache.size, 10);
    await assertAbsent('a');
    await assertValue('b', 'bb', 'bbbb');
    await assertValue('c', 'c', 'c');
    await assertValue('d', 'd', 'd');

    // Causing the size to grow to 18 should evict 'B' and 'C'.
    await set('e', 'eeee', 'eeee'); // size 8
    // await cache.flush();
    expect(await cache.size, 10);
    await assertAbsent('a');
    await assertAbsent('b');
    await assertAbsent('c');
    await assertValue('d', 'd', 'd');
    await assertValue('e', 'eeee', 'eeee');
  });

  test('evict on update', () async {
    await cache.close();
    await createNewCacheWithSize(10);
    await set('a', 'a', 'aa'); // size 3
    await set('b', 'b', 'bb'); // size 3
    await set('c', 'c', 'cc'); // size 3
    expect(await cache.size, 9);

    // Causing the size to grow to 11 should evict 'A'.
    await set('b', 'b', 'bbbb'); // size 5
    // await cache.flush();
    expect(await cache.size, 8);
    await assertAbsent('a');
    await assertValue('b', 'b', 'bbbb');
    await assertValue('c', 'c', 'cc');
  });

  test('eviction honors lru from current session', () async {
    await cache.close();
    await createNewCacheWithSize(10);
    await set('a', 'a', 'a'); // size 2
    await set('b', 'b', 'b'); // size 2
    await set('c', 'c', 'c'); // size 2
    await set('d', 'd', 'd'); // size 2
    await set('e', 'e', 'e'); // size 2
    await cache
        .get('b')
        .then((value) => value?.close()); // 'B' is now least recently used.

    // Causing the size to grow to 12 should evict 'A'.
    await set('f', 'f', 'f'); // size 2
    // Causing the size to grow to 12 should evict 'C'.
    await set('g', 'g', 'g'); // size 2
    // await cache.flush();
    expect(await cache.size, 10);
    await assertAbsent('a');
    await assertValue('b', 'b', 'b');
    await assertAbsent('c');
    await assertValue('d', 'd', 'd');
    await assertValue('e', 'e', 'e');
    await assertValue('f', 'f', 'f');
  });

  test('eviction honors lru from previous session', () async {
    await set('a', 'a', 'a'); // size 2
    await set('b', 'b', 'b'); // size 2
    await set('c', 'c', 'c'); // size 2
    await set('d', 'd', 'd'); // size 2
    await set('e', 'e', 'e'); // size 2
    await set('f', 'f', 'f'); // size 2
    await cache
        .get('b')
        .then((value) => value?.close()); // 'B' is now least recently used.
    expect(await cache.size, 12);
    await cache.close();
    await createNewCacheWithSize(10);
    await set('g', 'g', 'g'); // size 2
    // await cache.flush();
    expect(await cache.size, 10);
    await assertAbsent('a');
    await assertValue('b', 'b', 'b');
    await assertAbsent('c');
    await assertValue('d', 'd', 'd');
    await assertValue('e', 'e', 'e');
    await assertValue('f', 'f', 'f');
    await assertValue('g', 'g', 'g');
  });

  test('cache single entry of size greater than max size', () async {
    await cache.close();
    await createNewCacheWithSize(10);
    await set('a', 'aaaaa', 'aaaaaa'); // size 11
    // await cache.flush();
    await assertAbsent('a');
  });

  test('cache single value of size greater than max size', () async {
    await cache.close();
    await createNewCacheWithSize(10);
    await set('a', 'aaaaaaaaaaa', 'a'); // size 12
    // await cache.flush();
    await assertAbsent('a');
  });

  test('constructor does not allow zero cache size', () async {
    try {
      DiskCache(fileSystem, cacheDir,
          appVersion: appVersion, valueCount: valueCount, maxSize: 0);
      expect(0, 1);
    } catch (_) {}
  });

  test('constructor does not allow zero values per entry', () async {
    try {
      DiskCache(fileSystem, cacheDir,
          appVersion: appVersion, valueCount: 0, maxSize: 10);
      expect(0, 1);
    } catch (_) {}
  });

  test('remove absent element', () async {
    await cache.remove('a');
  });

  test('reading the same stream multiple times', () async {
    await set('a', 'a', 'a'); // size 2
    await set('b', 'b', 'b'); // size 2
  });

  test('rebuild journal on repeated reads', () async {
    await set('a', 'a', 'a');
    await set('b', 'b', 'b');
    while (true) {
      final count = await cache.redundantOpCount();
      await assertValue('a', 'a', 'a');
      await assertValue('b', 'b', 'b');
      final count2 = await cache.redundantOpCount();
      if (count > count2) {
        print('journal count: $count - $count2');
        break;
      }
    }
  });

  test('rebuild journal on repeated edits', () async {
    while (true) {
      final count = await cache.redundantOpCount();
      await set('a', 'a', 'a');
      await set('b', 'b', 'b');
      final count2 = await cache.redundantOpCount();
      if (count > count2) {
        print('journal count: $count - $count2');
        break;
      }
    }
    // Sanity check that a rebuilt journal behaves normally.
    await assertValue('a', 'a', 'a');
    await assertValue('b', 'b', 'b');
  });

  test('rebuild journal on repeated reads with open and close', () async {
    await set('a', 'a', 'a');
    await set('b', 'b', 'b');
    while (true) {
      final count = await cache.redundantOpCount();
      await assertValue('a', 'a', 'a');
      await assertValue('b', 'b', 'b');
      await cache.close();
      await createNewCache();
      final count2 = await cache.redundantOpCount();
      if (count > count2) {
        print('journal count: $count - $count2');
        break;
      }
    }
  });

  test('rebuild journal failure prevents editors', () async {
    await cache.initialize();
    // Cause the rebuild action to fail.
    fileSystem.setFaulty(journalFile, true);

    while (true) {
      try {
        await set('a', 'a', 'a');
        await set('b', 'b', 'b');
      } catch (_) {
        expect(await cache.redundantOpCount(), 2000);
        break;
      }
    }
    // Don't allow edits under any circumstances.
    expect(await cache.edit('a'), isNull);
    expect(await cache.edit('b'), isNull);
    final snapshot = await cache.get('a').then((value) => value!);
    expect(await snapshot.edit(), isNull);
    await snapshot.close();

    fileSystem.setFaulty(journalFile, false);
  });

  test('rebuild journal failure is retried', () async {
    await cache.initialize();
    await addOp2000();
    fileSystem.setFaulty(journalFile, false);
    // The rebuild is retried on cache hits and on cache edits.
    final snapshot = await cache.get('b').then((value) => value!);
    await snapshot.close();
    expect(await cache.redundantOpCount(), 0);

    await addOp2000();
    fileSystem.setFaulty(journalFile, false);
    expect(await cache.edit('d'), isNull);
    expect(await cache.redundantOpCount(), 0);

    await assertJournalEquals(['CLEAN a 1 1', 'CLEAN b 1 1']);
  });

  test('rebuild journal failure allows removals', () async {
    await addOp2000();
    expect(await cache.remove('a'), isTrue);
    await assertAbsent('a');
    expect(await cache.redundantOpCount(), 2001);

    // Let the rebuild complete successfully.
    fileSystem.setFaulty(journalFile, false);
    await assertValue('b', 'b', 'b');
    expect(await cache.redundantOpCount(), 0);
    await assertJournalEquals(['CLEAN b 1 1']);
  });

  test('rebuild journal failure with removal then close', () async {
    await addOp2000();
    expect(await cache.remove('a'), isTrue);
    await assertAbsent('a');
    await cache.close();
    // Wait pre work done.
    await cache.redundantOpCount();
    fileSystem.setFaulty(journalFile, false);
    await createNewCache();

    // The journal will have no record that 'a' was removed. It will have an entry for 'a', but when
    // it tries to read the cache files, it will find they were deleted. Once it encounters an entry
    // with missing cache files, it should remove it from the cache entirely.
    expect(await cache.size, 4);
    expect(await cache.get('a'), isNull);
    expect(await cache.size, 2);
  });

  test('rebuild journal failure allows evictAll', () async {
    await addOp2000();
    await cache.evictAll();
    expect(await cache.size, 0);
    await assertAbsent('a');
    await assertAbsent('b');
    await cache.close();
    // Wait pre work done.
    await cache.redundantOpCount();
    fileSystem.setFaulty(journalFile, false);
    await createNewCache();

    // The journal has no record that 'a' and 'b' were removed. It will have an entry for both, but
    // when it tries to read the cache files for either entry, it will discover the cache files are
    // missing and remove the entries from the cache.
    expect(await cache.size, 4);
    expect(await cache.get('a'), isNull);
    expect(await cache.get('b'), isNull);
    expect(await cache.size, 0);
  });

  test('rebuild journal failure with cache trim', () async {
    await addOp2000();

    // Trigger a job to trim the cache.
    await cache.setMaxSize(2);
    await assertAbsent('a');
    await assertValue('b', 'b', 'b');
    fileSystem.setFaulty(journalFile, false);
  });

  test('restore backup file', () async {
    final creator = await cache.edit('k1').then((value) => value!);
    await creator.setString(0, 'ABC');
    await creator.setString(1, 'DE');
    await creator.commit();
    await cache.close();
    await fileSystem.atomicMove(journalFile, journalBkpFile);
    expect(await fileSystem.exists(journalFile), isFalse);
    await createNewCache();
    final snapshot = await cache.get('k1').then((value) => value!);
    await snapshot.assertValue(0, 'ABC');
    await snapshot.assertValue(1, 'DE');
    expect(await fileSystem.exists(journalBkpFile), isFalse);
    expect(await fileSystem.exists(journalFile), isTrue);
  });

  test('journal file is preferred over backup file', () async {
    var creator = await cache.edit('k1').then((value) => value!);
    await creator.setString(0, 'ABC');
    await creator.setString(1, 'DE');
    await creator.commit();
    await cache.flush();
    await fileSystem.copy(journalFile, journalBkpFile);
    creator = await cache.edit('k2').then((value) => value!);
    await creator.setString(0, 'F');
    await creator.setString(1, 'GH');
    await creator.commit();
    await cache.close();
    expect(await fileSystem.exists(journalFile), isTrue);
    expect(await fileSystem.exists(journalBkpFile), isTrue);
    await createNewCache();
    final snapshotA = await cache.get('k1').then((value) => value!);
    await snapshotA.assertValue(0, 'ABC');
    await snapshotA.assertValue(1, 'DE');
    await snapshotA.close();
    final snapshotB = await cache.get('k2').then((value) => value!);
    await snapshotB.assertValue(0, 'F');
    await snapshotB.assertValue(1, 'GH');
    await snapshotB.close();
    expect(await fileSystem.exists(journalBkpFile), isFalse);
    expect(await fileSystem.exists(journalFile), isTrue);
  });

  test('open creates directory if necessary', () async {
    await cache.close();
    const dir = '$cacheDir/testOpenCreatesDirectoryIfNecessary';
    cache = DiskCache(fileSystem, dir,
        appVersion: appVersion, valueCount: valueCount);
    await set('a', 'a', 'a');
    expect(await fileSystem.exists('$dir/a.0'), isTrue);
    expect(await fileSystem.exists('$dir/a.1'), isTrue);
    expect(await fileSystem.exists('$dir/journal'), isTrue);
  });

  test('file deleted externally', () async {
    await set('a', 'a', 'a');
    await fileSystem.delete(getCleanFile('a', 1));
    expect(await cache.get('a'), isNull);
    expect(await cache.size, 0);
  });

  test('edit same version', () async {
    await set('a', 'a', 'a');
    final snapshot = await cache.get('a').then((value) => value!);
    await snapshot.close();
    final editor = await cache.edit('a').then((value) => value!);
    await editor.setString(1, 'a2');
    await editor.commit();
    await assertValue('a', 'a', 'a2');
  });

  test('edit snapshot after change aborted', () async {
    await set('a', 'a', 'a');
    final snapshot = await cache.get('a').then((value) => value!);
    await snapshot.close();
    final toAbort = await snapshot.edit().then((value) => value!);
    await toAbort.setString(0, 'b');
    await toAbort.abort();
    final editor = await snapshot.edit().then((value) => value!);
    await editor.setString(1, 'a2');
    await editor.commit();
    await assertValue('a', 'a', 'a2');
  });

  test('edit snapshot after change committed', () async {
    await set('a', 'a', 'a');
    final snapshot = await cache.get('a').then((value) => value!);
    await snapshot.close();
    final toAbort = await snapshot.edit().then((value) => value!);
    await toAbort.setString(0, 'b');
    await toAbort.commit();
    await assertValue('a', 'b', 'a');
    expect(await snapshot.edit(), isNull);
  });

  test('edit since evicted', () async {
    await cache.close();
    await createNewCacheWithSize(10);
    await set('a', 'aa', 'aaa'); // size 5
    final snapshot = await cache.get('a').then((value) => value!);
    await set('b', 'bb', 'bbb'); // size 5
    await set('c', 'cc', 'ccc'); // size 5; will evict 'A'
    await cache.flush();
    expect(await snapshot.edit(), isNull);
  });

  test('edit since evicted and recreated', () async {
    await cache.close();
    await createNewCacheWithSize(10);
    await set('a', 'aa', 'aaa'); // size 5
    final snapshot = await cache.get('a').then((value) => value!);
    await snapshot.close();
    await set('b', 'bb', 'bbb'); // size 5
    await set('c', 'cc', 'ccc'); // size 5; will evict 'A'
    await set('a', 'aa', 'aaaa'); // size 5; will evict 'B'
    await cache.flush();
    expect(await snapshot.edit(), isNull);
  });

  test('aggressive clearing handles write', () async {
    await set('a', 'a', 'a');
    final a = await cache.edit('a').then((value) => value!);
    await fileSystem.delete(cacheDir);
    await a.setString(1, 'a2');
    await a.commit();
  }, onPlatform: {
    'windows': const Skip("Can't deleteContents while the journal is open.")
  });

  test('remove handles missing file', () async {
    await set('a', 'a', 'a');
    await fileSystem.delete(getCleanFile('a', 0));
    await cache.remove('a');
  });

  test('aggressive clearing handles partial edit', () async {
    await set('a', 'a', 'a');
    await set('b', 'b', 'b');
    final a = await cache.edit('a').then((value) => value!);
    await a.setString(0, 'a1');
    await fileSystem.delete(cacheDir);
    await a.setString(1, 'a2');
    await a.commit();
    expect(await cache.get('a'), isNull);
    expect(await cache.get('b'), isNull);
  }, onPlatform: {
    'windows': const Skip("Can't deleteContents while the journal is open.")
  });

  test('aggressive clearing handles read', () async {
    await fileSystem.delete(cacheDir);
    expect(await cache.get('a'), isNull);
  }, onPlatform: {
    'windows': const Skip("Can't deleteContents while the journal is open.")
  });

  test('trim to size with active edit', () async {
    const emulateWindows = false;
    final windows = Platform.isWindows || emulateWindows;
    if (windows) {
      await cache.emulateWindows();
    }
    final expectedByteCount = windows ? 10 : 0;
    final afterRemoveFileContents = windows ? 'a1234' : null;

    await set('a', 'a1234', 'a1234');
    final a = await cache.edit('a').then((value) => value!);
    await cache.setMaxSize(8); // Smaller than the sum of active edits!
    await cache.flush(); // Force trimToSize().
    expect(await cache.size, expectedByteCount);
    expect(await readFileOrNull(getCleanFile('a', 0)), afterRemoveFileContents);
    expect(await readFileOrNull(getCleanFile('a', 1)), afterRemoveFileContents);

    // After the edit is completed, its entry is still gone.
    await a.setString(1, 'a1');
    await a.commit();
    await assertAbsent('a');
    expect(await cache.size, 0);
  });

  test('evict all', () async {
    await set('a', 'a', 'a');
    await set('b', 'b', 'b');
    await cache.evictAll();
    expect(await cache.size, 0);
    await assertAbsent('a');
    await assertAbsent('b');
  });

  test('evict all with partial create', () async {
    final a = await cache.edit('a').then((value) => value!);
    await a.setString(0, 'a1');
    await a.setString(1, 'a2');
    await cache.evictAll();
    expect(await cache.size, 0);
    await a.commit();
    await assertAbsent('a');
  });

  test('evict all with partial edit does not store a value', () async {
    const emulateWindows = false;
    final windows = Platform.isWindows || emulateWindows;
    if (windows) {
      await cache.emulateWindows();
    }
    final expectedByteCount = windows ? 2 : 0;

    await set('a', 'a', 'a');
    final a = await cache.edit('a').then((value) => value!);
    await a.setString(0, 'a1');
    await a.setString(1, 'a2');
    await cache.evictAll();
    expect(await cache.size, expectedByteCount);
    await a.commit();
    await assertAbsent('a');
  });

  test('evict all doesnt interrupt partial read', () async {
    const emulateWindows = false;
    final windows = Platform.isWindows || emulateWindows;
    if (windows) {
      await cache.emulateWindows();
    }
    final expectedByteCount = windows ? 2 : 0;
    final afterRemoveFileContents = windows ? 'a' : null;

    await set('a', 'a', 'a');
    await cache.get('a').then((value) => value!.use((snapshot) async {
          await snapshot.assertValue(0, 'a');
          await cache.evictAll();
          expect(await cache.size, expectedByteCount);
          expect(await readFileOrNull(getCleanFile('a', 0)),
              afterRemoveFileContents);
          expect(await readFileOrNull(getCleanFile('a', 1)),
              afterRemoveFileContents);
          await snapshot.assertValue(1, 'a');
        }));
    expect(await cache.size, 0);
  });

  test('edit snapshot after evict all returns null due to stale value',
      () async {
    const emulateWindows = false;
    final windows = Platform.isWindows || emulateWindows;
    if (windows) {
      await cache.emulateWindows();
    }
    final expectedByteCount = windows ? 2 : 0;
    final afterRemoveFileContents = windows ? 'a' : null;

    await set('a', 'a', 'a');
    await cache.get('a').then((value) => value!).use((snapshot) async {
      await cache.evictAll();
      expect(await cache.size, expectedByteCount);
      expect(
          await readFileOrNull(getCleanFile('a', 0)), afterRemoveFileContents);
      expect(
          await readFileOrNull(getCleanFile('a', 1)), afterRemoveFileContents);
      expect(await snapshot.edit(), isNull);
    });
    expect(await cache.size, 0);
  });

  test('is closed uninitialized cache', () async {
    // Create an uninitialized cache.
    cache = DiskCache(fileSystem, cacheDir,
        appVersion: appVersion, valueCount: valueCount);
    toClose.add(cache);

    expect(await cache.isClosed(), isFalse);
    await cache.close();
    expect(await cache.isClosed(), true);
  });

  test('journal write fails during edit', () async {
    await set('a', 'a', 'a');
    await set('b', 'b', 'b');

    // Once the journal has a failure, subsequent writes aren't permitted.
    await cache.hasJournalErrors(true);
    expect(await cache.edit('c'), isNull);

    // Confirm that the fault didn't corrupt entries stored before the fault was introduced.
    await cache.close();
    await createNewCache();
    await assertValue('a', 'a', 'a');
    await assertValue('b', 'b', 'b');
    await assertAbsent('c');
  });

  test('cleanup trim failure prevents new editors', () async {
    await cache.setMaxSize(8);
    await set('a', 'aa', 'aa');
    // Cause the cache trim job to fail.
    fileSystem.setFaulty('$cacheDir/a.0', true);
    await set('b', 'bb', 'bbb');

    // Confirm that edits are prevented after a cache trim failure.
    expect(await cache.edit('a'), isNull);
    // Allows edits after clean task called.
    expect(await cache.edit('a'), isNotNull);

    // Allow the test to clean up.
    fileSystem.setFaulty('$cacheDir/a.0', false);
  });

  test('cleanup trim failure allows snapshot reads', () async {
    await cache.setMaxSize(8);
    await set('a', 'aa', 'aa');
    // Cause the cache trim job to fail.
    fileSystem.setFaulty('$cacheDir/a.0', true);
    await set('b', 'bb', 'bbb');

    await cache.initialize();
    fileSystem.setFaulty('$cacheDir/a.0', false);
    // Confirm we still allow snapshot reads after a trim failure.
    await assertValue('a', 'aa', 'aa');
    await assertValue('b', 'bb', 'bbb');
  });

  test('evict all after cleanup trim failure', () async {
    await cache.setMaxSize(8);
    await set('a', 'aa', 'aa');
    // Cause the cache trim job to fail.
    fileSystem.setFaulty('$cacheDir/a.0', true);
    await set('b', 'bb', 'bbb');

    // Confirm we prevent edits after a trim failure.
    expect(await cache.edit('c'), isNull);

    // A successful removal which trims the cache should allow new writes.
    fileSystem.setFaulty('$cacheDir/a.0', false);
    await cache.remove('a');
    await set('c', 'cc', 'cc');
    await assertValue('c', 'cc', 'cc');
  });

  test('flushing after cleanup trim failure', () async {
    await cache.setMaxSize(8);
    await set('a', 'aa', 'aa');
    // Cause the cache trim job to fail.
    fileSystem.setFaulty('$cacheDir/a.0', true);
    await set('b', 'bb', 'bbb');

    // A successful flush trims the cache and should allow new writes.
    fileSystem.setFaulty('$cacheDir/a.0', false);
    // Confirm we prevent edits after a trim failure.
    expect(await cache.get('c'), isNull);

    await set('c', 'cc', 'cc');
    await assertValue('c', 'cc', 'cc');
  });

  test('cleanup trim failure with partial snapshot', () async {
    await cache.setMaxSize(8);
    await set('a', 'aa', 'aa');
    // Cause the cache trim job to fail.
    fileSystem.setFaulty('$cacheDir/a.1', true);
    await set('b', 'bb', 'bbb');

    // Confirm the partial snapshot is not returned.
    expect(await cache.get('a'), isNull);

    // Confirm we prevent edits after a trim failure.
    expect(await cache.edit('a'), isNull);

    fileSystem.setFaulty('$cacheDir/a.1', false);
    // Confirm the partial snapshot is not returned after a successful trim.
    await cache.flush();
    expect(await cache.get('a'), isNull);
  });

  test('no size corruption after creator detached', () async {
    // Create an editor for k1. Detach it by clearing the cache.
    final editor = await cache.edit('k1').then((value) => value!);
    await editor.setString(0, 'a');
    await editor.setString(1, 'a');
    await cache.evictAll();

    // Create a new value in its place.
    await set('k1', 'bb', 'bb');
    expect(await cache.size, 4);

    // Committing the detached editor should not change the cache's size.
    await editor.commit();
    expect(await cache.size, 4);
    await assertValue('k1', 'bb', 'bb');
  }, onPlatform: {
    'windows': const Skip("Windows can't have two concurrent editors.")
  });

  test('no size corruption after editor detached', () async {
    await set('k1', 'a', 'a');

    // Create an editor for k1. Detach it by clearing the cache.
    final editor = await cache.edit('k1').then((value) => value!);
    await editor.setString(0, 'bb');
    await editor.setString(1, 'bb');
    await cache.evictAll();

    // Create a new value in its place.
    await set('k1', 'ccc', 'ccc');
    expect(await cache.size, 6);

    // Committing the detached editor should not change the cache's size.
    await editor.commit();
    expect(await cache.size, 6);
    await assertValue('k1', 'ccc', 'ccc');
  }, onPlatform: {
    'windows': const Skip("Windows can't have two concurrent editors.")
  });

  test('no new source after editor detached', () async {
    await set('k1', 'a', 'a');
    final editor = await cache.edit('k1').then((value) => value!);
    await cache.evictAll();
    expect(await editor.newSource(0), isNull);
  });

  test('edit discarded after editor detached', () async {
    await set('k1', 'a', 'a');

    // Create an editor, then detach it.
    final editor = await cache.edit('k1').then((value) => value!);
    await editor.newSink(0).buffered().use((closable) async {
      await cache.evictAll();
      // Complete the original edit. It goes into a black hole.
      await closable.writeString('bb');
    });
    expect(await cache.get('k1'), isNull);
  });

  test('edit discarded after editor detached with concurrent write', () async {
    await set('k1', 'a', 'a');

    // Create an editor, then detach it.
    final editor = await cache.edit('k1').then((value) => value!);
    await editor.newSink(0).buffered().use((closable) async {
      await cache.evictAll();

      // Create another value in its place.
      await set('k1', 'ccc', 'ccc');

      // Complete the original edit. It goes into a black hole.
      await closable.writeString('bb');
    });
    await assertValue('k1', 'ccc', 'ccc');
  });

  test('abort after detach', () async {
    await set('k1', 'a', 'a');

    final editor = await cache.edit('k1').then((value) => value!);
    await cache.evictAll();
    await editor.abort();

    expect(await cache.size, 0);
    await assertAbsent('k1');
  });

  test('dont remove unfinished entry when creating snapshot', () async {
    final creator = await cache.edit('k1').then((value) => value!);
    await creator.setString(0, 'ABC');
    await creator.setString(1, 'DE');
    expect(await creator.newSource(0), isNull);
    expect(await creator.newSource(1), isNull);
  });

  test('windows cannot read while writing', () async {
    const emulateWindows = true;
    final windows = Platform.isWindows || emulateWindows;
    if (windows) {
      await cache.emulateWindows();
    }
    await set('k1', 'a', 'a');
    final editor = await cache.edit('k1').then((value) => value!);
    expect(await cache.get('k1'), isNull);
    await editor.commit();
  });

  test('can read while reading', () async {
    await set('k1', 'a', 'a');
    await cache.get('k1').then((value) => value!).use((closable) async {
      await closable.assertValue(0, 'a');
      await cache.get('k1').then((value) => value!).use((snapshot) async {
        await snapshot.assertValue(0, 'a');
        await closable.assertValue(1, 'a');
        await snapshot.assertValue(1, 'a');
      });
    });
  });

  test('remove while reading creates zombie that is removed when read finishes',
      () async {
    const emulateWindows = false;
    final windows = Platform.isWindows || emulateWindows;
    if (windows) {
      await cache.emulateWindows();
    }
    final afterRemoveFileContents = windows ? 'a' : null;

    await set('k1', 'a', 'a');
    await cache.get('k1').then((value) => value!).use((snapshot1) async {
      await cache.remove('k1');

      // On Windows files still exist with open with 2 open sources.
      expect(
          await readFileOrNull(getCleanFile('k1', 0)), afterRemoveFileContents);
      expect(await readFileOrNull(getDirtyFile('k1', 0)), isNull);

      // On Windows files still exist with open with 1 open source.
      await snapshot1.assertValue(0, 'a');
      expect(
          await readFileOrNull(getCleanFile('k1', 0)), afterRemoveFileContents);
      expect(await readFileOrNull(getDirtyFile('k1', 0)), isNull);

      // On all platforms files are deleted when all sources are closed.
      await snapshot1.assertValue(1, 'a');
      expect(await readFileOrNull(getCleanFile('k1', 0)), isNull);
      expect(await readFileOrNull(getDirtyFile('k1', 0)), isNull);
    });
  });

  test(
      'remove while writing creates zombie that is removed when write finishes',
      () async {
    const emulateWindows = false;
    final windows = Platform.isWindows || emulateWindows;
    if (windows) {
      await cache.emulateWindows();
    }
    final afterRemoveFileContents = windows ? 'a' : null;

    await set('k1', 'a', 'a');
    final editor = await cache.edit('k1').then((value) => value!);
    await cache.remove('k1');
    expect(await cache.get('k1'), isNull);

    // On Windows files still exist while being edited.
    expect(
        await readFileOrNull(getCleanFile('k1', 0)), afterRemoveFileContents);
    expect(await readFileOrNull(getDirtyFile('k1', 0)), isNull);

    // On all platforms files are deleted when the edit completes.
    await editor.commit();
    expect(await readFileOrNull(getCleanFile('k1', 0)), isNull);
    expect(await readFileOrNull(getDirtyFile('k1', 0)), isNull);
  });

  test('windows cannot read zombie entry', () async {
    const emulateWindows = true;
    final windows = Platform.isWindows || emulateWindows;
    if (windows) {
      await cache.emulateWindows();
    }
    await set('k1', 'a', 'a');
    await cache.get('k1').then((value) => value!).use((closable) async {
      await cache.remove('k1');
      expect(await cache.get('k1'), isNull);
    });
  });

  test('windows cannot write zombie entry', () async {
    const emulateWindows = true;
    final windows = Platform.isWindows || emulateWindows;
    if (windows) {
      await cache.emulateWindows();
    }
    await set('k1', 'a', 'a');
    await cache.get('k1').then((value) => value!).use((closable) async {
      await cache.remove('k1');
      expect(await cache.edit('k1'), isNull);
    });
  });

  test('close with zombie read', () async {
    const emulateWindows = false;
    final windows = Platform.isWindows || emulateWindows;
    if (windows) {
      await cache.emulateWindows();
    }
    final afterRemoveFileContents = windows ? 'a' : null;
    await set('k1', 'a', 'a');
    await cache.get('k1').then((value) => value!).use((closable) async {
      await cache.remove('k1');

      // After we close the cache the files continue to exist!
      await cache.close();
      expect(
          await readFileOrNull(getCleanFile('k1', 0)), afterRemoveFileContents);
      expect(await readFileOrNull(getDirtyFile('k1', 0)), isNull);

      // But they disappear when the sources are closed.
      await closable.assertValue(0, 'a');
      await closable.assertValue(1, 'a');
      expect(await readFileOrNull(getCleanFile('k1', 0)), isNull);
      expect(await readFileOrNull(getDirtyFile('k1', 0)), isNull);
    });
  });

  test('close with zombie write', () async {
    const emulateWindows = false;
    final windows = Platform.isWindows || emulateWindows;
    if (windows) {
      await cache.emulateWindows();
    }
    final afterRemoveCleanFileContents = windows ? 'a' : null;
    final afterRemoveDirtyFileContents = windows ? '' : null;
    await set('k1', 'a', 'a');
    final editor = await cache.edit('k1').then((value) => value!);
    final sink0 = await editor.newSink(0);
    await cache.remove('k1');

    // After we close the cache the files continue to exist!
    await cache.close();
    expect(await readFileOrNull(getCleanFile('k1', 0)),
        afterRemoveCleanFileContents);
    expect(await readFileOrNull(getDirtyFile('k1', 0)),
        afterRemoveDirtyFileContents);
    // But they disappear when the edit completes.
    await sink0.close();
    await editor.commit();
    expect(await readFileOrNull(getCleanFile('k1', 0)), isNull);
    expect(await readFileOrNull(getDirtyFile('k1', 0)), isNull);
  });

  test('close with completed zombie write', () async {
    const emulateWindows = false;
    final windows = Platform.isWindows || emulateWindows;
    if (windows) {
      await cache.emulateWindows();
    }
    final afterRemoveCleanFileContents = windows ? 'a' : null;
    final afterRemoveDirtyFileContents = windows ? 'b' : null;
    await set('k1', 'a', 'a');
    final editor = await cache.edit('k1').then((value) => value!);
    await editor.setString(0, 'b');
    await cache.remove('k1');

    // After we close the cache the files continue to exist!
    await cache.close();
    expect(await readFileOrNull(getCleanFile('k1', 0)),
        afterRemoveCleanFileContents);
    expect(await readFileOrNull(getDirtyFile('k1', 0)),
        afterRemoveDirtyFileContents);
    // But they disappear when the edit completes.
    await editor.commit();
    expect(await readFileOrNull(getCleanFile('k1', 0)), isNull);
    expect(await readFileOrNull(getDirtyFile('k1', 0)), isNull);
  });
}

class FaultyFileSystem extends ForwardingFileSystem {
  final faults = <String>{};

  FaultyFileSystem(super.delegate);

  void setFaulty(String path, bool faulty) {
    if (faulty) {
      faults.add(path);
    } else {
      faults.remove(path);
    }
  }

  @override
  Future<FileSystemEntityType> type(String path, {bool followLinks = true}) {
    if (faults.contains(path) || faults.contains(path)) {
      throw StateError('boom!');
    }
    return super.type(path, followLinks: followLinks);
  }
}

extension EditorShortcuts on Editor {
  Future<void> setString(int index, String value) =>
      newSink(index).buffered().use((sink) => sink.writeString(value));

  Future<void> assertInoperable() async {
    try {
      await setString(0, 'A').then((value) => expect(0, 1));
    } on StateError catch (_) {}
    try {
      await newSource(0).then((value) => expect(0, 1));
    } on StateError catch (_) {}
    try {
      await newSink(0).then((value) => expect(0, 1));
    } on StateError catch (_) {}
    try {
      await commit().then((value) => expect(0, 1));
    } on StateError catch (_) {}
    try {
      await abort().then((value) => expect(0, 1));
    } on StateError catch (_) {}
  }
}

extension SnapshotShortcuts on Snapshot {
  Future<void> assertValue(int index, String value) async {
    expect(
      await getSource(index).buffered().use((source) => source.readString()),
      value,
    );
  }
}
