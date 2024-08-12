part of 'zip_entry_source.dart';

abstract class _CipherSource implements Source {
  _CipherSource(Source entrySource) : entrySource = entrySource.buffered();

  static Future<Source> create(BufferedSource source, Source entrySource,
      LocalFileHeader header, Uint8List? password) async {
    if (header.encryptionMethod == EncryptionMethod.none) {
      return _NoCipherSource(entrySource);
    } else if (header.encryptionMethod == EncryptionMethod.aes) {
      final aesData = header.aesExtraDataRecord;
      if (aesData == null) {
        throw ZipException('AES extra data record not present in header');
      }
      if (password == null || password.isEmpty) {
        throw ZipException('no password provided for AES decryption');
      }
      final strength = aesData.aesKeyStrength;
      final salt = await source.readBytes(strength.saltLength);
      final passwordVerifier = await source.readBytes(aesVerifierLength);
      final decrypter =
          AESDecrypter(strength, salt, passwordVerifier, password);
      return _AesCipherSource(source, entrySource, decrypter);
    } else if (header.encryptionMethod == EncryptionMethod.standard) {
      if (password == null || password.isEmpty) {
        throw ZipException('no password provided for standard decryption');
      }
      final headerBytes = await source.readBytes(stdDecHdrSize);
      final decrypter = StandardDecrypter(
          headerBytes, header.rawLastModifiedTime, header.crc, password);
      return _StandardCipherSource(entrySource, decrypter);
    } else {
      throw ZipException(
          'Entry [${header.fileName}] ${header.encryptionMethod.name} not supported');
    }
  }

  final BufferedSource entrySource;

  @override
  FutureOr<void> close() => entrySource.close();
}

class _NoCipherSource extends _CipherSource {
  _NoCipherSource(super.source);

  @override
  FutureOr<int> read(Buffer sink, int count) => entrySource.read(sink, count);
}

class _AesCipherSource extends _CipherSource {
  _AesCipherSource(this._source, super.entrySource, this._decrypter);

  final BufferedSource _source;
  final AESDecrypter _decrypter;
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

  FutureOr<void> _decrypt() async {
    if (!_decryptedBuffer.exhausted()) return;
    if (await entrySource.exhausted()) {
      if (_finished) return;
      _finished = true;
      final bytes = _decryptBuffer.readBytes();
      _decrypter.decryptData(bytes, 0, bytes.length);
      _decryptedBuffer.writeFromBytes(bytes);
    } else {
      _decryptBuffer.writeFromBytes(entrySource.buffer.readBytes());
      final length = _decryptBuffer.length;
      final bytes = _decryptBuffer.readBytes(length - length % aesBlockSize);
      _decrypter.decryptData(bytes, 0, bytes.length);
      _decryptedBuffer.writeFromBytes(bytes);
    }
  }

  FutureOr<void> _verify() async {
    if (_verified) return;
    _verified = true;
    final storedMac = await _source.readBytes(aesAuthLength);
    final calculatedMac = _decrypter.doFinal();
    if (!const ListEquality().equals(storedMac, calculatedMac)) {
      throw ZipException(
          'Reached end of data for this entry, but aes verification failed');
    }
  }
}

class _StandardCipherSource extends _CipherSource {
  _StandardCipherSource(super.entrySource, this._decrypter);

  final StandardDecrypter _decrypter;
  final _buffer = Buffer();

  @override
  FutureOr<int> read(Buffer sink, int count) async {
    while (true) {
      await _decrypt();
      final result = _buffer.read(sink, count);
      if (result > 0) return result;
      if (await entrySource.exhausted()) return 0;
    }
  }

  FutureOr<void> _decrypt() async {
    if (!_buffer.exhausted()) return;
    if (!await entrySource.exhausted()) {
      final bytes = entrySource.buffer.readBytes();
      _decrypter.decryptData(bytes, 0, bytes.length);
      _buffer.writeFromBytes(bytes);
    }
  }
}
