/// Central, compile-time configuration for NutriSnap AI.
///
/// Everything here can be overridden at build time with `--dart-define`, e.g.
/// `flutter run --dart-define=GEMMA_MODEL_URL=https://cdn.example.com/model.litertlm`
/// which lets a release host the model on its own CDN instead of HuggingFace.
class AppConfig {
  const AppConfig._();

  /// The single on-device user. NutriSnap has no accounts and no server.
  static const String localUserId = 'local_user';

  // ---------------------------------------------------------------------------
  // On-device AI (Gemma via LiteRT-LM)
  // ---------------------------------------------------------------------------

  /// Gemma 4 E2B (Apache-2.0, multimodal, ungated). ~2.6 GB, downloaded once.
  static const String gemmaModelUrl = String.fromEnvironment(
    'GEMMA_MODEL_URL',
    defaultValue:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
  );

  /// Optional HuggingFace token, only needed if you point [gemmaModelUrl] at a
  /// gated repository. Never required for the default model.
  static const String huggingFaceToken =
      String.fromEnvironment('HUGGINGFACE_TOKEN');

  /// Exact size of the model file. The download is rejected if it differs, so a
  /// truncated file can never be loaded. Set to 0 to skip when using a custom
  /// [gemmaModelUrl] (override with `--dart-define=GEMMA_MODEL_BYTES=...`).
  static const int gemmaModelBytes =
      int.fromEnvironment('GEMMA_MODEL_BYTES', defaultValue: 2588147712);

  /// SHA-256 of the model file (lower-case hex); empty skips the check.
  static const String gemmaModelSha256 = String.fromEnvironment(
    'GEMMA_MODEL_SHA256',
    defaultValue: '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c',
  );

  /// File name of the model; used by the plugin as the install identifier.
  static String get gemmaModelId => gemmaModelUrl.split('/').last;

  static const String gemmaDisplayName = 'Gemma 4 E2B';
  static const double gemmaApproxSizeGb = 2.6;

  /// Context window (input + output tokens).
  static const int gemmaContextTokens = 4096;

  /// Unload the model from RAM after this much inactivity.
  static const Duration gemmaIdleUnload = Duration(minutes: 3);

  /// Hard ceilings so a stuck generation can never hang the UI.
  static const Duration foodAnalysisTimeout = Duration(seconds: 120);
  static const Duration coachReplyTimeout = Duration(seconds: 180);

  // ---------------------------------------------------------------------------
  // Data retention
  // ---------------------------------------------------------------------------

  static const int defaultRetentionDays = 30;

  /// Options offered in Settings. `null` means keep everything.
  static const List<int?> retentionOptions = [30, 90, 365, null];

  // ---------------------------------------------------------------------------
  // Safe input ranges (used to sanity-check model output and user input)
  // ---------------------------------------------------------------------------

  static const int maxMealCalories = 5000;
  static const int maxMealMacroGrams = 500;
  static const int maxWaterPerDayMl = 20000;
}
