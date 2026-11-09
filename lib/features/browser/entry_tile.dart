import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/file_logic.dart';
import '../../core/file_ops.dart';

enum EntryAction { open, share, copy, move, rename, delete, details }

/// One row in a folder listing. Long press starts selection; the ⋮ menu gives
/// every action for this one item, so nothing is hidden behind gestures.
class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onAction,
  });

  final FileEntry entry;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<EntryAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return ListTile(
      selected: selected,
      selectedTileColor: c.primaryContainer.withValues(alpha: 0.5),
      leading: _Leading(entry: entry),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: entry.isDir
          ? _FolderSubtitle(entry: entry)
          : Text(
              '${formatSize(entry.size)} · ${formatListDate(entry.modified)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: selecting
          ? Checkbox(value: selected, onChanged: (_) => onTap())
          : PopupMenuButton<EntryAction>(
              tooltip: 'Options',
              onSelected: onAction,
              itemBuilder: (_) => [
                if (!entry.isDir) _item(EntryAction.open, Icons.open_in_new, 'Open'),
                if (!entry.isDir) _item(EntryAction.share, Icons.share, 'Share'),
                _item(EntryAction.copy, Icons.copy, 'Copy'),
                _item(EntryAction.move, Icons.drive_file_move_outline, 'Move'),
                _item(EntryAction.rename, Icons.edit_outlined, 'Rename'),
                _item(EntryAction.delete, Icons.delete_outline, 'Delete'),
                _item(EntryAction.details, Icons.info_outline, 'Details'),
              ],
            ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  PopupMenuItem<EntryAction> _item(EntryAction a, IconData icon, String label) => PopupMenuItem(
    value: a,
    child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)]),
  );
}

class _Leading extends StatelessWidget {
  const _Leading({required this.entry});
  final FileEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    if (entry.kind == FileKind.image && entry.extension != 'svg') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(entry.path),
          width: 44,
          height: 44,
          cacheWidth: 120,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _icon(c),
        ),
      );
    }
    return _icon(c);
  }

  Widget _icon(ColorScheme c) {
    final (icon, color) = switch (entry.kind) {
      FileKind.folder => (Icons.folder, c.primary),
      FileKind.image => (Icons.image, Colors.teal),
      FileKind.video => (Icons.movie, Colors.deepOrange),
      FileKind.audio => (Icons.music_note, Colors.purple),
      FileKind.document => (entry.extension == 'pdf' ? Icons.picture_as_pdf : Icons.description, Colors.blueGrey),
      FileKind.archive => (Icons.folder_zip, Colors.brown),
      FileKind.apk => (Icons.android, Colors.green),
      FileKind.other => (Icons.insert_drive_file, c.outline),
    };
    return SizedBox(width: 44, height: 44, child: Icon(icon, color: color, size: 34));
  }
}

/// "12 items · date" — the count is read lazily so big listings open fast.
class _FolderSubtitle extends StatefulWidget {
  const _FolderSubtitle({required this.entry});
  final FileEntry entry;

  @override
  State<_FolderSubtitle> createState() => _FolderSubtitleState();
}

class _FolderSubtitleState extends State<_FolderSubtitle> {
  late Future<int?> _count = countItems(widget.entry.path);

  @override
  void didUpdateWidget(covariant _FolderSubtitle old) {
    super.didUpdateWidget(old);
    if (old.entry.path != widget.entry.path || old.entry.modified != widget.entry.modified) {
      _count = countItems(widget.entry.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int?>(
      future: _count,
      builder: (_, snap) {
        final n = snap.data;
        final items = n == null ? 'Folder' : '$n ${n == 1 ? 'item' : 'items'}';
        return Text('$items · ${formatListDate(widget.entry.modified)}', maxLines: 1, overflow: TextOverflow.ellipsis);
      },
    );
  }
}
