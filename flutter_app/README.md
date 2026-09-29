# NutriSnap AI - Flutter app

Private, on-device nutrition tracking. Meal photos are analysed by **Gemma 4 E2B running on the phone** (LiteRT-LM via [`flutter_gemma`](https://pub.dev/packages/flutter_gemma)); everything you log is stored in a local **SQLite** database and the app's private folder. There is no account, no cloud database and no analytics.

The only network use is the **one-time download of the model weights** (about 2.6 GB, from HuggingFace, Apache-2.0, no login needed).

## Features

- **Meal scanning** - camera or gallery -> dish name, calories and macros, all on-device. Output is validated (ranges, calories vs. macros) before it is saved; a failed scan never invents a fake meal, it offers manual logging instead.
- **AI coach** - streaming chat that knows your goals, today's totals and recent meals. Has a Stop button and never sends data anywhere.
- **Body scan** - rough body-fat estimate with a trend chart.
- **Hydration, history, analytics** (`fl_chart`), manual and search-based logging.
- **Real meal reminders** - OS-scheduled local notifications that fire when the app is closed.
- **Data controls** (Settings -> Data & privacy): export / restore a JSON backup (optionally with photos), configurable history retention, CSV export of the meal log, erase everything.

## Requirements

| | |
|---|---|
| Flutter | 3.44+ (Dart 3.4+) |
| Android | API 24+, **arm64-v8a only** (LiteRT-LM libraries are 64-bit ARM) |
| iOS | 15.0+, physical device recommended (the Simulator runs the model on CPU only) |
| Device | ~6 GB RAM or more recommended for Gemma 4 E2B; ~3 GB free storage |

## Run

```bash
cd flutter_app
flutter pub get
flutter run --release      # release mode is much faster for on-device inference
```

Debug builds work but generation is noticeably slower.

Optional build-time settings (`--dart-define`):

| Define | Purpose |
|---|---|
| `GEMMA_MODEL_URL` | Host the `.litertlm` file on your own CDN instead of HuggingFace |
| `HUGGINGFACE_TOKEN` | Only if your URL points at a gated repository |

## Architecture

```
lib/
  main.dart                 Bootstrap: SQLite, image store, Gemma engine, notifications
  app.dart                  MaterialApp + start-up housekeeping (retention, reminder schedule)
  core/
    config/                 AppConfig - model URL, limits, retention options
    database/               AppDatabase - sqflite, versioned migrations, reactive watch()
    repositories/           Profile / Scan / Summary / Chat / Settings (the only code that touches SQL)
    ai/
      nutrition_ai.dart     Interface the UI depends on
      gemma_service.dart    On-device inference: serial queue, GPU->CPU fallback, idle unload
      gemma_model_controller.dart   Download / progress / cancel / remove the model
      ai_prompts.dart       Prompts (pure)
      ai_parsing.dart       Robust JSON extraction + validation of model output (pure)
    services/               ImageStore, BackupService, RetentionService, Notification/Reminder services
    providers/              Riverpod wiring and reactive streams
  features/                 auth (profile state, splash), onboarding, home, chat, settings
test/                       Parsing, prompts, repositories, backup/restore, retention (54 tests)
```

Key design decisions:

- **Daily totals are computed, not stored.** Calories/macros are `SUM`s over the `scans` table, so editing or deleting a meal can never leave the summary inconsistent.
- **Days use local time** (`yyyy-MM-dd`), so a 11:30 pm snack belongs to that day.
- **Image paths are stored relative** to the private image folder (absolute container paths change on iOS across updates), and are validated against path traversal when a backup is restored.
- **One inference at a time.** A phone can hold one model instance; requests queue. The model is loaded lazily and released after 3 idle minutes.
- **Fail safe, not fail silent.** Retention writes an archive file, reads it back and verifies the counts *before* deleting anything. If archiving fails, nothing is deleted. Restores are validated first and applied in one SQLite transaction.

## Privacy notes

- Android Auto Backup and device-to-device transfer are **disabled** (`allowBackup=false` + `data_extraction_rules.xml`) so the health database is never uploaded to a Google account. Users move data with Export/Restore. Flip this deliberately if you prefer automatic backups.
- No analytics, crash reporters or ad SDKs are included.
- Photos are analysed in memory and stored only in the app's private directory.

## Tests

```bash
flutter test
flutter analyze
```

## Release checklist

- Create an upload keystore and replace the debug `signingConfig` in `android/app/build.gradle.kts`.
- Choose your final bundle id / application id (currently `com.nutrisnap.nutrisnap_app`).
- Decide where to host the model file (default HuggingFace; consider your own CDN for reliability).
- iOS: enable the *Increased Memory Limit* capability for your provisioning profile (entitlement is already in `Runner.entitlements`).
- Test on a low-RAM device: the app shows a clear error if the model cannot start.
