import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/services/gemma_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/ui_feedback.dart';
import '../../auth/providers/user_provider.dart';

/// Settings card for the on-device / hybrid AI engine: shows whether the
/// Gemma model is downloaded, lets the user download it (explicit action —
/// this is a multi-GB download, never triggered automatically), and exposes
/// the cloud-AI escalation opt-in toggle. Privacy-first means cloud AI stays
/// off until the user turns it on here.
class AiEngineCard extends ConsumerStatefulWidget {
  const AiEngineCard({super.key});

  @override
  ConsumerState<AiEngineCard> createState() => _AiEngineCardState();
}

class _AiEngineCardState extends ConsumerState<AiEngineCard> {
  bool? _modelInstalled;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  final TextEditingController _hfTokenController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshModelStatus();
  }

  @override
  void dispose() {
    _hfTokenController.dispose();
    super.dispose();
  }

  Future<void> _refreshModelStatus() async {
    final gemma = ref.read(gemmaServiceProvider);
    final installed = await gemma.isModelInstalled();
    if (mounted) setState(() => _modelInstalled = installed);
  }

  Future<void> _handleDownload() async {
    final token = _hfTokenController.text.trim();
    if (token.isEmpty) {
      UIFeedback.showError(context, 'A Hugging Face access token is required to download the Gemma model.');
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      final gemma = ref.read(gemmaServiceProvider);
      // TODO: GemmaService.modelRepoPageUrl is a placeholder repo-page link,
      // not a downloadable file URL — replace with the real
      // `.../resolve/main/<filename>.litertlm` asset URL before shipping.
      await gemma.downloadModel(
        modelAssetUrl: GemmaService.modelRepoPageUrl,
        huggingFaceToken: token,
        onProgress: (percent) {
          if (mounted) setState(() => _downloadProgress = percent);
        },
      );
      if (mounted) {
        UIFeedback.showSuccess(context, 'On-device AI model downloaded — food scans and coaching now run fully offline.');
        await _refreshModelStatus();
      }
    } catch (e) {
      if (mounted) UIFeedback.showError(context, 'Model download failed: $e');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _handleConsentToggle(bool value) async {
    HapticFeedback.selectionClick();
    final currentProfile = ref.read(userNotifierProvider).profile;
    if (currentProfile == null) return;
    await ref.read(userNotifierProvider.notifier).updateProfile(
          currentProfile.copyWith(cloudAiConsent: value),
        );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userNotifierProvider).profile;
    final cloudConsent = profile?.cloudAiConsent ?? false;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.cpu, size: 16, color: Colors.indigo.shade500),
              const SizedBox(width: 8),
              const Text('AI ENGINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 1.0)),
            ],
          ),
          const SizedBox(height: 12),

          // On-device model status
          Row(
            children: [
              Icon(
                _modelInstalled == true ? LucideIcons.checkCircle2 : LucideIcons.downloadCloud,
                size: 18,
                color: _modelInstalled == true ? Colors.green.shade600 : AppColors.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _modelInstalled == null
                      ? 'Checking on-device AI status…'
                      : _modelInstalled == true
                          ? 'On-device Gemma model ready — food scans & coaching run fully offline.'
                          : 'On-device Gemma model not downloaded yet (~a few GB, Wi-Fi recommended).',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),

          if (_modelInstalled == false) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _hfTokenController,
              enabled: !_isDownloading,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Hugging Face access token',
                hintStyle: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                filled: true,
                fillColor: const Color(0xFFF7F8FA),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 10),
            if (_isDownloading) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress / 100 : null,
                  minHeight: 8,
                  backgroundColor: AppColors.border,
                  color: Colors.indigo.shade500,
                ),
              ),
              const SizedBox(height: 8),
              Text('Downloading… ${_downloadProgress.toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
            ] else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _handleDownload,
                  icon: const Icon(LucideIcons.download, size: 16),
                  label: const Text('Download On-Device AI'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
          ],

          const SizedBox(height: 16),
          Container(height: 1, color: AppColors.border),
          const SizedBox(height: 16),

          // Cloud escalation consent — off by default
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Allow Cloud AI Escalation', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      'Off by default. When on, complex requests the on-device model can\'t '
                      'handle (or if it isn\'t downloaded) escalate to cloud Gemini — only ever with this consent.',
                      style: TextStyle(fontSize: 11, color: AppColors.textTertiary.withOpacity(0.9)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: cloudConsent,
                onChanged: _handleConsentToggle,
                activeColor: Colors.indigo.shade600,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
