import 'dart:convert';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/scan_result.dart';
import '../models/user_profile.dart';
import '../models/daily_summary.dart';

class GeminiService {
  late final GenerativeModel _visionModel;
  late final GenerativeModel _chatModel;

  GeminiService() {
    const apiKey = String.fromEnvironment('GEMINI_API_KEY');
    _visionModel = GenerativeModel(
      model: 'gemini-3.1-pro-preview',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );
    _chatModel = GenerativeModel(
      model: 'gemini-3-flash-preview',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );
  }

  Future<Map<String, dynamic>> analyzeImage(Uint8List bytes, String mimeType) async {
    final prompt = [
      Content.multi([
        DataPart(mimeType, bytes),
        TextPart(
            "Analyze this image. First, determine if it's a food item (anything edible), a person, or an animal. If it's a person, identify if it's a male or female. If it's an animal, identify the species. If it's food, provide a detailed nutritional breakdown. Return as JSON with: foodName (the name of the object), type ('food', 'person', 'animal', or 'other'), details (gender for person, species for animal, or specific food type), description (a brief summary of what you see), calories (number), protein (number), carbs (number), fats (number), and confidence (number 0-1). IMPORTANT: If the item is edible, ALWAYS set type to 'food'. For non-food items, set nutritional values to 0.")
      ])
    ];

    final response = await _visionModel.generateContent(prompt);
    final text = response.text;
    if (text == null) throw Exception('No response from Gemini');

    return jsonDecode(text);
  }

  Future<Map<String, dynamic>> analyzeBody(Uint8List bytes, String mimeType) async {
    final prompt = [
      Content.multi([
        DataPart(mimeType, bytes),
        TextPart(
            "Analyze this body image for fitness estimation. Estimate the body type (lean, normal, or obese) and provide a rough body fat percentage estimate. Return as JSON with keys 'bodyType' and 'fatEstimate'.")
      ])
    ];

    final response = await _visionModel.generateContent(prompt);
    final text = response.text;
    if (text == null) throw Exception('No response from Gemini');

    return jsonDecode(text);
  }

  Future<Map<String, dynamic>> getAICoachResponse({
    required List<Map<String, String>> messages,
    required UserProfile userProfile,
    required DailySummary? dailySummary,
    required List<ScanResult> recentHistory,
  }) async {
    final historySummary = recentHistory
        .take(15)
        .map((s) =>
            "- ${s.foodName}: ${s.calories}kcal, P:${s.protein}g, C:${s.carbs}g, F:${s.fats}g (${s.timestamp.toIso8601String()})")
        .join("\n");

    final remainingCalories = (userProfile.calorieLimit) - (dailySummary?.totalCalories ?? 0);
    final waterProgress = dailySummary?.totalWater ?? 0;
    final waterGoal = userProfile.waterGoal;

    final systemInstruction = """
You are NutriSnap AI, a world-class nutrition and fitness coach.
You have access to the user's real-time health data, meal history, and personal goals.

User Profile:
- Name: ${userProfile.displayName}
- Height: ${userProfile.height} cm
- Weight: ${userProfile.weight} kg
- BMI: ${userProfile.bmi.toStringAsFixed(1)}
- Goal: ${userProfile.goal}
- Daily Calorie Limit: ${userProfile.calorieLimit} kcal
- Protein Goal: ${userProfile.proteinGoal}g
- Carbs Goal: ${userProfile.carbsGoal}g
- Fats Goal: ${userProfile.fatsGoal}g
- Water Goal: ${waterGoal}ml

Today's Progress:
- Calories consumed: ${dailySummary?.totalCalories ?? 0} kcal (${remainingCalories > 0 ? remainingCalories.toString() + ' remaining' : remainingCalories.abs().toString() + ' over limit'})
- Protein: ${dailySummary?.totalProtein ?? 0}g / ${userProfile.proteinGoal}g
- Carbs: ${dailySummary?.totalCarbs ?? 0}g / ${userProfile.carbsGoal}g
- Fats: ${dailySummary?.totalFats ?? 0}g / ${userProfile.fatsGoal}g
- Water: ${waterProgress}ml / ${waterGoal}ml

Recent Meal History (Last 15 scans):
${historySummary.isEmpty ? "No meals recorded yet." : historySummary}

Your Task:
1. Provide highly personalized, data-driven advice. Reference specific numbers from their progress.
2. If they are over their calorie limit, be firm but encouraging, suggesting light activities or low-calorie meals for the rest of the day.
3. If they are behind on water or protein, give specific food/drink suggestions.
4. Keep responses concise, professional, and motivating. Use markdown for clarity.
5. Provide 3 short, context-aware follow-up suggestions.

Return the response as JSON with 'text' (the advice) and 'suggestions' (array of strings).
""";

    final chatHistory = messages.map((m) {
      return m['role'] == 'user'
          ? Content.text(m['text']!)
          : Content.model([TextPart(m['text']!)]);
    }).toList();

    // The current SDK doesn't support systemInstruction in the same way as the JS SDK yet in all versions,
    // but we can prepend it to the first message or use a specialized chat session if supported.
    // For simplicity, we'll use a single generation with the system instruction prepended.
    
    final fullPrompt = "$systemInstruction\n\nUser Message: ${messages.last['text']}";
    final response = await _chatModel.generateContent([Content.text(fullPrompt)]);
    
    final text = response.text;
    if (text == null) return {'text': 'Sorry, I couldn\'t generate a response.', 'suggestions': []};

    try {
      return jsonDecode(text);
    } catch (e) {
      return {'text': text, 'suggestions': []};
    }
  }
}
