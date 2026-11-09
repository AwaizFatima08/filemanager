# AdMob — File Manager

AdMob account: **homilabs.smc@gmail.com** (publisher `pub-2087846699268567`), same as the other HomiLabs apps.

| What | ID |
|---|---|
| App (Android) | _to be created in AdMob_ |
| Interstitial `filemanager_paste_done` | _to be created_ |
| Banner `filemanager_about_banner` | _to be created_ |

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

## To do
1. In AdMob (homilabs.smc@gmail.com): Apps → Add app → Android, "not on Play yet", name "File Manager".
2. Add two ad units: Interstitial `filemanager_paste_done`, Banner `filemanager_about_banner`.
3. Put the three ids in `.secrets/ad-units.env` and this table.
4. After the Play listing is live: AdMob → app → **Add store** to link it (review takes a few days).
5. `app-ads.txt` on homilabs.org already lists `pub-2087846699268567` (checked for Business Calculator, Oct 2026).
