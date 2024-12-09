import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'bit_utils.dart';
import 'model/compression_method.dart';
import 'model/encryption_method.dart';
import 'model/file_entry.dart';

const dosTimeBefore1980 = (1 << 21) | (1 << 16);

int determineVersionMadeBy() {
  return Uint8List.fromList([51, Platform.isWindows ? 0 : 3])
      .buffer
      .asByteData()
      .getInt16(0, Endian.little);
}

Future<int> determineVersionNeeded(FileEntry entity) async {
  final compressionVersion = switch (entity.compressionMethod) {
    CompressionStore() => 10,
    CompressionDeflate() => 20,
    CompressionDeflate64() => 21,
    CompressionBzip2() => 46,
    CompressionLzma() => 63,
    CompressionXz() => 63,
    _ => 45
  };
  final cryptoVersion = switch (entity.encryptionMethod) {
    EncryptionAes() => 51,
    EncryptionZipCrypto() => 20,
    EncryptionNone() => 10,
  };
  final int miscFeatureVersion;
  if (await entity.isZip64Format()) {
    miscFeatureVersion = 45;
  } else if (entity.isDirectory) {
    miscFeatureVersion = 20;
  } else {
    miscFeatureVersion = 10;
  }
  return max(max(compressionVersion, cryptoVersion), miscFeatureVersion);
}

Uint8List determineGeneralPurposeBitFlag(FileEntry entry, Encoding? encoding) {
  return Uint8List.fromList([
    () {
      var byte = 0;
      if (entry.encryptionMethod.isEncrypted) byte = setBit(byte, 0);
      if (entry.useDataDescriptor) byte = setBit(byte, 3);
      return byte;
    }(),
    if (encoding?.name == 'utf-8') setBit(0, 3) else 0
  ]);
}

DateTime dosToEpochTime(int dosTime) {
  final sec = (dosTime << 1) & 0x3e;
  final min = (dosTime >> 5) & 0x3f;
  final hrs = (dosTime >> 11) & 0x1f;
  final day = (dosTime >> 16) & 0x1f;
  final mon = ((dosTime >> 21) & 0xf) - 1;
  final year = ((dosTime >> 25) & 0x7f) + 1980;
  final time = DateTime.utc(year, mon, day, hrs, min, sec);
  return DateTime.fromMillisecondsSinceEpoch(
    time.millisecondsSinceEpoch + (dosTime >> 32),
  );
}

int epochToDosTime(DateTime epochTime) {
  final year = epochTime.year;
  if (year < 1980) {
    return dosTimeBefore1980;
  }
  return (year - 1980) << 25 |
      (epochTime.month + 1) << 21 |
      epochTime.day << 16 |
      epochTime.hour << 11 |
      epochTime.minute << 5 |
      epochTime.second >> 1;
}
