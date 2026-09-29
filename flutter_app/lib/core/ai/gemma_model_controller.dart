import 'dart:async';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config/app_config.dart';
import 'model_downloader.dart';

enum ModelPhase { checking, notInstalled, downloading, verifying, installed, error }

class GemmaModelState extends Equatable {
  const GemmaModelState({
    this.phase = ModelPhase.checking,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.partialBytes = 0,
    this.error,
  });

  final ModelPhase phase;

  /// Bytes on disk during a download.
  final int receivedBytes;
  final int totalBytes;

  /// Bytes left over from an interrupted download (when not downloading).
  final int partialBytes;
  final String? error;

  bool get isInstalled => phase == ModelPhase.installed;
  bool get isDownloading => phase == ModelPhase.downloading || phase == ModelPhase.verifying;

  /// 0-100, never above 100.
  int get progress {
    final total = totalBytes > 0 ? totalBytes : AppConfig.gemmaModelBytes;
    if (total <= 0) return 0;
    return ((receivedBytes / total) * 100).floor().clamp(0, 100);
  }

  int get partialPercent {
    final total = AppConfig.gemmaModelBytes;
    if (total <= 0 || partialBytes <= 0) return 0;
    return ((partialBytes / total) * 100).floor().clamp(0, 99);
  }

  @override
  List<Object?> get props => [phase, receivedBytes, totalBytes, partialBytes, error];
}

/// Owns the lifecycle of the Gemma weights: detect, download (resumable,
/// verified), register with the inference engine, and remove.
class GemmaModelController extends StateNotifier<GemmaModelState> {
  /// [autoRefresh] and [initial] exist for tests, which must not touch the
  /// native plugin.
  GemmaModelController({bool autoRefresh = true, GemmaModelState? initial})
      : super(initial ?? const GemmaModelState()) {
    if (autoRefresh) refresh();
  }

  DownloadCancelToken? _cancel;

  Future<File> _modelFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'models', AppConfig.gemmaModelId));
  }

  ModelDownloader _newDownloader(File file) {
    final token = AppConfig.huggingFaceToken;
    return ModelDownloader(
      url: AppConfig.gemmaModelUrl,
      destination: file,
      expectedBytes: AppConfig.gemmaModelBytes > 0 ? AppConfig.gemmaModelBytes : null,
      expectedSha256: AppConfig.gemmaModelSha256.isEmpty ? null : AppConfig.gemmaModelSha256,
      authToken: token.isEmpty ? null : token,
    );
  }

  Future<void> refresh() async {
    if (state.isDownloading) return;
    try {
      final file = await _modelFile();
      final registered = await FlutterGemma.isModelInstalled(AppConfig.gemmaModelId);
      final present = await file.exists() &&
          (AppConfig.gemmaModelBytes <= 0 || await file.length() == AppConfig.gemmaModelBytes);

      if (registered && present) {
        state = const GemmaModelState(phase: ModelPhase.installed);
        return;
      }
      if (registered && !present) {
        // Registered but the file is gone (storage cleared): forget it.
        try {
          await FlutterGemma.uninstallModel(AppConfig.gemmaModelId);
        } catch (_) {}
      }
      if (present) {
        // Fully downloaded but never registered (e.g. app closed mid-install).
        await _register(file);
        state = const GemmaModelState(phase: ModelPhase.installed);
        return;
      }

      final partial = await _newDownloader(file).partialBytes();
      state = GemmaModelState(phase: ModelPhase.notInstalled, partialBytes: partial);
    } catch (e) {
      debugPrint('[GemmaModel] status check failed: $e');
      state = GemmaModelState(
        phase: ModelPhase.error,
        error: 'Could not check the AI model. Please try again.',
      );
    }
  }

  Future<void> _register(File file) => FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromFile(file.path).install();

  /// Downloads (or resumes) the model. Interrupted downloads continue from the
  /// bytes already on disk.
  Future<void> download() async {
    if (state.isDownloading || state.isInstalled) return;

    final cancel = _cancel = DownloadCancelToken();
    final file = await _modelFile();
    final downloader = _newDownloader(file);

    state = GemmaModelState(
      phase: ModelPhase.downloading,
      receivedBytes: await downloader.partialBytes(),
      totalBytes: AppConfig.gemmaModelBytes,
    );

    // Keep the screen on: the download runs in the app while it is in front.
    try {
      await WakelockPlus.enable();
    } catch (_) {}

    var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await downloader.download(
        cancel: cancel,
        onProgress: (received, total) {
          final now = DateTime.now();
          // ~4 UI updates per second is plenty and keeps the UI thread free.
          if (now.difference(lastUpdate).inMilliseconds < 250 || !mounted) return;
          lastUpdate = now;
          state = GemmaModelState(
            phase: ModelPhase.downloading,
            receivedBytes: received,
            totalBytes: total > 0 ? total : AppConfig.gemmaModelBytes,
          );
        },
        onVerifying: () {
          if (mounted) {
            state = GemmaModelState(
              phase: ModelPhase.verifying,
              receivedBytes: AppConfig.gemmaModelBytes,
              totalBytes: AppConfig.gemmaModelBytes,
            );
          }
        },
      );

      await _register(file);
      if (mounted) state = const GemmaModelState(phase: ModelPhase.installed);
    } on ModelDownloadCancelled {
      if (mounted) {
        state = GemmaModelState(
          phase: ModelPhase.notInstalled,
          partialBytes: await downloader.partialBytes(),
        );
      }
    } on ModelDownloadException catch (e) {
      debugPrint('[GemmaModel] download failed: ${e.message}');
      if (mounted) {
        state = GemmaModelState(
          phase: ModelPhase.error,
          partialBytes: await downloader.partialBytes(),
          error: e.message,
        );
      }
    } catch (e) {
      debugPrint('[GemmaModel] install failed: $e');
      if (mounted) {
        state = GemmaModelState(
          phase: ModelPhase.error,
          partialBytes: await downloader.partialBytes(),
          error: 'Could not finish installing the AI model. Please try again.',
        );
      }
    } finally {
      _cancel = null;
      downloader.close();
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  /// Stops the download but keeps the bytes, so it can be resumed later.
  void cancelDownload() => _cancel?.cancel();

  Future<void> remove() async {
    try {
      await FlutterGemma.uninstallModel(AppConfig.gemmaModelId);
    } catch (e) {
      debugPrint('[GemmaModel] uninstall failed: $e');
    }
    try {
      await _newDownloader(await _modelFile()).deleteAll();
    } catch (e) {
      debugPrint('[GemmaModel] file delete failed: $e');
    }
    if (mounted) state = const GemmaModelState(phase: ModelPhase.notInstalled);
  }

  /// Clears an error so the UI returns to the download call-to-action.
  void dismissError() {
    if (state.phase == ModelPhase.error) refresh();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }
}
