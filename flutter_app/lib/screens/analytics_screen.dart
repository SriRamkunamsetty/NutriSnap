import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/user_provider.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Analytics',
                    style: GoogleFonts.outfit(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0F172A),
                      letterSpacing: -1,
                    ),
                  ),
                  _buildHeaderButton(LucideIcons.fileText),
                ],
              ).animate().fadeIn().moveY(begin: 10, end: 0),
              const SizedBox(height: 32),

              // Weekly Activity
              _buildSectionTitle('WEEKLY ACTIVITY'),
              _buildChartCard(
                'Calories Consumed',
                'Last 7 Days',
                _buildBarChart(),
              ),
              const SizedBox(height: 24),

              // Macro Distribution
              _buildSectionTitle('MACRO DISTRIBUTION'),
              _buildChartCard(
                'Nutrient Balance',
                'Average this week',
                _buildPieChart(),
              ),
              const SizedBox(height: 24),

              // Weight Trend
              _buildSectionTitle('WEIGHT TREND'),
              _buildChartCard(
                'Body Mass Index',
                'Last 30 Days',
                _buildLineChart(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderButton(IconData icon) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.grey, size: 20),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 16),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: Colors.grey,
          letterSpacing: 2.0,
        ),
      ),
    );
  }

  Widget _buildChartCard(String title, String subtitle, Widget chart) {
    return Container(
      padding: const EdgeInsets.all(24),
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
            title,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
          ),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(height: 200, child: chart),
        ],
      ),
    ).animate().fadeIn(delay: 100.ms).moveY(begin: 10, end: 0);
  }

  Widget _buildBarChart() {
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(7, (i) => 
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: (i + 1) * 200.0 + 1000,
                color: const Color(0xFF10B981),
                width: 16,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPieChart() {
    return PieChart(
      PieChartData(
        sections: [
          PieChartSectionData(value: 40, color: Colors.blue, radius: 60, title: '40%', titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          PieChartSectionData(value: 35, color: Colors.orange, radius: 60, title: '35%', titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          PieChartSectionData(value: 25, color: Colors.purple, radius: 60, title: '25%', titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
        centerSpaceRadius: 40,
      ),
    );
  }

  Widget _buildLineChart() {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: const [
              FlSpot(0, 24),
              FlSpot(1, 23.5),
              FlSpot(2, 23.8),
              FlSpot(3, 23.2),
              FlSpot(4, 23.0),
            ],
            isCurved: true,
            color: const Color(0xFF3B82F6),
            barWidth: 4,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0xFF3B82F6).withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }
}
