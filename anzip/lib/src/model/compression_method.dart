import 'package:meta/meta.dart';

import '../zip_exception.dart';

/// Indicates the algorithm used for compression.
sealed class CompressionMethod {
  const CompressionMethod();

  static CompressionMethod fromCode(int code) {
    if (code == 0) {
      return const CompressionStore();
    } else if (code == 1) {
      return const CompressionShrink();
    } else if (code == 2) {
      return CompressionReduce.reduce1;
    } else if (code == 3) {
      return CompressionReduce.reduce2;
    } else if (code == 4) {
      return CompressionReduce.reduce3;
    } else if (code == 5) {
      return CompressionReduce.reduce4;
    } else if (code == 6) {
      return const CompressionImplode();
    } else if (code == 8) {
      return const CompressionDeflate();
    } else if (code == 9) {
      return const CompressionDeflate64();
    } else if (code == 10) {
      return const CompressionPkwareImplode();
    } else if (code == 12) {
      return const CompressionBzip2();
    } else if (code == 14) {
      return const CompressionLzma();
    } else if (code == 16) {
      return const CompressionIbmZosCmpsc();
    } else if (code == 18) {
      return const CompressionIbmTerse();
    } else if (code == 20) {
      return const CompressionZstdDeprecated();
    } else if (code == 93) {
      return const CompressionZstd();
    } else if (code == 94) {
      return const CompressionMp3();
    } else if (code == 95) {
      return const CompressionXz();
    } else if (code == 96) {
      return const CompressionJpeg();
    } else if (code == 97) {
      return const CompressionWavpack();
    } else if (code == 98) {
      return const CompressionPpmd();
    } else if (code == 99) {
      return const CompressionAes();
    }
    throw ZipException('Unsupported compression method: $code');
  }

  int get code;

  String get name;
}

/// No compression is performed.
class CompressionStore extends CompressionMethod {
  const CompressionStore();

  @override
  int get code => 0;

  @override
  String get name => 'Store';
}

class CompressionShrink extends CompressionMethod {
  const CompressionShrink();

  @override
  int get code => 1;

  @override
  String get name => 'Shrink';
}

class CompressionReduce extends CompressionMethod {
  const CompressionReduce(this.code);

  @override
  final int code;

  static const reduce1 = CompressionReduce(2);
  static const reduce2 = CompressionReduce(3);
  static const reduce3 = CompressionReduce(4);
  static const reduce4 = CompressionReduce(5);

  @override
  String get name => 'Reduce(${code - 1})';
}

class CompressionImplode extends CompressionMethod {
  const CompressionImplode();

  @override
  int get code => 6;

  @override
  String get name => 'Implode';
}

/// The Deflate compression is used.
class CompressionDeflate extends CompressionMethod {
  /// The compression-[level] can be set in the range of `-1..9`, with `6` being
  /// the default compression level. Levels above `6` will have higher
  /// compression rates at the cost of more CPU and memory usage. Levels below
  /// `6` will use less CPU and memory at the cost of lower compression rates.
  final int level;

  const CompressionDeflate([this.level = 6]);

  @override
  int get code => 8;

  @override
  String get name => 'Deflate';
}

class CompressionDeflate64 extends CompressionMethod {
  const CompressionDeflate64();

  @override
  int get code => 9;

  @override
  String get name => 'Deflate64';
}

/// PKWARE Data Compression Library (DCL) Imploding.
class CompressionPkwareImplode extends CompressionMethod {
  const CompressionPkwareImplode();

  @override
  int get code => 10;

  @override
  String get name => 'PKWARE Implode';
}

class CompressionBzip2 extends CompressionMethod {
  /// 0 - 9. Default is 6
  final int level;

  const CompressionBzip2([this.level = 6]);

  @override
  int get code => 12;

  @override
  String get name => 'BZIP2';
}

class CompressionLzma extends CompressionMethod {
  const CompressionLzma();

  @override
  int get code => 14;

  @override
  String get name => 'LZMA';
}

class CompressionIbmZosCmpsc extends CompressionMethod {
  const CompressionIbmZosCmpsc();

  @override
  int get code => 16;

  @override
  String get name => 'IBM ZOS CMPSC';
}

class CompressionIbmTerse extends CompressionMethod {
  const CompressionIbmTerse();

  @override
  int get code => 18;

  @override
  String get name => 'IBM Terse';
}

class CompressionZstdDeprecated extends CompressionMethod {
  const CompressionZstdDeprecated();

  @override
  int get code => 20;

  @override
  String get name => 'ZSTD Deprecated';
}

class CompressionZstd extends CompressionMethod {
  /// -7 - 22, with zero being mapped to default level. Default is 3
  final int level;

  const CompressionZstd([this.level = 3]);

  @override
  int get code => 93;

  @override
  String get name => 'ZSTD';
}

class CompressionMp3 extends CompressionMethod {
  const CompressionMp3();

  @override
  int get code => 94;

  @override
  String get name => 'MP3';
}

class CompressionXz extends CompressionMethod {
  const CompressionXz();

  @override
  int get code => 95;

  @override
  String get name => 'XZ';
}

class CompressionJpeg extends CompressionMethod {
  const CompressionJpeg();

  @override
  int get code => 96;

  @override
  String get name => 'JPEG';
}

class CompressionWavpack extends CompressionMethod {
  const CompressionWavpack();

  @override
  int get code => 97;

  @override
  String get name => 'WAVPACK';
}

class CompressionPpmd extends CompressionMethod {
  const CompressionPpmd();

  @override
  int get code => 98;

  @override
  String get name => 'PPMD';
}

@internal
class CompressionAes extends CompressionMethod {
  const CompressionAes();

  @override
  int get code => 99;

  @override
  String get name => 'AES';
}
