import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

/// One file or folder as shown in a listing. Plain data, so listings can be
/// built in a background isolate and sorted and grouped in tests.
class FileEntry {
  const FileEntry({required this.path, required this.isDir, required this.size, required this.modified});

  final String path;
  final bool isDir;

  /// Bytes for files; 0 for folders.
  final int size;
  final DateTime modified;

  String get name => p.basename(path);
  bool get isHidden => name.startsWith('.');

  /// Lower-case extension without the dot, '' for folders and files without one.
  String get extension => isDir ? '' : p.extension(path).replaceFirst('.', '').toLowerCase();

  FileKind get kind => isDir ? FileKind.folder : kindForExtension(extension);
}

enum SortBy { name, date, size, type }

enum GroupBy { none, type, date, size, letter }

enum FileKind {
  folder('Folders'),
  image('Images'),
  video('Videos'),
  audio('Audio'),
  document('Documents'),
  archive('Archives'),
  apk('Apps (APK)'),
  other('Other');

  const FileKind(this.label);
  final String label;
}

const _kindByExtension = <FileKind, Set<String>>{
  FileKind.image: {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'svg'},
  FileKind.video: {'mp4', 'mkv', 'avi', 'mov', 'webm', '3gp', 'm4v', 'flv', 'wmv'},
  FileKind.audio: {'mp3', 'wav', 'ogg', 'm4a', 'aac', 'flac', 'opus', 'amr', 'wma'},
  FileKind.document: {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf', 'odt', 'ods', 'odp', //
    'csv', 'md', 'json', 'xml', 'html', 'htm', 'epub',
  },
  FileKind.archive: {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'},
  FileKind.apk: {'apk', 'apks', 'xapk'},
};

FileKind kindForExtension(String ext) {
  for (final MapEntry(:key, :value) in _kindByExtension.entries) {
    if (value.contains(ext)) return key;
  }
  return FileKind.other;
}

/// Sorts a copy of [entries]. Folders always come first; [ascending] flips the
/// order within folders and within files.
List<FileEntry> sortEntries(List<FileEntry> entries, SortBy by, {bool ascending = true}) {
  int byName(FileEntry a, FileEntry b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
  int compare(FileEntry a, FileEntry b) {
    final c = switch (by) {
      SortBy.name => 0,
      SortBy.date => a.modified.compareTo(b.modified),
      SortBy.size => a.size.compareTo(b.size),
      SortBy.type => a.extension.compareTo(b.extension),
    };
    return c != 0 ? c : byName(a, b);
  }

  final list = [...entries];
  list.sort((a, b) {
    if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
    // Folders have no size or type, so those sorts keep them A → Z.
    if (a.isDir && (by == SortBy.size || by == SortBy.type)) return byName(a, b);
    final c = compare(a, b);
    return ascending ? c : -c;
  });
  return list;
}

/// A titled section of a listing.
class EntryGroup {
  const EntryGroup(this.title, this.entries);
  final String title;
  final List<FileEntry> entries;
}

/// Splits already sorted [entries] into sections, keeping their order inside
/// each section. Sections appear in a fixed, meaningful order (e.g. Today
/// before Yesterday), and empty ones are left out. [GroupBy.none] gives one
/// untitled section.
List<EntryGroup> groupEntries(List<FileEntry> entries, GroupBy by, {DateTime? now}) {
  if (by == GroupBy.none) return [EntryGroup('', entries)];
  final today = now ?? DateTime.now();
  final buckets = <String, List<FileEntry>>{};
  final order = <String, int>{};
  for (final e in entries) {
    final (title, rank) = _bucketFor(e, by, today);
    buckets.putIfAbsent(title, () => []).add(e);
    order[title] = rank;
  }
  final titles = buckets.keys.toList()
    ..sort((a, b) {
      final c = order[a]!.compareTo(order[b]!);
      return c != 0 ? c : a.compareTo(b);
    });
  return [for (final t in titles) EntryGroup(t, buckets[t]!)];
}

(String, int) _bucketFor(FileEntry e, GroupBy by, DateTime now) {
  switch (by) {
    case GroupBy.none:
      return ('', 0);
    case GroupBy.type:
      return (e.kind.label, e.kind.index);
    case GroupBy.letter:
      if (e.isDir) return ('Folders', 0);
      final first = e.name.isEmpty ? '#' : e.name[0].toUpperCase();
      return RegExp('[A-Z]').hasMatch(first) ? (first, 2) : ('#', 1);
    case GroupBy.size:
      if (e.isDir) return ('Folders', 0);
      const mb = 1024 * 1024;
      if (e.size >= 100 * mb) return ('Large (over 100 MB)', 1);
      if (e.size >= mb) return ('Medium (1–100 MB)', 2);
      return ('Small (under 1 MB)', 3);
    case GroupBy.date:
      final day = DateTime(now.year, now.month, now.day);
      final m = e.modified;
      final d = DateTime(m.year, m.month, m.day);
      final age = day.difference(d).inDays;
      if (age <= 0) return ('Today', 0);
      if (age == 1) return ('Yesterday', 1);
      if (age < 7) return ('This week', 2);
      if (m.year == now.year && m.month == now.month) return ('This month', 3);
      if (m.year == now.year) return ('Earlier this year', 4);
      return ('${m.year}', 10000 - m.year); // newer years first
  }
}

String formatSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final digits = i == 0 || v >= 100 ? 0 : 1;
  return '${v.toStringAsFixed(digits)} ${units[i]}';
}

String formatDate(DateTime d) => DateFormat('d MMM yyyy, HH:mm').format(d);

/// Short date for list rows, so it fits next to the size even with large text:
/// "Today 14:05", "12 Oct" (this year), "3 Mar 2024".
String formatListDate(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  if (d.year == n.year && d.month == n.month && d.day == n.day) return 'Today ${DateFormat('HH:mm').format(d)}';
  if (d.year == n.year) return DateFormat('d MMM').format(d);
  return DateFormat('d MMM yyyy').format(d);
}

/// A name in [existing] that does not clash: "photo.jpg" → "photo (1).jpg".
String uniqueName(String name, Set<String> existing) {
  if (!existing.contains(name)) return name;
  final ext = p.extension(name);
  final base = ext.isEmpty || name.startsWith('.') && ext == name ? name : p.basenameWithoutExtension(name);
  final suffix = base == name ? '' : ext;
  for (var i = 1; ; i++) {
    final candidate = '$base ($i)$suffix';
    if (!existing.contains(candidate)) return candidate;
  }
}

/// True when [child] is [parent] itself or lies inside it — copying or moving a
/// folder there would never end.
bool isSameOrInside(String parent, String child) {
  final a = p.normalize(parent);
  final b = p.normalize(child);
  return a == b || p.isWithin(a, b);
}
