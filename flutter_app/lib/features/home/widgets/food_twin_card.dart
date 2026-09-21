import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/models/food_memory_item.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/theme/app_colors.dart';

final foodMemoryProvider = FutureProvider.autoDispose<List<FoodMemoryItem>>((ref) async {
  // Re-fetches whenever a new scan is saved, since saveScanResult updates
  // food memory — cheap enough (single indexed SQLite query) to just re-run.
  ref.watch(scanHistoryStreamProvider);
  return ref.read(storageServiceProvider).getFoodMemory();
});

/// "Personal Food Twin" — the on-device model of the user's most-repeated
/// meals, built automatically from every food scan (see
/// StorageService.recordFoodScanInMemory). Regional & home-cooked dishes a
/// generic nutrition database would never recognize get remembered here.
class FoodTwinCard extends ConsumerWidget {
  const FoodTwinCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoryAsync = ref.watch(foodMemoryProvider);

    return memoryAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (memory) {
        if (memory.isEmpty) return const SizedBox.shrink();
        final topItems = memory.take(8).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.brainCircuit, size: 16, color: Colors.purple.shade500),
                const SizedBox(width: 8),
                const Text(
                  'YOUR PERSONAL FOOD TWIN',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textTertiary, letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Learned from your scans — recognizes your regional & repeat meals instantly.',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: topItems.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final item = topItems[index];
                  return Container(
                    width: 150,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (item.isPreferred == true) Icon(LucideIcons.star, size: 12, color: Colors.amber.shade500),
                            if (item.isPreferred == true) const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item.localName ?? item.foodName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.avgCalories} kcal avg',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.purple.shade600),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(999)),
                          child: Text(
                            'Eaten ${item.scanCount}x',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.purple.shade700),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
