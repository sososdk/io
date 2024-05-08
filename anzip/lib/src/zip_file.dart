import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anio/anio.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'model/file_header.dart';
import 'model/local_file_header.dart';
import 'model/zip_model.dart';
import 'source/zip_entry_source.dart';
import 'split_random_access_file.dart';
import 'zip_exception.dart';
import 'zip_header_reader.dart';

class ZipFile {
  ZipFile(
    this._file,
    this._model, {
    Encoding encoding = utf8,
    String? password,
  })  : _password = password,
        _encoding = encoding;

  static Future<ZipFile> open(
    File file, {
    Encoding encoding = utf8,
    String? password,
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
  final String? _password;
  Future<FileHandle>? __handleFuture;

  Future<FileHandle> get _handleFuture async {
    return __handleFuture ??= () async {
      RandomAccessFile randomAccessFile;
      SplitFileNaming? naming;
      int? splitLength;
      if (splitArchive) {
        naming = SplitFileNaming(p.basenameWithoutExtension(_file.path));
        final first = File(p.join(_file.parent.path, naming.splitName(1)));
        splitLength = await first.length();
        randomAccessFile = await SplitRandomAccessFile.openRead(
            _file, _model.numberOfThisDisk, splitLength, naming);
      } else {
        randomAccessFile = await _file.open();
      }
      return randomAccessFile.handle();
    }();
  }

  bool get splitArchive => _model.splitArchive;

  List<FileHeader> get fileHeaders =>
      _model.centralDirectory?.fileHeaders ?? const [];

  bool exists(String name) => fileHeaders.any((e) => e.fileName == name);

  FileHeader? getEntry(String name) {
    return fileHeaders.firstWhereOrNull((e) => e.fileName == name);
  }

  Future<BufferedSource> _source(FileHeader header) => _handleFuture.then((e) {
        int position = 0;
        if (splitArchive) {
          final file = e.file as SplitRandomAccessFile;
          final splitLength = file.splitLength;
          position = header.diskNumberStart * splitLength;
        }
        position += header.offsetLocalHeader;
        return e.source(position).buffered();
      });

  Future<Source?> getEntrySource(FileHeader fileHeader, [String? password]) {
    return _source(fileHeader).then((closable) async {
      // Read and verify header
      final header = await _verifyHeader(closable, fileHeader);
      // create decompression source
      return createZipEntrySource(closable, header, password ?? _password);
    });
  }

  Future<Source?> getEntrySourceWithName(String name, [String? password]) {
    final fileHeader = fileHeaders.firstWhereOrNull((e) => e.fileName == name);
    if (fileHeader == null) return Future.value();
    return getEntrySource(fileHeader);
  }

  Future<LocalFileHeader> _verifyHeader(
    BufferedSource source,
    FileHeader fileHeader,
  ) async {
    final header = await LocalFileHeaderReader(source, _encoding).parse();
    if (header == null) {
      throw ZipException(
          'Could not read corresponding local file header for file header: ${fileHeader.fileName}');
    }
    if (fileHeader.fileName != header.fileName) {
      throw ZipException('File header and local file header mismatch');
    }
    return header.copyWith(
      crc: fileHeader.crc,
      compressedSize: fileHeader.compressedSize,
      uncompressedSize: fileHeader.uncompressedSize,
      isDirectory: fileHeader.isDirectory,
    );
  }

  Future<void> close() => _handleFuture.then((e) => e.close());
}
