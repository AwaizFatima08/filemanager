import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../../core/file_logic.dart';

/// Bottom sheet with sort order, grouping and hidden-file options.
Future<void> showViewSheet(BuildContext context, ViewSettings settings) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => ListenableBuilder(
      listenable: settings,
      builder: (context, _) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sort by', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final by in SortBy.values)
                    ChoiceChip(
                      label: Text(_sortLabel(by, settings, active: settings.sortBy == by)),
                      selected: settings.sortBy == by,
                      onSelected: (_) => settings.setSort(by),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Tap the selected option again to reverse the order.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 20),
              Text('Group into sections', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final by in GroupBy.values)
                    ChoiceChip(
                      label: Text(_groupLabel(by)),
                      selected: settings.groupBy == by,
                      onSelected: (_) => settings.setGroup(by),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show hidden files'),
                value: settings.showHidden,
                onChanged: (_) => settings.toggleHidden(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _sortLabel(SortBy by, ViewSettings s, {required bool active}) {
  final up = s.ascending;
  final (name, dir) = switch (by) {
    SortBy.name => ('Name', up ? 'A → Z' : 'Z → A'),
    SortBy.date => ('Date', up ? 'oldest first' : 'newest first'),
    SortBy.size => ('Size', up ? 'smallest first' : 'largest first'),
    SortBy.type => ('Type', up ? 'A → Z' : 'Z → A'),
  };
  return active ? '$name · $dir' : name;
}

String _groupLabel(GroupBy by) => switch (by) {
  GroupBy.none => 'No groups',
  GroupBy.type => 'File type',
  GroupBy.date => 'Date',
  GroupBy.size => 'Size',
  GroupBy.letter => 'First letter',
};
