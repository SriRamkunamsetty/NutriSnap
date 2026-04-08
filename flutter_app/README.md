# NutriSnap AI - Flutter Mobile App

This is the complete Flutter implementation of the NutriSnap AI project, designed to match the React web application's UI, logic, and backend integration.

## 🚀 Getting Started

### 1. Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.
- [Firebase account](https://console.firebase.google.com/) and project.
- [Gemini API Key](https://aistudio.google.com/app/apikey).

### 2. Firebase Configuration
The app is pre-configured with the project ID `gen-lang-client-0654629425`. However, for local mobile runs, you must register the Android and iOS apps in your Firebase console:

1.  **Android**:
    - Register `com.example.nutrisnapAi` in Firebase.
    - Download `google-services.json` and place it in `android/app/`.
2.  **iOS**:
    - Register `com.example.nutrisnapAi` in Firebase.
    - Download `GoogleService-Info.plist` and place it in `ios/Runner/`.

Alternatively, update `lib/firebase_options.dart` with the specific `appId` values generated for your platforms.

### 3. Gemini API Key
Open `lib/screens/chat_screen.dart` and replace `'YOUR_GEMINI_API_KEY'` with your actual API key from Google AI Studio.

### 4. Running the App
```bash
cd flutter_app
flutter pub get
flutter run
```

## 🛠 Project Structure
- `lib/models/`: Data structures (User, Scan, Chat, Summary).
- `lib/services/`: Firebase and Gemini API logic.
- `lib/providers/`: State management using Provider.
- `lib/screens/`: UI screens (Home, Analytics, History, Settings, Chat).
- `lib/widgets/`: Reusable UI components.

## 🔐 Security
The app uses the same Firestore rules as the web version. Ensure you have deployed the `firestore.rules` from the root of this project to your Firebase console to maintain data security.
