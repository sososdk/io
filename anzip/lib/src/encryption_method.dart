/// Indicates the encryption method used in the ZIP file
enum EncryptionMethod {
  /// No encryption is performed
  none,

  /// Encrypted with the weak ZIP standard algorithm
  standard,

  /// Encrypted with the stronger ZIP standard algorithm
  standardVariantStrong,

  /// Encrypted with AES, the strongest choice but currently
  /// cannot be expanded in Windows Explorer
  aes
}
