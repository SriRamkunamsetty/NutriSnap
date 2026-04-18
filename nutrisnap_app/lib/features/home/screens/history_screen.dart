import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import '../../../core/models/scan_result.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/user_provider.dart';

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
  bool _isFiltering = false;
  Timer? _debounceTimer;

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _isFiltering = true;
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _isFiltering = false);
      }
    });
  }

  void _onTypeSelected(String type) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedType = type;
      _isFiltering = true;
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _isFiltering = false);
    });
  }

  void _clearFilters() {
    HapticFeedback.lightImpact();
    setState(() {
      _startDate = null;
      _endDate = null;
      _selectedType = 'all';
      _isFiltering = true;
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _isFiltering = false);
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
        _isFiltering = true;
      });

      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _isFiltering = false);
      });
    }
  }

  List<ScanResult> _getFilteredScans(List<ScanResult> scans) {
    return scans.where((item) {
      final matchesSearch = item.foodName.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesType = _selectedType == 'all' || item.type == _selectedType;

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

  @override
  Widget build(BuildContext context) {
    final scansAsync = ref.watch(scanHistoryStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: scansAsync.when(
          data: (scans) {
            final filteredScans = _getFilteredScans(scans);
            final groupedHistory = _groupScans(filteredScans);

            return CustomScrollView(
              slivers: [
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
                            _buildFilterButton(LucideIcons.calendar, _startDate != null, () => _selectDate(context, true)),
                            const SizedBox(width: 8),
                            _buildFilterButton(LucideIcons.calendar, _endDate != null, () => _selectDate(context, false)),
                            const SizedBox(width: 8),
                            _buildFilterButton(LucideIcons.filter, _showFilters, () {
                              HapticFeedback.lightImpact();
                              setState(() => _showFilters = !_showFilters);
                            }),
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
                                    if (_startDate != null || _endDate != null || _selectedType != 'all')
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
                                        boxShadow: _selectedType == type ? [BoxShadow(color: Colors.green.shade600.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
                                      ),
                                      child: Text(type.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: _selectedType == type ? Colors.white : AppColors.textTertiary, letterSpacing: 1.0)),
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
                                Text('Showing results from \${_startDate ?? 'the beginning'} to \${_endDate ?? 'today'}.', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          )
                        ],
                      ],
                    ),
                  ),
                ),
                
                // History List
                if (_isFiltering)
                  const SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.green),
                          SizedBox(height: 16),
                          Text('Analyzing History...', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      )
                    ),
                  )
                else if (groupedHistory.isEmpty)
                   SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 80, height: 80, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: AppColors.border)), child: const Icon(LucideIcons.apple, size: 40, color: AppColors.textTertiary)),
                          const SizedBox(height: 24),
                          const Text('No scans found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          const SizedBox(height: 8),
                          const Text('Start scanning your meals to build your history.', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
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
                                  context.push('/result/\${item.id}');
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
                                        child: item.imageUrl != null 
                                          ? Image.network(item.imageUrl!, fit: BoxFit.cover, errorBuilder: (c,e,s) => const Icon(LucideIcons.image, color: AppColors.textTertiary))
                                          : const Icon(LucideIcons.image, color: AppColors.textTertiary),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item.foodName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                if (item.type == 'food')
                                                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade100)), child: Text('\${item.calories} kcal', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade600)))
                                                else
                                                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade100)), child: Text('\${item.type?.toUpperCase() ?? "OTHER"}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade600, letterSpacing: 1.0))),
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
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: Colors.green)),
          error: (err, stack) => Center(child: Text('Error: \$err')),
        ),
      ),
    );
  }

  Widget _buildFilterButton(IconData icon, bool isActive, VoidCallback onTap) {
    return InkWell(
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
    );
  }

  Widget _buildQuickDate(String label, String Function() getStart) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _startDate = getStart();
          _endDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
          _isFiltering = true;
        });
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => _isFiltering = false);
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
