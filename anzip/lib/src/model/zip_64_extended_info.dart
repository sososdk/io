class Zip64ExtendedInfo {
  Zip64ExtendedInfo(
    this.compressedSize,
    this.uncompressedSize,
    this.offsetLocalHeader,
    this.diskNumberStart,
  );

  final int? compressedSize;
  final int? uncompressedSize;
  final int? offsetLocalHeader;
  final int? diskNumberStart;
}
