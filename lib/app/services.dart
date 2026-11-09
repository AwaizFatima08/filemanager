import '../ads/ads.dart';
import '../core/app_state.dart';

export '../core/app_state.dart';

/// App-wide objects, handed down from main() to every screen.
class Services {
  const Services({required this.settings, required this.clipboard, required this.ads});

  final ViewSettings settings;
  final FileClipboard clipboard;
  final AdService ads;
}

const kAppVersion = '1.0.0';
