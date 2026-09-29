import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/models/food.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ios_kit.dart';
import '../widgets/food_sheets.dart';

/// Search the built-in Indian/regional food library and your own foods.
/// Works entirely offline.
class FoodLibraryScreen extends ConsumerStatefulWidget {
  const FoodLibraryScreen({super.key});

  @override
  ConsumerState<FoodLibraryScreen> createState() => _FoodLibraryScreenState();
}

class _FoodLibraryScreenState extends ConsumerState<FoodLibraryScreen> {
  static const _filters = [
    'Indian', 'South Indian', 'Andhra', 'Telangana', 'North Indian', 'Home Food', 'Hostel', 'Snacks',
    'Breakfast', 'Lunch', 'Dinner',
  ];
  static const _pageSize = 40;

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _selected = <String>{};
  Timer? _debounce;

  List<Food> _results = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _error = false;
  int _generation = 0; // discards answers to outdated searches
  int _total = 0;

  bool get _browsing => _controller.text.trim().isEmpty && _selected.isEmpty;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final repo = ref.read(foodRepositoryProvider);
      final rows = await repo.search(_controller.text, tags: _selected, limit: _pageSize);
      final total = await repo.count();
      if (!mounted || gen != _generation) return;
      setState(() {
        _results = rows;
        _hasMore = rows.length == _pageSize;
        _total = total;
        _loading = false;
      });
    } catch (_) {
      if (mounted && gen == _generation) setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final rows = await ref.read(foodRepositoryProvider).search(
            _controller.text,
            tags: _selected,
            limit: _pageSize,
            offset: _results.length,
          );
      if (!mounted || gen != _generation) return;
      setState(() {
        _results = [..._results, ...rows];
        _hasMore = rows.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _search);
    setState(() {});
  }

  Future<void> _log(Food food) async {
    final saved = await showLogFoodSheet(context, food);
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Logged ${food.name} · ${saved.calories} kcal'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => ref.read(scanRepositoryProvider).delete(saved.id),
        ),
      ));
    _search(); // usage order changed
  }

  Future<void> _edit(Food food) async {
    final saved = await showFoodEditorSheet(context, food: food);
    if (saved != null && mounted) _search();
  }

  Future<void> _addNew() async {
    final saved = await showFoodEditorSheet(context, initialName: _controller.text.trim());
    if (saved != null && mounted) _search();
  }

  @override
  Widget build(BuildContext context) {
    final custom = ref.watch(customFoodsProvider).valueOrNull ?? const <Food>[];
    final recent = ref.watch(recentFoodsProvider).valueOrNull ?? const <Food>[];
    final frequent = ref.watch(frequentFoodsProvider).valueOrNull ?? const <Food>[];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverList.list(children: [
                Row(children: [
                  RoundIconButton(icon: LucideIcons.chevronLeft, tooltip: 'Back', onTap: () => context.pop()),
                ]),
                const SizedBox(height: 14),
                LargeTitle(
                  title: 'Food Library',
                  subtitle: _total == 0 ? 'Works offline' : '$_total foods · works offline',
                  actions: [RoundIconButton(icon: LucideIcons.plus, tooltip: 'Add your own food', onTap: _addNew)],
                ),
                const SizedBox(height: 16),
                _searchField(),
                const SizedBox(height: 12),
                _filterChips(),
                const SizedBox(height: 16),
              ]),
            ),
            if (_browsing && !_loading) ...[
              _horizontalSection('Recent', recent),
              _horizontalSection('Frequently used', frequent),
              _horizontalSection('Your foods', custom, emptyHint: 'Foods you create appear here.'),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
                sliver: SliverToBoxAdapter(child: SectionTitle('All foods')),
              ),
            ],
            _resultsSliver(),
            const SliverToBoxAdapter(child: SizedBox(height: 60)),
          ],
        ),
      ),
    );
  }

  Widget _searchField() => TextField(
        controller: _controller,
        onChanged: _onQueryChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search foods, e.g. pappu, biryani, idli',
          prefixIcon: const Icon(LucideIcons.search, size: 20),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(LucideIcons.x, size: 18),
                  onPressed: () {
                    _controller.clear();
                    _onQueryChanged('');
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: AppColors.border)),
        ),
      );

  Widget _filterChips() => SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _filters.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final f = _filters[i];
            final on = _selected.contains(f);
            return FilterChip(
              label: Text(f),
              selected: on,
              showCheckmark: false,
              avatar: on ? const Icon(LucideIcons.check, size: 14) : null,
              onSelected: (v) {
                HapticFeedback.selectionClick();
                setState(() => v ? _selected.add(f) : _selected.remove(f));
                _search();
              },
              selectedColor: Colors.green.shade100,
              backgroundColor: Colors.white,
              side: BorderSide(color: on ? Colors.green.shade300 : AppColors.border),
              labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: on ? Colors.green.shade900 : AppColors.textPrimary),
            );
          },
        ),
      );

  SliverToBoxAdapter _horizontalSection(String title, List<Food> foods, {String? emptyHint}) {
    if (foods.isEmpty && emptyHint == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 0), child: SectionTitle(title)),
          if (foods.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(emptyHint!, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
            )
          else
            SizedBox(
              height: 142,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                scrollDirection: Axis.horizontal,
                itemCount: foods.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _MiniFoodCard(food: foods[i], onLog: () => _log(foods[i]), onTap: () => showFoodDetailsSheet(context, foods[i])),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _resultsSliver() {
    if (_loading && _results.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator(color: AppColors.primary))),
      );
    }
    if (_error) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: IosCard(
            child: EmptyPanel(
              icon: LucideIcons.circleAlert,
              title: 'Couldn\'t load foods',
              message: 'Something went wrong reading the food library.',
              action: TextButton(onPressed: _search, child: const Text('Retry')),
            ),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: IosCard(
            child: EmptyPanel(
              icon: LucideIcons.searchX,
              title: 'No foods found',
              message: _controller.text.trim().isEmpty
                  ? 'No foods match these filters.'
                  : 'Nothing matches "${_controller.text.trim()}". Add it as your own food so it\'s always here.',
              action: OutlinedButton.icon(
                onPressed: _addNew,
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add a food'),
              ),
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.separated(
        itemCount: _results.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (i >= _results.length) {
            return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
          }
          final f = _results[i];
          return _FoodCard(
            food: f,
            onLog: () => _log(f),
            onEdit: () => _edit(f),
            onDetails: () => showFoodDetailsSheet(context, f),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _FoodCard extends StatelessWidget {
  const _FoodCard({required this.food, required this.onLog, required this.onEdit, required this.onDetails});
  final Food food;
  final VoidCallback onLog;
  final VoidCallback onEdit;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return IosCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
      semanticLabel:
          '${food.name}, ${food.serving}, ${food.calories.round()} calories, ${fmtNum(food.protein)} grams protein',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(food.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  ),
                  if (food.isCustom) ...[
                    const SizedBox(width: 8),
                    const SourceChip('Yours'),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(food.serving, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${food.calories.round()}',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
              const Text('kcal', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textTertiary)),
            ]),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 14, children: [
            _m('Protein', food.protein, Colors.blue),
            _m('Carbs', food.carbs, Colors.orange),
            _m('Fat', food.fats, Colors.purple),
          ]),
          const SizedBox(height: 6),
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
            FilledButton.icon(
              onPressed: onLog,
              icon: const Icon(LucideIcons.plus, size: 16),
              label: const Text('Log'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            TextButton(onPressed: onEdit, style: TextButton.styleFrom(minimumSize: const Size(0, 44)), child: Text(food.isCustom ? 'Edit' : 'Customize')),
            TextButton(onPressed: onDetails, style: TextButton.styleFrom(minimumSize: const Size(0, 44)), child: const Text('Details')),
          ]),
        ],
      ),
    );
  }

  Widget _m(String label, double v, MaterialColor c) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: c.shade400, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$label ${fmtNum(v)} g',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      ]);
}

class _MiniFoodCard extends StatelessWidget {
  const _MiniFoodCard({required this.food, required this.onLog, required this.onTap});
  final Food food;
  final VoidCallback onLog;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: IosCard(
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(food.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            Text(food.serving, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const Spacer(),
            Row(children: [
              Expanded(
                child: Text('${food.calories.round()} kcal',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              ),
              IconButton(
                tooltip: 'Log ${food.name}',
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: onLog,
                icon: Icon(LucideIcons.circlePlus, color: Colors.green.shade600),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
