# NutriSnap AI - Flutter Mobile App

This is the complete Flutter implementation of the NutriSnap AI project, designed to match the React web application's UI, logic, and backend integration.

## 🚀 Getting Started

### 1. Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.
- [Firebase account](https://console.firebase.google.com/) and project.
- [Gemini API Key](https://aistudio.google.com/app/apikey).

### 2. Firebase Configuration
The app is now **fully configured** with the credentials from your screenshot (`nutrisnap-3bf24`). 

- **Android**: The `google-services.json` is already created in `android/app/` with your App ID (`1:799302501650:android:5befcaa0cef90b27fd5fcb`) and Package Name (`nutrisnap.sri`).
- **iOS**: The `firebase_options.dart` is updated with your project details.

You can now run the app directly without manual ID replacement.

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
