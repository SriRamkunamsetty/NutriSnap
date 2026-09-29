import 'package:flutter_test/flutter_test.dart';
import 'package:nutrisnap_app/core/ai/ai_prompts.dart';
import 'package:nutrisnap_app/core/models/chat_message.dart';

void main() {
  test('coach system prompt embeds the briefing and no unresolved templates', () {
    final p = AiPrompts.coachSystem(briefing: 'GOALS: 1800 kcal\nTODAY EATEN: 1200 kcal (600 left)');
    expect(p, contains('GOALS: 1800 kcal'));
    expect(p, contains('600 left'));
    expect(p, contains('SUGGESTIONS:'));
    expect(p, contains('1200 kcal a day')); // safety floor stated to the model
    expect(p.contains(r'${'), isFalse);
    expect(p.contains(r'\$'), isFalse);
    expect(p.contains('null'), isFalse);
  });

  test('history is folded into the user message, newest turns kept within budget', () {
    final history = [
      for (var i = 0; i < 30; i++)
        ChatMessage(
          id: '$i',
          userId: 'u',
          role: i.isEven ? 'user' : 'model',
          text: 'message number $i ${'x' * 400}',
          timestamp: '2025-03-01T09:00:00.000',
        ),
    ];
    final out = AiPrompts.coachUser(message: 'What now?', history: history, maxChars: 1500);
    expect(out, endsWith("User's new message: What now?"));
    expect(out, contains('message number 29')); // newest kept
    expect(out, isNot(contains('message number 0 '))); // oldest dropped
    expect(out.length, lessThan(2200));
  });

  test('no history means the raw message', () {
    expect(AiPrompts.coachUser(message: 'hi', history: const []), 'hi');
  });
}
