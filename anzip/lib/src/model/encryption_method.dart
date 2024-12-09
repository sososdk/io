import 'dart:math';
import 'dart:typed_data';

import '../zip_exception.dart';

/// Indicates the encryption method used in the ZIP file.
sealed class EncryptionMethod {
  const EncryptionMethod();

  String get name;

  bool get isEncrypted;
}

/// No encryption is performed.
class EncryptionNone extends EncryptionMethod {
  const EncryptionNone();

  @override
  String get name => 'None';

  @override
  bool get isEncrypted => false;
}

/// Encrypted with the weak ZIP standard algorithm.
class EncryptionZipCrypto extends EncryptionMethod {
  const EncryptionZipCrypto();

  @override
  String get name => 'ZipCrypto';

  @override
  bool get isEncrypted => true;
}

/// Encrypted with AES, the strongest choice but currently cannot be expanded in
/// Windows Explorer.
class EncryptionAes extends EncryptionMethod {
  final String vendorID;
  final AesVersion aesVersion;
  final AesKeyStrength aesKeyStrength;

  const EncryptionAes(
    this.aesVersion,
    this.aesKeyStrength, {
    this.vendorID = 'AE',
  }) : assert(vendorID.length == 2);

  @override
  String get name => 'AES-$aesVersion-$aesKeyStrength-$vendorID';

  @override
  bool get isEncrypted => true;
}

/// Indicates the AES format used.
enum AesVersion {
  /// Version 1 of the AES format.
  one(1),

  /// Version 2 of the AES format.
  two(2);

  final int versionNumber;

  const AesVersion(this.versionNumber);

  static AesVersion fromVersionNumber(int versionNumber) =>
      switch (versionNumber) {
        1 => one,
        2 => two,
        _ => throw ZipException('Unsupported AES version: $versionNumber')
      };
}

/// Indicates the AES encryption key length.
enum AesKeyStrength {
  /// 128-bit AES key length.
  keyStrength128(1, 8, 16, 16),

  /// 192-bit AES key length.
  keyStrength192(2, 12, 24, 24),

  /// 256-bit AES key length.
  keyStrength256(3, 16, 32, 32);

  final int code;
  final int saltLength;
  final int macLength;
  final int keyLength;

  const AesKeyStrength(
      this.code, this.saltLength, this.macLength, this.keyLength);

  static AesKeyStrength fromRawCode(int rawCode) {
    return switch (rawCode) {
      1 => keyStrength128,
      2 => keyStrength192,
      3 => keyStrength256,
      _ => throw ZipException('Invalid raw code: $rawCode')
    };
  }

  Uint8List genSalt() {
    final random = Random.secure();
    return Uint8List.fromList(
        List.generate(saltLength, (_) => random.nextInt(256)));
  }
}
