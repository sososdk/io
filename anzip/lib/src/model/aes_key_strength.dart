import '../zip_exception.dart';

/// Indicates the AES encryption key length
///
enum AesKeyStrength {
  /// 128-bit AES key length
  keyStrength128(1, 8, 16, 16),

  /// 192-bit AES key length
  keyStrength192(2, 12, 24, 24),

  /// 256-bit AES key length
  keyStrength256(3, 16, 32, 32);

  final int rawCode;
  final int saltLength;
  final int macLength;
  final int keyLength;

  const AesKeyStrength(
      this.rawCode, this.saltLength, this.macLength, this.keyLength);

  static AesKeyStrength fromRawCode(int rawCode) {
    return switch (rawCode) {
      1 => keyStrength128,
      2 => keyStrength192,
      3 => keyStrength256,
      _ => throw ZipException('Invalid raw code: $rawCode')
    };
  }
}
