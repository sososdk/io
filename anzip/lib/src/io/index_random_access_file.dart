import 'dart:io';

import 'package:anio/anio.dart';

class IndexFileHandle with FileHandleBase {
  final int index;

  @override
  final RandomAccessFile delegate;

  IndexFileHandle(this.index, this.delegate);
}
