import 'dart:io';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/user_profile.dart';
import '../models/daily_summary.dart';
import '../models/scan_result.dart';

class GeminiService {
  final String apiKey;
  late final GenerativeModel _visionModel;
  late final GenerativeModel _chatModel;

  GeminiService({required this.apiKey}) {
    _visionModel = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );
    _chatModel = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
    );
  }

  Future<Map<String, dynamic>> analyzeFoodImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final content = [
      Content.multi([
        TextPart("""
          Analyze this food image and provide nutritional information in JSON format.
          Return ONLY the JSON object with these fields:
          - foodName: string
          - calories: number
          - protein: number (grams)
          - carbs: number (grams)
          - fats: number (grams)
          - confidence: number (0-1)
          - description: string (brief summary)
          - details: string (detailed breakdown)
        """),
        DataPart('image/jpeg', bytes),
      ])
    ];

    final response = await _visionModel.generateContent(content);
    final text = response.text;
    if (text == null) throw Exception('No response from Gemini');

    // Clean up JSON response
    final jsonString = text.replaceAll('```json', '').replaceAll('```', '').trim();
    return json.decode(jsonString);
  }

  Future<String> getAICoachResponse({
    required String message,
    required UserProfile profile,
    required DailySummary? dailySummary,
    required List<ScanResult> recentScans,
    required List<Map<String, String>> history,
  }) async {
    final systemPrompt = """
      You are NutriSnap AI, a premium health and fitness coach.
      
      User Profile:
      - Goal: ${profile.goal}
      - Calorie Limit: ${profile.calorieLimit} kcal
      - Weight: ${profile.weight} kg
      - Height: ${profile.height} cm
      - BMI: ${profile.bmi?.toStringAsFixed(1) ?? 'N/A'}
      
      Today's Progress:
      - Calories: ${dailySummary?.totalCalories ?? 0} / ${profile.calorieLimit}
      - Protein: ${dailySummary?.totalProtein ?? 0}g / ${profile.proteinGoal}g
      - Carbs: ${dailySummary?.totalCarbs ?? 0}g / ${profile.carbsGoal}g
      - Fats: ${dailySummary?.totalFats ?? 0}g / ${profile.fatsGoal}g
      - Water: ${dailySummary?.totalWater ?? 0}ml / ${profile.waterGoal}ml
      
      Recent Scans:
      ${recentScans.take(5).map((s) => "- ${s.foodName}: ${s.calories} kcal").join('\n')}
      
      Guidelines:
      1. Be encouraging, professional, and data-driven.
      2. Keep responses concise but insightful.
      3. Use emojis occasionally to maintain a friendly tone.
      4. If the user is over their limit, suggest healthy adjustments.
    """;

    final chatHistory = history.map((m) {
      if (m['role'] == 'user') {
        return Content.text(m['text']!);
      } else {
        return Content.model([TextPart(m['text']!)]);
      }
    }).toList();

    final chat = _chatModel.startChat(history: chatHistory);
    final response = await chat.sendMessage(Content.text("$systemPrompt\n\nUser: $message"));
    
    return response.text ?? "I'm sorry, I couldn't process that request.";
  }
}
