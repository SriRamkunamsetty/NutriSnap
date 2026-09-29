# Releasing NutriSnap (Android)

1. Create a keystore once and keep it (and its passwords) somewhere safe and OUT of git:
   `keytool -genkey -v -keystore ~/nutrisnap-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. Create `android/key.properties` (already git-ignored):
   ```
   storeFile=C:/path/to/nutrisnap-upload.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```
3. `flutter build appbundle --release` (Play) or `flutter build apk --release`.

Without `key.properties` the build falls back to the debug key: fine for testing, not for the store.
