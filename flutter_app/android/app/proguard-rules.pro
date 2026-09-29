# Keep rules for release builds (R8).
# flutter_gemma_litertlm ships as a native-assets library and needs no rules.
# flutter_local_notifications serialises scheduled notifications with Gson:
-keep class com.dexterous.** { *; }
-keepattributes *Annotation*, Signature
