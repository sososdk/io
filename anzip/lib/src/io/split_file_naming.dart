class SplitFileNaming {
  static const String prefix = 'z';

  SplitFileNaming(this.name) : _pattern = RegExp('^$name\\.$prefix(\\d*)\$');

  final String name;
  final RegExp _pattern;

  String indexName(int index) {
    return '$name.$prefix${index.toString().padLeft(2, '0')}';
  }

  int? index(String name) {
    final match = _pattern.firstMatch(name);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }
}
