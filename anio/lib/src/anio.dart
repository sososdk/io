import 'dart:async';
import 'dart:convert';
import 'dart:core' as core show Sink;
import 'dart:core';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:synchronizer/synchronizer.dart';

part 'buffer.dart';
part 'file_handle.dart';
part 'sink.dart';
part 'source.dart';

const int kLF = 10; // \n
const int kCR = 13; // \r
const int kBlockSize = 8192;

class EOFException implements IOException {}

check(bool closed, [String? message]) {
  if (!closed) throw StateError(message ?? '');
}
