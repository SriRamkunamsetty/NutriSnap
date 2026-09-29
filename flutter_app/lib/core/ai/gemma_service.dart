import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../config/app_config.dart';
import '../models/chat_message.dart';
import '../models/user_profile.dart';
import '../services/image_preprocessor.dart';
import 'ai_models.dart';
import 'ai_parsing.dart';
import 'ai_prompts.dart';
import 'nutrition_ai.dart';

/// On-device inference with Gemma through LiteRT-LM (`flutter_gemma`).
///
/// Design notes
/// * **One request at a time.** A phone can hold one model instance; requests
///   queue on [_lock] instead of racing for GPU memory.
/// * **Fresh chat per request.** Food and body analysis are independent and the
///   coach folds its history into the prompt, so no stale context leaks in and
///   the 4k context window is never exhausted.
/// * **Lazy load + idle unload.** The model (~2.6 GB on disk, more in RAM) is
///   loaded on first use and released after [AppConfig.gemmaIdleUnload].
/// * **GPU first, CPU fallback** if the accelerator can not create the engine.
class GemmaService implements NutritionAi {
  GemmaService({required bool Function() isInstalled}) : _isInstalled = isInstalled;

  final bool Function() _isInstalled;

  InferenceModel? _model;
  Timer? _idleTimer;
  Future<void> _lock = Future.value();

  // ---------------------------------------------------------------------------
  // Concurrency + lifecycle
  // ---------------------------------------------------------------------------

  /// Runs [job] after every previously queued job has finished.
  Future<T> _serial<T>(Future<T> Function() job) {
    final done = Completer<void>();
    final previous = _lock;
    _lock = done.future;
    return previous.then((_) => job()).whenComplete(done.complete);
  }

  Future<InferenceModel> _ensureModel() async {
    _idleTimer?.cancel();
    if (!_isInstalled() || !FlutterGemma.hasActiveModel()) {
      throw AiException(
        'Download the on-device AI model to use this feature.',
        needsModel: true,
        retryable: false,
      );
    }
    final existing = _model;
    if (existing != null) return existing;

    Future<InferenceModel> create(PreferredBackend backend) =>
        FlutterGemma.getActiveModel(
          maxTokens: AppConfig.gemmaContextTokens,
          preferredBackend: backend,
          supportImage: true,
          maxNumImages: 1,
        );

    try {
      try {
        return _model = await create(PreferredBackend.gpu);
      } catch (e) {
        debugPrint('[Gemma] GPU init failed ($e); falling back to CPU');
        return _model = await create(PreferredBackend.cpu);
      }
    } catch (e) {
      debugPrint('[Gemma] model load failed: $e');
      throw AiException(
        'The AI model could not start. Close other apps to free memory and try again.',
      );
    }
  }

  void _scheduleIdleUnload() {
    _idleTimer?.cancel();
    _idleTimer = Timer(AppConfig.gemmaIdleUnload, () {
      _serial(() => _closeModel());
    });
  }

  Future<void> _closeModel() async {
    final m = _model;
    _model = null;
    try {
      await m?.close();
    } catch (e) {
      debugPrint('[Gemma] close failed: $e');
    }
  }

  @override
  Future<void> unload() {
    _idleTimer?.cancel();
    return _serial(_closeModel);
  }

  // ---------------------------------------------------------------------------
  // Single-shot generation (food / body)
  // ---------------------------------------------------------------------------

  Future<String> _generateOnce({
    required String system,
    required Message message,
    required int maxOutputTokens,
    required Duration timeout,
    String? repairPrompt,
    bool Function(String)? isValid,
  }) {
    return _serial(() async {
      try {
        final model = await _ensureModel();
        final chat = await model.createChat(
          temperature: 0.2, // extraction, not creativity
          topK: 40,
          topP: 0.95,
          supportImage: message.hasImage,
          systemInstruction: system,
          maxOutputTokens: maxOutputTokens,
        );
        try {
          await chat.addQueryChunk(message);
          var text = _textOf(await chat.generateChatResponse().timeout(timeout));

          // One repair attempt if the reply is unusable.
          if (isValid != null && repairPrompt != null && !isValid(text)) {
            await chat.addQueryChunk(Message.text(text: repairPrompt, isUser: true));
            text = _textOf(await chat.generateChatResponse().timeout(timeout));
          }
          return text;
        } finally {
          await chat.close();
        }
      } on TimeoutException {
        await _closeModel(); // a wedged engine must be recreated
        throw AiException('The AI took too long. Please try again.');
      } on AiException {
        rethrow;
      } catch (e) {
        debugPrint('[Gemma] generation failed: $e');
        throw AiException('The AI could not analyse this. Please try again.');
      } finally {
        _scheduleIdleUnload();
      }
    });
  }

  static String _textOf(ModelResponse r) => r is TextResponse ? r.token : '';

  /// Short model identifier stored with every AI-analysed meal.
  static String get modelVersion =>
      AppConfig.gemmaModelId.replaceAll(RegExp(r'\.(litertlm|task|bin)$'), '');

  @override
  Future<MealAnalysisResult> analyzeMeal(Uint8List image) async {
    // Fix rotation, shrink and re-encode before the (expensive) inference.
    final prepared = await ImagePreprocessor.prepare(image);
    final raw = await _generateOnce(
      system: AiPrompts.foodSystem,
      message: Message.withImage(
        text: AiPrompts.foodUser,
        imageBytes: prepared,
        isUser: true,
      ),
      maxOutputTokens: 1100, // room for a multi-item plate
      timeout: AppConfig.foodAnalysisTimeout,
      repairPrompt: AiPrompts.jsonRepair,
      isValid: (t) => AiParsing.extractJsonObject(t) != null,
    );
    return AiParsing.parseMeal(raw, modelVersion: modelVersion);
  }

  @override
  Future<List<DishEstimate>> estimateDishes(List<String> dishNames) async {
    final names = dishNames.map((n) => n.trim()).where((n) => n.isNotEmpty).take(12).toList();
    if (names.isEmpty) return const [];
    final raw = await _generateOnce(
      system: AiPrompts.dishSystem,
      message: Message.text(text: AiPrompts.dishUser(names), isUser: true),
      maxOutputTokens: 900,
      timeout: AppConfig.foodAnalysisTimeout,
      repairPrompt: AiPrompts.jsonRepair,
      isValid: (t) => AiParsing.extractJsonObject(t) != null,
    );
    return AiParsing.parseDishEstimates(raw, names);
  }

  @override
  Future<BodyAnalysis> analyzeBody(Uint8List image, {UserProfile? profile}) async {
    final raw = await _generateOnce(
      system: AiPrompts.bodySystem,
      message: Message.withImage(
        text: AiPrompts.bodyUser(profile),
        imageBytes: image,
        isUser: true,
      ),
      maxOutputTokens: 250,
      timeout: AppConfig.foodAnalysisTimeout,
      repairPrompt: AiPrompts.jsonRepair,
      isValid: (t) => AiParsing.extractJsonObject(t) != null,
    );
    return AiParsing.parseBody(raw);
  }

  // ---------------------------------------------------------------------------
  // Streaming coach
  // ---------------------------------------------------------------------------

  @override
  CoachStream coach({
    required String message,
    required List<ChatMessage> history,
    required String briefing,
  }) {
    final replyDone = Completer<CoachReply>();
    final controller = StreamController<String>();
    var cancelled = false;

    controller.onCancel = () => cancelled = true;

    () async {
      final release = Completer<void>();
      final previous = _lock;
      _lock = release.future;
      InferenceChat? chat;
      final buffer = StringBuffer();
      var finished = false;
      try {
        await previous;
        if (cancelled) throw AiException('Cancelled', retryable: false);

        final model = await _ensureModel();
        chat = await model.createChat(
          temperature: 0.7,
          topK: 40,
          topP: 0.95,
          systemInstruction: AiPrompts.coachSystem(briefing: briefing),
          maxOutputTokens: 700,
        );
        await chat.addQueryChunk(Message.text(
          text: AiPrompts.coachUser(message: message, history: history),
          isUser: true,
        ));

        final deadline = DateTime.now().add(AppConfig.coachReplyTimeout);
        // 90 s of silence covers a slow CPU prefill; the deadline bounds the rest.
        await for (final r in chat
            .generateChatResponseAsync()
            .timeout(const Duration(seconds: 90))) {
          if (cancelled) break;
          if (r is TextResponse) {
            buffer.write(r.token);
            if (!controller.isClosed) {
              controller.add(AiParsing.visibleCoachText(buffer.toString()));
            }
          }
          if (DateTime.now().isAfter(deadline)) {
            throw TimeoutException('coach deadline');
          }
        }
        finished = true;

        final reply = AiParsing.parseCoachReply(buffer.toString());
        if (reply.text.isEmpty && !cancelled) {
          throw AiException('The coach had no answer. Please try again.');
        }
        if (!replyDone.isCompleted) replyDone.complete(reply);
      } on TimeoutException {
        await _closeModel();
        _fail(replyDone, controller,
            AiException('The coach took too long. Please try again.'));
      } on AiException catch (e) {
        _fail(replyDone, controller, e);
      } catch (e) {
        debugPrint('[Gemma] coach failed: $e');
        _fail(replyDone, controller,
            AiException('The coach could not answer right now. Please try again.'));
      } finally {
        try {
          if (!finished) await chat?.stopGeneration();
          await chat?.close();
        } catch (_) {}
        if (!controller.isClosed) await controller.close();
        if (!replyDone.isCompleted) {
          // Cancelled by the caller: resolve with whatever we have.
          replyDone.complete(AiParsing.parseCoachReply(buffer.toString()));
        }
        _scheduleIdleUnload();
        release.complete();
      }
    }();

    return CoachStream(controller.stream, replyDone.future);
  }

  void _fail(Completer<CoachReply> c, StreamController<String> s, AiException e) {
    if (!c.isCompleted) {
      c.future.ignore(); // the stream error is the primary channel
      c.completeError(e);
    }
    if (!s.isClosed) s.addError(e);
  }
}
