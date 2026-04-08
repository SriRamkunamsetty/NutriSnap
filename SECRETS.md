# NutriSnap AI - Secrets & API Configuration

This document lists the required secrets and API keys for the NutriSnap AI project.

## 🔑 Required Secrets

| Secret Name | Description | Source |
|-------------|-------------|--------|
| `GEMINI_API_KEY` | API key for Google Gemini AI models. | [Google AI Studio](https://aistudio.google.com/) |
| `GITHUB_CLIENT_ID` | Client ID for GitHub OAuth application. | [GitHub Developer Settings](https://github.com/settings/developers) |
| `GITHUB_CLIENT_SECRET` | Client Secret for GitHub OAuth application. | [GitHub Developer Settings](https://github.com/settings/developers) |

## 🛠 Firebase Configuration

The application requires a `firebase-applet-config.json` file in the root directory with the following structure:

```json
{
  "projectId": "YOUR_PROJECT_ID",
  "appId": "YOUR_APP_ID",
  "apiKey": "YOUR_API_KEY",
  "authDomain": "YOUR_AUTH_DOMAIN",
  "firestoreDatabaseId": "(default)",
  "storageBucket": "YOUR_STORAGE_BUCKET",
  "messagingSenderId": "YOUR_SENDER_ID"
}
```

## 🌐 OAuth Redirect URIs

When configuring OAuth providers (Google, GitHub), use the following redirect URI:

- **Firebase Auth Handler**: `https://<YOUR_PROJECT_ID>.firebaseapp.com/__/auth/handler`

## 📝 Environment Variables (.env)

Ensure your `.env` file (copied from `.env.example`) is populated:

```env
GEMINI_API_KEY="your_gemini_key"
GITHUB_CLIENT_ID="your_github_client_id"
GITHUB_CLIENT_SECRET="your_github_client_secret"
APP_URL="your_app_url"
```
