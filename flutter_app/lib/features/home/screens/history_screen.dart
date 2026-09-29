import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import '../../../core/models/activity.dart';
import '../../../core/models/scan_result.dart';
import '../../../core/widgets/ios_kit.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/scan_image.dart';
import '../../../core/providers/app_providers.dart';

/// Breakfast / lunch / snack / dinner by the time the meal was logged.
String mealPeriodOf(DateTime t) {
  if (t.hour < 11) return 'breakfast';
  if (t.hour < 15) return 'lunch';
  if (t.hour < 18) return 'snack';
  return 'dinner';
}

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String _searchQuery = '';
  bool _showFilters = false;
  String? _startDate;
  String? _endDate;
  String _selectedType = 'all';
  String _period = 'all';
  String _mode = 'meals';
  int _visible = _pageSize;
  Timer? _debounceTimer;

  static const int _pageSize = 30;

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() {
          _searchQuery = query.trim();
          _visible = _pageSize;
        });
      }
    });
  }

  void _onTypeSelected(String type) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedType = type;
      _visible = _pageSize;
    });
  }

  void _clearFilters() {
    HapticFeedback.lightImpact();
    setState(() {
      _startDate = null;
      _endDate = null;
      _selectedType = 'all';
      _period = 'all';
      _visible = _pageSize;
    });
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    HapticFeedback.lightImpact();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(primary: Colors.green.shade600),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formattedDate = DateFormat('yyyy-MM-dd').format(picked);
      setState(() {
        if (isStart) {
          _startDate = formattedDate;
        } else {
          _endDate = formattedDate;
        }
        _visible = _pageSize;
      });
    }
  }

  List<ScanResult> _getFilteredScans(List<ScanResult> scans) {
    return scans.where((item) {
      final q = _searchQuery.toLowerCase();
      final matchesSearch = q.isEmpty ||
          item.foodName.toLowerCase().contains(q) ||
          item.items.any((i) => i.name.toLowerCase().contains(q));
      final matchesType = (_selectedType == 'all' || item.type == _selectedType) && _matchesPeriod(item);

      if (_startDate == null && _endDate == null) return matchesSearch && matchesType;

      try {
        final itemDate = DateTime.parse(item.timestamp);
        final start = _startDate != null ? DateTime.parse(_startDate!) : DateTime(2000);
        final end = _endDate != null ? DateTime.parse(_endDate!).add(const Duration(days: 1)) : DateTime.now().add(const Duration(days: 1));

        final matchesDate = itemDate.isAfter(start) && itemDate.isBefore(end);
        return matchesSearch && matchesDate && matchesType;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  bool _matchesPeriod(ScanResult item) {
    if (_period == 'all') return true;
    final t = DateTime.tryParse(item.timestamp);
    return t != null && item.isFood && mealPeriodOf(t) == _period;
  }

  Map<String, List<ScanResult>> _groupScans(List<ScanResult> filteredScans) {
    final Map<String, List<ScanResult>> grouped = {};
    for (var item in filteredScans) {
      try {
        final date = DateFormat('MMMM d, yyyy').format(DateTime.parse(item.timestamp));
        if (!grouped.containsKey(date)) {
          grouped[date] = [];
        }
        grouped[date]!.add(item);
      } catch (_) {}
    }
    return grouped;
  }

  Widget _modeSwitch() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Segmented<String>(
          value: _mode,
          options: const {'meals': 'Meals', 'activity': 'Workouts'},
          onChanged: (v) => setState(() => _mode = v),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_mode == 'activity') {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(child: Column(children: [_modeSwitch(), const Expanded(child: _WorkoutHistory())])),
      );
    }
    final scansAsync = ref.watch(scanHistoryStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: scansAsync.when(
          data: (scans) {
            final allFiltered = _getFilteredScans(scans);
            final filteredScans = allFiltered.take(_visible).toList();
            final hasMore = allFiltered.length > filteredScans.length;
            final groupedHistory = _groupScans(filteredScans);

            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _modeSwitch()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    child: Column(
                      children: [
                        // Search & Filters Bar
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(LucideIcons.search, color: AppColors.textTertiary, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: _searchController,
                                        onChanged: _onSearchChanged,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          hintText: 'Search meals...',
                                          hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildFilterButton(LucideIcons.calendar, _startDate != null, () => _selectDate(context, true), 'Start date'),
                            const SizedBox(width: 8),
                            _buildFilterButton(LucideIcons.calendar, _endDate != null, () => _selectDate(context, false), 'End date'),
                            const SizedBox(width: 8),
                            _buildFilterButton(LucideIcons.filter, _showFilters, () {
                              HapticFeedback.lightImpact();
                              setState(() => _showFilters = !_showFilters);
                            }, 'Filters'),
                          ],
                        ),
                        
                        // Filters Dropdown
                        if (_showFilters) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: AppColors.border)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(LucideIcons.filter, size: 16, color: Colors.green.shade600),
                                        const SizedBox(width: 8),
                                        const Text('ADVANCED FILTERS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.5)),
                                      ],
                                    ),
                                    if (_startDate != null || _endDate != null || _selectedType != 'all' || _period != 'all')
                                      InkWell(
                                        onTap: _clearFilters,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.red.shade100)),
                                          child: Row(
                                            children: [
                                              Text('Clear All', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.red.shade500, letterSpacing: 1.0)),
                                              const SizedBox(width: 4),
                                              Icon(LucideIcons.x, size: 12, color: Colors.red.shade500),
                                            ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                const Text('SCAN TYPE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.5)),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8, runSpacing: 8,
                                  children: ['all', 'food', 'person', 'animal', 'other'].map((type) => InkWell(
                                    onTap: () => _onTypeSelected(type),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: _selectedType == type ? Colors.green.shade600 : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: _selectedType == type ? Colors.green.shade600 : AppColors.border),
                                        boxShadow: _selectedType == type ? [BoxShadow(color: Colors.green.shade600.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
                                      ),
                                      child: Text(type.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _selectedType == type ? Colors.white : AppColors.textTertiary, letterSpacing: 1.0)),
                                    ),
                                  )).toList(),
                                ),
                                const SizedBox(height: 24),
                                const Text('MEAL TIME', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.5)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: ['all', 'breakfast', 'lunch', 'snack', 'dinner'].map((p) => Semantics(
                    button: true,
                    selected: _period == p,
                    label: p == 'all' ? 'All meal times' : p,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _period = p;
                          _visible = _pageSize;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _period == p ? Colors.green.shade600 : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _period == p ? Colors.green.shade600 : AppColors.border),
                        ),
                        child: Text(p.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _period == p ? Colors.white : AppColors.textTertiary, letterSpacing: 1.0)),
                      ),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 24),
                const Text('QUICK DATE RANGE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.5)),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8, runSpacing: 8,
                                  children: [
                                    _buildQuickDate('Today', () => DateFormat('yyyy-MM-dd').format(DateTime.now())),
                                    _buildQuickDate('Last 7 Days', () => DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 7)))),
                                    _buildQuickDate('This Month', () => DateFormat('yyyy-MM-dd').format(DateTime(DateTime.now().year, DateTime.now().month, 1))),
                                  ]
                                ),
                                const SizedBox(height: 16),
                                Text('Showing results from ${_startDate ?? 'the beginning'} to ${_endDate ?? 'today'}.', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          )
                        ],
                      ],
                    ),
                  ),
                ),
                
                // History List
                if (groupedHistory.isEmpty)
                   SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 80, height: 80, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border)), child: const Icon(LucideIcons.apple, size: 40, color: AppColors.textTertiary)),
                          const SizedBox(height: 24),
                          Text(scans.isEmpty ? 'No meals yet' : 'Nothing matches', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          const SizedBox(height: 8),
                          Text(scans.isEmpty ? 'Scan or log a meal to start your history.' : 'Try a different search or clear the filters.',
                              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                          if (scans.isNotEmpty && (_searchQuery.isNotEmpty || _startDate != null || _endDate != null || _selectedType != 'all' || _period != 'all')) ...[
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                                _clearFilters();
                              },
                              child: const Text('Clear search and filters'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else ...groupedHistory.entries.map((entry) {
                  return SliverMainAxisGroup(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                          child: Text(entry.key.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 2.0)),
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final item = entry.value[index];
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  context.push('/result/${item.id}');
                                },
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border)),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 64, height: 64,
                                        decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(16)),
                                        clipBehavior: Clip.hardEdge,
                                        child: ScanImage(path: item.imageUrl, cacheWidth: 200),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item.foodName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            if (item.items.length > 1) ...[
                                              const SizedBox(height: 2),
                                              Text(item.itemsSummary, maxLines: 1, overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                            ],
                                            if (item.isFood) ...[
                                              const SizedBox(height: 2),
                                              Text('${item.calories} kcal',
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                                            ],
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                if (item.type == 'food')
                                                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade100)), child: Text('${item.calories} kcal', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade600)))
                                                else
                                                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade100)), child: Text('${item.type?.toUpperCase() ?? "OTHER"}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade600, letterSpacing: 1.0))),
                                                const SizedBox(width: 8),
                                                Text(_formatTime(item.timestamp), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 1.0)),
                                              ],
                                            )
                                          ],
                                        ),
                                      ),
                                      Container(
                                        width: 40, height: 40,
                                        decoration: const BoxDecoration(color: AppColors.surfaceMuted, shape: BoxShape.circle),
                                        child: const Icon(LucideIcons.chevronRight, size: 20, color: AppColors.textTertiary),
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: entry.value.length,
                        ),
                      ),
                    ],
                  );
                }),
                if (hasMore)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                      child: OutlinedButton(
                        onPressed: () => setState(() => _visible += _pageSize),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        child: Text('Show more (${allFiltered.length - filteredScans.length} older)'),
                      ),
                    ),
                  ),
                if (!hasMore && groupedHistory.isNotEmpty) const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.green)),
          error: (err, stack) => Center(child: Text('Could not load your history.')),
        ),
      ),
    );
  }

  Widget _buildFilterButton(IconData icon, bool isActive, VoidCallback onTap, String label) {
    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: isActive ? Colors.green.shade600 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? Colors.green.shade600 : AppColors.border),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 18, color: isActive ? Colors.white : AppColors.textTertiary),
            if (isActive)
              Positioned(
                top: 8, right: 8,
                child: Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.red.shade500, shape: BoxShape.circle, border: Border.all(color: Colors.green.shade600, width: 2))),
              )
          ],
        ),
      ),
    ));
  }

  Widget _buildQuickDate(String label, String Function() getStart) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _startDate = getStart();
          _endDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
          _visible = _pageSize;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
      ),
    );
  }

  String _formatTime(String isoString) {
    try {
      final date = DateTime.parse(isoString);
      return DateFormat('h:mm a').format(date);
    } catch (_) {
      return '';
    }
  }
}

/// Every recorded workout, grouped by day. Only real workouts are listed.
class _WorkoutHistory extends ConsumerStatefulWidget {
  const _WorkoutHistory();

  @override
  ConsumerState<_WorkoutHistory> createState() => _WorkoutHistoryState();
}

class _WorkoutHistoryState extends ConsumerState<_WorkoutHistory> {
  int _visible = 30;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allWorkoutsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Colors.green)),
      error: (_, __) => const Center(child: Text('Could not load your workouts.')),
      data: (all) {
        if (all.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: EmptyPanel(
              icon: LucideIcons.dumbbell,
              title: 'No workouts yet',
              message: 'Workouts from Health Connect or ones you add in the Activity tab appear here.',
            ),
          );
        }
        final shown = all.take(_visible).toList();
        final rows = <Widget>[];
        String? lastDay;
        for (final w in shown) {
          final day = DateFormat('MMMM d, yyyy').format(w.start);
          if (day != lastDay) {
            rows.add(Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
              child: Text(day.toUpperCase(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 2.0)),
            ));
            lastDay = day;
          }
          final mins = w.end.difference(w.start).inMinutes;
          final parts = <String>[
            '$mins min',
            if ((w.distanceMeters ?? 0) > 0) '${(w.distanceMeters! / 1000).toStringAsFixed(2)} km',
            if ((w.calories ?? 0) > 0) '${w.calories!.round()} kcal${w.caloriesEstimated ? ' (est.)' : ''}',
            if (w.avgHeartRate != null) '${w.avgHeartRate} bpm',
          ];
          rows.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: IosCard(
              semanticLabel: '${ActivityType.label(w.type)} at ${DateFormat('h:mm a').format(w.start)}, ${parts.join(', ')}',
              child: ExcludeSemantics(
                child: Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(14)),
                    child: Icon(LucideIcons.dumbbell, size: 20, color: Colors.purple.shade600),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${ActivityType.label(w.type)} · ${DateFormat('h:mm a').format(w.start)}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                      Text(parts.join('  ·  '), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ]),
                  ),
                  SourceChip(DataSource.label(w.source)),
                ]),
              ),
            ),
          ));
        }
        if (all.length > shown.length) {
          rows.add(OutlinedButton(
            onPressed: () => setState(() => _visible += 30),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text('Show more (${all.length - shown.length} older)'),
          ));
        }
        return ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), children: rows);
      },
    );
  }
}
