class ExtraDataRecord {
  const ExtraDataRecord(this.header, this.size, this.data);

  final int header;
  final int size;
  final List<int> data;
}
