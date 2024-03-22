import 'zip_exception.dart';

enum CompressionMethod {
  store(0),
  shrink(1),
  reduce1(2),
  reduce2(3),
  reduce3(4),
  reduce4(5),
  implode(6),
  tokenize(7),
  deflate(8),
  deflate64(9),
  pkwareImplode(10),
  bzip2(12),
  lzma(14),
  ibmZosCmpsc(16),
  ibmTerse(18),
  zstdDeprecated(20),
  zstd(93),
  mp3(94),
  xz(95),
  jpeg(96),
  wavPack(97),
  ppmd(98),
  aes(99);

  const CompressionMethod(this.code);

  final int code;

  static CompressionMethod fromCode(int code) {
    for (final method in CompressionMethod.values) {
      if (method.code == code) {
        return method;
      }
    }
    throw ZipException('Unknown compression method: $code');
  }
}
