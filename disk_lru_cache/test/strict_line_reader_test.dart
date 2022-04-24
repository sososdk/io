import 'package:disk_lru_cache/src/strict_line_reader.dart';
import 'package:file/local.dart';
import 'package:file_system/file_system.dart';
import 'package:test/test.dart';

void main() {
  final fileSystem = const LocalFileSystem();

  test('strict line reader', () {
    return fileSystem.read('test/strict_line_reader_journal', (source) async {
      final reader = StrictLineReader(source);
      try {
        expect(await reader.readLine(), '1');
        expect(await reader.readLine(), '2');
        expect(await reader.readLine(), '3');
        while (true) {
          await reader.readLine();
        }
      } on EOFException {
        expect(reader.hasUnterminatedLine, false);
      }
    });
  });

  test('strict line reader has unterminated Line', () {
    return fileSystem.read('test/strict_line_reader_journal_unterminated',
        (source) async {
      final reader = StrictLineReader(source);
      try {
        expect(await reader.readLine(), '1');
        expect(await reader.readLine(), '2');
        expect(await reader.readLine(), '3');
        while (true) {
          await reader.readLine();
        }
      } on EOFException {
        expect(reader.hasUnterminatedLine, true);
      }
    });
  });
}
