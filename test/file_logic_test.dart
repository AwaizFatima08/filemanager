import 'dart:io';

import 'package:filemanager/core/file_logic.dart';
import 'package:filemanager/core/file_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

FileEntry f(String name, {int size = 0, DateTime? at, bool dir = false}) =>
    FileEntry(path: '/s/$name', isDir: dir, size: size, modified: at ?? DateTime(2026, 1, 1));

void main() {
  group('sortEntries', () {
    final items = [
      f('b.txt', size: 10, at: DateTime(2026, 3)),
      f('Zed', dir: true),
      f('a.mp3', size: 30, at: DateTime(2026, 1)),
      f('alpha', dir: true),
      f('c.jpg', size: 20, at: DateTime(2026, 2)),
    ];

    test('folders first, then by name ignoring case', () {
      expect(sortEntries(items, SortBy.name).map((e) => e.name), ['alpha', 'Zed', 'a.mp3', 'b.txt', 'c.jpg']);
    });

    test('descending keeps folders first', () {
      expect(sortEntries(items, SortBy.size, ascending: false).map((e) => e.name), [
        'Zed',
        'alpha',
        'a.mp3',
        'c.jpg',
        'b.txt',
      ]);
    });

    test('by date and type', () {
      expect(sortEntries(items, SortBy.date).skip(2).map((e) => e.name), ['a.mp3', 'c.jpg', 'b.txt']);
      expect(sortEntries(items, SortBy.type).skip(2).map((e) => e.name), ['c.jpg', 'a.mp3', 'b.txt']);
    });
  });

  group('groupEntries', () {
    test('by type in fixed order', () {
      final g = groupEntries([f('x.pdf'), f('y.jpg'), f('d', dir: true), f('z.weird')], GroupBy.type);
      expect(g.map((e) => e.title), ['Folders', 'Images', 'Documents', 'Other']);
    });

    test('by date, newest sections first', () {
      final now = DateTime(2026, 11, 9, 12);
      final g = groupEntries(
        [
          f('old', at: DateTime(2024, 5, 1)),
          f('today', at: DateTime(2026, 11, 9, 8)),
          f('yday', at: DateTime(2026, 11, 8)),
          f('week', at: DateTime(2026, 11, 5)),
          f('month', at: DateTime(2026, 11, 1)),
          f('year', at: DateTime(2026, 2, 1)),
          f('older', at: DateTime(2025, 5, 1)),
        ],
        GroupBy.date,
        now: now,
      );
      expect(g.map((e) => e.title), [
        'Today',
        'Yesterday',
        'This week',
        'This month',
        'Earlier this year',
        '2025',
        '2024',
      ]);
    });

    test('by size and letter', () {
      const mb = 1024 * 1024;
      expect(
        groupEntries([f('s', size: 5), f('l', size: 200 * mb), f('m', size: 5 * mb)], GroupBy.size).map((e) => e.title),
        ['Large (over 100 MB)', 'Medium (1–100 MB)', 'Small (under 1 MB)'],
      );
      expect(groupEntries([f('beta'), f('1x'), f('Alpha')], GroupBy.letter).map((e) => e.title), ['#', 'A', 'B']);
    });

    test('none gives one untitled group', () {
      final g = groupEntries([f('a'), f('b')], GroupBy.none);
      expect(g, hasLength(1));
      expect(g.single.title, '');
    });
  });

  test('uniqueName', () {
    expect(uniqueName('a.jpg', {}), 'a.jpg');
    expect(uniqueName('a.jpg', {'a.jpg', 'a (1).jpg'}), 'a (2).jpg');
    expect(uniqueName('Folder', {'Folder'}), 'Folder (1)');
    expect(uniqueName('.nomedia', {'.nomedia'}), '.nomedia (1)');
  });

  test('formatSize', () {
    expect(formatSize(500), '500 B');
    expect(formatSize(1536), '1.5 KB');
    expect(formatSize(150 * 1024 * 1024), '150 MB');
  });

  test('isSameOrInside and validateName', () {
    expect(isSameOrInside('/a/b', '/a/b/c'), isTrue);
    expect(isSameOrInside('/a/b', '/a/b'), isTrue);
    expect(isSameOrInside('/a/b', '/a/bc'), isFalse);
    expect(validateName(' '), isNotNull);
    expect(validateName('a/b'), isNotNull);
    expect(validateName('Holiday 2026'), isNull);
  });

  group('file operations on disk', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('fm_test');
      await Directory(p.join(tmp.path, 'src/sub')).create(recursive: true);
      await File(p.join(tmp.path, 'src/one.txt')).writeAsString('1');
      await File(p.join(tmp.path, 'src/sub/two.txt')).writeAsString('2');
      await Directory(p.join(tmp.path, 'dest')).create();
      await File(p.join(tmp.path, 'dest/one.txt')).writeAsString('existing');
    });
    tearDown(() => tmp.delete(recursive: true));

    String t(String rel) => p.join(tmp.path, rel);

    test('copy keeps the source and never overwrites', () async {
      final r = await paste([t('src/one.txt'), t('src/sub')], t('dest'), PasteMode.copy);
      expect(r.done, 2);
      expect(await File(t('dest/one.txt')).readAsString(), 'existing');
      expect(await File(t('dest/one (1).txt')).readAsString(), '1');
      expect(await File(t('dest/sub/two.txt')).readAsString(), '2');
      expect(File(t('src/one.txt')).existsSync(), isTrue);
    });

    test('move removes the source', () async {
      final r = await paste([t('src/sub')], t('dest'), PasteMode.move);
      expect(r.done, 1);
      expect(Directory(t('src/sub')).existsSync(), isFalse);
      expect(File(t('dest/sub/two.txt')).existsSync(), isTrue);
    });

    test('a folder cannot go inside itself', () async {
      final r = await paste([t('src')], t('src/sub'), PasteMode.copy);
      expect(r.done, 0);
      expect(r.errors.single, contains('inside itself'));
    });

    test('listFolder hides dot files unless asked', () async {
      await File(t('src/.hidden')).writeAsString('h');
      expect((await listFolder(t('src'))).map((e) => e.name).toSet(), {'one.txt', 'sub'});
      expect((await listFolder(t('src'), showHidden: true)).length, 3);
    });

    test('rename, new folder and delete', () async {
      await rename(t('src/one.txt'), 'uno.txt');
      expect(File(t('src/uno.txt')).existsSync(), isTrue);
      await expectLater(rename(t('src/uno.txt'), 'sub'), throwsA(isA<FileSystemException>()));
      await createFolder(t('src'), 'New');
      final r = await deleteAll([t('src/New'), t('src/sub'), t('src/uno.txt')]);
      expect(r.done, 3);
      expect(Directory(t('src')).listSync(), isEmpty);
    });
  });
}
