import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anio/anio.dart';
import 'package:collection/collection.dart';

import 'model/file_header.dart';
import 'model/zip_model.dart';
import 'source/zip_entry_source.dart';
import 'zip_exception.dart';
import 'zip_file_handle.dart';
import 'zip_header_reader.dart';

class ZipFile {
  ZipFile(
    this._file,
    this._model, {
    Encoding encoding = utf8,
    Uint8List? password,
  })  : _password = password,
        _encoding = encoding;

  static Future<ZipFile> file(
    File file, {
    Encoding encoding = utf8,
    Uint8List? password,
  }) async {
    if (await file.length() <= 0) throw ZipException('zip file is empty');

    return await file.openHandle().use((closable) async {
      final reader = FileHeaderReader(closable, encoding);
      final model = await reader.parse();
      return ZipFile(file, model, encoding: encoding, password: password);
    });
  }

  final File _file;
  final ZipModel _model;
  final Encoding _encoding;
  final Uint8List? _password;

  bool get splitArchive => _model.splitArchive;

  List<FileHeader> get fileHeaders =>
      _model.centralDirectory?.fileHeaders ?? const [];

  bool exists(String name) => fileHeaders.any((e) => e.fileName == name);

  FileHeader? getEntry(String name) {
    return fileHeaders.firstWhereOrNull((e) => e.fileName == name);
  }

  Future<ZipFileHandle> openRead() => ZipFileHandle.openRead(_file, _model);

  Future<Source> getZipEntrySource(ZipFileHandle handle, FileHeader header,
      [Uint8List? password]) async {
    final source = handle.source(header);
    try {
      return await createZipEntrySource(
          source, header, _encoding, password ?? _password);
    } catch (_) {
      await source.close();
      rethrow;
    }
  }

  Future<Source> getEntrySource(FileHeader header, [Uint8List? password]) =>
      openRead().use((handle) => getZipEntrySource(handle, header, password));

  Future<Source?> getEntrySourceWithName(String name, [Uint8List? password]) {
    final entry = getEntry(name);
    if (entry == null) {
      return Future.value();
    } else {
      return getEntrySource(entry, password);
    }
  }
}
