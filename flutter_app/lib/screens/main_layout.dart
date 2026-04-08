import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'home_screen.dart';
import 'history_screen.dart';
import 'analytics_screen.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;
  final List<Widget> _screens = [
    const HomeScreen(),
    const HistoryScreen(),
    const AnalyticsScreen(),
    const ChatScreen(),
    const SettingsScreen(),
  ];

  final List<IconData> _icons = [
    LucideIcons.home,
    LucideIcons.history,
    LucideIcons.barChart2,
    LucideIcons.messageSquare,
    LucideIcons.settings,
  ];

  final List<String> _labels = ['Home', 'History', 'Stats', 'AI', 'Settings'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Stack(
        children: [
          // Main Content
          IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),

          // Floating Pill Navigation
          Positioned(
            bottom: 32,
            left: 32,
            right: 32,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                height: 64,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white.withOpacity(0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    children: [
                      // Liquid Pill Indicator
                      AnimatedAlign(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.elasticOut,
                        alignment: Alignment(
                          -1.0 + (_currentIndex * (2.0 / (_icons.length - 1))),
                          0,
                        ),
                        child: FractionallySizedBox(
                          widthFactor: 1 / _icons.length,
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Nav Items
                      Row(
                        children: List.generate(_icons.length, (index) {
                          final isSelected = _currentIndex == index;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _currentIndex = index),
                              behavior: HitTestBehavior.opaque,
                              child: Center(
                                child: Icon(
                                  _icons[index],
                                  color: isSelected
                                      ? const Color(0xFF10B981)
                                      : Colors.grey.withOpacity(0.5),
                                  size: 20,
                                  strokeWidth: isSelected ? 2.5 : 2.0,
                                ).animate(target: isSelected ? 1 : 0).scale(begin: const Offset(0.8, 0.8), end: const Offset(1.1, 1.1)),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
