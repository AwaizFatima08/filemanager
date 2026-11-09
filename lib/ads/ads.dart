import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'admob_ad_service.dart';

/// Ad seam. Every place the app can show an ad is a named [AdPlacement]; the
/// rest of the app only talks to [AdService]. AdMob lives in
/// `admob_ad_service.dart`; see docs/admob.md.
enum AdPlacement {
  /// Banner on the About screen. Never on the file list itself.
  aboutBanner('about_banner'),

  /// Full-screen ad after a copy or move has finished.
  pasteDone('paste_done');

  const AdPlacement(this.id);
  final String id;
}

/// Height of the placeholder banner (AdMob's standard 320x50).
const double bannerHeight = 50;

abstract class AdService {
  /// Chooses the implementation from `--dart-define=FM_ADS=off|placeholder|admob`.
  /// Default: AdMob in release builds (it stays ad-free unless the real unit ids
  /// were passed, see scripts/build_release.sh), placeholders in debug/profile.
  /// `admob` in a debug build uses Google's test units.
  factory AdService.fromEnvironment() {
    const mode = String.fromEnvironment('FM_ADS');
    return switch (mode) {
      'off' => const NoAdService(),
      'admob' => AdMobAdService(),
      'placeholder' => PlaceholderAdService(),
      _ => kReleaseMode ? AdMobAdService() : PlaceholderAdService(),
    };
  }

  /// Consent (where required) and SDK start-up. Safe to call more than once;
  /// never throws. Ads stay off until it has finished.
  Future<void> init();

  bool get enabled;

  /// True where the law requires a way to change ad consent (EEA, UK, CH).
  Future<bool> get privacyOptionsRequired;

  Future<void> showPrivacyOptions();

  /// A banner for [placement], or null when there is nothing to show.
  Widget? banner(AdPlacement placement);

  /// Called at natural breaks. Implementations decide (with [FrequencyCap])
  /// whether to actually show something. Never called in the middle of a file operation.
  Future<void> maybeShowInterstitial(BuildContext context, AdPlacement placement);
}

class NoAdService implements AdService {
  const NoAdService();

  @override
  Future<void> init() async {}

  @override
  bool get enabled => false;

  @override
  Future<bool> get privacyOptionsRequired async => false;

  @override
  Future<void> showPrivacyOptions() async {}

  @override
  Widget? banner(AdPlacement placement) => null;

  @override
  Future<void> maybeShowInterstitial(BuildContext context, AdPlacement placement) async {}
}

/// Minimum spacing between full-screen ads, plus a grace period after launch
/// so the first thing a user sees is their files, not an ad.
class FrequencyCap {
  FrequencyCap({
    this.minInterval = const Duration(seconds: 90),
    this.launchGrace = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _startedAt = (clock ?? DateTime.now)();

  final Duration minInterval;
  final Duration launchGrace;
  final DateTime Function() _clock;
  final DateTime _startedAt;
  DateTime? _lastShown;

  bool get canShow {
    final now = _clock();
    if (now.difference(_startedAt) < launchGrace) return false;
    final last = _lastShown;
    return last == null || now.difference(last) >= minInterval;
  }

  void recordShown() => _lastShown = _clock();
}

/// Visible stand-ins used while developing, so placements and layout can be
/// checked on a device before any ad network is added.
class PlaceholderAdService implements AdService {
  PlaceholderAdService({FrequencyCap? cap}) : cap = cap ?? FrequencyCap();

  final FrequencyCap cap;

  /// Every interstitial request, for logs and tests.
  final List<String> log = [];

  @override
  Future<void> init() async {}

  @override
  bool get enabled => true;

  @override
  Future<bool> get privacyOptionsRequired async => false;

  @override
  Future<void> showPrivacyOptions() async {}

  @override
  Widget? banner(AdPlacement placement) => _PlaceholderBanner(placement);

  @override
  Future<void> maybeShowInterstitial(BuildContext context, AdPlacement placement) async {
    final allowed = cap.canShow;
    log.add('${placement.id}:${allowed ? 'shown' : 'capped'}');
    debugPrint('[ads] interstitial ${placement.id} ${allowed ? 'shown' : 'capped'}');
    if (!allowed || !context.mounted) return;
    cap.recordShown();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('ad-interstitial'),
        title: const Text('Interstitial ad slot'),
        content: Text('Placement: ${placement.id}\n\nA full-screen ad would appear here.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }
}

class _PlaceholderBanner extends StatelessWidget {
  const _PlaceholderBanner(this.placement);
  final AdPlacement placement;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      key: Key('ad-banner-${placement.id}'),
      height: bannerHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(color: c.outlineVariant),
      ),
      child: Text(
        'Ad slot · ${placement.id} · 320×50',
        style: TextStyle(color: c.onSurfaceVariant, fontSize: 12, letterSpacing: 0.3),
      ),
    );
  }
}

/// A banner area. Collapses to nothing when ads are off or no ad has loaded,
/// so the screen never shows an empty bar.
class AdBannerSlot extends StatelessWidget {
  const AdBannerSlot({super.key, required this.ads, required this.placement});
  final AdService ads;
  final AdPlacement placement;

  @override
  Widget build(BuildContext context) {
    final b = ads.banner(placement);
    if (b == null) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      child: Center(child: b),
    );
  }
}
