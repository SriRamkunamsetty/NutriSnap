import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/user_provider.dart';

class AIChatScreen extends ConsumerStatefulWidget {
  const AIChatScreen({super.key});

  @override
  ConsumerState<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends ConsumerState<AIChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isTyping = false;
  List<String> _suggestions = [];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendMessage([String? suggestion]) async {
    final text = suggestion ?? _messageController.text.trim();
    if (text.isEmpty || _isTyping) return;

    final userState = ref.read(userNotifierProvider);
    if (userState.profile == null) return;

    HapticFeedback.lightImpact();
    setState(() {
      _isTyping = true;
      _messageController.clear();
      _suggestions = [];
    });

    final storage = ref.read(storageServiceProvider);
    final gemini = ref.read(geminiServiceProvider);

    try {
      // 1. Save user message locally
      await storage.saveChatMessage('user', text);
      _scrollToBottom();

      // 2. Get history for context
      final history = await storage.getChatHistory();
      final scans = await storage.getScanHistory();
      final dailySummary = ref.read(dailySummaryStreamProvider).valueOrNull;

      // 3. Request AI response
      final response = await gemini.getAICoachResponse(
        historyMessages: history,
        profile: userState.profile!,
        dailySummary: dailySummary,
        recentHistory: scans,
      );

      // 4. Save AI response
      await storage.saveChatMessage('model', response['text']);
      
      if (mounted) {
        setState(() {
          _suggestions = List<String>.from(response['suggestions'] ?? []);
          _isTyping = false;
        });
        HapticFeedback.mediumImpact();
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTyping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to get AI response. Please try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatHistoryAsync = ref.watch(chatHistoryStreamProvider);
    final userProfile = ref.watch(userNotifierProvider).profile;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(12),
                image: userProfile?.aiAvatarUrl != null 
                  ? DecorationImage(image: NetworkImage(userProfile!.aiAvatarUrl!), fit: BoxFit.cover)
                  : null,
              ),
              child: userProfile?.aiAvatarUrl == null ? Icon(LucideIcons.sparkles, color: Colors.green.shade600, size: 20) : null,
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NutriSnap Coach', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                Text('Real-time AI Guidance', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 0.5)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              // Option to clear chat or see info
            },
            icon: const Icon(LucideIcons.info, color: AppColors.textTertiary),
          ),
        ],
      ),
      body: Column(
        children: [
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: chatHistoryAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return _buildEmptyState();
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(24),
                  itemCount: messages.length + (_isTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return _buildTypingIndicator();
                    }
                    return _buildMessageBubble(messages[index]);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: Colors.green)),
              error: (err, _) => Center(child: Text('Error: $err')),
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(32)),
              child: Icon(LucideIcons.sparkles, size: 48, color: Colors.green.shade600),
            ),
            const SizedBox(height: 24),
            const Text('Your AI Health Coach', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            const Text(
              'Ask me anything about your nutrition, workouts, or how to reach your fitness goals faster.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500, height: 1.5),
            ),
            const SizedBox(height: 32),
            _buildSuggestionChip('How is my protein intake today?'),
            const SizedBox(height: 12),
            _buildSuggestionChip('Tips for better sleep?'),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(String text) {
    return InkWell(
      onTap: () => _handleSendMessage(text),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.messageCircle, size: 14, color: Colors.green.shade600),
            const SizedBox(width: 8),
            Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isMe = message.role == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
             const CircleAvatar(radius: 12, backgroundColor: Colors.transparent, child: Icon(LucideIcons.sparkles, size: 12, color: Colors.green)),
             const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isMe ? Colors.green.shade600 : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isMe ? 20 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 20),
                ),
                border: isMe ? null : Border.all(color: AppColors.border),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Text(
                message.text,
                style: TextStyle(color: isMe ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w500, height: 1.4),
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 32), // Padding for alignment
          if (!isMe) const SizedBox(width: 32),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          const CircleAvatar(radius: 12, backgroundColor: Colors.transparent, child: Icon(LucideIcons.sparkles, size: 12, color: Colors.green)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 4, height: 4, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.green)),
                const SizedBox(width: 8),
                Text('AI is thinking...', style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
      child: Column(
        children: [
          if (_suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) => _buildSuggestionChip(_suggestions[index]),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(24)),
                  child: TextField(
                    controller: _messageController,
                    onSubmitted: (_) => _handleSendMessage(),
                    decoration: const InputDecoration(hintText: 'Ask your coach...', hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14), border: InputBorder.none),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: _isTyping ? null : _handleSendMessage,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: _isTyping ? Colors.grey.shade300 : Colors.green.shade600, shape: BoxShape.circle),
                  child: const Icon(LucideIcons.send, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
