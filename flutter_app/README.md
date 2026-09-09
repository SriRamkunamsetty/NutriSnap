# NutriSnap AI - Flutter Mobile Application

The native mobile counterpart for NutriSnap AI, built with Flutter 3, Riverpod, and on-device privacy persistence.

## 📱 Features
- **100% On-Device Storage**: Zero external cloud database tracking. All data is saved to a local SQLite database (`nutrisnap_ai.db`) and local app storage (`nutrisnap_local_storage`).
- **30-Day Auto-Purge & Email Backup**: Automatically detects records older than 30 days on startup/login, bundles and emails the full health archive to the user's login email ID, and safely cleans aged records and images from local storage.
- **Multimodal AI Food Scanner**: Camera & image picker integrated with Google Generative AI for real-time macronutrient detection.
- **AI Coach Chat**: Context-aware coaching using local user metrics and scan history.
- **Interactive Analytics**: Rich charts powered by `fl_chart`.
- **Live Hydration Tracker**: Real-time fluid animation with quick-log controls.

## 🚀 Getting Started

### Prerequisites
- Flutter SDK >= 3.0.0
- Dart SDK >= 3.0.0 < 4.0.0
- Android Studio / Xcode

### Setup & Run
```bash
# 1. Install dependencies
flutter pub get

# 2. Run app
flutter run
```

## 🏗 Architecture
- `lib/core/db/`: On-device SQLite database schema and CRUD operations.
- `lib/core/services/`: Local file manager (`local_file_service.dart`), storage service (`storage_service.dart`), and Gemini AI service (`gemini_service.dart`).
- `lib/core/utils/`: Auto-purge and email delivery engine (`data_purge.dart`).
- `lib/features/`: Feature modules organized into `auth`, `home`, `scan`, `chat`, `analytics`, and `settings`.
