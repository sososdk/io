import 'dart:io';

import 'package:anio/anio.dart';
import 'package:path/path.dart' as p;

import 'model/file_header.dart';
import 'model/zip_model.dart';
import 'split_random_access_file.dart';

class ZipFileHandle {
  final FileHandle handle;

  ZipFileHandle(this.handle);

  static Future<ZipFileHandle> openRead(File file, ZipModel model) async {
    final RandomAccessFile randomAccessFile;
    if (model.numberOfThisDisk > 0) {
      final naming = SplitFileNaming(p.basenameWithoutExtension(file.path));
      final part = File(p.join(file.parent.path, naming.splitName(1)));
      final splitLength = await part.length();
      randomAccessFile = await SplitRandomAccessFile.openRead(
          file, model.numberOfThisDisk, splitLength, naming);
    } else {
      randomAccessFile = await file.open(mode: FileMode.read);
    }
    return ZipFileHandle(randomAccessFile.handle());
  }

  RandomAccessFile get randomAccessFile => handle.file;

  int getPosition(FileHeader header) {
    final file = randomAccessFile;
    if (file is SplitRandomAccessFile) {
      final start = header.diskNumberStart * file.splitLength;
      return start + header.offsetLocalHeader;
    } else {
      return header.offsetLocalHeader;
    }
  }

  Source source(FileHeader header) {
    return handle.source(getPosition(header));
  }

  Future<void> close() => handle.close();
}
