part of 'zip_entry_sink.dart';

abstract class _CipherSink implements Sink {
  _CipherSink(this.sink, this.bufferedSink);

  static Future<_CipherSink> create(
      _OriginalSink sink, LocalFileHeader header, Uint8List? password) async {
    final bufferedSink = sink.buffered();
    final encryptionMethod = header.encryptionMethod;
    return switch (encryptionMethod) {
      EncryptionNone() => Future.value(_NoCipherSink(sink, bufferedSink)),
      EncryptionZipCrypto() => () async {
          final encrypter = ZipCryptoEncrypter(password!);
          final headerBytes = encrypter.genHeaderBytes(header.encryptionKey);
          await bufferedSink.writeFromBytes(headerBytes);
          return _ZipCryptoCipherSink(sink, bufferedSink, encrypter);
        }(),
      EncryptionAes() => () async {
          if (password == null || password.isEmpty) {
            throw ZipException('no password provided for AES decryption');
          }
          final encrypter =
              AesEncrypter(encryptionMethod.aesKeyStrength, password);
          await bufferedSink.writeFromBytes(encrypter.salt);
          await bufferedSink.writeFromBytes(encrypter.derivedPasswordVerifier);
          return _AesCipherSink(sink, bufferedSink, encrypter);
        }(),
    };
  }

  final _OriginalSink sink;

  final BufferedSink bufferedSink;

  int get compressedSize => sink.writtenSize;

  @override
  FutureOr<void> flush() => bufferedSink.flush();

  @override
  FutureOr<void> close() => bufferedSink.close();
}

class _NoCipherSink extends _CipherSink {
  _NoCipherSink(super.sink, super.bufferedSink);

  @override
  FutureOr<void> write(Buffer source, int count) =>
      bufferedSink.write(source, count);
}

class _ZipCryptoCipherSink extends _CipherSink {
  _ZipCryptoCipherSink(super.sink, super.bufferedSink, this._encrypter);

  final ZipCryptoEncrypter _encrypter;

  @override
  FutureOr<void> write(Buffer source, int count) async {
    final bytes = source.readBytes(count);
    _encrypter.encryptBytes(bytes, 0, bytes.length);
    await bufferedSink.writeFromBytes(bytes);
  }
}

class _AesCipherSink extends _CipherSink {
  _AesCipherSink(super.sink, super.bufferedSink, this._encrypter);

  final AesEncrypter _encrypter;
  final _encryptBuffer = Buffer();

  @override
  Future<void> write(Buffer source, int count) async {
    _encryptBuffer.write(source, count);
    final length = _encryptBuffer.length;
    final bytes = _encryptBuffer.readBytes(length - length % kAesBlockSize);
    _encrypter.encryptData(bytes, 0, bytes.length);
    await bufferedSink.writeFromBytes(bytes);
  }

  @override
  Future<void> close() async {
    if (!_encryptBuffer.exhausted()) {
      final bytes = _encryptBuffer.readBytes();
      _encrypter.encryptData(bytes, 0, bytes.length);
      await bufferedSink.writeFromBytes(bytes);
    }
    final calculatedMac = _encrypter.doFinal();
    await bufferedSink.writeFromBytes(calculatedMac);
    return super.close();
  }
}
