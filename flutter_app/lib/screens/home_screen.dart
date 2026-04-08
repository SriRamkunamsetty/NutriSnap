import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/user_provider.dart';
import '../widgets/custom_widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final profile = userProvider.profile;
    final summary = userProvider.dailySummary;

    if (userProvider.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              title: Text(
                'NutriSnap AI',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(LucideIcons.camera, color: Color(0xFF10B981)),
                onPressed: () {
                  // Handle camera scan
                },
              ),
              const SizedBox(width: 10),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Calorie Card
                  CalorieCard(
                    consumed: summary?.totalCalories ?? 0,
                    limit: profile?.calorieLimit ?? 2000,
                  ),
                  const SizedBox(height: 20),
                  
                  // Macros Row
                  Row(
                    children: [
                      Expanded(
                        child: MacroMiniCard(
                          label: 'Protein',
                          value: summary?.totalProtein ?? 0,
                          goal: profile?.proteinGoal ?? 150,
                          color: Colors.blue,
                          icon: LucideIcons.zap,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MacroMiniCard(
                          label: 'Carbs',
                          value: summary?.totalCarbs ?? 0,
                          goal: profile?.carbsGoal ?? 250,
                          color: Colors.orange,
                          icon: LucideIcons.apple,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MacroMiniCard(
                          label: 'Fats',
                          value: summary?.totalFats ?? 0,
                          goal: profile?.fatsGoal ?? 70,
                          color: Colors.purple,
                          icon: LucideIcons.droplets,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Water Card
                  WaterCard(
                    consumed: summary?.totalWater ?? 0,
                    goal: profile?.waterGoal ?? 2500,
                  ),
                  const SizedBox(height: 30),
                  
                  Text(
                    'Recent Meals',
                    style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 15),
                  
                  // Recent Scans List
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: userProvider.scans.take(5).length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final scan = userProvider.scans[index];
                      return MealListItem(scan: scan);
                    },
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
