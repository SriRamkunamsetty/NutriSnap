import 'dart:typed_data';

import '../models/chat_message.dart';
import '../models/user_profile.dart';
import 'ai_models.dart';

/// Everything the app needs from an AI backend. The production implementation
/// is `GemmaService` (on-device); tests use a fake.
abstract class NutritionAi {
  /// Identifies every food in a meal photo (JPEG/PNG). The result is a
  /// proposal for the user to review; nothing is saved by this call.
  Future<MealAnalysisResult> analyzeMeal(Uint8List image);

  /// Estimates one typical serving of each named dish (no photo). Dishes the
  /// model can't estimate are omitted from the result.
  Future<List<DishEstimate>> estimateDishes(List<String> dishNames);

  /// Rough body-composition estimate from a photo.
  Future<BodyAnalysis> analyzeBody(Uint8List image, {UserProfile? profile});

  /// Streams the coach's reply. Each event is the full visible text so far
  /// (suggestion line already removed). Cancelling the subscription stops
  /// generation. Use [AiParsing.parseCoachReply] on the final raw text via
  /// [CoachStream.reply].
  CoachStream coach({
    required String message,
    required List<ChatMessage> history,
    required String briefing,
  });

  /// Frees the model's memory. It reloads on next use.
  Future<void> unload();
}

/// A live coach response.
class CoachStream {
  CoachStream(this.text, this.reply);

  /// Cumulative visible text as tokens arrive.
  final Stream<String> text;

  /// Completes with the final reply (text + follow-up suggestions).
  final Future<CoachReply> reply;
}
