import 'package:file_system/file_system.dart';

class IndexRandomAccessFile with ForwardingRandomAccessFile {
  final int index;

  @override
  final RandomAccessFile delegate;

  IndexRandomAccessFile(this.index, this.delegate);
}
