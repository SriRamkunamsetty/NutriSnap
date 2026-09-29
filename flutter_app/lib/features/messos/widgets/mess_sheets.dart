import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/ai/ai_models.dart';
import '../../../core/models/mess.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/mess_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ai_model_card.dart';
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

InputDecoration _dec({String? hint, String? label, String? suffix}) => InputDecoration(
      hintText: hint,
      labelText: label,
      suffixText: suffix,
      filled: true,
      fillColor: AppColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
    );

// -----------------------------------------------------------------------------
// Add a mess (college -> hostel -> mess)
// -----------------------------------------------------------------------------

Future<Mess?> showAddMessSheet(BuildContext context) => _sheet<Mess>(context, const _AddMess());

class _AddMess extends ConsumerStatefulWidget {
  const _AddMess();

  @override
  ConsumerState<_AddMess> createState() => _AddMessState();
}

class _AddMessState extends ConsumerState<_AddMess> {
  final _college = TextEditingController();
  final _hostel = TextEditingController();
  final _name = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _college.dispose();
    _hostel.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_college.text.trim().isEmpty || _hostel.text.trim().isEmpty) {
      setState(() => _error = 'Enter your college and hostel.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final mess = await ref.read(messRepositoryProvider).createMess(
          college: _college.text,
          hostel: _hostel.text,
          name: _name.text.trim().isEmpty ? '${_hostel.text.trim()} Mess' : _name.text,
        );
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.pop(context, mess);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        const Text('Add your mess',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Stored only on this phone. You can add more than one.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 18),
        TextField(controller: _college, textCapitalization: TextCapitalization.words, decoration: _dec(label: 'College', hint: 'e.g. JNTU Hyderabad')),
        const SizedBox(height: 12),
        TextField(controller: _hostel, textCapitalization: TextCapitalization.words, decoration: _dec(label: 'Hostel', hint: 'e.g. Block A')),
        const SizedBox(height: 12),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: _dec(label: 'Mess name (optional)', hint: 'e.g. Main Mess')),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: ProminentButton(label: 'Add mess', busy: _saving, onPressed: _save)),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Switch mess
// -----------------------------------------------------------------------------

Future<void> showSwitchMessSheet(BuildContext context, List<Mess> all, Mess active) => _sheet<void>(
      context,
      _SwitchMess(all: all, active: active),
    );

class _SwitchMess extends ConsumerWidget {
  const _SwitchMess({required this.all, required this.active});
  final List<Mess> all;
  final Mess active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        const Text('Your messes', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        for (final m in all)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(m.id == active.id ? LucideIcons.circleCheck : LucideIcons.circle,
                color: m.id == active.id ? Colors.green.shade600 : AppColors.textTertiary),
            title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(m.subtitle),
            trailing: IconButton(
              tooltip: 'Delete ${m.label}',
              icon: Icon(LucideIcons.trash2, size: 18, color: Colors.red.shade400),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('Delete ${m.label}?'),
                    content: const Text('Its saved menus are removed. Meals you already logged stay in your diary.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref.read(messRepositoryProvider).deleteMess(m.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
            onTap: () async {
              await ref.read(messRepositoryProvider).setActive(m.id);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            Navigator.pop(context);
            await showAddMessSheet(context);
          },
          icon: const Icon(LucideIcons.plus, size: 16),
          label: const Text('Add another mess'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Paste a whole-day menu
// -----------------------------------------------------------------------------

/// Parses pasted text and saves it. Returns how many meals were filled.
Future<int?> showPasteMenuSheet(BuildContext context, {required Mess mess, required String date}) =>
    _sheet<int>(context, _PasteMenu(mess: mess, date: date));

class _PasteMenu extends ConsumerStatefulWidget {
  const _PasteMenu({required this.mess, required this.date});
  final Mess mess;
  final String date;

  @override
  ConsumerState<_PasteMenu> createState() => _PasteMenuState();
}

class _PasteMenuState extends ConsumerState<_PasteMenu> {
  final _text = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final parsed = MessMenuParser.parse(_text.text);
    if (parsed.isEmpty) {
      setState(() => _error = 'Nothing to read. Try "Breakfast: Idli, Sambar" on each line.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final svc = ref.read(messServiceProvider);
    final repo = ref.read(messRepositoryProvider);
    var filled = 0;
    for (final entry in parsed.meals.entries) {
      if (entry.value.isEmpty) continue;
      final existing = (await repo.menu(widget.mess.id, widget.date))?.meal(entry.key);
      final dishes = await svc.match(entry.value, keep: existing?.dishes ?? const []);
      await repo.saveMeal(messId: widget.mess.id, date: widget.date, mealType: entry.key, dishes: dishes);
      filled++;
    }
    if (filled == 0) {
      setState(() {
        _saving = false;
        _error = 'Add a meal name before the dishes, like "Lunch: Rice, Dal".';
      });
      return;
    }
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.pop(context, filled);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        const Text('Paste today\'s menu',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Copy the menu from your mess group or notice board. One meal per line.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 14),
        TextField(
          controller: _text,
          minLines: 6,
          maxLines: 10,
          decoration: _dec(hint: 'Breakfast: Idli, Sambar, Chutney\nLunch: Rice, Dal, Chicken Curry, Curd\nSnacks: Samosa, Tea\nDinner: Chapati, Paneer Curry'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: ProminentButton(label: 'Read menu', busy: _saving, onPressed: _save)),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Edit one meal
// -----------------------------------------------------------------------------

Future<void> showEditMessMealSheet(
  BuildContext context, {
  required Mess mess,
  required String date,
  required String mealType,
  required List<MessDish> initial,
}) =>
    _sheet<void>(context, _EditMeal(mess: mess, date: date, mealType: mealType, initial: initial));

class _EditMeal extends ConsumerStatefulWidget {
  const _EditMeal({required this.mess, required this.date, required this.mealType, required this.initial});
  final Mess mess;
  final String date;
  final String mealType;
  final List<MessDish> initial;

  @override
  ConsumerState<_EditMeal> createState() => _EditMealState();
}

class _EditMealState extends ConsumerState<_EditMeal> {
  late List<MessDish> _dishes = List.of(widget.initial);
  late final _text = TextEditingController(text: widget.initial.map((d) => d.name).join(', '));
  bool _working = false;
  String? _message;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _applyText() async {
    final names = MessMenuParser.splitDishes(_text.text);
    final matched = await ref.read(messServiceProvider).match(names, keep: _dishes);
    if (mounted) setState(() => _dishes = matched);
  }

  Future<void> _estimateWithAi() async {
    if (!ref.read(gemmaModelProvider).isInstalled) {
      await showAiModelSheet(context);
      return;
    }
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final filled = await ref.read(messServiceProvider).fillWithAi(_dishes, ref.read(nutritionAiProvider));
      final stillUnknown = filled.where((d) => d.needsEstimate).length;
      if (mounted) setState(() {
        _dishes = filled;
        _message = stillUnknown == 0
            ? 'Estimated by the on-device AI. These are guesses; adjust any you know.'
            : '$stillUnknown dish${stillUnknown == 1 ? '' : 'es'} the AI couldn\'t estimate. Enter them by hand.';
      });
    } on AiException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _editNumbers(int i) async {
    final updated = await showDialog<MessDish>(context: context, builder: (_) => _DishNumbers(dish: _dishes[i]));
    if (updated != null && mounted) setState(() => _dishes = [..._dishes]..[i] = updated);
  }

  Future<void> _save() async {
    setState(() => _working = true);
    await ref.read(messRepositoryProvider).saveMeal(
          messId: widget.mess.id,
          date: widget.date,
          mealType: widget.mealType,
          dishes: _dishes,
        );
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final est = MessNutritionEstimate.of(_dishes);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _grabber(),
        Text('${MealType.label(widget.mealType)} menu',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        TextField(
          controller: _text,
          minLines: 2,
          maxLines: 4,
          onChanged: (_) => _applyText(),
          decoration: _dec(hint: 'Dishes, separated by commas: Rice, Dal, Curd'),
        ),
        const SizedBox(height: 14),
        if (_dishes.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Add the dishes served. Leave empty to clear this meal.',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          ),
        for (var i = 0; i < _dishes.length; i++) _dishRow(i),
        if (_dishes.any((d) => d.needsEstimate)) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _working ? null : _estimateWithAi,
            icon: _working
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(LucideIcons.sparkles, size: 16),
            label: const Text('Estimate missing dishes with AI'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ],
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_message!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        if (!est.isEmpty) ...[
          const Divider(height: 28, color: AppColors.border),
          Row(children: [
            const Expanded(child: Text('Meal total', style: TextStyle(fontWeight: FontWeight.w800))),
            Text('${est.calories} kcal · P ${est.protein} C ${est.carbs} F ${est.fats}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ],
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, child: ProminentButton(label: 'Save menu', busy: _working, onPressed: _save)),
      ],
    );
  }

  Widget _dishRow(int i) {
    final d = _dishes[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: InkWell(
            onTap: () => _editNumbers(i),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                Text(
                  d.needsEstimate
                      ? 'No nutrition yet · tap to enter'
                      : '${d.totalCalories.round()} kcal · ${d.source == DishSource.library ? 'library' : d.source == DishSource.ai ? 'AI estimate' : 'entered by you'}',
                  style: TextStyle(
                      fontSize: 12,
                      color: d.needsEstimate ? Colors.orange.shade800 : AppColors.textSecondary,
                      fontWeight: d.needsEstimate ? FontWeight.w700 : FontWeight.w500),
                ),
              ]),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Less ${d.name}',
          onPressed: d.servings <= 0.5 ? null : () => setState(() => _dishes = [..._dishes]..[i] = d.copyWith(servings: d.servings - 0.5)),
          icon: const Icon(LucideIcons.minus, size: 16),
        ),
        Text(d.servings == d.servings.roundToDouble() ? '${d.servings.round()}×' : '${d.servings}×',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        IconButton(
          tooltip: 'More ${d.name}',
          onPressed: d.servings >= 6 ? null : () => setState(() => _dishes = [..._dishes]..[i] = d.copyWith(servings: d.servings + 0.5)),
          icon: const Icon(LucideIcons.plus, size: 16),
        ),
      ]),
    );
  }
}

class _DishNumbers extends StatefulWidget {
  const _DishNumbers({required this.dish});
  final MessDish dish;

  @override
  State<_DishNumbers> createState() => _DishNumbersState();
}

class _DishNumbersState extends State<_DishNumbers> {
  late final _kcal = TextEditingController(text: widget.dish.calories == 0 ? '' : widget.dish.calories.round().toString());
  late final _p = TextEditingController(text: widget.dish.protein == 0 ? '' : widget.dish.protein.toString());
  late final _c = TextEditingController(text: widget.dish.carbs == 0 ? '' : widget.dish.carbs.toString());
  late final _f = TextEditingController(text: widget.dish.fats == 0 ? '' : widget.dish.fats.toString());
  String? _error;

  @override
  void dispose() {
    for (final c in [_kcal, _p, _c, _f]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _n(TextEditingController c) => c.text.trim().isEmpty ? 0 : double.tryParse(c.text.trim().replaceAll(',', '.'));

  void _save() {
    final k = _n(_kcal), p = _n(_p), c = _n(_c), f = _n(_f);
    if (k == null || k <= 0 || k > 3000 || p == null || c == null || f == null || [p, c, f].any((v) => v < 0 || v > 300)) {
      setState(() => _error = 'Enter calories (1-3000) and macros (0-300 g) for one serving.');
      return;
    }
    Navigator.pop(context, widget.dish.copyWith(calories: k, protein: p, carbs: c, fats: f, source: DishSource.manual, confidence: 1));
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, String suffix) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: TextField(
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _dec(label: label, suffix: suffix),
            ),
          ),
        );
    return AlertDialog(
      title: Text(widget.dish.name),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Nutrition for ONE serving', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        Row(children: [field(_kcal, 'Calories', 'kcal'), field(_p, 'Protein', 'g')]),
        Row(children: [field(_c, 'Carbs', 'g'), field(_f, 'Fat', 'g')]),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
