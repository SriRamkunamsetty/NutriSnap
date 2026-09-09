# Agent Instructions: NutriSnap AI

This document provides context and guidelines for AI agents working on the NutriSnap AI project.

## 🎯 Project Overview
NutriSnap AI is a privacy-first health and fitness app that uses Gemini AI to analyze food images and provide personalized coaching. It operates entirely on-device with zero external cloud database or storage tracking.

## 🛠 Tech Stack & Patterns
- **Frontend (Web)**: React 18, Vite, TypeScript, Tailwind CSS.
- **Mobile (Flutter)**: Flutter 3, Dart, Riverpod, GoRouter, fl_chart, google_generative_ai.
- **Storage**: 100% On-Device Private Local Storage (browser storage on web, local state & SharedPreferences on mobile).
- **AI**: Gemini API (`@google/genai`). Services in `src/services/geminiService.ts` and Flutter `core/services/gemini_service.dart`.

## 🔐 Privacy & Security
- **On-Device Data Privacy**: All nutritional logs, scans, daily summaries, and chat history remain exclusively on the user's device.
- **No Cloud Database**: Cloud Firestore and Firebase Storage are removed to ensure absolute user data privacy.
- **Data Export & Import**: Users can export full backups of their health records as private JSON or restore them anytime.

## 🤖 AI Coaching Logic
- The AI Coach uses contextual prompting incorporating:
  - User profile (BMI, goals, limits).
  - Today's progress (calories, macros, water).
  - Last 15 meal scans.

## 📈 Analytics & Charts
- Web uses `recharts` (`ComposedChart` for calories and macros).
- Flutter uses `fl_chart`.
