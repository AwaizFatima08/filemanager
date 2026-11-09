import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_logic.dart';
import 'file_ops.dart';

/// How listings are shown. Saved on the phone, so the choice survives restarts.
class ViewSettings extends ChangeNotifier {
  ViewSettings._(this._prefs)
    : sortBy = SortBy.values.asNameMap()[_prefs.getString('sortBy')] ?? SortBy.name,
      ascending = _prefs.getBool('ascending') ?? true,
      groupBy = GroupBy.values.asNameMap()[_prefs.getString('groupBy')] ?? GroupBy.none,
      showHidden = _prefs.getBool('showHidden') ?? false;

  static Future<ViewSettings> load() async => ViewSettings._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;
  SortBy sortBy;
  bool ascending;
  GroupBy groupBy;
  bool showHidden;

  void setSort(SortBy by) {
    // Tapping the active sort again flips the direction.
    if (by == sortBy) {
      ascending = !ascending;
    } else {
      sortBy = by;
      ascending = by == SortBy.name || by == SortBy.type; // newest / biggest first feels natural
    }
    _prefs.setString('sortBy', sortBy.name);
    _prefs.setBool('ascending', ascending);
    notifyListeners();
  }

  void setGroup(GroupBy by) {
    groupBy = by;
    _prefs.setString('groupBy', by.name);
    notifyListeners();
  }

  void toggleHidden() {
    showHidden = !showHidden;
    _prefs.setBool('showHidden', showHidden);
    notifyListeners();
  }
}

/// Items picked with Copy or Move, waiting for "Paste here" in another folder.
class FileClipboard extends ChangeNotifier {
  List<String> paths = const [];
  PasteMode mode = PasteMode.copy;

  bool get isEmpty => paths.isEmpty;

  void set(List<String> items, PasteMode m) {
    paths = List.unmodifiable(items);
    mode = m;
    notifyListeners();
  }

  void clear() {
    paths = const [];
    notifyListeners();
  }
}
