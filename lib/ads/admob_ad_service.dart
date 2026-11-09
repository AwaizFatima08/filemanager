import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ads.dart';

/// AdMob unit ids. Debug and profile builds use Google's public test units, so
/// testing on a device can never create invalid traffic on the real account.
/// Release builds read the real ids from `--dart-define` (scripts/build_release.sh
/// reads them from `.secrets/ad-units.env`); without them a release shows no ads
/// at all, so test ads can never ship.
class AdUnits {
  const AdUnits._();

  static const testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const testInterstitial = 'ca-app-pub-3940256099942544/1033173712';

  static const _banner = String.fromEnvironment('AD_BANNER_ID');
  static const _interstitial = String.fromEnvironment('AD_INTERSTITIAL_ID');

  static String? get banner => kReleaseMode ? (_banner.isEmpty ? null : _banner) : testBanner;
  static String? get interstitial => kReleaseMode ? (_interstitial.isEmpty ? null : _interstitial) : testInterstitial;
  static bool get anyConfigured => banner != null || interstitial != null;
}

/// AdMob behind [AdService], with Google's User Messaging Platform for consent
/// (EEA, UK and Switzerland). Ads are family-safe: content rated up to PG.
class AdMobAdService implements AdService {
  AdMobAdService({FrequencyCap? cap})
    : cap = cap ?? FrequencyCap(minInterval: const Duration(minutes: 3), launchGrace: const Duration(seconds: 60));

  /// Spacing for full-screen ads: none in the first minute, then at most one
  /// every three minutes.
  final FrequencyCap cap;

  final Completer<bool> _ready = Completer<bool>();
  bool _started = false;
  bool _canRequest = false;
  InterstitialAd? _interstitial;

  /// Completes with whether ads may be requested, once [init] has finished.
  Future<bool> get ready => _ready.future;

  @override
  bool get enabled => _canRequest;

  @override
  Future<void> init() async {
    if (_started) return;
    _started = true;
    try {
      if (!AdUnits.anyConfigured) return; // release build without real ids: stay ad-free
      final done = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () async {
          await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
          if (!done.isCompleted) done.complete();
        },
        (error) {
          debugPrint('[ads] consent update failed: ${error.message}');
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      _canRequest = await ConsentInformation.instance.canRequestAds();
      if (!_canRequest) return;
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(maxAdContentRating: MaxAdContentRating.pg),
      );
      await MobileAds.instance.initialize();
      _loadInterstitial();
    } on Object catch (e) {
      debugPrint('[ads] init failed: $e');
      _canRequest = false;
    } finally {
      if (!_ready.isCompleted) _ready.complete(_canRequest);
    }
  }

  @override
  Future<bool> get privacyOptionsRequired async {
    try {
      return await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> showPrivacyOptions() async {
    try {
      await ConsentForm.showPrivacyOptionsForm((_) {});
    } on Object catch (e) {
      debugPrint('[ads] privacy options failed: $e');
    }
  }

  void _loadInterstitial() {
    final id = AdUnits.interstitial;
    if (id == null || !_canRequest) return;
    InterstitialAd.load(
      adUnitId: id,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (e) => debugPrint('[ads] interstitial failed: ${e.message}'),
      ),
    );
  }

  @override
  Future<void> maybeShowInterstitial(BuildContext context, AdPlacement placement) async {
    if (!_canRequest || !cap.canShow) return;
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return;
    }
    _interstitial = null;
    final done = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadInterstitial();
        if (!done.isCompleted) done.complete();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _loadInterstitial();
        if (!done.isCompleted) done.complete();
      },
    );
    cap.recordShown();
    debugPrint('[ads] interstitial ${placement.id} shown');
    await ad.show();
    await done.future.timeout(const Duration(minutes: 2), onTimeout: () {});
  }

  @override
  Widget? banner(AdPlacement placement) {
    final id = AdUnits.banner;
    if (id == null || (_ready.isCompleted && !_canRequest)) return null;
    return _BannerSlot(service: this, adUnitId: id);
  }
}

/// Loads an anchored adaptive banner once consent and start-up are done; takes
/// no space until an ad has actually loaded.
class _BannerSlot extends StatefulWidget {
  const _BannerSlot({required this.service, required this.adUnitId});

  final AdMobAdService service;
  final String adUnitId;

  @override
  State<_BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<_BannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    unawaited(_load(MediaQuery.sizeOf(context).width.truncate()));
  }

  Future<void> _load(int width) async {
    if (!await widget.service.ready || !mounted) return;
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null) return;
    final ad = BannerAd(
      adUnitId: widget.adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (a, e) {
          debugPrint('[ads] banner failed: ${e.message}');
          a.dispose();
          if (identical(_ad, a)) _ad = null;
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
