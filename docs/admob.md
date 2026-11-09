# AdMob — File Manager

AdMob account: **homilabs.smc@gmail.com** (publisher `pub-2087846699268567`), same as the other HomiLabs apps.

| What | ID |
|---|---|
| App (Android) | `ca-app-pub-2087846699268567~1747542883` |
| Interstitial `filemanager_paste_done` | `ca-app-pub-2087846699268567/1617736287` |
| Banner `filemanager_about_banner` | `ca-app-pub-2087846699268567/8959159358` |

The ids are not secrets (they ship inside the APK), but they live in `.secrets/ad-units.env`
(copy `.secrets/ad-units.env.example`) so a plain `flutter build` can never ship them by accident.

## Placements (lib/ads/ads.dart)
- **Interstitial after a finished copy or move** (`paste_done`): never in the first minute after launch,
  at most one every 3 minutes (`FrequencyCap` in `admob_ad_service.dart`). Never during an operation.
- **Banner on the About screen** only (`about_banner`). No banner on the file list.
- Google UMP consent form where the law requires it (EEA, UK, CH); "Ad privacy options" button on About.
- Max ad content rating: PG.

## Builds
- Debug / profile: placeholders by default; `--dart-define=FM_ADS=admob` shows Google's **test** ads.
- Plain `flutter build apk --release`: no ads at all (no real ids) and Google's test app id in the manifest.
- Release with ads: `bash scripts/build_release.sh` — reads `.secrets/ad-units.env`, refuses test ids, checks
  the APK manifest carries the real app id and the unit ids are compiled in.

## Status
- 2026-11-09: app and both ad units created by Claude in AdMob (not linked to a store yet, so ad serving is
  limited, "Requires review"); ids are in `.secrets/ad-units.env` (gitignored; in the local backups).

## To do
1. After the Play listing is live: AdMob → app → **Add store** to link it (review takes a few days).
2. `app-ads.txt` on homilabs.org already lists `pub-2087846699268567` (checked for Business Calculator, Oct 2026).
