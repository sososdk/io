import '../zip_exception.dart';

/// Indicates the AES format used
enum AesVersion {
  /// Version 1 of the AES format
  one(1),

  /// Version 2 of the AES format
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
