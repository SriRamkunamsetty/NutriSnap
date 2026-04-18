# NutriSnap AI 🍏🤖

NutriSnap AI is an advanced, AI-powered health and fitness application built with Flutter. By leveraging Google's Gemini Vision AI and a robust Firebase backend, the app removes the friction from traditional calorie counting. Users can simply snap a photo of their meals, and the app automatically estimates calories, macro-nutrients, and logs the data, empowering users with data-driven insights and AI conversational coaching.

---

## 🌟 Key Features

### 📸 AI Food Tracking & Analysis
*   **Instant Dietary Assessment:** Uses Gemini Vision API to instantly summarize calories, protein, carbs, and fats from meal photos.
*   **AI Diet Coach:** A personalized chat interface that utilizes the user's daily goals and logged scan history to provide actionable, contextual health advice.
*   **Body Scan Analysis:** Analyze full-body metrics leveraging the Gemini API for visual fat estimation and body-type matching.

### 🔐 Robust Authentication & Profiles
*   **Firebase Auth:** Email/Password implementation requiring email verification.
*   **Stream-Based Identity:** Real-time synchronization of `UserProfile` across devices.

### 📊 Analytics & Health Tracking
*   **Data Aggregation:** Aggregates macro and caloric intake into historical records.
*   **Visual Charting:** Beautiful, responsive tracking utilizing `fl_chart` to view daily trends.
*   **Macro Synchronization:** Dynamic forms that auto-balance gram targets based on user-defined intake percentages.

### ⚙️ Production-Ready UI/UX
*   **Glassmorphism & Theming:** Crisp, pixel-perfect UI with centralized color and typography themes.
*   **Unsaved Changes Guard:** Global mechanisms detecting pending edits across forms to warn users before unintentional navigation.
*   **Haptic Feedback & Toasts:** Centralized `UIFeedback` system coordinating SnackBars and system-level haptics for premium tactile interactions.

---

## 📂 Complete File Architecture

The project is structured using a **Feature-Driven Architecture**, keeping UI, state, and business logic neatly compartmentalized.

```text
lib/
├── main.dart                          # Application entry point & Riverpod Scope provider
├── app.dart                           # Root MaterialApp, ThemeData, & Router configuration
├── core/                              # Shared configuration and app-wide dependencies
│   ├── constants/                     # Constant keys, magic strings, layouts
│   ├── enums/
│   │   └── app_enums.dart             # Shared enumerations (Goal, BodyType, AppTheme)
│   ├── models/                        # Immutable data models
│   │   ├── chat_message.dart
│   │   ├── daily_summary.dart
│   │   ├── reminder.dart
│   │   ├── scan_result.dart
│   │   └── user_profile.dart
│   ├── providers/                     # Global state providers
│   │   └── unsaved_changes_provider.dart
│   ├── router/                        
│   │   └── app_router.dart            # GoRouter configuration & route definitions
│   ├── services/                      # Decoupled backend integrations
│   │   ├── firebase_service.dart      # Core Initialization & Auth wrapper
│   │   ├── gemini_service.dart        # LLM integration (Vision & Chat)
│   │   └── storage_service.dart       # Firestore & Firebase Storage handlers
│   ├── theme/
│   │   └── app_colors.dart            # Centralized systemic color palette
│   ├── utils/                         # Helper functions
│   │   ├── datetime_utils.dart
│   │   ├── firebase_exception_handler.dart
│   │   └── ui_feedback.dart           # Haptic & SnackBar management
│   └── widgets/                       # Reusable UI abstractions
│       ├── animated_entry.dart
│       ├── app_alert_banner.dart
│       ├── app_buttons.dart
│       ├── app_card.dart
│       └── app_text_field.dart
└── features/                          # Isolated feature domains
    ├── auth/
    │   ├── providers/
    │   │   └── user_provider.dart     # Authentication state & profile orchestration
    │   └── screens/
    │       └── auth_screen.dart       # Login / Registration view
    ├── home/
    │   └── screens/
    │       ├── analytics_screen.dart  # Data visualizations (fl_chart)
    │       ├── history_screen.dart    # Historical scan repository
    │       ├── home_screen.dart       # Main dashboard & AI scanner trigger
    │       ├── main_layout.dart       # Shell route & BottomNavigationBar wrapper
    │       └── result_screen.dart     # Detailed result view + manual edit overrides
    ├── onboarding/
    │   └── screens/
    │       └── onboarding_screen.dart # Data-gathering flow for new users
    └── settings/
        └── screens/
            └── settings_screen.dart   # Profile edits & target adjustments
```

---

## 🏗 Architecture Explanation

NutriSnap AI uses a **Feature-Driven Structure** layered with **Core Services**.

1.  **`features/`:** Houses the primary domain verticals (Auth, Home, Onboarding, Settings). Each feature encapsulates its own `screens/`, local `providers/`, and `widgets/` when specific to that domain. This prevents sprawling codebases and groups related logical files together.
2.  **`core/`:** Holds globally required resources. Things like global models (`UserProfile`), overarching theme configurations, and routing logic live here since multiple separate `features` must import them.
3.  **`core/services/`:** Business/API logic is fully abstracted from the UI. Features talk to Riverpod Providers, and Providers talk to Services. This makes mocking, testing, and replacing backend resources seamless.
4.  **`State Management (Riverpod)`:** Replaces fragile `setState` trees with immutable `StateNotifier` classes. Provides predictable, reactive streams preventing race conditions.

---

## 🛠 Tech Stack

### Frontend
- **Flutter Framework:** UI rendering across mobile platforms.
- **Riverpod (`flutter_riverpod`):** Reactive, compile-safe state management.
- **GoRouter (`go_router`):** Deep-linkable, declarative routing.
- **UI & Graphics:** `lucide_icons` for consistent iconography, `flutter_animate` for high-performance physics-based motion, and `fl_chart` for granular analytics.

### Backend (Firebase)
- **Firebase Auth:** Secure user identity lifecycle management.
- **Cloud Firestore:** NoSQL real-time document sync.
- **Firebase Storage:** Cloud bucket for high-res food images and avatars.

### AI Engine
- **Google Gemini API (`google_generative_ai`):** Processing multipart requests (images + prompt) to extract nutritional matrices and powering conversational chat boundaries.

---

## 🔄 Data & Execution Workflow

### User Experience Flow
`Login / Register` ➡️ `Onboarding (Height, Weight, Goals)` ➡️ `Home / Main Layout` ➡️ `Capture Food Image` ➡️ `Process Result` ➡️ `Analytics Update`

### Technical Data Flow (Image Scan Workflow)
1. **Trigger:** User initiates the camera via `ImagePicker`.
2. **Pre-Processing:** Image is immediately compressed locally via `imageQuality` metrics to save bandwidth.
3. **Cloud Storage:** Image is pushed to `Firebase Storage` (`storage_service.dart`).
4. **AI Resolution:** The image bytes and system prompt are pushed into `gemini_service.dart` invoking `analyzeImage()`.
5. **Database Transaction:** The returning JSON response is parsed into a `ScanResult` object and pushed into Firestore (`users/{id}/scans`).
6. **Reactivity:** Firestore streams emit the new data. Riverpod catches the update, broadcasting implicitly to `analytics_screen.dart` and `home_screen.dart` which rebuilt non-destructively to display the latest macro achievements.

---

## 🔑 Key Modules

*   **Auth System (`user_provider.dart`):** Listens explicitly to `FirebaseAuth.instance.authStateChanges()`. If a user appears without a matching `UserProfile` document in Firestore, it forces them to the `OnboardingScreen`. It coordinates global session data without heavy prop-drilling.
*   **Storage & Firestore (`storage_service.dart`):** Acts as a singleton instance injected via Riverpod locking in robust logic including strict schema handling via `handleFirestoreError`. Guarantees default-deny security behaviors.
*   **Routing System (`app_router.dart`):** Applies `ShellRoute` mechanisms. The `MainLayout` acts as a static skeleton (Navbar), while child screens (Home, Analytics, History) fade seamlessly into the internal slot. Uses redirection logic mapping user `Riverpod` auth-state to redirect protected views natively.

---

## 🚀 Setup Instructions

1.  **Clone the Repository:**
    ```bash
    git clone https://github.com/your-org/nutrisnap_app.git
    cd nutrisnap_app
    ```
2.  **Fetch Dependencies:**
    ```bash
    flutter pub get
    ```
3.  **Firebase Configuration:**
    - Initialize your project via the Firebase CLI using `flutterfire configure`.
    - Ensure `Authentication` (Email/Password), `Firestore Database`, and `Storage` are enabled in your console.
    - Deploy the security rules matching the project requirements (provided in `firestore.rules`).
4.  **Environmental Keys:**
    - Provide your Google Gemini API Key via dart definitions or `.env` files (e.g. `--dart-define=GEMINI_API_KEY=your_api_key_here`).
5.  **Run Application:**
    ```bash
    flutter run
    ```

---

## 📈 Scalability Notes

This application is built entirely as a **Production-Ready** scale-friendly system. 
*   **Decoupled Services:** UI layer knows *nothing* about Firebase or Gemini APIs. The service layers can be swapped out individually in the future (e.g. moving from Firestore to a custom GraphQL backend) without touching a single UI widget.
*   **Stream Opt-Ins:** Riverpod's localized subscriptions (`ref.watch`) prevent full-screen rebuilds. Only the charts re-render when data streams update, ensuring fluid 60FPS scrolling mechanics unconditionally.
*   **Future-Proof Structure:** The feature-driven layout inherently defends against spaghetti-code. Teams can work on `/settings` completely independently from `/home` without triggering merge conflicts across the codebase.
