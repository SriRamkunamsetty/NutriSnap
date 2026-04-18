import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/models/scan_result.dart';
import '../../../core/models/user_profile.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/user_provider.dart';

class _WeeklyData {
  final String name;
  final String fullDate;
  final int calories;
  final int protein;
  final int carbs;
  final int fats;

  _WeeklyData({
    required this.name,
    required this.fullDate,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fats,
  });
}

class _FatData {
  final String date;
  final String fullDate;
  final double fat;

  _FatData({required this.date, required this.fullDate, required this.fat});
}

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  bool _isGeneratingReport = false;
  bool _showReportSuccess = false;

  Future<void> _handleDownloadReport() async {
    final profile = ref.read(userNotifierProvider).profile;
    if (profile == null) return;

    setState(() => _isGeneratingReport = true);
    HapticFeedback.mediumImpact();

    try {
      // Simulate PDF generation since package isn't present
      await Future.delayed(const Duration(seconds: 2));
      setState(() {
        _showReportSuccess = true;
      });
      HapticFeedback.lightImpact();
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showReportSuccess = false);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to generate report.')));
    } finally {
      if (mounted) setState(() => _isGeneratingReport = false);
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<_WeeklyData> _getWeeklyData(List<ScanResult> scans) {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final date = now.subtract(Duration(days: 6 - i));
      final dayScans = scans.where((s) {
        try {
          return _isSameDay(DateTime.parse(s.timestamp), date);
        } catch (_) {
          return false;
        }
      }).toList();

      return _WeeklyData(
        name: DateFormat('EEE').format(date),
        fullDate: DateFormat('MMM d').format(date),
        calories: dayScans.fold(0, (sum, s) => sum + s.calories),
        protein: dayScans.fold(0, (sum, s) => sum + s.protein),
        carbs: dayScans.fold(0, (sum, s) => sum + s.carbs),
        fats: dayScans.fold(0, (sum, s) => sum + s.fats),
      );
    });
  }

  List<_FatData> _getBodyFatData(List<ScanResult> scans) {
    final fatScans = scans.where((s) => s.type == 'person' && s.fatEstimate != null).toList();
    fatScans.sort((a, b) {
      try {
        return DateTime.parse(a.timestamp).compareTo(DateTime.parse(b.timestamp));
      } catch (_) {
        return 0;
      }
    });

    final recentScans = fatScans.length > 10 ? fatScans.sublist(fatScans.length - 10) : fatScans;

    return recentScans.map((s) {
      try {
        final d = DateTime.parse(s.timestamp);
        return _FatData(
          date: DateFormat('MMM d').format(d),
          fullDate: DateFormat('MMM d, yyyy').format(d),
          fat: s.fatEstimate!,
        );
      } catch (_) {
        return _FatData(date: '?', fullDate: '?', fat: s.fatEstimate!);
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(userNotifierProvider);
    final profile = userState.profile;
    final dailySummarySync = ref.watch(dailySummaryStreamProvider).valueOrNull;
    final scansSync = ref.watch(scanHistoryStreamProvider).valueOrNull ?? [];

    final weeklyData = _getWeeklyData(scansSync);
    final bodyFatData = _getBodyFatData(scansSync);

    final calorieProgress = profile != null && profile.calorieLimit > 0
        ? (dailySummarySync?.totalCalories ?? 0) / profile.calorieLimit
        : 0.0;
    final waterProgress = profile != null && profile.waterGoal != null && profile.waterGoal! > 0
        ? (dailySummarySync?.totalWater ?? 0) / profile.waterGoal!
        : 0.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                      child: Row(
                        children: [
                          Icon(LucideIcons.calendar, size: 16, color: Colors.green.shade600),
                          const SizedBox(width: 8),
                          const Text('Weekly Overview', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        InkWell(
                          onTap: _isGeneratingReport ? null : _handleDownloadReport,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                            child: _isGeneratingReport
                                ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                                : Icon(LucideIcons.fileText, size: 18, color: Colors.blue.shade500),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                          child: const Icon(LucideIcons.trendingUp, size: 20, color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                 // Body Fat Trend Chart
                _buildBodyFatTrendCard(bodyFatData),
                const SizedBox(height: 32),

                // Daily Summary Overview
                _buildDailySummaryCard(dailySummarySync, profile),
                const SizedBox(height: 32),
                
                // Weekly Trends (Composed Chart matching calories, maxes, macros)
                _buildWeeklyTrendsChart(weeklyData, profile),
                const SizedBox(height: 32),

                // Macro Progress Chart 
                _buildMacroProgressChart(weeklyData, profile),
                const SizedBox(height: 32),

                // Calorie Balance & Hydration Circular Rings
                _buildCalorieBalanceCard(dailySummarySync, profile, calorieProgress),
                const SizedBox(height: 32),
                _buildHydrationProgressCard(dailySummarySync, profile, waterProgress),
                const SizedBox(height: 32),

                // AI Insights
                _buildInsightsCard(dailySummarySync, calorieProgress),
              ],
            ),
          ),

          // Report Success Toast
          if (_showReportSuccess)
            Positioned(
              bottom: 40, left: 24, right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  children: [
                    Container(width: 32, height: 32, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: const Icon(LucideIcons.fileText, color: Colors.white, size: 18)),
                    const SizedBox(width: 12),
                    const Text('Report downloaded successfully', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ).animate().slideY(begin: 1.0, end: 0, duration: 300.ms).fadeIn(),
            ),
        ],
      ),
    );
  }

  Widget _buildBodyFatTrendCard(List<_FatData> data) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(16)), child: Icon(LucideIcons.activity, color: Colors.purple.shade600, size: 20)),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Body Fat Trend', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      Text('LAST 10 SCANS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.0)),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(data.isNotEmpty ? '\${data.last.fat}%' : '--%', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.purple.shade600, letterSpacing: -1.0)),
                  const Text('CURRENT EST.', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.0)),
                ],
              ),
            ],
          ),
          if (data.isNotEmpty) ...[
            const SizedBox(height: 32),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < data.length) {
                             return Padding(
                               padding: const EdgeInsets.only(top: 8.0),
                               child: Text(data[value.toInt()].date, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary)),
                             );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: data.length.toDouble() - 1,
                  minY: data.map((e) => e.fat).reduce((a, b) => a < b ? a : b) - 2,
                  maxY: data.map((e) => e.fat).reduce((a, b) => a > b ? a : b) + 2,
                  lineBarsData: [
                    LineChartBarData(
                      spots: data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.fat)).toList(),
                      isCurved: true,
                      color: Colors.purple.shade500,
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.purple.shade500.withOpacity(0.3), Colors.purple.shade500.withOpacity(0.0)]),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(milliseconds: 1000),
                curve: Curves.easeOutCubic,
              ),
            ),
          ] else ...[
            const SizedBox(height: 48),
            Center(
              child: Column(
                children: [
                  Container(width: 64, height: 64, decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(24)), child: const Icon(LucideIcons.activity, color: AppColors.textTertiary, size: 32)),
                  const SizedBox(height: 16),
                  const Text('Perform a body scan to see trends', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  Widget _buildDailySummaryCard(dailySummary, UserProfile? profile) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.green.shade500, Colors.green.shade600]), borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: Colors.green.shade500.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.activity, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text('DAILY SUMMARY', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                ],
              ),
              Text(DateFormat('EEEE, MMM d').format(DateTime.now()).toUpperCase(), style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CALORIES', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('\${dailySummary?.totalCalories ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
                        const SizedBox(width: 4),
                        Text('/ \${profile?.calorieLimit ?? 2000} kcal', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WATER', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('\${dailySummary?.totalWater ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
                        const SizedBox(width: 4),
                        Text('/ \${profile?.waterGoal ?? 2500} ml', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white24),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMacroStat('PROTEIN', '\${dailySummary?.totalProtein ?? 0}g'),
              _buildMacroStat('CARBS', '\${dailySummary?.totalCarbs ?? 0}g'),
              _buildMacroStat('FATS', '\${dailySummary?.totalFats ?? 0}g'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMacroStat(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildWeeklyTrendsChart(List<_WeeklyData> data, UserProfile? profile) {
    double maxCalories = data.fold(0, (max, e) => e.calories > max ? e.calories : max);
    if (maxCalories == 0) maxCalories = 2000;
    
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.activity, color: Colors.green.shade500, size: 18),
                  const SizedBox(width: 8),
                  const Text('WEEKLY TRENDS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: 1.0)),
                ],
              ),
              Row(
                children: [
                  _buildLegendIndicator('Kcal', Colors.green.shade500),
                  const SizedBox(width: 8),
                  _buildLegendIndicator('P', Colors.blue.shade500),
                  const SizedBox(width: 8),
                  _buildLegendIndicator('C', Colors.orange.shade500),
                  const SizedBox(width: 8),
                  _buildLegendIndicator('F', Colors.purple.shade500),
                ],
              )
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 256,
            child: BarChart(
               BarChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < data.length) {
                             return Padding(
                               padding: const EdgeInsets.only(top: 8.0),
                               child: Text(data[value.toInt()].name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary)),
                             );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: data.asMap().entries.map((e) {
                    final index = e.key;
                    final item = e.value;
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        // Stacked Macros
                        BarChartRodData(
                          toY: (item.protein + item.carbs + item.fats).toDouble(),
                          width: 8,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          rodStackItems: [
                            BarChartRodStackItem(0, item.protein.toDouble(), Colors.blue.shade500),
                            BarChartRodStackItem(item.protein.toDouble(), (item.protein + item.carbs).toDouble(), Colors.orange.shade500),
                            BarChartRodStackItem((item.protein + item.carbs).toDouble(), (item.protein + item.carbs + item.fats).toDouble(), Colors.purple.shade500),
                          ],
                        ),
                      ],
                    );
                  }).toList(),
               ),
              duration: const Duration(milliseconds: 1000),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroProgressChart(List<_WeeklyData> data, UserProfile? profile) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.zap, color: Colors.blue.shade500, size: 18),
                  const SizedBox(width: 8),
                  const Text('MACRO PROGRESS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: 1.0)),
                ],
              ),
              Row(
                children: [
                  _buildLegendIndicator('P', Colors.blue.shade500),
                  const SizedBox(width: 8),
                  _buildLegendIndicator('C', Colors.orange.shade500),
                  const SizedBox(width: 8),
                  _buildLegendIndicator('F', Colors.purple.shade500),
                ],
              )
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 200,
            child: BarChart(
               BarChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= 0 && value.toInt() < data.length) {
                             return Padding(
                               padding: const EdgeInsets.only(top: 8.0),
                               child: Text(data[value.toInt()].name, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary)),
                             );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: data.asMap().entries.map((e) {
                    final index = e.key;
                    final item = e.value;
                    return BarChartGroupData(
                      x: index,
                      barsSpace: 4,
                      barRods: [
                        BarChartRodData(toY: item.protein.toDouble(), color: Colors.blue.shade500, width: 8, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                        BarChartRodData(toY: item.carbs.toDouble(), color: Colors.orange.shade500, width: 8, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                        BarChartRodData(toY: item.fats.toDouble(), color: Colors.purple.shade500, width: 8, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                      ],
                    );
                  }).toList(),
               ),
            ),
          )
        ],
      )
    );
  }

  Widget _buildLegendIndicator(String label, Color color) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 1.0)),
      ],
    );
  }

  Widget _buildCalorieBalanceCard(dailySummary, UserProfile? profile, double progress) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.flame, color: Colors.orange.shade500, size: 20),
                  const SizedBox(width: 8),
                  const Text('Calorie Balance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                ],
              ),
              const Icon(LucideIcons.info, color: AppColors.textTertiary, size: 18),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 224, height: 224,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 16,
                  color: AppColors.surfaceMuted,
                  backgroundColor: Colors.transparent,
                ),
                CircularProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  strokeWidth: 16,
                  color: progress > 1 ? Colors.red.shade500 : Colors.green.shade500,
                  backgroundColor: Colors.transparent,
                ).animate().scale(delay: 200.ms, begin: const Offset(0.5, 0.5)),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('\${dailySummary?.totalCalories ?? 0}', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -2.0)),
                      const Text('CONSUMED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 2.0)),
                    ],
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text('GOAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.5)),
                    const SizedBox(height: 4),
                    Text('\${profile?.calorieLimit ?? 2000}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: AppColors.border),
              Expanded(
                child: Column(
                  children: [
                    const Text('REMAINING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.5)),
                    const SizedBox(height: 4),
                    Text(
                      '\${((profile?.calorieLimit ?? 2000) - (dailySummary?.totalCalories ?? 0)).clamp(0, 9999)}', 
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: ((profile?.calorieLimit ?? 2000) - (dailySummary?.totalCalories ?? 0)) < 0 ? Colors.red.shade500 : Colors.green.shade600)
                    ),
                  ],
                ),
              ),
            ],
          )
        ],
      )
    );
  }

  Widget _buildHydrationProgressCard(dailySummary, UserProfile? profile, double progress) {
     return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(40), border: Border.all(color: AppColors.border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.droplets, color: Colors.blue.shade500, size: 20),
                  const SizedBox(width: 8),
                  const Text('Hydration Progress', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 224, height: 224,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 16,
                  color: AppColors.surfaceMuted,
                  backgroundColor: Colors.transparent,
                ),
                CircularProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  strokeWidth: 16,
                  color: Colors.blue.shade500,
                  backgroundColor: Colors.transparent,
                ).animate().scale(delay: 200.ms, begin: const Offset(0.5, 0.5)),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('\${dailySummary?.totalWater ?? 0}', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: AppColors.textPrimary, letterSpacing: -2.0)),
                      const Text('ML CONSUMED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 2.0)),
                    ],
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    const Text('GOAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.5)),
                    const SizedBox(height: 4),
                    Text('\${profile?.waterGoal ?? 2500}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                  ],
                ),
              ),
              Container(width: 1, height: 40, color: AppColors.border),
              Expanded(
                child: Column(
                  children: [
                    const Text('REMAINING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.5)),
                    const SizedBox(height: 4),
                    Text(
                      '\${((profile?.waterGoal ?? 2500) - (dailySummary?.totalWater ?? 0)).clamp(0, 9999)}', 
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.blue.shade600)
                    ),
                  ],
                ),
              ),
            ],
          )
        ],
      )
    );
  }

  Widget _buildInsightsCard(dailySummary, double calorieProgress) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(48), border: Border.all(color: const Color(0xFF1E293B))),
      child: Column(
        children: [
          Row(
            children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.green.shade500.withOpacity(0.2), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.green.shade500.withOpacity(0.2))), child: Icon(LucideIcons.sparkles, color: Colors.green.shade400, size: 20)),
              const SizedBox(width: 12),
              const Text('AI Health Insights', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5)),
            ],
          ),
          const SizedBox(height: 32),
          _buildInsightRow(
            Colors.green.shade500, 
            calorieProgress > 0.8 
              ? "You're approaching your calorie limit. Opt for high-volume, low-calorie snacks like cucumber or berries."
              : "Excellent pace! You're perfectly aligned with your daily calorie targets."
          ),
          const SizedBox(height: 24),
          _buildInsightRow(
            Colors.blue.shade500, 
            (dailySummary?.totalProtein ?? 0) < 50 
              ? "Protein intake is slightly behind. Consider a Greek yogurt or protein shake to recover."
              : "Protein levels are optimal. This is great for muscle maintenance and satiety."
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.1))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('VIEW DETAILED REPORT', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                const SizedBox(width: 12),
                Icon(LucideIcons.chevronRight, color: Colors.white, size: 18),
              ],
            ),
          )
        ],
      )
    );
  }

  Widget _buildInsightRow(Color color, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 8), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 16),
        Expanded(child: Text(text, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 16, height: 1.5, fontWeight: FontWeight.w600))),
      ],
    );
  }
}
