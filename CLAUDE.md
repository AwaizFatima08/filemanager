# File Manager — notes for Claude Code

Flutter Android app (package `com.homilabs.filemanager`): browse phone storage, sort, group into sections,
copy / move / rename / delete / share files. Simple UI for non-technical users.

- Root: `/mnt/storage/projects/filemanager`. Backup: `bash scripts/backup.sh` → local copies in
  `/mnt/storage/project_backups/filemanager_backup/` + push to GitHub `AwaizFatima08/filemanager` (**PUBLIC** —
  never commit `.secrets/`, keystores or `key.properties`). No Google Drive layer yet.
- Ads: AdMob account homilabs.smc@gmail.com, see `docs/admob.md`. Release builds with ads only via
  `bash scripts/build_release.sh`.

## Code map
- `lib/core/file_logic.dart` — `FileEntry`, sort, group (type/date/size/letter), names, sizes. Pure Dart, tested.
- `lib/core/file_ops.dart` — list (isolate), paste (copy/move, never overwrites: "name (1)"), delete, rename, new folder.
- `lib/core/app_state.dart` — `ViewSettings` (saved with shared_preferences) and `FileClipboard`.
- `lib/core/storage.dart` — storage roots (internal + SD/USB), quick folders, "All files access" permission.
- `lib/features/` — `home/` (volumes + quick folders), `browser/` (folder list, selection, paste bar, sort sheet), `about/`.
- `lib/ads/` — ad seam copied from Business Calculator (`FM_ADS=off|placeholder|admob`).

## Commands
```bash
flutter analyze && flutter test
jobq run --name filemanager-apk -- flutter build apk --release   # test APK, ad-free
bash scripts/build_release.sh                                     # real ads (needs .secrets/ad-units.env)
cd android && ./gradlew --stop
```

## Gotchas
- `MANAGE_EXTERNAL_STORAGE`: Play allows it for file managers but asks for a declaration form at upload.
- Android 11+ blocks `Android/data` and `Android/obb`; the browser shows a message instead of an error.
- Release signing still uses the debug key (no upload keystore yet) — create one before the first Play upload.
