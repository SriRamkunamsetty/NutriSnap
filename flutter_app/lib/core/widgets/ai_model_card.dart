import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ai/gemma_model_controller.dart';
import '../config/app_config.dart';
import '../providers/app_providers.dart';
import '../theme/app_colors.dart';

/// Starts the model download, warning first if the device is on mobile data.
Future<void> startModelDownload(BuildContext context, WidgetRef ref) async {
  var onMobileOnly = false;
  try {
    final c = await Connectivity().checkConnectivity();
    onMobileOnly = c.contains(ConnectivityResult.mobile) &&
        !c.contains(ConnectivityResult.wifi) &&
        !c.contains(ConnectivityResult.ethernet);
  } catch (_) {
    // If we can't tell, don't block the user.
  }

  if (onMobileOnly && context.mounted) {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download on mobile data?'),
        content: Text(
          'The AI model is about ${AppConfig.gemmaApproxSizeGb} GB. '
          'A Wi-Fi connection is recommended.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Download anyway')),
        ],
      ),
    );
    if (go != true) return;
  }
  await ref.read(gemmaModelProvider.notifier).download();
}

/// Shows the model card in a bottom sheet (used when a feature needs the AI).
Future<void> showAiModelSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const Padding(
      padding: EdgeInsets.all(16),
      child: SafeArea(child: AiModelCard()),
    ),
  );
}

/// Status + controls for the on-device Gemma model.
class AiModelCard extends ConsumerWidget {
  const AiModelCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gemmaModelProvider);
    final controller = ref.read(gemmaModelProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(LucideIcons.cpu, color: Colors.green.shade700, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'On-device AI',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                ),
              ),
              _StatusChip(state: state),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${AppConfig.gemmaDisplayName} runs entirely on your phone. Your photos '
            'and chats never leave your device, and it works offline once downloaded.',
            style: const TextStyle(fontSize: 13, height: 1.45, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          ..._body(context, ref, state, controller),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context, WidgetRef ref, GemmaModelState state,
      GemmaModelController controller) {
    switch (state.phase) {
      case ModelPhase.checking:
        return const [Center(child: CircularProgressIndicator())];

      case ModelPhase.notInstalled:
        return [
          _info(state.partialBytes > 0
              ? 'A previous download stopped at ${state.partialPercent}%. It will continue from there.'
              : 'One-time download of about ${AppConfig.gemmaApproxSizeGb} GB. Wi-Fi recommended.'),
          const SizedBox(height: 14),
          _button(
              state.partialBytes > 0
                  ? 'Resume download (${state.partialPercent}%)'
                  : 'Download AI model',
              LucideIcons.download,
              () => startModelDownload(context, ref)),
        ];

      case ModelPhase.downloading:
        final pct = state.progress;
        return [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: state.receivedBytes <= 0 ? null : pct / 100,
              minHeight: 10,
              backgroundColor: AppColors.border,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '$pct%  ·  ${_gb(state.receivedBytes)} of ${_gb(state.totalBytes)} GB',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              TextButton(onPressed: controller.cancelDownload, child: const Text('Pause')),
            ],
          ),
          _info('Keep NutriSnap open on Wi-Fi. If the connection drops it '
              'reconnects and continues; you never start over.'),
        ];

      case ModelPhase.verifying:
        return [
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            child: LinearProgressIndicator(minHeight: 10, color: AppColors.primary),
          ),
          const SizedBox(height: 10),
          const Text('Verifying download…',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          _info('Checking the file is complete and untampered. This takes a few seconds.'),
        ];

      case ModelPhase.installed:
        return [
          _info('Ready. Meal scanning, body scans and the AI coach work offline.'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _confirmRemove(context, controller),
              icon: const Icon(LucideIcons.trash2, size: 16),
              label: const Text('Remove model to free space'),
              style: TextButton.styleFrom(foregroundColor: AppColors.errorRed),
            ),
          ),
        ];

      case ModelPhase.error:
        return [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.errorBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(state.error ?? 'Something went wrong.',
                style: TextStyle(color: Colors.red.shade700, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 14),
          _button(state.partialBytes > 0 ? 'Resume download' : 'Try again', LucideIcons.refreshCw, () async {
            controller.dismissError();
            await startModelDownload(context, ref);
          }),
        ];
    }
  }

  static String _gb(int bytes) => (bytes / (1024 * 1024 * 1024)).toStringAsFixed(2);

  Widget _info(String text) => Text(
        text,
        style: const TextStyle(fontSize: 12, color: AppColors.textTertiary, height: 1.4),
      );

  Widget _button(String label, IconData icon, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
        ),
      );

  Future<void> _confirmRemove(BuildContext context, GemmaModelController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove AI model?'),
        content: const Text(
            'This frees about 2.6 GB. Scanning and the coach stop working until you download it again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await c.remove();
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});
  final GemmaModelState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state.phase) {
      ModelPhase.installed => ('Ready', Colors.green),
      ModelPhase.downloading => ('Downloading', Colors.blue),
      ModelPhase.verifying => ('Verifying', Colors.blue),
      ModelPhase.error => ('Error', Colors.red),
      ModelPhase.notInstalled => ('Not installed', Colors.orange),
      ModelPhase.checking => ('Checking', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(color: color.shade700, fontWeight: FontWeight.w800, fontSize: 11)),
    );
  }
}
