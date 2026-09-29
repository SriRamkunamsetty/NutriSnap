import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ios_kit.dart';

/// Entry points to the secondary modules, so the tab bar stays uncluttered.
class ModuleShortcuts extends StatelessWidget {
  const ModuleShortcuts({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Explore'),
        SizedBox(
          height: 108,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              _tile(context, LucideIcons.bookOpen, 'Food Library', 'Indian & regional foods', Colors.orange, AppRoutes.foodLibrary),
              _tile(context, LucideIcons.brain, 'Food Twin', 'What it learned about you', Colors.green, AppRoutes.foodTwin),
              _tile(context, LucideIcons.school, 'MessOS', 'Campus & hostel menus', Colors.blue, AppRoutes.messOs),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String sub, MaterialColor c, String route) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 170,
        child: IosCard(
          onTap: () => context.push(route),
          padding: const EdgeInsets.all(14),
          semanticLabel: '$title. $sub',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: c.shade50, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 19, color: c.shade600),
              ),
              const Spacer(),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
