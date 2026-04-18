# 🚀 Project Blueprint: NutriSnap AI

## 1. 📌 Project Overview
* **Project Name:** NutriSnap AI
* **Purpose:** A smart, AI-powered health and fitness application that acts as a personal nutritionist. It allows users to track their daily food intake simply by taking pictures of their meals, while also providing personalized AI coaching based on their unique physical profile and goals.
* **Real-world problem it solves:** Manual calorie and macro counting is tedious, inaccurate, and discouraging. NutriSnap AI removes the friction of food logging by using advanced vision AI to instantly estimate calories, protein, carbs, and fats from a single photo.
* **Target Users:** Health-conscious individuals, fitness enthusiasts, people trying to lose or gain weight, and anyone looking for a frictionless way to track their diet and receive personalized nutritional advice.

---

## 2. 🛠️ Technologies & Tools Used

### Frontend
* **Framework:** React 18 (with TypeScript)
* **Build Tool:** Vite
* **Styling:** Tailwind CSS 4.0 (Utility-first CSS, custom animations, glowing blurs)
* **Routing:** React Router DOM (`BrowserRouter`, `Routes`, `Route`)
* **Icons:** Lucide React
* **Charts:** Recharts (for analytics and macro tracking)
* **State Management:** React Context API (`UserContext.tsx`)

### Backend & Database (BaaS)
* **Platform:** Firebase
* **Authentication:** Firebase Auth (Email/Password, Google OAuth, GitHub OAuth)
* **Database:** Cloud Firestore (NoSQL, structured by user subcollections)
* **Storage:** Firebase Cloud Storage (for profile images, body scans, and food photos)

### APIs & AI
* **AI Engine:** Google Gemini API (`@google/genai`)
* **Capabilities Used:** Multimodal Vision (food image analysis) and Text Generation (AI Coaching Chat).

### Libraries and Utilities
* **Haptics:** Custom local haptics library (`src/lib/haptics.ts`) for premium tactile feedback.
* **Notifications:** Browser-based local notifications (`src/lib/notifications.ts`) for meal and water reminders.

---

## 3. 🎨 COMPLETE UI/UX BREAKDOWN

### Page 1: Authentication / Login Screen (`App.tsx`)
* **Layout Structure:** Full-screen flex layout, centered content.
* **Components Used:** Custom input fields with Lucide icons, `ScaleButton` (custom active scale animation), OAuth buttons.
* **Color Theme:** `#F7F8FA` background, glowing ambient orbs (green and blue `blur-[120px]`), pure white cards with soft shadows.
* **Exact User View:** A central card with the NutriSnap AI logo (sparkles icon). Email/password inputs, a "Sign In" / "Create Account" toggle, and "Continue with Google/GitHub" buttons. If email is unverified, a sticky amber banner appears at the top.
* **Animations:** Buttons scale down to 0.98 on press. Glowing background orbs. Loading state features a spinning bordered circle with a pulsing "NutriSnap AI is loading" text.
* **Interactions:** Clicking login triggers haptic feedback (`triggerHaptic`). Success routes to Onboarding or Home.

### Page 2: Onboarding Screen (`OnboardingScreen.tsx`)
* **Layout Structure:** Multi-step wizard layout.
* **Components Used:** Progress bar, selectable cards (for goals/body type), numeric inputs (height, weight).
* **Exact User View:** Asks the user step-by-step for their Height, Weight, Goal (Lose, Maintain, Gain), and Body Type.
* **Interactions:** Completing the wizard calculates BMI, sets default macro goals (e.g., 2000 kcal, 150g protein), updates the `UserProfile` in Firestore, and redirects to `/`.

### Page 3: Home Screen / Dashboard (`HomeScreen.tsx`)
* **Layout Structure:** Top app bar (greeting + profile pic), daily summary cards, recent scans list, and a prominent floating action button (FAB) for scanning.
* **Components Used:** Circular progress rings (for calories/water), horizontal macro bars (Protein, Carbs, Fats).
* **Exact User View:** Shows "Calories Remaining", a water tracker with "+" buttons, and a quick list of today's meals.
* **Interactions:** Clicking the FAB opens the camera/file picker. Clicking "+" on water updates Firestore and the UI instantly.

### Page 4: Result Screen (`ResultScreen.tsx`)
* **Layout Structure:** Image header, detailed nutritional breakdown card.
* **Exact User View:** Shows the uploaded food image at the top. Below it, a clean card displaying AI-estimated Calories, Protein, Carbs, Fats, and an AI-generated description of the food.
* **Interactions:** User can confirm and save the log, or discard it. Saving updates the `daily_summary` in Firestore.

### Page 5: History Screen (`HistoryScreen.tsx`)
* **Layout Structure:** Scrollable list/grid of past scans.
* **Components Used:** Image thumbnails, date dividers, summary text.
* **Exact User View:** A chronological feed of all meals logged, showing the image, food name, and calorie count.

### Page 6: Analytics Screen (`AnalyticsScreen.tsx`)
* **Layout Structure:** Time-range selector (Week/Month), main chart area, average stats summary.
* **Components Used:** `ComposedChart` from Recharts.
* **Exact User View:** A line chart showing calorie trends overlaid with bar charts showing macro breakdowns per day.

### Page 7: AI Chat Screen (`AIChatScreen.tsx`)
* **Layout Structure:** Standard chat interface (message list taking up remaining height, sticky input area at bottom).
* **Components Used:** Chat bubbles (differentiated by user vs. model), text input, send button.
* **Exact User View:** A conversational interface where the AI acts as a coach.
* **Interactions:** Sending a message triggers `geminiService.ts`, which reads the user's profile and daily summary to provide highly contextual advice.

---

## 4. ⚙️ FEATURES (COMPLETE LIST)

1. **AI Food Scanning:**
   * *What it does:* Analyzes an image of food to extract nutritional data.
   * *Interaction:* User uploads/takes a photo. App uploads to Firebase Storage, sends URL to Gemini Vision, parses the JSON response, and presents the macros.
2. **Context-Aware AI Coaching:**
   * *What it does:* A chatbot that knows the user's goals, today's macros, and recent meals.
   * *Interaction:* User asks "What should I eat for dinner?" -> AI sees the user has 50g of protein left and suggests a high-protein meal.
3. **Daily Macro & Water Tracking:**
   * *What it does:* Aggregates daily intake.
   * *Interaction:* Visual rings and bars update in real-time as food is logged or water is added.
4. **Authentication & Security:**
   * *What it does:* Secures user data.
   * *Interaction:* Email/password, Google, GitHub login. Enforces email verification.
5. **Local Reminders:**
   * *What it does:* Pings the user to drink water or log meals.
   * *Interaction:* Configured in settings. Runs a 1-minute interval check in `UserContext` to trigger browser notifications.

---

## 5. 🔗 INTEGRATIONS (DETAILED)

### Firebase
* **Why it is used:** Complete backend-as-a-service for auth, database, and image storage.
* **Authentication Flow:** Managed in `App.tsx`. Uses `signInWithPopup` and `createUserWithEmailAndPassword`. State is listened to globally via `onAuthStateChanged` in `UserContext.tsx`.
* **Firestore Structure:** Strictly partitioned by `uid`. Users cannot read/write other users' data.
* **Storage:** Images are uploaded to `users/{uid}/scans/scan_{timestamp}`. The resulting download URL is saved to Firestore and sent to Gemini.

### Google Gemini API (`@google/genai`)
* **Where it is used:** `ResultScreen` (Vision) and `AIChatScreen` (Text).
* **Input → Output Flow (Vision):** Image URL + Prompt ("Analyze this food and return JSON with calories, protein, carbs, fats") → Gemini Model → JSON String → Parsed to `ScanResult` object.
* **Input → Output Flow (Chat):** System Prompt (containing user profile, daily summary, last 15 scans) + User Message → Gemini Model → Text Response → Saved to Firestore `messages` collection.

---

## 6. 🧠 CORE LOGIC & WORKFLOW

### Step-by-Step System Flow (Logging Food)
1. **User:** Clicks "Scan" and selects an image.
2. **UI:** Shows loading state.
3. **Backend (Storage):** `storageService.uploadScanImage(file)` uploads image to Firebase Storage and gets URL.
4. **Backend (AI):** `geminiService.analyzeFood(url)` sends image to Gemini.
5. **Response:** Gemini returns JSON. App parses it into a `ScanResult`.
6. **UI:** `ResultScreen` displays the data. User clicks "Save".
7. **Database:** `storageService.saveScanResult()` writes to `users/{uid}/scans` AND increments values in `users/{uid}/daily_summary/{date}` using Firestore `increment()`.
8. **UI:** `UserContext` real-time listeners detect the database change and instantly update the Home Screen rings.

### Business Logic
* **Macro Calculation:** Handled via Firestore `increment()` to prevent race conditions when logging multiple items quickly.
* **AI Context Injection:** Before sending a chat message to Gemini, the app dynamically builds a system prompt: *"You are NutriSnap Coach. The user is {profile.weight}kg, goal is {profile.goal}. Today they have eaten {summary.totalCalories} / {profile.calorieLimit} kcal."*

---

## 7. 📊 DATA STRUCTURE / DATABASE (Firestore)

**Collection:** `users`
* **Document:** `{userId}` (Type: `UserProfile`)
  * `uid` (string)
  * `email` (string)
  * `height`, `weight`, `bmi` (number)
  * `goal` (string: 'lose' | 'maintain' | 'gain')
  * `calorieLimit`, `proteinGoal`, `carbsGoal`, `fatsGoal` (number)
  * `reminders` (array of objects: `{id, time, type, enabled}`)

**Subcollection:** `users/{userId}/scans`
* **Document:** `{scanId}` (Type: `ScanResult`)
  * `foodName` (string)
  * `calories`, `protein`, `carbs`, `fats` (number)
  * `confidence` (number)
  * `imageUrl` (string)
  * `timestamp` (timestamp)

**Subcollection:** `users/{userId}/daily_summary`
* **Document:** `{YYYY-MM-DD}` (Type: `DailySummary`)
  * `date` (string)
  * `totalCalories`, `totalProtein`, `totalCarbs`, `totalFats`, `totalWater` (number)

**Subcollection:** `users/{userId}/messages`
* **Document:** `{messageId}` (Type: `ChatMessage`)
  * `role` (string: 'user' | 'model')
  * `text` (string)
  * `timestamp` (timestamp)

---

## 8. 📁 PROJECT STRUCTURE

```text
/
├── firebase-applet-config.json # Firebase project credentials
├── firestore.rules             # Security rules (Default deny, owner-only access)
├── package.json                # Dependencies (React, Firebase, GenAI, Recharts)
├── vite.config.ts              # Vite bundler configuration
└── src/
    ├── App.tsx                 # Entry point, Error Boundary, Auth UI, Routing
    ├── main.tsx                # React DOM render
    ├── index.css               # Tailwind imports and global CSS variables
    ├── firebase.ts             # Firebase initialization
    ├── types.ts                # TypeScript interfaces (UserProfile, ScanResult, etc.)
    ├── components/             # Reusable UI components
    │   └── Layout.tsx          # Main app shell (Navbar/Sidebar)
    ├── contexts/
    │   └── UserContext.tsx     # Global state, Auth listener, Real-time Firestore listeners
    ├── lib/
    │   ├── haptics.ts          # Browser vibration API wrapper
    │   └── notifications.ts    # Browser Notification API wrapper
    ├── screens/                # Full page views
    │   ├── HomeScreen.tsx      # Dashboard
    │   ├── HistoryScreen.tsx   # Past scans list
    │   ├── AnalyticsScreen.tsx # Recharts data visualization
    │   ├── AIChatScreen.tsx    # Gemini chat interface
    │   ├── SettingsScreen.tsx  # Profile and reminder configuration
    │   ├── ResultScreen.tsx    # Post-scan analysis view
    │   └── OnboardingScreen.tsx# Initial user setup wizard
    └── services/
        ├── storageService.ts   # All Firebase Firestore and Storage operations
        └── geminiService.ts    # All Google Gemini API calls and prompt engineering
```

---

## 9. ▶️ HOW TO RUN THE PROJECT

### Requirements
* Node.js (v18+)
* Firebase Project (with Auth, Firestore, and Storage enabled)
* Google Gemini API Key

### Installation Steps
1. Clone the repository.
2. Run `npm install` to install dependencies.
3. Ensure `firebase-applet-config.json` is populated with your Firebase credentials.
4. Create a `.env` file in the root directory and add:
   `VITE_GEMINI_API_KEY=your_api_key_here`
5. Run `npm run dev` to start the Vite development server.
6. Open `http://localhost:3000` in your browser.

---

## 10. 🔁 COMPLETE USER FLOW

1. **Launch & Auth:** User opens the app. `App.tsx` checks auth state. User logs in via Google.
2. **Onboarding (First Time):** `UserContext` detects `hasCompletedOnboarding` is false. User is routed to `/onboarding`. They enter height/weight/goals. Profile is saved to Firestore.
3. **Dashboard:** User lands on `/` (Home). They see their daily rings (currently at 0).
4. **Action (Log Meal):** User clicks the FAB, takes a picture of a salad.
5. **Processing:** App shows a loading spinner. Image goes to Firebase Storage -> Gemini Vision.
6. **Review:** User is routed to `/result/:id`. They see "Chicken Salad: 350 kcal, 30g Protein". They click "Save".
7. **Update:** Data writes to Firestore. `UserContext` listener triggers.
8. **Feedback:** User is routed back to Home. The calorie ring animates to show 350 kcal consumed. Haptic feedback plays.
9. **Coaching:** User navigates to `/chat` and asks, "Was that salad good for my diet?" The AI responds contextually, knowing the user's goal is weight loss and they just ate 350 kcal.
10. **Review:** At the end of the week, user navigates to `/analytics` to view their macro trends on the Recharts graph.
