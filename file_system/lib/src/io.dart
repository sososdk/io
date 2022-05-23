import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'file_system.dart';

part 'buffer.dart';
part 'sink.dart';
part 'source.dart';

const int kLF = 10; // \n
const int kCR = 13; // \r
const int kBlockSize = 8192;

class EOFException implements IOException {}
