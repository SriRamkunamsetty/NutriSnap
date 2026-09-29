import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/food.dart';
import '../../../core/models/meal_item.dart';
import '../../../core/models/scan_result.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ios_kit.dart';

Future<T?> _sheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: SingleChildScrollView(child: child),
        ),
      ),
    );

Widget _grabber() => Center(
      child: Container(
        width: 40,
        height: 5,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(color: AppColors.borderDark, borderRadius: BorderRadius.circular(3)),
      ),
    );

String fmtNum(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

// -----------------------------------------------------------------------------
// Log a food
// -----------------------------------------------------------------------------

/// Logs [servings] of [food] as a meal. Returns the saved meal (or null).
Future<ScanResult?> showLogFoodSheet(BuildContext context, Food food) =>
    _sheet<ScanResult>(context, _LogFood(food: food));

class _LogFood extends ConsumerStatefulWidget {
  const _LogFood({required this.food});
  final Food food;

  @override
  ConsumerState<_LogFood> createState() => _LogFoodState();
}

class _LogFoodState extends ConsumerState<_LogFood> {
  double _servings = 1;
  bool _saving = false;

  Food get f => widget.food;

  Future<void> _save() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      final item = MealItem(
        id: 'item_${const Uuid().v4()}',
        name: f.name,
        category: f.category,
        estimatedWeight: _servings,
        servingUnit: ServingUnit.serving,
        calories: f.calories * _servings,
        protein: f.protein * _servings,
        carbs: f.carbs * _servings,
        fats: f.fats * _servings,
        confidence: f.isCustom ? 1.0 : f.confidence,
        source: ItemSource.library,
      );
      final t = MealTotals.of([item]);
      final saved = await ref.read(scanRepositoryProvider).add(ScanResult(
            id: '',
            userId: '',
            foodName: f.name,
            type: 'food',
            details: '${fmtNum(_servings)} × ${f.serving}',
            calories: t.calories,
            protein: t.protein,
            carbs: t.carbs,
            fats: t.fats,
            confidence: item.confidence,
            timestamp: DateTime.now().toIso8601String(),
            items: [item],
            analysisStatus: AnalysisStatus.manual,
          ));
      await ref.read(foodRepositoryProvider).markUsed(f.id);
      if (mounted) Navigator.pop(context, saved);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not log this food.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final kcal = (f.calories * _servings).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        Text(f.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text('1 serving = ${f.serving} (about ${fmtNum(f.servingGrams)} g)',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        Center(
          child: Container(
            decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Fewer servings',
                iconSize: 22,
                onPressed: _servings <= 0.5 ? null : () => setState(() => _servings -= 0.5),
                icon: const Icon(LucideIcons.minus),
              ),
              SizedBox(
                width: 110,
                child: Column(children: [
                  Text(fmtNum(_servings),
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -1)),
                  Text(_servings == 1 ? 'serving' : 'servings',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                ]),
              ),
              IconButton(
                tooltip: 'More servings',
                iconSize: 22,
                onPressed: _servings >= 10 ? null : () => setState(() => _servings += 0.5),
                icon: const Icon(LucideIcons.plus),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        Row(children: [
          _macro('Calories', '$kcal', 'kcal', Colors.green),
          _macro('Protein', fmtNum(f.protein * _servings), 'g', Colors.blue),
          _macro('Carbs', fmtNum(f.carbs * _servings), 'g', Colors.orange),
          _macro('Fat', fmtNum(f.fats * _servings), 'g', Colors.purple),
        ]),
        if (!f.isCustom)
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Text('Approximate values for a typical serving; your portion may differ.',
                style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
          ),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: ProminentButton(label: 'Log meal', busy: _saving, onPressed: _save)),
      ],
    );
  }

  Widget _macro(String label, String value, String unit, MaterialColor c) => Expanded(
        child: Column(children: [
          Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: c.shade700)),
          Text(unit, style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ]),
      );
}

// -----------------------------------------------------------------------------
// Details
// -----------------------------------------------------------------------------

Future<void> showFoodDetailsSheet(BuildContext context, Food food) => _sheet<void>(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _grabber(),
          Text(food.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Per ${food.serving} (about ${fmtNum(food.servingGrams)} g)',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 18),
          _row('Calories', '${food.calories.round()} kcal'),
          _row('Protein', '${fmtNum(food.protein)} g'),
          _row('Carbohydrates', '${fmtNum(food.carbs)} g'),
          _row('Fat', '${fmtNum(food.fats)} g'),
          if (food.fiber != null) _row('Fibre', '${fmtNum(food.fiber!)} g'),
          const Divider(height: 28, color: AppColors.border),
          if (food.aliases.isNotEmpty) ...[
            const Text('ALSO KNOWN AS',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textTertiary)),
            const SizedBox(height: 6),
            Text(food.aliases.join(', '), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
          ],
          if (food.tags.isNotEmpty)
            Wrap(spacing: 6, runSpacing: 6, children: [for (final t in food.tags) SourceChip(t)]),
          const SizedBox(height: 16),
          Row(children: [
            Icon(food.isCustom ? LucideIcons.userRound : LucideIcons.bookOpen, size: 14, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${food.source} · ${food.isCustom ? 'exact as you entered it' : '${(food.confidence * 100).round()}% confidence'}',
                style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
              ),
            ),
          ]),
        ],
      ),
    );

Widget _row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Expanded(child: Text(k, style: const TextStyle(fontSize: 15, color: AppColors.textSecondary))),
        Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      ]),
    );

// -----------------------------------------------------------------------------
// Create / edit a custom food
// -----------------------------------------------------------------------------

/// Opens the editor. For a built-in food this creates the user's own copy.
Future<Food?> showFoodEditorSheet(BuildContext context, {Food? food, String? initialName}) =>
    _sheet<Food>(context, _FoodEditor(food: food, initialName: initialName));

class _FoodEditor extends ConsumerStatefulWidget {
  const _FoodEditor({this.food, this.initialName});
  final Food? food;
  final String? initialName;

  @override
  ConsumerState<_FoodEditor> createState() => _FoodEditorState();
}

class _FoodEditorState extends ConsumerState<_FoodEditor> {
  static const _tagChoices = [
    'Indian', 'South Indian', 'Andhra', 'Telangana', 'North Indian', 'Home Food', 'Hostel', 'Snacks',
    'Breakfast', 'Lunch', 'Dinner',
  ];
  static const _categories = [
    'breakfast', 'rice', 'bread', 'curry', 'dal', 'chutney', 'snack', 'sweet', 'beverage', 'fruit',
    'protein', 'salad', 'dairy', 'meal', 'other',
  ];

  late final _name = TextEditingController(text: widget.food?.name ?? widget.initialName ?? '');
  late final _aliases = TextEditingController(text: widget.food?.aliases.join(', ') ?? '');
  late final _serving = TextEditingController(text: widget.food?.serving ?? '1 serving');
  late final _grams = TextEditingController(text: widget.food == null ? '' : fmtNum(widget.food!.servingGrams));
  late final _kcal = TextEditingController(text: widget.food == null ? '' : fmtNum(widget.food!.calories));
  late final _protein = TextEditingController(text: widget.food == null ? '' : fmtNum(widget.food!.protein));
  late final _carbs = TextEditingController(text: widget.food == null ? '' : fmtNum(widget.food!.carbs));
  late final _fats = TextEditingController(text: widget.food == null ? '' : fmtNum(widget.food!.fats));
  late final Set<String> _tags = {...?widget.food?.tags};
  late String _category = widget.food?.category ?? 'other';
  String? _error;
  bool _saving = false;

  bool get _isEdit => widget.food?.isCustom == true;

  @override
  void dispose() {
    for (final c in [_name, _aliases, _serving, _grams, _kcal, _protein, _carbs, _fats]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _n(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final name = _name.text.trim();
    final grams = _n(_grams);
    final kcal = _n(_kcal);
    final p = _n(_protein) ?? 0, c = _n(_carbs) ?? 0, fa = _n(_fats) ?? 0;

    String? err;
    if (name.isEmpty) {
      err = 'Give the food a name.';
    } else if (_serving.text.trim().isEmpty) {
      err = 'Describe one serving, e.g. "1 katori".';
    } else if (grams == null || grams <= 0 || grams > 3000) {
      err = 'Serving weight must be between 1 and 3000 g.';
    } else if (kcal == null || kcal < 0 || kcal > 3000) {
      err = 'Calories per serving must be between 0 and 3000.';
    } else if ([p, c, fa].any((v) => v < 0 || v > 300)) {
      err = 'Protein, carbs and fat must be between 0 and 300 g.';
    }
    if (err != null) {
      HapticFeedback.mediumImpact();
      setState(() => _error = err);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = Food(
      id: _isEdit ? widget.food!.id : '',
      name: name,
      aliases: [for (final a in _aliases.text.split(',')) if (a.trim().isNotEmpty) a.trim()],
      tags: _tags.toList(),
      category: _category,
      serving: _serving.text.trim(),
      servingGrams: grams!,
      calories: kcal!,
      protein: p,
      carbs: c,
      fats: fa,
      isCustom: true,
      useCount: widget.food?.useCount ?? 0,
      lastUsed: widget.food?.lastUsed,
    );
    try {
      final saved = await ref.read(foodRepositoryProvider).saveCustom(draft);
      if (mounted) Navigator.pop(context, saved);
    } catch (_) {
      if (mounted) setState(() {
        _saving = false;
        _error = 'Could not save this food.';
      });
    }
  }

  InputDecoration _dec({String? suffix, String? hint}) => InputDecoration(
        suffixText: suffix,
        hintText: hint,
        filled: true,
        fillColor: AppColors.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      );

  Widget _lbl(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(t.toUpperCase(),
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textTertiary)),
      );

  Widget _num(TextEditingController c, String suffix) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: _dec(suffix: suffix),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        Text(_isEdit ? 'Edit food' : (widget.food != null ? 'Save my version' : 'New food'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        if (widget.food != null && !_isEdit)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Built-in foods stay as they are; this saves your own copy.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        _lbl('Name'),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: _dec(hint: 'e.g. Amma\'s Pulusu')),
        _lbl('Other names (comma separated)'),
        TextField(controller: _aliases, decoration: _dec(hint: 'e.g. Charu, Saaru')),
        _lbl('One serving is'),
        Row(children: [
          Expanded(flex: 3, child: TextField(controller: _serving, decoration: _dec(hint: '1 katori'))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: _num(_grams, 'g')),
        ]),
        _lbl('Nutrition per serving'),
        Row(children: [
          Expanded(child: _num(_kcal, 'kcal')),
          const SizedBox(width: 10),
          Expanded(child: _num(_protein, 'g P')),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _num(_carbs, 'g C')),
          const SizedBox(width: 10),
          Expanded(child: _num(_fats, 'g F')),
        ]),
        _lbl('Category'),
        DropdownButtonFormField<String>(
          initialValue: _categories.contains(_category) ? _category : 'other',
          items: [for (final c in _categories) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => setState(() => _category = v ?? _category),
          decoration: _dec(),
        ),
        _lbl('Tags'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final t in _tagChoices)
            FilterChip(
              label: Text(t),
              selected: _tags.contains(t),
              onSelected: (on) => setState(() => on ? _tags.add(t) : _tags.remove(t)),
              selectedColor: Colors.green.shade100,
            ),
        ]),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: ProminentButton(label: 'Save food', busy: _saving, onPressed: _save)),
      ],
    );
  }
}
