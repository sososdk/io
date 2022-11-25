import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

part 'buffer.dart';
part 'sink.dart';
part 'source.dart';

const int kLF = 10; // \n
const int kCR = 13; // \r
const int kBlockSize = 8192;

class EOFException implements IOException {}
