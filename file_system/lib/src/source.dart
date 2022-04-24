import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

// Read the source in blocks of size 64k.
const int _blockSize = 64 * 1024;

abstract class Source {
  /// Reads up to [count] bytes from a source.
  Future<Uint8List> read(int count);

  /// Reads the source contents as a list of bytes.
  ///
  /// Returns a `Future<Uint8List>` that completes with the list of bytes that
  /// is the contents of the source.
  Future<Uint8List> readAsBytes() {
    final builder = BytesBuilder(copy: false);
    final completer = Completer<Uint8List>();
    void read() {
      this.read(_blockSize).then((data) {
        if (data.isNotEmpty) {
          builder.add(data);
          read();
        } else {
          completer.complete(builder.takeBytes());
        }
      }, onError: completer.completeError);
    }

    read();
    return completer.future;
  }

  /// Reads the source contents as a string using the given [Encoding].
  ///
  /// Returns a `Future<String>` that completes with the string once
  /// the source has been read.
  Future<String> readAsString({Encoding encoding = utf8}) =>
      readAsBytes().then((bytes) => encoding.decode(bytes));

  /// Reads the source contents as lines of text using the given
  /// [Encoding].
  ///
  /// Returns a `Future<List<String>>` that completes with the lines
  /// once the source has been read.
  Future<List<String>> readAsLines({Encoding encoding = utf8}) =>
      readAsString(encoding: encoding).then(const LineSplitter().convert);

  /// Closes this source and releases the resources held by this source. It is
  /// an error to read a closed source. It is safe to close a source more than
  /// once.
  Future close();
}
