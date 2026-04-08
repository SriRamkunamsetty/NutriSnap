# Agent Instructions: NutriSnap AI

This document provides context and guidelines for AI agents working on the NutriSnap AI project.

## 🎯 Project Overview
NutriSnap AI is a health and fitness app that uses Gemini AI to analyze food images and provide personalized coaching. It uses Firebase for backend services (Auth, Firestore, Storage).

## 🛠 Tech Stack & Patterns
- **Frontend**: React 18, Vite, TypeScript.
- **Styling**: Tailwind CSS 4.0. Use utility classes directly.
- **State**: `UserContext` (`src/contexts/UserContext.tsx`) manages user profile, scans, and daily summaries.
- **Database**: Firestore. Data is organized by user ID: `users/{userId}/scans`, `users/{userId}/messages`, etc.
- **AI**: Gemini API (`@google/genai`). Services are in `src/services/geminiService.ts`.

## 🔐 Security & Auth
- **Firestore Rules**: Strict "Default Deny". Users can only access their own subcollections. Schema validation is enforced using `hasOnly` and type checks.
- **Authentication**: Supports Google, GitHub, and Email/Password.
- **Email Verification**: Required for email/password users. A banner in `App.tsx` handles the UI for unverified users.

## 🤖 AI Coaching Logic
- The AI Coach (`getAICoachResponse` in `geminiService.ts`) uses a detailed system prompt that includes:
  - User profile (BMI, goals, limits).
  - Today's progress (calories, macros, water).
  - Last 15 meal scans.
- **Always** ensure the AI has access to the latest `dailySummary` and `profile` data when generating responses.

## 📈 Analytics & Charts
- Uses `recharts`.
- The `AnalyticsScreen.tsx` uses a `ComposedChart` to show Calories (Line) and Macros (Bars) together.
- Data is aggregated daily into the `daily_summary` collection via `storageService.ts`.

## 📝 Coding Standards
- **TypeScript**: Use strict typing. Define interfaces in `src/types/index.ts`.
- **Tailwind**: Use the `cn()` utility for conditional classes.
- **Firebase**: Use the `handleFirestoreError` utility in `storageService.ts` for all Firestore operations to ensure consistent error reporting.
- **Haptics**: Use `triggerHaptic` from `src/lib/haptics.ts` for user interactions to maintain the premium feel.

## 🚀 Key Files
- `src/App.tsx`: Routing, Auth logic, and Global Error Boundary.
- `src/services/storageService.ts`: All Firebase Firestore/Storage logic.
- `src/services/geminiService.ts`: All Gemini AI logic.
- `firestore.rules`: Security definitions.
- `firebase-blueprint.json`: Data schema IR.
