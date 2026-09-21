import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_gemma_mediapipe/flutter_gemma_mediapipe.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_result.dart';
import '../models/user_profile.dart';
import '../models/daily_summary.dart';
import '../models/chat_message.dart';

final gemmaServiceProvider = Provider<GemmaService>((ref) => GemmaService());

/// NutriSnap AI - On-Device Gemma Inference Engine
///
/// Runs Gemma 4 (E4B, multimodal) fully on-device via the MediaPipe /
/// LiteRT-LM runtimes (`flutter_gemma`). Nothing here ever leaves the phone —
/// no network call is made once the model is downloaded.
///
/// NOTE ON THE MODEL URL: current Gemma 4 E2B/E4B releases are published by
/// Google under the `litert-community` org on Hugging Face in `.litertlm`
/// format (gated — requires a free HF account + access token). Confirm the
/// exact asset filename on the model's Hugging Face page before shipping;
/// this class does not hardcode a filename it can't verify from a sandboxed
/// environment with no Hugging Face access.
///
/// NOTE ON API SURFACE: this file was written against flutter_gemma 1.8.4's
/// published README (confirmed via pub.dev on 2026-09-21) for
/// `FlutterGemma.initialize/installModel/getActiveModel`, `InferenceChat`,
/// and `Message.text`/`Message.withImages`. `FlutterGemma.isModelInstalled(...)`
/// and the exact `session.close()`/`model.close()`/`generateChatResponse()`
/// return type were NOT directly confirmed against the live docs (no Dart/
/// Flutter SDK or pub.dev doc-browsing tool was available in this sandbox to
/// verify by compiling). Run `flutter pub get` and check
/// `flutter_gemma_interface`'s generated docs for these three specifically
/// before relying on this file.
class GemmaService {
  /// PLACEHOLDER — this is the model's Hugging Face *repo page*, not a
  /// downloadable file. `fromNetwork()` needs a direct asset URL, of the
  /// shape `https://huggingface.co/<repo>/resolve/main/<filename>.litertlm`.
  /// This sandbox has no Hugging Face access to read the repo's actual file
  /// listing, so replace this with the real asset URL (visible on the
  /// "Files and versions" tab of the repo below) before using downloadModel().
  static const String modelRepoPageUrl = 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm';
  static const ModelFileType modelFileType = ModelFileType.litertlm;
  static const int maxTokens = 4096;

  bool _engineInitialized = false;
  InferenceModel? _model;
  InferenceChat? _coachChat;

  Future<void> _ensureEngineInitialized({String? huggingFaceToken}) async {
    if (_engineInitialized) return;
    await FlutterGemma.initialize(
      inferenceEngines: const [
        LiteRtLmEngine(),
        MediaPipeEngine(),
      ],
      huggingFaceToken: huggingFaceToken ?? const String.fromEnvironment('HUGGINGFACE_TOKEN'),
    );
    _engineInitialized = true;
  }

  /// Whether the on-device model has already been downloaded and installed.
  Future<bool> isModelInstalled() async {
    try {
      await _ensureEngineInitialized();
      return await FlutterGemma.isModelInstalled(
        modelType: ModelType.gemmaIt,
        fileType: modelFileType,
      );
    } catch (e) {
      debugPrint('[GemmaService] isModelInstalled check failed: $e');
      return false;
    }
  }

  /// Downloads and installs the Gemma 4 E4B model. This is a multi-GB
  /// download — callers should gate this behind explicit user action
  /// (a "Download on-device AI" button), show [onProgress] as a progress
  /// bar, and warn about storage space / recommend Wi-Fi.
  Future<void> downloadModel({
    required String modelAssetUrl,
    required String huggingFaceToken,
    required void Function(double percent) onProgress,
  }) async {
    await _ensureEngineInitialized(huggingFaceToken: huggingFaceToken);
    await FlutterGemma.installModel(
      modelType: ModelType.gemmaIt,
      fileType: modelFileType,
    )
        .fromNetwork(modelAssetUrl, token: huggingFaceToken)
        .withProgress((progress) => onProgress(progress.toDouble()))
        .install();
  }

  Future<InferenceModel> _activeModel() async {
    if (_model != null) return _model!;
    await _ensureEngineInitialized();
    _model = await FlutterGemma.getActiveModel(
      maxTokens: maxTokens,
      preferredBackend: PreferredBackend.gpu,
    );
    return _model!;
  }

  /// Extracts the first JSON object/array from a raw model response, since
  /// on-device Gemma (unlike cloud Gemini) has no native structured-output
  /// schema mode — it's prompted to return JSON but may wrap it in prose or
  /// a markdown code fence.
  dynamic _extractJson(String raw) {
    final cleaned = raw.replaceAll('```json', '```').trim();
    final fenced = RegExp(r'```([\s\S]*?)```').firstMatch(cleaned);
    final candidate = fenced != null ? fenced.group(1)!.trim() : cleaned;

    final objStart = candidate.indexOf('{');
    final arrStart = candidate.indexOf('[');
    final start = (objStart == -1)
        ? arrStart
        : (arrStart == -1 ? objStart : (objStart < arrStart ? objStart : arrStart));
    if (start == -1) throw const FormatException('No JSON object/array found in Gemma response');

    final isObject = candidate[start] == '{';
    final closeChar = isObject ? '}' : ']';
    final end = candidate.lastIndexOf(closeChar);
    if (end == -1 || end < start) throw const FormatException('Unterminated JSON in Gemma response');

    return jsonDecode(candidate.substring(start, end + 1));
  }

  /// On-device multimodal food recognition — mirrors GeminiService.analyzeFoodImage.
  Future<ScanResult?> analyzeFoodImage(Uint8List imageBytes, String mimeType) async {
    final model = await _activeModel();
    final session = await model.createChat(supportImage: true);
    try {
      final prompt = '''Analyze this image. First, determine if it's a food item (anything edible), a person, or an animal.
If it's food, provide a detailed nutritional breakdown.
Respond with ONLY a single JSON object (no prose, no markdown fences) with exactly these keys:
foodName (string), type (one of "food","person","animal","other"), details (string), description (string), calories (number), protein (number, grams), carbs (number, grams), fats (number, grams), confidence (number, 0-1).
If the item is edible, ALWAYS set type to "food". For non-food items, set nutritional values to 0.''';

      await session.addQueryChunk(Message.withImages(
        text: prompt,
        imageBytes: [imageBytes],
        isUser: true,
      ));
      final response = await session.generateChatResponse();
      final text = response is String ? response : response.toString();
      final jsonMap = _extractJson(text) as Map<String, dynamic>;
      return ScanResult.fromMap(jsonMap);
    } catch (e) {
      debugPrint('[GemmaService] On-device food analysis failed: $e');
      rethrow;
    } finally {
      await session.close();
    }
  }

  /// On-device body composition estimate — mirrors GeminiService.analyzeBodyImage.
  Future<Map<String, dynamic>> analyzeBodyImage(Uint8List imageBytes, String mimeType) async {
    final model = await _activeModel();
    final session = await model.createChat(supportImage: true);
    try {
      const prompt = 'Analyze this body image for fitness estimation. Estimate the body type '
          '(lean, normal, or obese) and a rough body fat percentage. '
          'Respond with ONLY a JSON object: {"bodyType": string, "fatEstimate": number}.';

      await session.addQueryChunk(Message.withImages(text: prompt, imageBytes: [imageBytes], isUser: true));
      final response = await session.generateChatResponse();
      final text = response is String ? response : response.toString();
      return _extractJson(text) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[GemmaService] On-device body analysis failed: $e');
      return {'bodyType': 'unknown', 'fatEstimate': 0};
    } finally {
      await session.close();
    }
  }

  /// On-device AI coach chat — mirrors GeminiService.getAICoachResponse.
  Future<Map<String, dynamic>> getAICoachResponse({
    required List<ChatMessage> historyMessages,
    required UserProfile profile,
    required DailySummary? dailySummary,
    required List<ScanResult> recentHistory,
  }) async {
    final model = await _activeModel();
    _coachChat ??= await model.createChat();

    final historySummary = recentHistory.take(10).map((s) {
      return '- ${s.foodName}: ${s.calories}kcal, P:${s.protein}g, C:${s.carbs}g, F:${s.fats}g';
    }).join('\n');

    final remainingCalories = (profile.calorieLimit ?? 2000) - (dailySummary?.totalCalories ?? 0);
    final systemContext = '''You are NutriSnap AI, a private on-device nutrition coach. Respond with ONLY a JSON object:
{"text": string, "suggestions": [string, string, string]}

User goal: ${profile.goal?.name ?? 'maintain'}. Daily calorie limit: ${profile.calorieLimit ?? 2000} kcal (${remainingCalories} remaining today).
Macros today: ${dailySummary?.totalProtein ?? 0}g protein, ${dailySummary?.totalCarbs ?? 0}g carbs, ${dailySummary?.totalFats ?? 0}g fats.
Recent meals:\n${historySummary.isNotEmpty ? historySummary : 'None logged yet.'}

User's latest message follows. Give concise, data-driven, motivating advice using Markdown, and up to 3 short follow-up suggestions.''';

    final latestUserMessage = historyMessages.isNotEmpty ? historyMessages.last.text : '';

    try {
      await _coachChat!.addQueryChunk(Message.text(text: systemContext, isUser: true));
      await _coachChat!.addQueryChunk(Message.text(text: latestUserMessage, isUser: true));
      final response = await _coachChat!.generateChatResponse();
      final text = response is String ? response : response.toString();
      final decoded = _extractJson(text) as Map<String, dynamic>;
      if (decoded['suggestions'] is! List) decoded['suggestions'] = <String>[];
      return decoded;
    } catch (e) {
      debugPrint('[GemmaService] On-device coach response failed: $e');
      rethrow;
    }
  }

  Future<void> dispose() async {
    await _coachChat?.close();
    _coachChat = null;
    await _model?.close();
    _model = null;
  }
}
