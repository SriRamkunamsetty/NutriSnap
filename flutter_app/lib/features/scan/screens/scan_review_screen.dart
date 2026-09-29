import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/ai/ai_models.dart';
import '../../../core/constants/app_routes.dart';
import '../../../core/models/meal_item.dart';
import '../../../core/models/scan_result.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/image_store.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/meal_item_editor.dart';

/// What to review: a fresh AI result, or a saved meal being edited.
class ScanReviewArgs {
  const ScanReviewArgs.newMeal({required MealAnalysisResult this.analysis, required Uint8List this.imageBytes})
      : existing = null;
  const ScanReviewArgs.edit(ScanResult meal)
      : existing = meal,
        analysis = null,
        imageBytes = null;

  final MealAnalysisResult? analysis;
  final Uint8List? imageBytes;
  final ScanResult? existing;
}

/// Pop result asking the caller to open the camera/gallery again.
const String kRetakeResult = 'retake';

/// Lets the user check, correct and confirm a meal before it is saved.
/// Nothing reaches the database until "Confirm & Log" (or "Save changes").
class ScanReviewScreen extends ConsumerStatefulWidget {
  const ScanReviewScreen({super.key, required this.args});
  final ScanReviewArgs args;

  @override
  ConsumerState<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends ConsumerState<ScanReviewScreen> {
  late List<MealItem> _items;
  late List<MealItem> _original;
  MealAnalysisResult? _analysis;
  bool _portionMode = false;
  bool _busy = false;
  final Map<String, double> _baseWeight = {};

  bool get _isNew => widget.args.existing == null;
  Uint8List? get _bytes => widget.args.imageBytes;
  bool _rescanned = false;
  bool get _isEdited => _rescanned || !listEquals(_items, _original);

  @override
  void initState() {
    super.initState();
    _analysis = widget.args.analysis;
    _items = List.of(_analysis?.detectedItems ?? widget.args.existing!.items);
    _original = List.of(_items);
    _rememberBases();
  }

  void _rememberBases() {
    for (final i in _items) {
      _baseWeight.putIfAbsent(i.id, () => i.estimatedWeight > 0 ? i.estimatedWeight : 1);
    }
  }

  // ---------------------------------------------------------------------------
  // Editing
  // ---------------------------------------------------------------------------

  void _setItem(MealItem updated) {
    setState(() {
      _items = [for (final i in _items) i.id == updated.id ? updated : i];
    });
  }

  void _step(MealItem item, int direction) {
    HapticFeedback.selectionClick();
    final step = _stepFor(item.servingUnit);
    final next = (item.estimatedWeight + direction * step).clamp(step, 5000.0);
    _setItem(item.withWeight(next));
  }

  static double _stepFor(String unit) => switch (unit) {
        ServingUnit.gram => 10,
        ServingUnit.millilitre => 25,
        _ => 0.5,
      };

  Future<void> _edit(MealItem item) async {
    final updated = await showMealItemEditor(context, item: item);
    if (updated != null && mounted) {
      _setItem(updated);
      _baseWeight[updated.id] = updated.estimatedWeight > 0 ? updated.estimatedWeight : 1;
    }
  }

  Future<void> _add() async {
    final item = await showMealItemEditor(context);
    if (item != null && mounted) {
      setState(() => _items = [..._items, item]);
      _rememberBases();
    }
  }

  Future<void> _remove(MealItem item) async {
    HapticFeedback.mediumImpact();
    final index = _items.indexOf(item);
    setState(() => _items = _items.where((i) => i.id != item.id).toList());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: _snackMargin,
        content: Text('Removed ${item.name}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => setState(() {
            final copy = [..._items];
            copy.insert(index.clamp(0, copy.length), item);
            _items = copy;
          }),
        ),
      ));
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<bool> _confirmDiscard(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _cancel() async {
    if (_isEdited || _isNew) {
      final discard = await _confirmDiscard(
        _isNew ? 'Discard this meal?' : 'Discard changes?',
        _isNew ? 'It has not been logged yet.' : 'Your edits will be lost.',
        'Discard',
      );
      if (!discard || !mounted) return;
    }
    context.pop();
  }

  Future<void> _retake() async {
    if (_isEdited) {
      final ok = await _confirmDiscard('Retake photo?', 'Your edits to this result will be lost.', 'Retake');
      if (!ok || !mounted) return;
    }
    context.pop(kRetakeResult);
  }

  /// The photo to analyse: the fresh capture, or the saved photo of a meal
  /// that is being edited.
  Future<Uint8List?> _photoBytes() async {
    final fresh = _bytes;
    if (fresh != null) return fresh;
    final path = widget.args.existing?.imageUrl;
    if (path == null) return null;
    final f = File(path);
    return await f.exists() ? f.readAsBytes() : null;
  }

  bool get _canRescan =>
      _isNew || (widget.args.existing?.imageUrl != null && File(widget.args.existing!.imageUrl!).existsSync());

  Future<void> _rescan() async {
    if (_busy) return;
    final bytes = await _photoBytes();
    if (bytes == null) {
      if (mounted) _snack('The photo for this meal is no longer on this phone.');
      return;
    }
    if (_isEdited) {
      final ok = await _confirmDiscard('Analyse again?', 'Your edits to this result will be replaced.', 'Analyse again');
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final fresh = await ref.read(nutritionAiProvider).analyzeMeal(bytes);
      if (!mounted) return;
      setState(() {
        _analysis = fresh;
        _items = List.of(fresh.detectedItems);
        _original = List.of(_items);
        _baseWeight.clear();
        _rememberBases();
        _portionMode = false;
        _rescanned = !_isNew;
      });
    } on AiException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_busy) return;
    if (_items.isEmpty) {
      _snack('Add at least one food to log this meal.');
      return;
    }
    final t = MealTotals.of(_items);
    if (t.calories == 0 && _items.every((i) => i.protein + i.carbs + i.fats == 0)) {
      _snack('This meal has no nutrition yet. Edit a food to add calories.');
      return;
    }

    // Never silently save an uncertain AI result.
    final a = _analysis;
    if (_isNew && a != null && _uncertain(a) && !_isEdited) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(LucideIcons.triangleAlert, color: Colors.orange.shade600),
          title: const Text('The AI wasn\'t sure'),
          content: const Text(
              'Some of these estimates are low-confidence. Check the portions and '
              'names first, or log it as it is.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Review')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log anyway')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final repo = ref.read(scanRepositoryProvider);
      final ScanResult saved;
      if (_isNew) {
        final images = ref.read(imageStoreProvider);
        final rel = await images.saveBytes(_bytes!, ImageKind.scan);
        final scan = a!.toScan(
          items: _items,
          imagePath: images.absolutePath(rel),
          status: _isEdited ? AnalysisStatus.edited : AnalysisStatus.confirmed,
        );
        saved = await repo.add(scan);
      } else {
        final old = widget.args.existing!;
        saved = await repo.update(old.copyWith(
          items: _items,
          foodName: MealAnalysisResult.titleOf(_items),
          details: _items.map((i) => i.name).join(', '),
          analysisStatus: old.analysisStatus == AnalysisStatus.manual
              ? AnalysisStatus.manual
              : AnalysisStatus.edited,
        ));
      }
      // Teach the Food Twin what was corrected (local only).
      await ref.read(foodTwinServiceProvider).recordMeal(saved);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      if (_isNew) {
        context.pushReplacement('${AppRoutes.result}/${saved.id}', extra: saved);
      } else {
        context.pop();
      }
    } catch (e) {
      debugPrint('[ScanReview] save failed: $e');
      if (mounted) {
        setState(() => _busy = false);
        _snack('Could not save this meal. Please try again.');
      }
    }
  }

  bool _uncertain(MealAnalysisResult a) =>
      a.needsReview || _items.any((i) => i.confidence < 0.5);

  void _snack(String msg) => ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, margin: _snackMargin, content: Text(msg)));

  /// Keeps snackbars above the action bar so they never cover its buttons.
  static const EdgeInsets _snackMargin = EdgeInsets.fromLTRB(20, 0, 20, 176);

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final a = _analysis;

    // The model said this isn't food: nothing to log.
    if (_isNew && a != null && !a.isFood) return _notFood(a);

    final totals = MealTotals.of(_items);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: AppColors.background.withValues(alpha: 0.92),
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    tooltip: 'Cancel',
                    icon: const Icon(LucideIcons.x),
                    onPressed: _busy ? null : _cancel,
                  ),
                  centerTitle: true,
                  title: Text(_isNew ? 'Review meal' : 'Edit meal',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 200),
                  sliver: SliverList.list(
                    children: [
                      _hero(a),
                      const SizedBox(height: 16),
                      if (_isNew && a != null) _confidenceBanner(a),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _isNew ? 'Detected foods' : 'Foods',
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                            ),
                          ),
                          Text('${_items.length} item${_items.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textTertiary)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_items.isEmpty) _emptyItems(),
                      for (var i = 0; i < _items.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ItemCard(
                            key: ValueKey(_items[i].id),
                            item: _items[i],
                            portionMode: _portionMode,
                            baseWeight: _baseWeight[_items[i].id] ?? _items[i].estimatedWeight,
                            onStep: (d) => _step(_items[i], d),
                            onSlide: (w) => _setItem(_items[i].withWeight(w)),
                            onEdit: () => _edit(_items[i]),
                            onRemove: () => _remove(_items[i]),
                          ).animate().fadeIn(duration: 250.ms, delay: (40 * i).ms).slideY(begin: 0.06, end: 0),
                        ),
                      const SizedBox(height: 4),
                      _totalsCard(totals),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: _actionBar()),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.25),
                  child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _hero(MealAnalysisResult? a) {
    final bytes = _bytes;
    final path = widget.args.existing?.imageUrl;
    final hasImage = bytes != null || (path != null && File(path).existsSync());
    return Container(
      height: hasImage ? 230 : 0,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: !hasImage
          ? null
          : Stack(
              fit: StackFit.expand,
              children: [
                bytes != null ? Image.memory(bytes, fit: BoxFit.cover) : Image.file(File(path!), fit: BoxFit.cover),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x99000000)],
                    ),
                  ),
                ),
                if (a != null)
                  Positioned(
                    left: 16,
                    bottom: 14,
                    child: _glassChip(LucideIcons.cpu, 'On-device · ${a.modelVersion ?? 'Gemma'}'),
                  ),
                if (_canRescan)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Row(
                      children: [
                        _roundButton(LucideIcons.refreshCw, 'Analyse again', _rescan),
                        if (_isNew) ...[
                          const SizedBox(width: 8),
                          _roundButton(LucideIcons.camera, 'Retake photo', _retake),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _glassChip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _roundButton(IconData icon, String label, VoidCallback onTap) => Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: Colors.black.withValues(alpha: 0.4),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _busy ? null : onTap,
            child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 18, color: Colors.white)),
          ),
        ),
      ));

  Widget _confidenceBanner(MealAnalysisResult a) {
    final pct = (a.confidence * 100).round();
    final uncertain = _uncertain(a);
    final color = uncertain ? Colors.orange : Colors.green;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(uncertain ? LucideIcons.triangleAlert : LucideIcons.circleCheck, color: color.shade700, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  uncertain ? 'Please check this result' : 'Looks good',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: color.shade900),
                ),
                const SizedBox(height: 3),
                Text(
                  uncertain
                      ? 'The AI is $pct% sure. These are estimates from a photo; adjust anything that looks off.'
                      : 'The AI is $pct% sure. Portions are estimates, so adjust them if you know better.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: color.shade800),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _emptyItems() => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.border),
        ),
        child: const Column(
          children: [
            Icon(LucideIcons.utensils, size: 32, color: AppColors.textTertiary),
            SizedBox(height: 12),
            Text('No foods in this meal',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary)),
            SizedBox(height: 4),
            Text('Add what you ate to log it.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      );

  Widget _totalsCard(MealTotals t) {
    return Semantics(
      container: true,
      label: 'Meal total: ${t.calories} calories, ${t.protein} grams protein, '
          '${t.carbs} grams carbohydrates, ${t.fats} grams fat',
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TOTAL NUTRITION',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textTertiary, letterSpacing: 1)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text('${t.calories}',
                      key: ValueKey(t.calories),
                      style: const TextStyle(
                          fontSize: 48, fontWeight: FontWeight.w900, letterSpacing: -1.5, color: AppColors.textPrimary)),
                ),
                const SizedBox(width: 6),
                const Text('kcal',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textTertiary)),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _macro('Protein', t.protein, Colors.blue),
                _macro('Carbs', t.carbs, Colors.orange),
                _macro('Fat', t.fats, Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _macro(String label, int grams, MaterialColor color) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color.shade500, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('$grams g',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ],
        ),
      );

  Widget _actionBar() {
    return ClipRect(
      child: BackdropFilterBar(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _secondary(
                        _portionMode ? LucideIcons.check : LucideIcons.slidersHorizontal,
                        _portionMode ? 'Done' : 'Edit portions',
                        _items.isEmpty ? null : () => setState(() => _portionMode = !_portionMode),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _secondary(LucideIcons.plus, 'Add item', _add)),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text(_isNew ? 'Confirm & Log' : 'Save changes',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _secondary(IconData icon, String label, VoidCallback? onTap) => SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : onTap,
          icon: Icon(icon, size: 17),
          label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppColors.borderDark),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      );

  Widget _notFood(MealAnalysisResult a) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(LucideIcons.x), onPressed: () => context.pop()),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.scanSearch, size: 56, color: AppColors.textTertiary),
              const SizedBox(height: 20),
              const Text("That doesn't look like food",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text(
                a.description.isNotEmpty
                    ? a.description
                    : 'Try a clear photo of your meal from above, in good light.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () => context.pop(kRetakeResult),
                  icon: const Icon(LucideIcons.camera, size: 18),
                  label: const Text('Try another photo', style: TextStyle(fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A frosted bar that keeps its content readable over scrolling cards.
class BackdropFilterBar extends StatelessWidget {
  const BackdropFilterBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.94),
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: child,
    );
  }
}

// -----------------------------------------------------------------------------

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    super.key,
    required this.item,
    required this.portionMode,
    required this.baseWeight,
    required this.onStep,
    required this.onSlide,
    required this.onEdit,
    required this.onRemove,
  });

  final MealItem item;
  final bool portionMode;
  final double baseWeight;
  final ValueChanged<int> onStep;
  final ValueChanged<double> onSlide;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  static String _amount(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final low = item.confidence < 0.5;
    final sliderMax = (baseWeight * 3).clamp(10.0, 5000.0);
    final sliderMin = (baseWeight * 0.25).clamp(1.0, sliderMax - 1);

    return Semantics(
      container: true,
      label: '${item.name}, ${_amount(item.estimatedWeight)} ${item.servingUnit}, '
          '${item.calories.round()} calories${low ? ', low confidence' : ''}',
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: low ? Colors.orange.shade200 : AppColors.border),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onEdit,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              _tag(item.category, AppColors.textSecondary, AppColors.surfaceMuted),
                              if (low) _tag('Low confidence', Colors.orange.shade800, Colors.orange.shade50),
                              if (item.wasCorrected) _tag('Edited', Colors.blue.shade700, Colors.blue.shade50),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit ${item.name}',
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: const Icon(LucideIcons.pencil, size: 18, color: AppColors.textSecondary),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: 'Remove ${item.name}',
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: Icon(LucideIcons.trash2, size: 18, color: Colors.red.shade400),
                  onPressed: onRemove,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _stepper(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${item.calories.round()} kcal',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Protein ${_amount(item.protein)} g  ·  Carbs ${_amount(item.carbs)} g  ·  Fat ${_amount(item.fats)} g',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: portionMode
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Semantics(
                        label: 'Portion of ${item.name}',
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppColors.primary,
                            thumbColor: AppColors.primary,
                            inactiveTrackColor: AppColors.border,
                          ),
                          child: Slider(
                            value: item.estimatedWeight.clamp(sliderMin, sliderMax),
                            min: sliderMin,
                            max: sliderMax,
                            onChanged: (v) => onSlide(
                              item.servingUnit == ServingUnit.gram || item.servingUnit == ServingUnit.millilitre
                                  ? v.roundToDouble()
                                  : (v * 2).round() / 2,
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String text, Color fg, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
      );

  Widget _stepper() => Container(
        decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(16)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _stepButton(LucideIcons.minus, 'Decrease amount of ${item.name}', () => onStep(-1)),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 64),
              child: Text(
                '${_amount(item.estimatedWeight)} ${item.servingUnit}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ),
            _stepButton(LucideIcons.plus, 'Increase amount of ${item.name}', () => onStep(1)),
          ],
        ),
      );

  Widget _stepButton(IconData icon, String label, VoidCallback onTap) => Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 18, color: AppColors.textPrimary)),
          ),
        ),
      );
}
