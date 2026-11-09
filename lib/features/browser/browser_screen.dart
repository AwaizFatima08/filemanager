import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../ads/ads.dart';
import '../../app/services.dart';
import '../../core/file_logic.dart';
import '../../core/file_ops.dart';
import 'entry_tile.dart';
import 'view_sheet.dart';

/// Shows one folder at a time inside [root]. Back goes up a folder until the
/// root is reached, then leaves the screen.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, required this.services, required this.root, required this.start});

  final Services services;
  final String root;
  final String start;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late String _path = widget.start;
  List<FileEntry> _entries = const [];
  String? _error;
  bool _loading = true;
  bool _busy = false;
  final Set<String> _selected = {};
  String _filter = '';
  bool _searching = false;
  final _scroll = ScrollController();

  ViewSettings get _settings => widget.services.settings;
  FileClipboard get _clipboard => widget.services.clipboard;
  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettings);
    _load();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    _scroll.dispose();
    super.dispose();
  }

  bool _lastHidden = false;
  void _onSettings() {
    if (_settings.showHidden != _lastHidden) {
      _load(); // hidden files change what is read from disk
    } else {
      setState(() {}); // sort and group work on what we already have
    }
  }

  Future<void> _load() async {
    _lastHidden = _settings.showHidden;
    setState(() => _loading = true);
    try {
      final list = await listFolder(_path, showHidden: _settings.showHidden);
      if (!mounted) return;
      setState(() {
        _entries = list;
        _error = null;
        _selected.removeWhere((s) => !list.any((e) => e.path == s));
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = const [];
        _error = e is FileSystemException && _path.contains('/Android/')
            ? 'Android does not let apps open this folder.'
            : 'This folder cannot be opened.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goTo(String path) {
    setState(() {
      _path = path;
      _selected.clear();
      _filter = '';
      _searching = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load();
  }

  bool get _atRoot => p.equals(_path, widget.root);

  void _handleBack() {
    if (_selecting) {
      setState(_selected.clear);
    } else if (_searching) {
      setState(() {
        _searching = false;
        _filter = '';
      });
    } else if (!_atRoot) {
      _goTo(p.dirname(_path));
    } else {
      Navigator.of(context).pop();
    }
  }

  List<FileEntry> get _visible {
    final f = _filter.trim().toLowerCase();
    final list = f.isEmpty ? _entries : _entries.where((e) => e.name.toLowerCase().contains(f)).toList();
    return sortEntries(list, _settings.sortBy, ascending: _settings.ascending);
  }

  // ---------- actions ----------

  void _toggle(FileEntry e) =>
      setState(() => _selected.contains(e.path) ? _selected.remove(e.path) : _selected.add(e.path));

  void _tap(FileEntry e) {
    if (_selecting) return _toggle(e);
    e.isDir ? _goTo(e.path) : _openFile(e.path);
  }

  Future<void> _openFile(String path) async {
    final r = await OpenFilex.open(path);
    if (r.type != ResultType.done) _snack('No app on this phone can open this file.');
  }

  Future<void> _share(List<String> paths) async {
    final files = [
      for (final s in paths)
        if (FileSystemEntity.isFileSync(s)) XFile(s),
    ];
    if (files.isEmpty) return _snack('Folders cannot be shared. Pick files instead.');
    if (files.length < paths.length) _snack('Folders were left out; only files are shared.');
    await SharePlus.instance.share(ShareParams(files: files));
  }

  void _pick(List<String> paths, PasteMode mode) {
    _clipboard.set(paths, mode);
    setState(_selected.clear);
    _snack('Now open the folder to ${mode == PasteMode.copy ? 'copy' : 'move'} into, and tap "Paste here".');
  }

  Future<void> _paste() async {
    final mode = _clipboard.mode;
    final items = _clipboard.paths;
    setState(() => _busy = true);
    final r = await paste(items, _path, mode);
    if (!mounted) return;
    setState(() => _busy = false);
    if (mode == PasteMode.move || r.errors.isEmpty) _clipboard.clear();
    await _load();
    final verb = mode == PasteMode.copy ? 'Copied' : 'Moved';
    _report(r, '$verb ${_count(r.done)}');
    if (r.done > 0 && mounted) {
      await widget.services.ads.maybeShowInterstitial(context, AdPlacement.pasteDone);
    }
  }

  Future<void> _delete(List<String> paths) async {
    final names = paths.map(p.basename).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_forever),
        title: Text('Delete ${paths.length == 1 ? '"${names.first}"' : _count(paths.length)}?'),
        content: const Text('This cannot be undone. Folders are deleted with everything inside them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final r = await deleteAll(paths);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
    });
    await _load();
    _report(r, 'Deleted ${_count(r.done)}');
  }

  Future<void> _rename(String path) async {
    final name = await _askName(title: 'Rename', initial: p.basename(path), action: 'Rename');
    if (name == null || name == p.basename(path)) return;
    try {
      await rename(path, name);
      setState(_selected.clear);
      await _load();
    } on FileSystemException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _newFolder() async {
    final name = await _askName(title: 'New folder', initial: '', action: 'Create');
    if (name == null) return;
    try {
      await createFolder(_path, name);
      await _load();
    } on FileSystemException catch (e) {
      _snack(e.osError?.message ?? e.message);
    }
  }

  Future<String?> _askName({required String title, required String initial, required String action}) {
    final ctrl = TextEditingController(text: initial);
    // Select the name without its extension, so typing replaces just that.
    final dot = initial.lastIndexOf('.');
    ctrl.selection = TextSelection(baseOffset: 0, extentOffset: dot > 0 ? dot : initial.length);
    String? error;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          void submit() {
            final e = validateName(ctrl.text);
            if (e != null) return setD(() => error = e);
            Navigator.pop(ctx, ctrl.text.trim());
          }

          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Name', errorText: error),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(onPressed: submit, child: Text(action)),
            ],
          );
        },
      ),
    );
  }

  void _details(FileEntry e) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(e.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detail(
              'Type',
              e.isDir ? 'Folder' : '${e.kind.label} (${e.extension.isEmpty ? 'no extension' : '.${e.extension}'})',
            ),
            if (!e.isDir) _detail('Size', '${formatSize(e.size)} (${e.size} bytes)'),
            _detail('Modified', formatDate(e.modified)),
            _detail('Location', p.dirname(e.path)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Widget _detail(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: Theme.of(context).textTheme.labelMedium),
        SelectableText(v),
      ],
    ),
  );

  void _onAction(FileEntry e, EntryAction a) {
    switch (a) {
      case EntryAction.open:
        _openFile(e.path);
      case EntryAction.share:
        _share([e.path]);
      case EntryAction.copy:
        _pick([e.path], PasteMode.copy);
      case EntryAction.move:
        _pick([e.path], PasteMode.move);
      case EntryAction.rename:
        _rename(e.path);
      case EntryAction.delete:
        _delete([e.path]);
      case EntryAction.details:
        _details(e);
    }
  }

  String _count(int n) => '$n ${n == 1 ? 'item' : 'items'}';

  void _report(OpResult r, String okText) {
    if (r.errors.isEmpty) return _snack(okText);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r.done > 0 ? '$okText, ${r.errors.length} failed' : 'Nothing was changed'),
        content: SingleChildScrollView(child: Text(r.errors.join('\n'))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: ListenableBuilder(
        listenable: _clipboard,
        builder: (context, _) => Scaffold(
          appBar: _selecting ? _selectionBar() : _normalBar(),
          body: Column(
            children: [
              _Breadcrumbs(root: widget.root, path: _path, onTap: _goTo),
              if (_busy) const LinearProgressIndicator(),
              Expanded(child: _list()),
            ],
          ),
          bottomNavigationBar: _clipboard.isEmpty || _selecting ? null : _pasteBar(),
        ),
      ),
    );
  }

  PreferredSizeWidget _normalBar() {
    return AppBar(
      leading: BackButton(onPressed: _handleBack),
      title: _searching
          ? TextField(
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Search this folder', border: InputBorder.none),
              onChanged: (v) => setState(() => _filter = v),
            )
          : Text(_atRoot ? 'Storage' : p.basename(_path)),
      actions: [
        IconButton(
          tooltip: _searching ? 'Close search' : 'Search',
          icon: Icon(_searching ? Icons.close : Icons.search),
          onPressed: () => setState(() {
            _searching = !_searching;
            _filter = '';
          }),
        ),
        IconButton(
          tooltip: 'Sort and group',
          icon: const Icon(Icons.sort),
          onPressed: () => showViewSheet(context, _settings),
        ),
        PopupMenuButton<String>(
          onSelected: (v) => switch (v) {
            'new' => _newFolder(),
            'all' => setState(() => _selected.addAll(_visible.map((e) => e.path))),
            'refresh' => _load(),
            _ => null,
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'new', child: Text('New folder')),
            PopupMenuItem(value: 'all', child: Text('Select all')),
            PopupMenuItem(value: 'refresh', child: Text('Refresh')),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _selectionBar() {
    final items = _selected.toList();
    return AppBar(
      leading: IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
      title: Text('${items.length} selected'),
      actions: [
        IconButton(tooltip: 'Copy', icon: const Icon(Icons.copy), onPressed: () => _pick(items, PasteMode.copy)),
        IconButton(
          tooltip: 'Move',
          icon: const Icon(Icons.drive_file_move_outline),
          onPressed: () => _pick(items, PasteMode.move),
        ),
        IconButton(tooltip: 'Share', icon: const Icon(Icons.share), onPressed: () => _share(items)),
        IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(items)),
        PopupMenuButton<String>(
          onSelected: (v) => switch (v) {
            'all' => setState(() => _selected.addAll(_visible.map((e) => e.path))),
            'rename' => _rename(items.single),
            _ => null,
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'all', child: Text('Select all')),
            if (items.length == 1) const PopupMenuItem(value: 'rename', child: Text('Rename')),
          ],
        ),
      ],
    );
  }

  Widget _pasteBar() {
    final n = _clipboard.paths.length;
    final verb = _clipboard.mode == PasteMode.copy ? 'copy' : 'move';
    return SafeArea(
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(_clipboard.mode == PasteMode.copy ? Icons.copy : Icons.drive_file_move_outline),
              const SizedBox(width: 12),
              Expanded(child: Text('${_count(n)} to $verb')),
              TextButton(onPressed: _clipboard.clear, child: const Text('Cancel')),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _busy ? null : _paste,
                icon: const Icon(Icons.content_paste),
                label: const Text('Paste here'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list() {
    if (_loading && _entries.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _Message(icon: Icons.block, text: _error!);
    final visible = _visible;
    if (visible.isEmpty) {
      return _Message(
        icon: _filter.isEmpty ? Icons.folder_off_outlined : Icons.search_off,
        text: _filter.isEmpty ? 'This folder is empty' : 'Nothing matches "$_filter"',
      );
    }
    final groups = groupEntries(visible, _settings.groupBy);
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          for (final g in groups) ...[
            if (g.title.isNotEmpty)
              SliverToBoxAdapter(
                child: _GroupHeader(title: g.title, count: g.entries.length),
              ),
            SliverList.builder(
              itemCount: g.entries.length,
              itemBuilder: (_, i) {
                final e = g.entries[i];
                return EntryTile(
                  key: ValueKey(e.path),
                  entry: e,
                  selecting: _selecting,
                  selected: _selected.contains(e.path),
                  onTap: () => _tap(e),
                  onLongPress: () => _toggle(e),
                  onAction: (a) => _onAction(e, a),
                );
              },
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      color: t.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text('$title  ($count)', style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary)),
    );
  }
}

/// Tappable path from the storage root to the current folder.
class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.root, required this.path, required this.onTap});
  final String root;
  final String path;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final parts = p.split(p.relative(path, from: root)).where((s) => s != '.').toList();
    final crumbs = <(String, String)>[('Storage', root)];
    var acc = root;
    for (final s in parts) {
      acc = p.join(acc, s);
      crumbs.add((s, acc));
    }
    final c = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        reverse: true, // keep the current folder in view
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: crumbs.length,
        separatorBuilder: (_, _) => Icon(Icons.chevron_right, size: 18, color: c.outline),
        itemBuilder: (_, i) {
          final (label, target) = crumbs[crumbs.length - 1 - i];
          final current = i == 0;
          return TextButton(
            onPressed: current ? null : () => onTap(target),
            child: Text(label, style: TextStyle(fontWeight: current ? FontWeight.bold : null)),
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: c.outline),
          const SizedBox(height: 12),
          Text(
            text,
            style: TextStyle(color: c.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
