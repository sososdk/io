part of 'zip_entry_source.dart';

abstract class _CipherSource implements Source {
  _CipherSource(this.source);

  static Future<Source> create(BufferedSource original, BufferedSource source,
      LocalFileHeader header, Uint8List? password) async {
    final encryptionMethod = header.encryptionMethod;
    return switch (encryptionMethod) {
      EncryptionNone() => Future.value(_NoCipherSource(source)),
      EncryptionZipCrypto() => () async {
          if (password == null || password.isEmpty) {
            throw ZipException('no password provided');
          }
          final headerBytes = await original.readBytes(kStdDecHdrSize);
          final decrypter = ZipCryptoDecrypter(password);
          decrypter.validate(headerBytes, header.crc, header.dosTime);
          return _ZipCryptoCipherSource(source, decrypter);
        }(),
      EncryptionAes() => () async {
          if (password == null || password.isEmpty) {
            throw ZipException('no password provided');
          }
          final strength = encryptionMethod.aesKeyStrength;
          final salt = await original.readBytes(strength.saltLength);
          final passwordVerifier = await original.readBytes(kAesVerifierLength);
          final decrypter =
              AesDecrypter(strength, salt, passwordVerifier, password);
          return _AesCipherSource(original, source, decrypter);
        }(),
    };
  }

  final BufferedSource source;

  @override
  FutureOr<void> close() => source.close();
}

class _NoCipherSource extends _CipherSource {
  _NoCipherSource(super.source);

  @override
  FutureOr<int> read(Buffer sink, int count) => source.read(sink, count);
}

class _ZipCryptoCipherSource extends _CipherSource {
  _ZipCryptoCipherSource(super.source, this._decrypter);

  final ZipCryptoDecrypter _decrypter;
  final _buffer = Buffer();

  @override
  FutureOr<int> read(Buffer sink, int count) async {
    while (true) {
      await _decrypt();
      final result = _buffer.read(sink, count);
      if (result > 0) return result;
      if (await source.exhausted()) return 0;
    }
  }

  FutureOr<void> _decrypt() async {
    if (!_buffer.exhausted()) return;
    if (!await source.exhausted()) {
      final bytes = source.buffer.readBytes();
      _decrypter.decryptBytes(bytes, 0, bytes.length);
      _buffer.writeFromBytes(bytes);
    }
  }
}

class _AesCipherSource extends _CipherSource {
  _AesCipherSource(this._original, super.source, this._decrypter);

  final BufferedSource _original;
  final AesDecrypter _decrypter;
  final _decryptedBuffer = Buffer();

  bool _finished = false, _verified = false;

  @override
  FutureOr<int> read(Buffer sink, int count) async {
    try {
      while (true) {
        await _decrypt();
        final result = _decryptedBuffer.read(sink, count);
        if (result > 0) return result;
        if (_finished) return 0;
      }
    } finally {
      if (_finished) await _verify();
    }
  }

  final _decryptBuffer = Buffer();

  Future<void> _decrypt() async {
    if (!_decryptedBuffer.exhausted()) return;
    if (await source.exhausted()) {
      if (_finished) return;
      _finished = true;
      final bytes = _decryptBuffer.readBytes();
      _decrypter.decryptData(bytes, 0, bytes.length);
      _decryptedBuffer.writeFromBytes(bytes);
    } else {
      _decryptBuffer.writeFromBytes(source.buffer.readBytes());
      final length = _decryptBuffer.length;
      final bytes = _decryptBuffer.readBytes(length - length % kAesBlockSize);
      _decrypter.decryptData(bytes, 0, bytes.length);
      _decryptedBuffer.writeFromBytes(bytes);
    }
  }

  FutureOr<void> _verify() async {
    if (_verified) return;
    _verified = true;
    final storedMac = await _original.readBytes(kAesAuthLength);
    final calculatedMac = _decrypter.doFinal();
    if (!const ListEquality().equals(storedMac, calculatedMac)) {
      throw ZipException(
          'Reached end of data for this entry, but aes verification failed');
    }
  }
}
