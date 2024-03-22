import 'dart:io';

class ZipException implements IOException {
  ZipException([this.message]);

  final String? message;

  @override
  String toString() => 'ZipException{message: $message}';
}
