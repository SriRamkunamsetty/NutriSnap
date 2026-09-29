import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ios_kit.dart';
import '../../chat/screens/ai_chat_screen.dart';
import '../../home/screens/analytics_screen.dart';

enum CoachTab { coach, insights }

/// One tab that holds both the on-device AI Coach and the Insights
/// (analytics), so advice and the numbers behind it live side by side.
class CoachHubScreen extends ConsumerStatefulWidget {
  const CoachHubScreen({super.key, this.initialTab = CoachTab.coach});
  final CoachTab initialTab;

  @override
  ConsumerState<CoachHubScreen> createState() => _CoachHubScreenState();
}

class _CoachHubScreenState extends ConsumerState<CoachHubScreen> {
  late CoachTab _tab = widget.initialTab;

  @override
  void didUpdateWidget(CoachHubScreen old) {
    super.didUpdateWidget(old);
    if (old.initialTab != widget.initialTab) _tab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: SizedBox(
                width: double.infinity,
                child: Segmented<CoachTab>(
                  value: _tab,
                  options: const {CoachTab.coach: 'AI Coach', CoachTab.insights: 'Insights'},
                  onChanged: (t) => setState(() => _tab = t),
                ),
              ),
            ),
            Expanded(
              // Keep both alive so a half-typed message or scroll position survives switching.
              child: IndexedStack(
                index: _tab.index,
                children: const [AIChatScreen(), AnalyticsScreen()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
