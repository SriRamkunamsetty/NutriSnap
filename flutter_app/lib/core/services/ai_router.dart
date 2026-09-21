import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_result.dart';
import '../models/user_profile.dart';
import '../models/daily_summary.dart';
import '../models/chat_message.dart';
import '../providers/connectivity_provider.dart';
import '../../features/auth/providers/user_provider.dart';
import 'gemma_service.dart';
import 'gemini_service.dart';

/// Which engine actually served the most recent AI request — surface this
/// in the UI ("Analyzed on-device" vs "Analyzed via cloud") so the privacy
/// story stays visible, not just a backend implementation detail.
enum AiEngine { onDeviceGemma, cloudGemini, unavailable }

final aiRouterProvider = Provider<AiRouter>((ref) => AiRouter(ref));

/// NutriSnap AI - Hybrid Privacy-First AI Router
///
/// Local-first: every request is tried on-device via Gemma first. Cloud
/// Gemini is only ever used as an escalation, and only when the user has
/// explicitly opted in ([UserProfile.cloudAiConsent]) AND the device is
/// online. If on-device Gemma isn't ready (model not downloaded yet) and
/// the user hasn't opted into cloud escalation, requests fail closed
/// (return null) rather than silently phoning home.
class AiRouter {
  final Ref _ref;
  AiEngine lastEngineUsed = AiEngine.unavailable;

  AiRouter(this._ref);

  bool get _hasCloudConsent => _ref.read(userNotifierProvider).profile?.cloudAiConsent ?? false;
  bool get _isOnline => _ref.read(isOnlineProvider).valueOrNull ?? false;

  Future<ScanResult?> analyzeFoodImage(Uint8List imageBytes, String mimeType) async {
    final gemma = _ref.read(gemmaServiceProvider);
    if (await gemma.isModelInstalled()) {
      try {
        final result = await gemma.analyzeFoodImage(imageBytes, mimeType);
        lastEngineUsed = AiEngine.onDeviceGemma;
        return result;
      } catch (e) {
        debugPrint('[AiRouter] On-device food analysis failed: $e');
      }
    }

    if (_hasCloudConsent && _isOnline) {
      final gemini = _ref.read(geminiServiceProvider);
      final result = await gemini.analyzeFoodImage(imageBytes, mimeType);
      lastEngineUsed = AiEngine.cloudGemini;
      return result;
    }

    lastEngineUsed = AiEngine.unavailable;
    return null;
  }

  Future<Map<String, dynamic>> analyzeBodyImage(Uint8List imageBytes, String mimeType) async {
    final gemma = _ref.read(gemmaServiceProvider);
    if (await gemma.isModelInstalled()) {
      try {
        final result = await gemma.analyzeBodyImage(imageBytes, mimeType);
        lastEngineUsed = AiEngine.onDeviceGemma;
        return result;
      } catch (e) {
        debugPrint('[AiRouter] On-device body analysis failed: $e');
      }
    }

    if (_hasCloudConsent && _isOnline) {
      final gemini = _ref.read(geminiServiceProvider);
      final result = await gemini.analyzeBodyImage(imageBytes, mimeType);
      lastEngineUsed = AiEngine.cloudGemini;
      return result;
    }

    lastEngineUsed = AiEngine.unavailable;
    return {'bodyType': 'unknown', 'fatEstimate': 0};
  }

  Future<Map<String, dynamic>> getAICoachResponse({
    required List<ChatMessage> historyMessages,
    required UserProfile profile,
    required DailySummary? dailySummary,
    required List<ScanResult> recentHistory,
  }) async {
    final gemma = _ref.read(gemmaServiceProvider);
    if (await gemma.isModelInstalled()) {
      try {
        final result = await gemma.getAICoachResponse(
          historyMessages: historyMessages,
          profile: profile,
          dailySummary: dailySummary,
          recentHistory: recentHistory,
        );
        lastEngineUsed = AiEngine.onDeviceGemma;
        return result;
      } catch (e) {
        debugPrint('[AiRouter] On-device coach response failed: $e');
      }
    }

    if (_hasCloudConsent && _isOnline) {
      final gemini = _ref.read(geminiServiceProvider);
      final result = await gemini.getAICoachResponse(
        historyMessages: historyMessages,
        profile: profile,
        dailySummary: dailySummary,
        recentHistory: recentHistory,
      );
      lastEngineUsed = AiEngine.cloudGemini;
      return result;
    }

    lastEngineUsed = AiEngine.unavailable;
    return {
      'text': 'On-device AI isn\'t set up yet. Download the on-device model, or enable cloud AI '
          'escalation, from Settings → AI Engine to chat with your coach.',
      'suggestions': <String>[],
    };
  }
}
