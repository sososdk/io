import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:anio/anio.dart';
import 'package:collection/collection.dart';
import 'package:file_system/file_system.dart';

import 'io/sink/zip_file_sink.dart';
import 'io/source/zip_entry_source.dart';
import 'io/source/zip_file_handle.dart';
import 'model/file_entry.dart';
import 'model/file_header.dart';
import 'model/zip_model.dart';
import 'zip_constants.dart';
import 'zip_exception.dart';
import 'zip_header_reader.dart';
import 'zip_header_writer.dart';
import 'zip_utils.dart';

class ZipFile {
  ZipFile(this._file, {ZipModel? model, Encoding? encoding = utf8})
      : _model = model,
        _encoding = encoding;

  static Future<ZipFile> parse(File file, {Encoding? encoding = utf8}) async {
    final model = await FileHeaderReader(file, encoding).parse();
    return ZipFile(file, model: model, encoding: encoding);
  }

  static Future<ZipFile> create(
    File file,
    Iterable<FileEntry> entries, {
    int? diskSize,
    String? comment,
    Encoding? encoding,
    Uint8List? password,
  }) async {
    assert(diskSize == null || diskSize >= 1024);
    _checkEntries(entries);
    final model = await ZipFileSink(file, diskSize).use((fileSink) async {
      final sink = fileSink.buffered();
      if (diskSize != null) await sink.writeFromBytes(kExtsig);
      await sink.emit();
      final fileHeaders = <FileHeader>[];
      final versionMadeBy = determineVersionMadeBy();
      for (final entry in entries) {
        final header = writeEntry(fileSink, entry, versionMadeBy, encoding);
        fileHeaders.add(await header);
      }
      if (diskSize != null) await fileSink.startFinalize();
      return finalize(fileSink, fileHeaders, versionMadeBy, encoding, comment);
    });
    return ZipFile(file, model: model);
  }

  static void _checkEntries(Iterable<FileEntry> entries) {
    final names = <String, List<FileEntry>>{};
    for (final entry in entries) {
      if (names.containsKey(entry.name)) {
        names[entry.name]!.add(entry);
      } else {
        names[entry.name] = [entry];
      }
    }
    final repeat = names.values.firstWhereOrNull((e) => e.length > 1)?.first;
    if (repeat != null) {
      throw ArgumentError('cannot repeat name(${repeat.name}) in zip file');
    }
  }

  final File _file;
  ZipModel? _model;
  final Encoding? _encoding;

  bool get isSplitArchive => _model?.isSplitArchive ?? false;

  bool get isZip64Format => _model?.isZip64Format ?? false;

  List<FileHeader> get fileHeaders =>
      _model?.centralDirectory.fileHeaders ?? const [];

  String? get comment => _model?.endOfCentralDirectoryRecord.comment;

  bool exists(String name) => fileHeaders.any((e) => e.name == name);

  FileHeader? getEntry(String name) {
    return fileHeaders.firstWhereOrNull((e) => e.name == name);
  }

  ZipFileHandle open() {
    return ZipFileHandle(_file, _model!.numberOfDisk);
  }

  Future<Source> getZipEntrySource(ZipFileHandle handle, FileHeader header,
      [Uint8List? password]) async {
    final source = handle.entrySource(header).buffered();
    try {
      return await createZipEntrySource(source, header, password, _encoding);
    } catch (_) {
      await source.close();
      rethrow;
    }
  }

  Future<Source> getEntrySource(FileHeader header, [Uint8List? password]) =>
      open().use((handle) => getZipEntrySource(handle, header, password));

  Future<Source?> getEntrySourceWithName(String name, [Uint8List? password]) {
    final entry = getEntry(name);
    if (entry == null) {
      return Future.value();
    } else {
      return getEntrySource(entry, password);
    }
  }

  Future<void> setComment(String? comment) async {
    if (_model == null) throw StateError('model does not exist');
    _model = await ZipFileSink(_file).use((fileSink) async {
      final position = _model!.offsetOfCentralDirectory;
      final versionMadeBy = determineVersionMadeBy();
      await fileSink.truncate(position);
      await fileSink.setPosition(position);
      return finalize(fileSink, fileHeaders, versionMadeBy, _encoding, comment);
    });
  }

  Future<void> add(Iterable<FileEntry> entries, [String? fileComment]) async {
    if (isSplitArchive) {
      throw ZipException('split archive modification is not supported');
    }
    _checkEntries(entries);
    // remove existed file and update it
    await removeWhere((header) => entries.any((e) => header.name == e.name));
    // add file
    _model = await ZipFileSink(_file).use((fileSink) async {
      final position = _model?.offsetOfCentralDirectory ?? 0;
      await fileSink.truncate(position);
      await fileSink.setPosition(position);
      final fileHeaders = List.of(this.fileHeaders);
      final versionMadeBy = determineVersionMadeBy();
      for (final entry in entries) {
        final header = writeEntry(fileSink, entry, versionMadeBy, _encoding);
        fileHeaders.add(await header);
      }
      return finalize(fileSink, fileHeaders, versionMadeBy, _encoding,
          fileComment ?? comment);
    });
  }

  Future<void> remove(Iterable<FileHeader> headers) async {
    if (isSplitArchive) {
      throw ZipException('split archive modification is not supported');
    }
    final model = _model;
    if (model == null) return;
    final fileHeaders = this
        .fileHeaders
        .sorted((a, b) => a.offsetLocalHeader - a.offsetLocalHeader);
    final removes = headers
        .where((e1) => fileHeaders.any((e2) => e1.name == e2.name))
        .toList();
    if (removes.isEmpty) return;

    var tempFile = _file.parent.childFile('${_file.basename}.tmp');
    final random = Random();
    const alphabets = 'abcdefghijklmnopqrstuvwxyz';
    var i = 0;
    while (await tempFile.exists()) {
      if (i++ > 99) throw StateError('unable to create temporary file');
      tempFile = _file.parent.childFile(
          '${_file.basename}.tmp-${alphabets[random.nextInt(25)]}${alphabets[random.nextInt(25)]}${alphabets[random.nextInt(25)]}');
    }
    try {
      final tempModel = await ZipFileSink(tempFile).use((fileSink) async {
        final sink = fileSink.buffered();
        return await _file.openHandle().use((sourceHandle) async {
          final headers = <FileHeader>[];
          for (var i = 0; i < fileHeaders.length; i++) {
            final header = fileHeaders[i];
            final end = i == fileHeaders.length - 1
                ? model.offsetOfCentralDirectory
                : fileHeaders[i + 1].offsetLocalHeader;
            final length = end - header.offsetLocalHeader;
            if (removes.any((e) => e.name == header.name)) {
              // removed. ignore
            } else {
              await sink.emit();
              final offsetLocalHeader = await fileSink.position();
              await sourceHandle
                  .source(header.offsetLocalHeader)
                  .limited(length)
                  .use((entrySource) => sink.writeFromSource(entrySource));
              headers.add(header.copyWith(offsetLocalHeader));
            }
          }
          await sink.emit();
          return finalize(fileSink, headers, determineVersionMadeBy(),
              _encoding, model.comment);
        });
      });
      await _file.delete();
      await tempFile.rename(_file.path);
      _model = tempModel;
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  Future<void> removeWhere(bool Function(FileHeader header) test) async {
    if (isSplitArchive) {
      throw ZipException('split archive modification is not supported');
    }
    await remove(fileHeaders.where(test));
  }
}
