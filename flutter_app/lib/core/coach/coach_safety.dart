import 'package:equatable/equatable.dart';

enum SafetyLevel {
  /// Ordinary nutrition / fitness question.
  none,

  /// Touches health conditions or medicines: answer generally, add a disclaimer.
  medical,

  /// Extreme dieting or disordered-eating signals: decline, be kind, redirect.
  extremeDiet,

  /// Possible emergency or self-harm: do not use the model, give safe guidance.
  emergency,
}

class SafetyAssessment extends Equatable {
  const SafetyAssessment(this.level, {this.reply});
  final SafetyLevel level;

  /// A fixed, human-reviewed answer that replaces the model for risky topics.
  final String? reply;

  bool get bypassesModel => reply != null;

  @override
  List<Object?> get props => [level, reply];
}

/// Guardrails around the coach.
///
/// NutriSnap gives wellness information. It must not diagnose, prescribe,
/// invent measurements, or coach dangerous dieting. The highest-risk cases are
/// handled with fixed, reviewed text and never reach the language model; the
/// model's own answers are filtered afterwards as a second line of defence.
class CoachSafety {
  const CoachSafety._();

  static const disclaimer =
      'NutriSnap shares general wellness information, not medical advice. For anything about a health condition, symptoms or medicines, please talk to a qualified healthcare professional.';

  static final _emergency = RegExp(
    r"(suicid|kill myself|end my life|want to die|self[- ]?harm|hurt myself|cut myself|overdos|can'?t breathe|cannot breathe|chest pain|heart attack|stroke|unconscious|severe bleeding|poison)",
    caseSensitive: false,
  );

  static final _extremeDiet = RegExp(
    r"(starv(e|ing) myself|stop eating|not eat(ing)? (at all|anything)|purge|make myself (throw up|vomit)|laxative|anorex|bulimi|pro[- ]?ana|eat nothing|zero calories? (a|per) day|(lose|drop) \d+\s?(kg|kilos?|pounds?|lbs?) in (a|one|1|two|2|three|3) (day|week)s?|\b([1-9]\d{2}|[1-9]\d?) ?(kcal|calories?) (a|per) day\b)",
    caseSensitive: false,
  );

  static final _medical = RegExp(
    r"(diabet|insulin|blood sugar|glucose|blood pressure|hypertens|cholesterol|thyroid|pcos|pregnan|breastfeed|lactat|kidney|liver|cancer|medicin|medication|tablet|prescri|dose|dosage|allerg|anaphyl|symptom|diagnos|disease|infection|fever|acid reflux|ibs|celiac|coeliac)",
    caseSensitive: false,
  );

  static SafetyAssessment assess(String message) {
    if (_emergency.hasMatch(message)) {
      return const SafetyAssessment(SafetyLevel.emergency, reply: _emergencyReply);
    }
    if (_extremeDiet.hasMatch(message)) {
      return const SafetyAssessment(SafetyLevel.extremeDiet, reply: _extremeDietReply);
    }
    if (_medical.hasMatch(message)) return const SafetyAssessment(SafetyLevel.medical);
    return const SafetyAssessment(SafetyLevel.none);
  }

  static const _emergencyReply =
      "I'm really sorry you're going through this, and I'm glad you said something. I can't help with this safely, but you don't have to handle it alone.\n\n"
      "If you might act on these thoughts or you're in danger, please call your local emergency number now (112 in India) or go to the nearest hospital.\n\n"
      "You can also talk to someone right away: in India, Tele-MANAS is free and open 24/7 at 14416. Elsewhere, search for your country's crisis line. If you can, tell someone you trust who can be with you.\n\n"
      "If this is about a physical symptom like chest pain or trouble breathing, please seek emergency care immediately rather than waiting.";

  static const _extremeDietReply =
      "I can't help with that, because it could seriously harm your health. Very low calorie targets, skipping food, or trying to lose weight extremely fast isn't something NutriSnap will coach.\n\n"
      "What I can do is help you plan steady, sustainable eating that fits your day. A gentle deficit of a few hundred calories with enough protein works better than crash dieting.\n\n"
      "If food or weight has started to feel stressful or out of control, please consider talking to a doctor, a registered dietitian, or someone you trust. You deserve support.";

  /// Checks (and if needed replaces) the model's answer.
  ///
  /// The prompt already forbids these things; this is the safety net for when
  /// a small on-device model ignores it.
  static String filterReply(String reply, SafetyLevel level) {
    final lower = reply.toLowerCase();

    final belowFloor = RegExp(r'\b([1-9]\d{2}|1[01]\d{2})\s?(kcal|calories?)\b(\s+(a|per)\s+day|\s+daily)').hasMatch(lower);
    final stopMeds = RegExp(r'(stop|skip|reduce|change|increase)\s+(taking\s+)?(your\s+)?(medic|insulin|tablet|pills?|dose)').hasMatch(lower);
    final diagnoses = RegExp(r'\byou (have|likely have|probably have|suffer from)\s+(diabet|thyroid|cancer|pcos|hypertens|an? (infection|disease|disorder|condition))').hasMatch(lower);
    if (belowFloor || stopMeds || diagnoses) {
      return "I can't give specific advice on that safely. Very low calorie targets, changing medicines, or working out what condition someone has all need a qualified professional who knows your health.\n\n$disclaimer";
    }

    if (level == SafetyLevel.medical && !lower.contains('healthcare professional')) {
      return '$reply\n\n$disclaimer';
    }
    return reply;
  }
}
