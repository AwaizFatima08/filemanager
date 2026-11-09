import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'file_logic.dart';

/// Reads a folder in a background isolate so big folders never freeze the UI.
/// Entries that cannot be read (permission, broken links) are skipped.
Future<List<FileEntry>> listFolder(String path, {bool showHidden = false}) {
  return Isolate.run(() {
    final out = <FileEntry>[];
    for (final e in Directory(path).listSync(followLinks: false)) {
      final name = p.basename(e.path);
      if (!showHidden && name.startsWith('.')) continue;
      try {
        final st = e.statSync();
        final isDir = st.type == FileSystemEntityType.directory;
        out.add(FileEntry(path: e.path, isDir: isDir, size: isDir ? 0 : st.size, modified: st.modified));
      } on FileSystemException {
        // unreadable entry: leave it out
      }
    }
    return out;
  });
}

/// Number of visible items inside a folder, or null if it cannot be read.
Future<int?> countItems(String path) async {
  try {
    return await Directory(path).list().where((e) => !p.basename(e.path).startsWith('.')).length;
  } on FileSystemException {
    return null;
  }
}

enum PasteMode { copy, move }

/// Result of a paste: how many items worked and the messages for the rest.
class OpResult {
  OpResult(this.done, this.errors);
  final int done;
  final List<String> errors;
}

/// Copies or moves [sources] into [targetDir]. A clashing name gets " (1)"
/// added rather than overwriting anything. Moves try a fast rename first and
/// fall back to copy-then-delete across storage volumes.
Future<OpResult> paste(List<String> sources, String targetDir, PasteMode mode) async {
  var done = 0;
  final errors = <String>[];
  final existing = (await Directory(targetDir).list().map((e) => p.basename(e.path)).toList()).toSet();
  for (final src in sources) {
    final name = p.basename(src);
    try {
      final isDir = await FileSystemEntity.isDirectory(src);
      if (isDir && isSameOrInside(src, targetDir)) {
        errors.add('$name: cannot put a folder inside itself');
        continue;
      }
      if (mode == PasteMode.move && p.equals(p.dirname(src), targetDir)) {
        done++; // already here
        continue;
      }
      final newName = uniqueName(name, existing);
      existing.add(newName);
      final dest = p.join(targetDir, newName);
      if (mode == PasteMode.move) {
        await _move(src, dest, isDir);
      } else {
        isDir ? await _copyDir(Directory(src), Directory(dest)) : await File(src).copy(dest);
      }
      done++;
    } on FileSystemException catch (e) {
      errors.add('$name: ${e.osError?.message ?? e.message}');
    }
  }
  return OpResult(done, errors);
}

Future<void> _move(String src, String dest, bool isDir) async {
  try {
    await (isDir ? Directory(src) : File(src)).rename(dest);
  } on FileSystemException {
    if (isDir) {
      await _copyDir(Directory(src), Directory(dest));
      await Directory(src).delete(recursive: true);
    } else {
      await File(src).copy(dest);
      await File(src).delete();
    }
  }
}

Future<void> _copyDir(Directory src, Directory dest) async {
  await dest.create(recursive: true);
  await for (final e in src.list(followLinks: false)) {
    final target = p.join(dest.path, p.basename(e.path));
    if (e is Directory) {
      await _copyDir(e, Directory(target));
    } else if (e is File) {
      await e.copy(target);
    }
  }
}

Future<OpResult> deleteAll(List<String> paths) async {
  var done = 0;
  final errors = <String>[];
  for (final path in paths) {
    try {
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
      done++;
    } on FileSystemException catch (e) {
      errors.add('${p.basename(path)}: ${e.osError?.message ?? e.message}');
    }
  }
  return OpResult(done, errors);
}

/// Checks a name typed by the user; returns an error message or null.
String? validateName(String name) {
  final n = name.trim();
  if (n.isEmpty) return 'Enter a name';
  if (n == '.' || n == '..') return 'Not a valid name';
  if (RegExp(r'[/\\:*?"<>|]').hasMatch(n)) return r'A name cannot contain / \ : * ? " < > |';
  return null;
}

Future<void> rename(String path, String newName) async {
  final dest = p.join(p.dirname(path), newName.trim());
  if (await FileSystemEntity.type(dest) != FileSystemEntityType.notFound) {
    throw const FileSystemException('Something with this name already exists');
  }
  await (await FileSystemEntity.isDirectory(path) ? Directory(path) : File(path)).rename(dest);
}

Future<void> createFolder(String parent, String name) async {
  final dir = Directory(p.join(parent, name.trim()));
  if (await dir.exists()) throw const FileSystemException('This folder already exists');
  await dir.create();
}
