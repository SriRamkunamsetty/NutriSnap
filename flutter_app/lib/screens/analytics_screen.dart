import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/user_provider.dart';
import 'package:intl/intl.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final scans = userProvider.scans;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Analytics',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.fileText, color: Colors.blue),
            onPressed: () {
              // Trigger PDF Report
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWeeklyChart(scans),
            const SizedBox(height: 30),
            _buildMacroDistribution(scans),
            const SizedBox(height: 30),
            _buildBodyFatTrend(scans),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyChart(List<dynamic> scans) {
    // Simplified weekly chart logic
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly Calories',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: 1800, color: Colors.green, width: 16)]),
                  BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: 2100, color: Colors.green, width: 16)]),
                  BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: 1500, color: Colors.green, width: 16)]),
                  BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: 2400, color: Colors.green, width: 16)]),
                  BarChartGroupData(x: 4, barRods: [BarChartRodData(toY: 1900, color: Colors.green, width: 16)]),
                  BarChartGroupData(x: 5, barRods: [BarChartRodData(toY: 2000, color: Colors.green, width: 16)]),
                  BarChartGroupData(x: 6, barRods: [BarChartRodData(toY: 1700, color: Colors.green, width: 16)]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroDistribution(List<dynamic> scans) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Macro Distribution',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(value: 30, color: Colors.blue, title: 'Protein', radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  PieChartSectionData(value: 50, color: Colors.orange, title: 'Carbs', radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  PieChartSectionData(value: 20, color: Colors.purple, title: 'Fats', radius: 50, titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyFatTrend(List<dynamic> scans) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Body Fat Trend',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 22),
                      FlSpot(1, 21.5),
                      FlSpot(2, 21.2),
                      FlSpot(3, 20.8),
                      FlSpot(4, 20.5),
                    ],
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 4,
                    dotData: const FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
