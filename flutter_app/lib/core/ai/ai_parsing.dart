import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../enums/app_enums.dart';
import '../models/meal_item.dart';
import 'ai_models.dart';

/// Turns raw model text into validated, typed results.
///
/// Small on-device models do not support hard JSON-schema decoding, so they
/// occasionally wrap JSON in prose or code fences, emit numbers as strings, or
/// return implausible values. Everything here is defensive and pure so it can
/// be unit-tested without a model.
class AiParsing {
  const AiParsing._();

  /// Finds and decodes the first balanced `{...}` object in [raw].
  static Map<String, dynamic>? extractJsonObject(String raw) {
    final text = raw.replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '');
    final start = text.indexOf('{');
    if (start < 0) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{') {
        depth++;
      } else if (ch == '}') {
        depth--;
        if (depth == 0) {
          try {
            final decoded = jsonDecode(text.substring(start, i + 1));
            return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
          } on FormatException {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// Reads a number from `350`, `350.5`, `"350"`, or `"about 350 kcal"`.
  static double? toNumber(dynamic v) {
    if (v is num) return v.isFinite ? v.toDouble() : null;
    if (v is String) {
      final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(v.replaceAll(',', ''));
      return m == null ? null : double.tryParse(m.group(0)!);
    }
    return null;
  }


  static String _str(dynamic v, {int max = 600}) {
    final s = (v is String ? v : v?.toString() ?? '').trim();
    return s.length > max ? '${s.substring(0, max).trimRight()}…' : s;
  }

  // ---------------------------------------------------------------------------
  // Meal (one or more foods)
  // ---------------------------------------------------------------------------

  static const _uuid = Uuid();
  static const int maxItems = 12;

  /// Parses the model's answer into a validated [MealAnalysisResult].
  ///
  /// Accepts the multi-food shape `{"items":[...]}` and, defensively, the older
  /// single-food shape `{"foodName": ..., "calories": ...}`.
  static MealAnalysisResult parseMeal(
    String raw, {
    String? modelVersion,
    DateTime? now,
  }) {
    final json = extractJsonObject(raw);
    if (json == null) {
      throw AiException('The AI response could not be read. Please try again.');
    }

    var type = _str(json['type']).toLowerCase();
    if (!const {'food', 'person', 'animal', 'other'}.contains(type)) type = 'food';

    final rawItems = json['items'] ?? json['foods'] ?? json['detectedItems'];
    final entries = <Map<String, dynamic>>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) entries.add(Map<String, dynamic>.from(e));
      }
    } else if (json['foodName'] != null || json['name'] != null) {
      entries.add(json); // legacy single-food answer
    }

    final items = <MealItem>[];
    if (type == 'food') {
      for (final e in entries.take(maxItems)) {
        final item = _parseItem(e);
        if (item != null) items.add(item);
      }
      if (items.isEmpty) {
        throw AiException('The AI could not tell what food this is. Try a clearer photo.');
      }
    }

    return MealAnalysisResult(
      mealId: 'meal_${_uuid.v4()}',
      detectedItems: items,
      type: type,
      description: _str(json['description'] ?? json['summary']),
      confidence: _overallConfidence(items, toNumber(json['confidence'])),
      timestamp: now ?? DateTime.now(),
      modelVersion: modelVersion,
    );
  }

  static MealItem? _parseItem(Map<String, dynamic> e) {
    final name = _str(e['name'] ?? e['foodName'] ?? e['food'], max: 60);
    if (name.isEmpty) return null;

    var confidence = _normConfidence(toNumber(e['confidence']), 0.6);

    // Portion. A missing amount is a guess, so be honest about it.
    var weight = toNumber(e['weightGrams'] ?? e['estimatedWeight'] ?? e['weight'] ?? e['grams'] ?? e['quantity']);
    var unit = ServingUnit.normalize(_str(e['servingUnit'] ?? e['unit']));
    if (weight == null || weight <= 0) {
      weight = 100;
      unit = ServingUnit.gram;
      confidence *= 0.7;
    }
    weight = weight.clamp(1.0, 5000.0);

    var calories = (toNumber(e['calories']) ?? 0).clamp(0.0, 3000.0);
    final protein = (toNumber(e['protein']) ?? 0).clamp(0.0, 300.0);
    final carbs = (toNumber(e['carbs'] ?? e['carbohydrates']) ?? 0).clamp(0.0, 300.0);
    final fats = (toNumber(e['fats'] ?? e['fat']) ?? 0).clamp(0.0, 300.0);

    // Energy must roughly agree with the macros (4/4/9 kcal per gram).
    final fromMacros = protein * 4 + carbs * 4 + fats * 9;
    if (fromMacros > 0) {
      final off = (calories - fromMacros).abs() / fromMacros;
      if (calories == 0 || off > 0.4) {
        calories = fromMacros.clamp(0.0, 3000.0);
        confidence *= 0.8;
      }
    }

    final category = _str(e['category'], max: 24).toLowerCase();
    return MealItem(
      id: 'item_${_uuid.v4()}',
      name: name,
      category: category.isEmpty ? 'other' : category,
      estimatedWeight: double.parse(weight.toStringAsFixed(1)),
      servingUnit: unit,
      calories: calories.roundToDouble(),
      protein: double.parse(protein.toStringAsFixed(1)),
      carbs: double.parse(carbs.toStringAsFixed(1)),
      fats: double.parse(fats.toStringAsFixed(1)),
      confidence: double.parse(confidence.clamp(0.0, 1.0).toStringAsFixed(2)),
      source: ItemSource.ai,
      originalName: name,
      originalCalories: calories.roundToDouble(),
    );
  }

  /// Parses the answer to "estimate these dishes". Results are matched back to
  /// the requested [names] by normalised name (falling back to order), and a
  /// dish the model skipped or garbled is simply absent - never invented.
  static List<DishEstimate> parseDishEstimates(String raw, List<String> names) {
    final json = extractJsonObject(raw);
    final list = json?['items'] ?? json?['dishes'];
    if (list is! List) {
      throw AiException('The AI response could not be read. Please try again.');
    }
    final parsed = <String, DishEstimate>{};
    final ordered = <DishEstimate>[];
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final name = _str(m['name'], max: 60);
      if (name.isEmpty) continue;
      final protein = (toNumber(m['protein']) ?? 0).clamp(0.0, 200.0);
      final carbs = (toNumber(m['carbs'] ?? m['carbohydrates']) ?? 0).clamp(0.0, 300.0);
      final fats = (toNumber(m['fats'] ?? m['fat']) ?? 0).clamp(0.0, 200.0);
      var kcal = (toNumber(m['calories']) ?? 0).clamp(0.0, 1500.0);
      final fromMacros = protein * 4 + carbs * 4 + fats * 9;
      var conf = _normConfidence(toNumber(m['confidence']), 0.5);
      if (fromMacros > 0 && (kcal == 0 || (kcal - fromMacros).abs() / fromMacros > 0.4)) {
        kcal = fromMacros.clamp(0.0, 1500.0);
        conf *= 0.8;
      }
      if (kcal <= 0) continue; // an estimate of nothing is not an estimate
      final est = DishEstimate(
        name: name,
        serving: _str(m['serving'] ?? m['servingUnit'], max: 40).isEmpty ? '1 serving' : _str(m['serving'] ?? m['servingUnit'], max: 40),
        calories: kcal.roundToDouble(),
        protein: double.parse(protein.toStringAsFixed(1)),
        carbs: double.parse(carbs.toStringAsFixed(1)),
        fats: double.parse(fats.toStringAsFixed(1)),
        // Text-only guesses are never treated as confident.
        confidence: double.parse(conf.clamp(0.0, 0.7).toStringAsFixed(2)),
      );
      parsed[normalizeKey(name)] = est;
      ordered.add(est);
    }
    final out = <DishEstimate>[];
    for (var i = 0; i < names.length; i++) {
      final hit = parsed[normalizeKey(names[i])] ?? (i < ordered.length && ordered.length == names.length ? ordered[i] : null);
      if (hit != null) out.add(DishEstimate(
        name: names[i],
        serving: hit.serving,
        calories: hit.calories,
        protein: hit.protein,
        carbs: hit.carbs,
        fats: hit.fats,
        confidence: hit.confidence,
      ));
    }
    return out;
  }

  static String normalizeKey(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static double _normConfidence(double? v, double fallback) {
    var c = v ?? fallback;
    if (c > 1) c = c / 100; // model said "85"
    return c.clamp(0.0, 1.0);
  }

  /// Calorie-weighted mean of the items' confidences, blended with the model's
  /// own overall figure when it gave one.
  static double _overallConfidence(List<MealItem> items, double? modelOverall) {
    if (items.isEmpty) return _normConfidence(modelOverall, 1.0);
    final totalKcal = items.fold<double>(0, (a, i) => a + i.calories);
    final weighted = totalKcal > 0
        ? items.fold<double>(0, (a, i) => a + i.confidence * i.calories) / totalKcal
        : items.fold<double>(0, (a, i) => a + i.confidence) / items.length;
    final c = modelOverall == null
        ? weighted
        : (weighted + _normConfidence(modelOverall, weighted)) / 2;
    return double.parse(c.clamp(0.0, 1.0).toStringAsFixed(2));
  }

  // ---------------------------------------------------------------------------
  // Body
  // ---------------------------------------------------------------------------

  static BodyAnalysis parseBody(String raw) {
    final json = extractJsonObject(raw);
    if (json == null) {
      throw AiException('The AI response could not be read. Please try again.');
    }
    final fat = toNumber(json['fatEstimate'] ?? json['bodyFat']);
    if (fat == null) {
      throw AiException('The AI could not estimate body composition from this photo.');
    }
    return BodyAnalysis(
      bodyType: BodyTypeExtension.fromString(_str(json['bodyType'])),
      fatEstimate: double.parse(fat.clamp(3.0, 60.0).toStringAsFixed(1)),
      observations: _str(json['observations'] ?? json['notes']),
    );
  }

  // ---------------------------------------------------------------------------
  // Coach
  // ---------------------------------------------------------------------------

  static const _marker = 'SUGGESTIONS:';

  /// The visible part of a (possibly still streaming) coach reply, i.e. with
  /// the trailing `SUGGESTIONS:` line removed.
  static String visibleCoachText(String raw) {
    final i = raw.lastIndexOf(_marker);
    return (i < 0 ? raw : raw.substring(0, i)).trim();
  }

  static CoachReply parseCoachReply(String raw) {
    final i = raw.lastIndexOf(_marker);
    final suggestions = <String>[];
    if (i >= 0) {
      final tail = raw.substring(i + _marker.length);
      for (final part in tail.split(RegExp(r'\||\n'))) {
        final s = part.replaceAll(RegExp(r'^[\s\-\*\d\.\)]+'), '').trim();
        if (s.isNotEmpty && s.length <= 80) suggestions.add(s);
        if (suggestions.length == 3) break;
      }
    }
    return CoachReply(text: visibleCoachText(raw), suggestions: suggestions);
  }

  /// Light markdown clean-up for plain `Text` widgets: drops emphasis markers
  /// and headings, turns list markers into bullets.
  static String stripMarkdown(String md) {
    return md
        .replaceAll(RegExp(r'^\s*#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'\*\*|__|`'), '')
        .replaceAll(RegExp(r'^\s*[\*\-]\s+', multiLine: true), '• ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
