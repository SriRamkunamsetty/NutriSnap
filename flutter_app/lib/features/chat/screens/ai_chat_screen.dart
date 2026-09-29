import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/ai/ai_models.dart';
import '../../../core/ai/ai_parsing.dart';
import '../../../core/coach/coach_context.dart';
import '../../../core/coach/coach_safety.dart';
import '../../../core/coach/why_engine.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ai_model_card.dart';
import '../../../core/widgets/ios_kit.dart';
import '../../coach/widgets/coach_context_sheet.dart';
import '../../coach/widgets/insight_card.dart';

/// One-tap questions that are answered from the user's real data.
class QuickAction {
  const QuickAction(this.label, this.icon, this.prompt);
  final String label;
  final IconData icon;
  final String prompt;
}

const kQuickActions = [
  QuickAction('What should I eat?', LucideIcons.utensils,
      'Based on my day so far, what should I eat for my next meal? Give me 3 options with portions.'),
  QuickAction('Analyze my day', LucideIcons.chartNoAxesColumn,
      'Analyze my day: how am I doing on calories, protein, water and activity, and what should I change?'),
  QuickAction('Protein check', LucideIcons.beef,
      'Am I meeting my protein goal today? If not, how can I close the gap?'),
  QuickAction('Hydration check', LucideIcons.droplets,
      'How is my hydration today and how much water do I have left to drink?'),
  QuickAction('Activity check', LucideIcons.footprints,
      'How was my activity today, and how does it relate to what I have eaten?'),
  QuickAction('Weekly summary', LucideIcons.calendarDays,
      'Give me a summary of my week for nutrition and activity, and one thing to improve.'),
  QuickAction('Improve my meals', LucideIcons.sparkles,
      'How can I improve my meals, based on what I usually eat?'),
];

class AIChatScreen extends ConsumerStatefulWidget {
  const AIChatScreen({super.key});

  @override
  ConsumerState<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends ConsumerState<AIChatScreen> {
  final _messageController = TextEditingController();
  final _scroll = ScrollController();

  bool _isTyping = false;
  bool _stopRequested = false;
  String? _streaming; // text of the reply being generated
  String? _failedPrompt; // last prompt that errored (offers Retry)
  String? _error;
  String _contextLabel = '';
  List<String> _suggestions = [];

  @override
  void dispose() {
    _messageController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      jump
          ? _scroll.jumpTo(max)
          : _scroll.animateTo(max, duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    });
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  Future<void> _send(String raw, {bool regenerate = false}) async {
    final text = raw.trim();
    if (text.isEmpty || _isTyping) return;

    final chat = ref.read(chatRepositoryProvider);
    final safety = CoachSafety.assess(text);

    // Emergencies and dangerous-diet requests get a fixed, reviewed answer.
    // They never touch the model, so they work even before it is downloaded.
    if (safety.bypassesModel) {
      _messageController.clear();
      if (!regenerate) await chat.add('user', text);
      await chat.add('model', safety.reply!);
      if (mounted) setState(() {
        _suggestions = [];
        _error = null;
        _failedPrompt = null;
      });
      HapticFeedback.mediumImpact();
      _scrollToBottom();
      return;
    }

    if (!ref.read(gemmaModelProvider).isInstalled) {
      await showAiModelSheet(context);
      return;
    }

    HapticFeedback.lightImpact();
    setState(() {
      _isTyping = true;
      _stopRequested = false;
      _streaming = '';
      _error = null;
      _failedPrompt = null;
      _suggestions = [];
      _messageController.clear();
    });

    try {
      // History is read before the new message is stored so it isn't sent twice.
      var history = await chat.all(limit: 14);
      if (regenerate) {
        // Drop the reply and the question being re-asked.
        if (history.isNotEmpty && !history.last.isUser) history = history.sublist(0, history.length - 1);
        if (history.isNotEmpty && history.last.isUser) history = history.sublist(0, history.length - 1);
        await chat.deleteLatestModelReply();
      } else {
        history = history.length > 12 ? history.sublist(history.length - 12) : history;
        await chat.add('user', text);
      }
      _scrollToBottom();

      final snapshot = await ref.read(coachSnapshotProvider.future);
      final briefing = CoachContext.build(snapshot, insights: WhyEngine.analyze(snapshot));
      _contextLabel = [
        if (snapshot.todayMeals.isNotEmpty) 'meals',
        if (snapshot.hasActivityData) 'activity',
        if (snapshot.sleep.isNotEmpty) 'sleep',
        'goals',
        if (snapshot.twinSummary.isNotEmpty) 'food habits',
      ].join(' · ');

      final coach = ref.read(nutritionAiProvider).coach(message: text, history: history, briefing: briefing);

      await for (final partial in coach.text) {
        if (!mounted || _stopRequested) break; // breaking cancels generation
        setState(() => _streaming = partial);
        _scrollToBottom(jump: true);
      }

      final reply = await coach.reply;
      final safe = CoachSafety.filterReply(reply.text, safety.level);
      if (safe.isNotEmpty) await chat.add('model', safe);

      if (mounted) {
        setState(() => _suggestions = safe == reply.text ? reply.suggestions : const []);
        HapticFeedback.mediumImpact();
        _scrollToBottom();
      }
    } on AiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _failedPrompt = text;
        });
        if (e.needsModel) await showAiModelSheet(context);
      }
    } catch (e) {
      debugPrint('[Coach] failed: $e');
      if (mounted) {
        setState(() {
          _error = 'Something went wrong. Please try again.';
          _failedPrompt = text;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _streaming = null;
        });
      }
    }
  }

  Future<void> _regenerate(List<ChatMessage> messages) async {
    final lastUser = messages.lastWhere((m) => m.isUser, orElse: () => ChatMessage(id: '', userId: '', role: 'user', text: '', timestamp: ''));
    if (lastUser.text.isEmpty) return;
    await _send(lastUser.text, regenerate: true);
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear conversation?'),
        content: const Text('This deletes your chat with the coach from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(chatRepositoryProvider).clear();
      if (mounted) setState(() {
        _suggestions = [];
        _error = null;
        _failedPrompt = null;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(chatHistoryStreamProvider);
    final installed = ref.watch(gemmaModelProvider).isInstalled;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 20,
        title: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(13)),
            child: Icon(LucideIcons.sparkles, color: Colors.green.shade700, size: 19),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI Coach', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              Text('Powered by Gemma 4 · On-device',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textTertiary)),
            ]),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: 'What the coach can see',
            onPressed: () => showCoachContextSheet(context),
            icon: const Icon(LucideIcons.shieldCheck, size: 20, color: AppColors.textSecondary),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(LucideIcons.ellipsis, size: 20, color: AppColors.textSecondary),
            onSelected: (v) {
              if (v == 'clear') _clear();
              if (v == 'model') showAiModelSheet(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('Clear conversation')),
              PopupMenuItem(value: 'model', child: Text('AI model')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: history.when(
            data: (messages) => _messages(messages, installed),
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            error: (_, __) => Center(
              child: EmptyPanel(
                icon: LucideIcons.circleAlert,
                title: 'Couldn\'t load the conversation',
                message: 'Something went wrong reading your chat.',
                action: TextButton(onPressed: () => ref.invalidate(chatHistoryStreamProvider), child: const Text('Retry')),
              ),
            ),
          ),
        ),
        _inputArea(),
      ]),
    );
  }

  Widget _messages(List<ChatMessage> messages, bool installed) {
    final insights = ref.watch(insightsProvider);
    final showWelcome = messages.isEmpty && !_isTyping;

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        if (showWelcome) ...[
          if (!installed) const Padding(padding: EdgeInsets.only(bottom: 16), child: AiModelCard()),
          const SectionTitle('Today\'s insights'),
          if (insights.isEmpty)
            const IosCard(
              child: EmptyPanel(
                icon: LucideIcons.sprout,
                title: 'Nothing to report yet',
                message: 'Log a meal, water or a walk and your coach will start noticing patterns.',
              ),
            )
          else
            for (final i in insights.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InsightCard(
                  insight: i,
                  onAsk: () => _send('Explain this to me: ${i.title}. What should I do?'),
                ),
              ),
        ],
        for (var idx = 0; idx < messages.length; idx++)
          _bubble(messages[idx], isLast: idx == messages.length - 1, all: messages),
        if (_isTyping) _streamingBubble(),
        if (_error != null) _errorBanner(),
      ],
    );
  }

  Widget _streamingBubble() {
    final partial = _streaming;
    if (partial == null || partial.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green)),
              const SizedBox(width: 10),
              Text('Coach is thinking…', style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      );
    }
    return _bubbleShell(text: AiParsing.stripMarkdown(partial), mine: false);
  }

  Widget _bubble(ChatMessage m, {required bool isLast, required List<ChatMessage> all}) {
    final mine = m.isUser;
    final time = DateTime.tryParse(m.timestamp);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          _bubbleShell(text: mine ? m.text : AiParsing.stripMarkdown(m.text), mine: mine),
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (time != null)
                Text(DateFormat('h:mm a').format(time),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textTertiary)),
              if (!mine) ...[
                _tiny(LucideIcons.copy, 'Copy reply', () {
                  Clipboard.setData(ClipboardData(text: AiParsing.stripMarkdown(m.text)));
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(const SnackBar(behavior: SnackBarBehavior.floating, content: Text('Copied')));
                }),
                if (isLast && !_isTyping) _tiny(LucideIcons.refreshCw, 'Regenerate reply', () => _regenerate(all)),
              ],
            ]),
          ),
          if (!mine && isLast && _contextLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 2),
              child: Text('Based on your $_contextLabel',
                  style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
            ),
        ],
      ),
    );
  }

  Widget _tiny(IconData icon, String tooltip, VoidCallback onTap) => Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(width: 40, height: 32, child: Icon(icon, size: 14, color: AppColors.textTertiary)),
        ),
      );

  Widget _bubbleShell({required String text, required bool mine}) => Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: mine ? Colors.green.shade600 : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(22),
                  topRight: const Radius.circular(22),
                  bottomLeft: Radius.circular(mine ? 22 : 6),
                  bottomRight: Radius.circular(mine ? 6 : 22),
                ),
                border: mine ? null : Border.all(color: AppColors.border),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: SelectableText(
                text,
                style: TextStyle(color: mine ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w500, height: 1.45, fontSize: 15),
              ),
            ),
          ),
        ],
      );

  Widget _errorBanner() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(LucideIcons.circleAlert, size: 18, color: Colors.red.shade600),
          const SizedBox(width: 10),
          Expanded(child: Text(_error!, style: TextStyle(fontSize: 13, color: Colors.red.shade800, fontWeight: FontWeight.w600))),
          if (_failedPrompt != null)
            TextButton(
              onPressed: () => _send(_failedPrompt!, regenerate: true),
              style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
              child: const Text('Retry'),
            ),
        ]),
      );

  Widget _inputArea() {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + MediaQuery.of(context).padding.bottom * 0),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_suggestions.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ActionChip(
                  label: Text(_suggestions[i], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  onPressed: () => _send(_suggestions[i]),
                  backgroundColor: Colors.green.shade50,
                  side: BorderSide.none,
                ),
              ),
            ),
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kQuickActions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final a = kQuickActions[i];
                return ActionChip(
                  avatar: Icon(a.icon, size: 15, color: Colors.green.shade700),
                  label: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  onPressed: _isTyping ? null : () => _send(a.prompt),
                  backgroundColor: AppColors.surfaceMuted,
                  side: BorderSide.none,
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(26)),
                child: TextField(
                  controller: _messageController,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: const InputDecoration(
                    hintText: 'Ask your coach…',
                    hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 15),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: _isTyping ? 'Stop generating' : 'Send message',
              child: InkWell(
                onTap: _isTyping ? () => setState(() => _stopRequested = true) : () => _send(_messageController.text),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: _isTyping ? Colors.red.shade400 : Colors.green.shade600, shape: BoxShape.circle),
                  child: Icon(_isTyping ? LucideIcons.square : LucideIcons.arrowUp, color: Colors.white, size: 20),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
