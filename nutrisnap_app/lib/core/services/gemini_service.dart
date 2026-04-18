import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/scan_result.dart';
import '../models/user_profile.dart';
import '../models/daily_summary.dart';
import '../models/chat_message.dart';

final geminiServiceProvider = Provider<GeminiService>((ref) {
  // Pulling API key securely. In production Flutter, use --dart-define or Remote Config.
  final apiKey = const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  return GeminiService(apiKey);
});

class GeminiService {
  final String apiKey;
  late final GenerativeModel _visionModel;
  late final GenerativeModel _coachModel;

  // Rate Limiting & Circuit Breaker constraints
  DateTime? _lastRequestTime;
  static const _throttleDuration = Duration(seconds: 2);
  static const _timeoutDuration = Duration(seconds: 20);

  int _consecutiveFailures = 0;
  DateTime? _circuitTripTime;
  static const _circuitBreakerDuration = Duration(minutes: 5);
  static const int _maxConsecutiveFailures = 5;

  GeminiService(this.apiKey) {
    if (apiKey.isEmpty) {
      debugPrint('⚠️ Warning: GEMINI_API_KEY is missing. Setup required.');
    }
    
    // Explicit model selection preserving TS mapping
    _visionModel = GenerativeModel(
      model: 'gemini-3.1-pro-preview',
      apiKey: apiKey,
    );

    _coachModel = GenerativeModel(
      model: 'gemini-3.1-flash-preview', 
      apiKey: apiKey,
    );
  }

  /// 6. Circuit Breaker Mechanism
  void _circuitBreakerCheck() {
    if (_circuitTripTime != null) {
      if (DateTime.now().difference(_circuitTripTime!) < _circuitBreakerDuration) {
        throw Exception('AI service is temporarily unavailable due to multiple recent failures. Please try again later.');
      } else {
        // Reset after time elapsed giving it a chance to recover
        _circuitTripTime = null;
        _consecutiveFailures = 0;
      }
    }
  }

  /// 2. Rate Limiting: Prevents excessive API usage and accidental double-taps
  void _throttleCheck() {
    final now = DateTime.now();
    if (_lastRequestTime != null && now.difference(_lastRequestTime!) < _throttleDuration) {
      throw Exception('Rate limit exceeded. Please wait a moment before trying again.');
    }
    _lastRequestTime = now;
  }

  /// 1 & 4. Timeout Handling and Retry Strategy
  Future<GenerateContentResponse> _generateWithResilience(
    GenerativeModel model,
    List<Content> contents,
    GenerationConfig config, {
    int maxAttempts = 3,
  }) async {
    _circuitBreakerCheck();
    _throttleCheck();
    
    int attempt = 0;
    while (attempt < maxAttempts) {
      try {
        final response = await model.generateContent(
          contents,
          generationConfig: config,
        ).timeout(_timeoutDuration);
        
        // Reset circuit breaker on success
        _consecutiveFailures = 0;
        return response;
      } catch (e) {
        attempt++;
        debugPrint('Gemini API attempt $attempt failed: $e');
        
        if (attempt >= maxAttempts) {
          // Record failure for Circuit Breaker
          _consecutiveFailures++;
          if (_consecutiveFailures >= _maxConsecutiveFailures) {
            _circuitTripTime = DateTime.now();
            debugPrint('🚨 Gemini Circuit Breaker Tripped!');
          }
          rethrow;
        }
        await Future.delayed(Duration(seconds: attempt * 2)); // Exponential backoff
      }
    }
    throw Exception('Gemini request failed after $maxAttempts attempts.');
  }

  /// Analyzes a food image for nutritional data using strict JSON schema output.
  Future<ScanResult?> analyzeFoodImage(List<int> imageBytes, String mimeType) async {
    final prompt = TextPart('''
Analyze this image. First, determine if it's a food item (anything edible), a person, or an animal. 
If it's a person, identify if it's a male or female. 
If it's an animal, identify the species. 
If it's food, provide a detailed nutritional breakdown. 
Return as JSON with: foodName (the name of the object), type ('food', 'person', 'animal', or 'other'), details (gender for person, species for animal, or specific food type), description (a brief summary of what you see), estimated calories, protein (g), carbs (g), fats (g), and your confidence level (0-1). 
IMPORTANT: If the item is edible, ALWAYS set type to 'food'. 
For non-food items, set nutritional values to 0.
''');

    final imagePart = DataPart(mimeType, imageBytes);
    final config = GenerationConfig(
      responseMimeType: 'application/json',
      responseSchema: Schema.object(
        properties: {
          "foodName": Schema.string(),
          "type": Schema.string(),
          "details": Schema.string(),
          "description": Schema.string(),
          "calories": Schema.number(),
          "protein": Schema.number(),
          "carbs": Schema.number(),
          "fats": Schema.number(),
          "confidence": Schema.number(),
        },
        requiredProperties: [
          "foodName", "type", "details", "description", 
          "calories", "protein", "carbs", "fats", "confidence"
        ],
      ),
    );

    try {
      final response = await _generateWithResilience(
        _visionModel,
        [Content.multi([prompt, imagePart])],
        config,
      );

      // 3. Response Validation
      if (response.text != null && response.text!.trim().isNotEmpty) {
        final Map<String, dynamic> jsonMap = jsonDecode(response.text!);
        return ScanResult.fromMap(jsonMap);
      }
      return null;
    } catch (e) {
      debugPrint('Failed to analyze image: \$e');
      throw Exception('Food analysis failed due to a network or AI error.');
    }
  }

  /// Analyzes a body image for fitness estimation
  Future<Map<String, dynamic>> analyzeBodyImage(List<int> imageBytes, String mimeType) async {
    final prompt = TextPart("Analyze this body image for fitness estimation. Estimate the body type (lean, normal, or obese) and provide a rough body fat percentage estimate. Return as JSON.");
    final imagePart = DataPart(mimeType, imageBytes);
    
    final config = GenerationConfig(
      responseMimeType: 'application/json',
      responseSchema: Schema.object(
        properties: {
          "bodyType": Schema.string(),
          "fatEstimate": Schema.number(),
        },
        requiredProperties: ["bodyType", "fatEstimate"],
      ),
    );

    try {
      final response = await _generateWithResilience(
        _visionModel,
        [Content.multi([prompt, imagePart])],
        config,
      );

      if (response.text != null && response.text!.trim().isNotEmpty) {
        return jsonDecode(response.text!);
      }
      // 4. Fallback Strategy
      return {'bodyType': 'unknown', 'fatEstimate': 0};
    } catch (e) {
      return {'bodyType': 'unknown', 'fatEstimate': 0};
    }
  }

  /// Simulates NutriSnap AI Coach using context variables and prompt history
  Future<Map<String, dynamic>> getAICoachResponse({
    required List<ChatMessage> historyMessages,
    required UserProfile profile,
    required DailySummary? dailySummary,
    required List<ScanResult> recentHistory,
  }) async {
    // 5. Optimize Context Size: Tightly constrain the mapped scans to the absolute top 10 most recent
    final historySummary = recentHistory.take(10).map((s) {
      return '- \${s.foodName}: \${s.calories}kcal, P:\${s.protein}g, C:\${s.carbs}g, F:\${s.fats}g (\${s.timestamp})';
    }).join('\\n');

    final remainingCalories = (profile.calorieLimit ?? 2000) - (dailySummary?.totalCalories ?? 0);
    final waterProgress = dailySummary?.totalWater ?? 0;
    final waterGoal = profile.waterGoal ?? 2500;

    final systemInstruction = '''You are NutriSnap AI, a world-class nutrition and fitness coach.
You have access to the user's real-time health data, meal history, and personal goals.

User Profile:
- Name: \${profile.displayName ?? 'User'}
- Goal: \${profile.goal?.name ?? 'maintain'}
- Daily Calorie Limit: \${profile.calorieLimit} kcal
- Protein/Carbs/Fats Goal: \${profile.proteinGoal}g / \${profile.carbsGoal}g / \${profile.fatsGoal}g
- BMI/Body Type: \${profile.bmi ?? 'Not set'} / \${profile.bodyType?.name ?? 'Unknown'}

Today's Progress:
- Calories consumed: \${dailySummary?.totalCalories ?? 0} kcal (\${remainingCalories > 0 ? '\$remainingCalories remaining' : '\${remainingCalories.abs()} over limit'})
- Macros (P/C/F): \${dailySummary?.totalProtein ?? 0}g / \${dailySummary?.totalCarbs ?? 0}g / \${dailySummary?.totalFats ?? 0}g
- Water: \$waterProgress ml / \$waterGoal ml

Recent Meal History:
\${historySummary.isNotEmpty ? historySummary : "No meals recorded yet."}

Your Task:
1. Provide highly personalized, data-driven advice. Reference specific numbers.
2. Maintain a \${profile.goal?.name == 'lose' ? 'satiety-focused' : 'nutrient-dense'} context.
3. Keep responses concise, professional, and motivating using Markdown.
4. Provide up to 3 short, context-aware follow-up suggestions in the array.
''';

    // Use a fresh model instance for the coach to inject the dynamic system context correctly
    final specializedCoachModel = GenerativeModel(
      model: 'gemini-3.1-flash-preview',
      apiKey: apiKey,
      systemInstruction: Content.system(systemInstruction),
    );

    final contents = historyMessages.map(
      (m) => Content(m.role, [TextPart(m.text)])
    ).toList();
    
    final config = GenerationConfig(
      responseMimeType: 'application/json',
      responseSchema: Schema.object(
        properties: {
          "text": Schema.string(),
          "suggestions": Schema.array(items: Schema.string()),
        },
        requiredProperties: ["text", "suggestions"],
      ),
    );

    try {
      final response = await _generateWithResilience(
        specializedCoachModel,
        contents,
        config,
      );

      if (response.text != null && response.text!.trim().isNotEmpty) {
        final decoded = jsonDecode(response.text!);
        if (decoded['suggestions'] == null || decoded['suggestions'] is! List) {
           decoded['suggestions'] = <String>[];
        }
        return decoded;
      }
      return {'text': 'No response available', 'suggestions': []};
    } catch (e) {
      // 4. Graceful Fallback Defaults
      debugPrint('Coach AI parsing/response error: \$e');
      return {
        'text': 'I am currently experiencing connection issues. Let\\'s review your baseline goals until I reconnect: Focus on protein today and stay hydrated!',
        'suggestions': ['Check daily summary', 'Log a meal'],
      };
    }
  }
}
