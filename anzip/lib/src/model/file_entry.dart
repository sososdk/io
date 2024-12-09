import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anio/anio.dart';
import 'package:path/path.dart';

import '../bit_utils.dart';
import '../cp437.dart';
import '../crypto/crc32.dart';
import '../zip_constants.dart';
import '../zip_utils.dart';
import 'aes_extra_data_record.dart';
import 'compression_method.dart';
import 'encryption_method.dart';

class FileEntry {
  final Object entity;
  final bool forceZip64Format;
  final String name;
  final DateTime? _modifyTime;
  final int? _length;
  final int? _crc;
  final String? comment;
  final Uint8List? password;
  final CompressionMethod compressionMethod;
  final EncryptionMethod encryptionMethod;

  FileEntry(
    this.entity, {
    this.forceZip64Format = false,
    String? name,
    DateTime? modifyTime,
    int? crc,
    int? length,
    this.comment,
    this.password,
    this.compressionMethod = const CompressionStore(),
    this.encryptionMethod = const EncryptionNone(),
  })  : assert(entity is FileSystemEntity || entity is Source),
        assert(() {
          if (entity is Source) return name != null;
          return true;
        }()),
        assert(() {
          if (encryptionMethod.isEncrypted) {
            return password != null && password.isNotEmpty;
          } else {
            return password == null;
          }
        }()),
        assert(() {
          if (entity is Link) {
            return !encryptionMethod.isEncrypted && password == null;
          }
          return true;
        }()),
        name = name ??= basename((entity as FileSystemEntity).path),
        _modifyTime = modifyTime,
        _length = length,
        _crc = crc;

  bool get isFile {
    return entity is File;
  }

  bool get isDirectory {
    return entity is Directory;
  }

  bool get isSymbolicLink {
    return entity is Link;
  }

  Future<bool> isZip64Format() async {
    if (forceZip64Format) return true;
    return await length() > kZip64sizelimit;
  }

  Future<int> dosTime() async {
    modifyTime() async {
      if (entity is FileSystemEntity) {
        return (await (entity as FileSystemEntity).stat()).modified;
      }
    }

    return epochToDosTime(_modifyTime ?? await modifyTime() ?? DateTime.now());
  }

  Future<int> length() async {
    length() async {
      if (entity is FileSystemEntity) {
        return (await (entity as FileSystemEntity).stat()).size;
      } else if (entity is Buffer) {
        return (entity as Buffer).length;
      }
    }

    return _length ?? await length() ?? 0;
  }

  bool get useDataDescriptor => entity is Source && entity is! Buffer;

  Future<int> maybeCrc() async {
    crc() async {
      if (encryptionMethod is EncryptionZipCrypto) {
        if (entity is File) {
          final crc32 = Crc32();
          return (entity as File)
              .openRead()
              .transform<int>(StreamTransformer<List<int>, int>.fromHandlers(
                handleData: (data, sink) => crc32.update(data),
                handleDone: (sink) {
                  sink.add(crc32.crc);
                  sink.close();
                },
              ))
              .single;
        } else if (entity is Buffer) {
          final crc32 = Crc32();
          final buffer = (entity as Buffer).peek();
          while (!await buffer.exhausted()) {
            crc32.update(buffer.buffer.readBytes());
          }
          return crc32.crc;
        }
      }
    }

    return _crc ?? await crc() ?? 0;
  }

  Uint8List get attributes {
    if (Platform.isWindows) {
      if (isDirectory) return Uint8List.fromList([setBit(0, 4), 0, 0, 0]);
    } else {
      if (isDirectory) {
        return Uint8List.fromList([0, 0, -19, 65]);
      } else {
        return Uint8List.fromList([0, 0, -92, -127]);
      }
    }
    return Uint8List(4);
  }

  AesExtraDataRecord? aesExtraDataRecord() {
    final method = encryptionMethod;
    if (method is EncryptionAes) {
      return AesExtraDataRecord.from(method);
    }
    return null;
  }

  Future<void> write(Sink sink, [Encoding? encoding]) async {
    if (entity is File) {
      await (entity as File)
          .openRead()
          .source()
          .buffered()
          .use((source) => source.readIntoSink(sink));
    } else if (entity is Link) {
      final target = await (entity as Link).target();
      final buffered = sink.buffered();
      await buffered.writeString(target, encoding ?? cp437);
      await buffered.emit();
    } else if (entity is Buffer) {
      await (entity as Buffer).readIntoSink(sink);
    } else if (entity is Source) {
      await (entity as Source).buffered().readIntoSink(sink);
    }
  }
}
