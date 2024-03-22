import 'dart:io';

import 'bit_utils.dart';

Future<void> setFileAttributes(String path, List<int> attributes) async {
  if (Platform.isWindows) {
    // No file attributes defined in the archive
    if (attributes[0] == 0) return;

    final isReadOnly = isBitSet(attributes[0], 0);
    final isHidden = isBitSet(attributes[0], 1);
    final isSystem = isBitSet(attributes[0], 2);
    final isArchive = isBitSet(attributes[0], 5);
    String cmd(bool flag, String arg) => '${flag ? '+' : '-'}$arg';
    final attribs =
        '${cmd(isReadOnly, 'R')} ${cmd(isHidden, 'H')} ${cmd(isSystem, 'S')} ${cmd(isArchive, 'A')}';
    await Process.run('attrib', [attribs, path]);
  } else {
    // No file attributes defined
    if (attributes[2] == 0 && attributes[3] == 0) return;

    final isOwnerRead = isBitSet(attributes[3], 0);
    final isOwnerWrite = isBitSet(attributes[2], 7);
    final isOwnerExecute = isBitSet(attributes[2], 6);
    final isGroupRead = isBitSet(attributes[2], 5);
    final isGroupWrite = isBitSet(attributes[2], 4);
    final isGroupExecute = isBitSet(attributes[2], 3);
    final isOthersRead = isBitSet(attributes[2], 2);
    final isOthersWrite = isBitSet(attributes[2], 1);
    final isOthersExecute = isBitSet(attributes[2], 0);
    String permission(String profile, bool read, bool write, bool execute) {
      return '$profile=${read ? 'r' : '-'}${write ? 'w' : '-'}${execute ? 'x' : '-'}';
    }

    final permissions =
        '${permission('u', isOwnerRead, isOwnerWrite, isOwnerExecute)} ${permission('g', isGroupRead, isGroupWrite, isGroupExecute)} ${permission('o', isOthersRead, isOthersWrite, isOthersExecute)}';
    await Process.run('chmod', [permissions, path]);
  }
}
