import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/meal_item.dart';
import '../../../core/theme/app_colors.dart';

/// Bottom sheet to add a food, or edit / replace an existing one.
///
/// Nutrition describes the **whole amount**. If the user only changes the
/// amount, the nutrition is scaled to match automatically; once they type into
/// a nutrition field themselves we stop touching it.
Future<MealItem?> showMealItemEditor(BuildContext context, {MealItem? item}) {
  return showModalBottomSheet<MealItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _MealItemEditor(item: item),
    ),
  );
}

class _MealItemEditor extends StatefulWidget {
  const _MealItemEditor({this.item});
  final MealItem? item;

  @override
  State<_MealItemEditor> createState() => _MealItemEditorState();
}

class _MealItemEditorState extends State<_MealItemEditor> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fats;
  late String _unit;
  String? _error;
  bool _nutritionTouched = false;

  bool get _isNew => widget.item == null;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _name = TextEditingController(text: i?.name ?? '');
    _amount = TextEditingController(text: i == null ? '100' : _fmt(i.estimatedWeight));
    _kcal = TextEditingController(text: i == null ? '' : i.calories.round().toString());
    _protein = TextEditingController(text: i == null ? '' : _fmt(i.protein));
    _carbs = TextEditingController(text: i == null ? '' : _fmt(i.carbs));
    _fats = TextEditingController(text: i == null ? '' : _fmt(i.fats));
    _unit = i?.servingUnit ?? ServingUnit.gram;
  }

  @override
  void dispose() {
    for (final c in [_name, _amount, _kcal, _protein, _carbs, _fats]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  void _onAmountChanged(String _) {
    final base = widget.item;
    final amount = _num(_amount);
    if (base == null || _nutritionTouched || amount == null || amount <= 0) return;
    // Scale from the original item so repeated edits don't accumulate error.
    final scaled = base.withWeight(amount);
    _kcal.text = scaled.calories.round().toString();
    _protein.text = _fmt(double.parse(scaled.protein.toStringAsFixed(1)));
    _carbs.text = _fmt(double.parse(scaled.carbs.toStringAsFixed(1)));
    _fats.text = _fmt(double.parse(scaled.fats.toStringAsFixed(1)));
  }

  void _save() {
    final name = _name.text.trim();
    final amount = _num(_amount);
    final kcal = _num(_kcal);
    final p = _num(_protein) ?? 0;
    final c = _num(_carbs) ?? 0;
    final f = _num(_fats) ?? 0;

    String? err;
    if (name.isEmpty) {
      err = 'Give this food a name.';
    } else if (name.length > 60) {
      err = 'Name is too long (60 characters max).';
    } else if (amount == null || amount <= 0 || amount > 5000) {
      err = 'Enter an amount between 1 and 5000.';
    } else if (kcal == null || kcal < 0 || kcal > 3000) {
      err = 'Calories must be between 0 and ${3000}.';
    } else if ([p, c, f].any((v) => v < 0 || v > AppConfig.maxMealMacroGrams)) {
      err = 'Protein, carbs and fats must be between 0 and ${AppConfig.maxMealMacroGrams} g.';
    }
    if (err != null) {
      HapticFeedback.mediumImpact();
      setState(() => _error = err);
      return;
    }

    final old = widget.item;
    HapticFeedback.lightImpact();
    Navigator.pop(
      context,
      MealItem(
        id: old?.id ?? 'item_${const Uuid().v4()}',
        name: name,
        category: old?.category ?? 'other',
        estimatedWeight: amount!,
        servingUnit: _unit,
        calories: kcal!.roundToDouble(),
        protein: p,
        carbs: c,
        fats: f,
        // The user has now vouched for this food.
        confidence: 1.0,
        source: old?.source ?? ItemSource.manual,
        originalName: old?.originalName,
        originalCalories: old?.originalCalories,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.borderDark,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(_isNew ? 'Add food' : 'Edit food',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(
              _isNew
                  ? 'Nutrition is for the whole amount you ate.'
                  : 'Change the name or numbers if the AI got it wrong. '
                      'Changing only the amount updates the nutrition for you.',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 20),
            _field('Food name', _name, capitalization: TextCapitalization.words),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: _field('Amount', _amount,
                      numeric: true, onChanged: _onAmountChanged),
                ),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: _unitPicker()),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _field('Calories', _kcal, numeric: true, suffix: 'kcal', touches: true)),
                const SizedBox(width: 12),
                Expanded(child: _field('Protein', _protein, numeric: true, suffix: 'g', touches: true)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _field('Carbs', _carbs, numeric: true, suffix: 'g', touches: true)),
                const SizedBox(width: 12),
                Expanded(child: _field('Fats', _fats, numeric: true, suffix: 'g', touches: true)),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Semantics(
                liveRegion: true,
                child: Row(
                  children: [
                    Icon(LucideIcons.circleAlert, size: 16, color: Colors.red.shade600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    child: Text(_isNew ? 'Add to meal' : 'Save',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
    String? suffix,
    bool touches = false,
    TextCapitalization capitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textTertiary, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: numeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          textCapitalization: capitalization,
          inputFormatters: numeric ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))] : null,
          onChanged: (v) {
            if (touches) _nutritionTouched = true;
            onChanged?.call(v);
            if (_error != null) setState(() => _error = null);
          },
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            suffixText: suffix,
            filled: true,
            fillColor: AppColors.surfaceMuted,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _unitPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('UNIT',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textTertiary, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _unit,
          items: [
            for (final u in ServingUnit.all) DropdownMenuItem(value: u, child: Text(u)),
          ],
          onChanged: (v) => setState(() => _unit = v ?? _unit),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceMuted,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
