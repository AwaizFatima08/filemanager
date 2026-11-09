import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const internalRoot = '/storage/emulated/0';

/// A storage volume the user can browse.
class StorageRoot {
  const StorageRoot(this.label, this.path);
  final String label;
  final String path;
}

/// Internal storage plus any SD card or USB drive. Removable volumes are found
/// from the app's own folder on them (`/storage/XXXX-XXXX/Android/data/...`).
Future<List<StorageRoot>> storageRoots() async {
  final roots = [const StorageRoot('Internal storage', internalRoot)];
  try {
    final dirs = await getExternalStorageDirectories() ?? const [];
    for (final d in dirs) {
      final i = d.path.indexOf('/Android/');
      if (i <= 0) continue;
      final root = d.path.substring(0, i);
      if (root == internalRoot || roots.any((r) => r.path == root)) continue;
      roots.add(StorageRoot('SD card / USB (${p.basename(root)})', root));
    }
  } on Object {
    // no extra volumes
  }
  return roots;
}

/// Common folders on internal storage, shown as shortcuts when they exist.
const quickFolders = <(String, String)>[
  ('Download', 'Downloads'),
  ('DCIM/Camera', 'Camera'),
  ('Pictures', 'Pictures'),
  ('Documents', 'Documents'),
  ('Music', 'Music'),
  ('Movies', 'Videos'),
];

/// A nested shortcut (DCIM/Camera) falls back to its parent (DCIM) when missing.
Future<List<(String, String)>> existingQuickFolders() async {
  final out = <(String, String)>[];
  for (final (dir, label) in quickFolders) {
    for (final candidate in {dir, p.split(dir).first}) {
      final path = p.join(internalRoot, candidate);
      if (await Directory(path).exists()) {
        out.add((path, label));
        break;
      }
    }
  }
  return out;
}

/// A file manager needs "All files access" on Android 11+, and the old storage
/// permission on Android 10 and below.
Future<bool> hasStorageAccess() async =>
    await Permission.manageExternalStorage.isGranted || await Permission.storage.isGranted;

Future<bool> requestStorageAccess() async {
  if (await Permission.manageExternalStorage.request().isGranted) return true;
  return Permission.storage.request().isGranted;
}
