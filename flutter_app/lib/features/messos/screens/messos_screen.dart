import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/models/mess.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/datetime_utils.dart';
import '../../../core/widgets/ios_kit.dart';
import '../widgets/mess_sheets.dart';

/// Campus / hostel food: pick your mess, see (or enter) today's menu,
/// get nutrition for it, and log a meal with one tap. Works offline.
class MessOsScreen extends ConsumerStatefulWidget {
  const MessOsScreen({super.key});

  @override
  ConsumerState<MessOsScreen> createState() => _MessOsScreenState();
}

class _MessOsScreenState extends ConsumerState<MessOsScreen> {
  late DateTime _day = DateTime.now();

  String get _date => DateTimeUtils.dayKey(_day);
  bool get _isToday => _date == DateTimeUtils.today();

  void _shift(int days) => setState(() => _day = DateTime(_day.year, _day.month, _day.day + days));

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(activeMessProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: active.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error: (_, __) => _scaffold(
            IosCard(
              child: EmptyPanel(
                icon: LucideIcons.circleAlert,
                title: 'Couldn\'t open MessOS',
                message: 'Something went wrong reading your saved messes.',
                action: TextButton(onPressed: () => ref.invalidate(activeMessProvider), child: const Text('Retry')),
              ),
            ),
          ),
          data: (mess) => mess == null ? _scaffold(_setup()) : _menuView(mess),
        ),
      ),
    );
  }

  Widget _scaffold(Widget body, {String? subtitle, List<Widget> actions = const []}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 60),
      children: [
        Row(children: [RoundIconButton(icon: LucideIcons.chevronLeft, tooltip: 'Back', onTap: () => context.pop())]),
        const SizedBox(height: 14),
        LargeTitle(title: 'MessOS', subtitle: subtitle ?? 'Campus food, offline', actions: actions),
        const SizedBox(height: 18),
        body,
      ],
    );
  }

  Widget _setup() {
    return IosCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16)),
            child: Icon(LucideIcons.school, color: Colors.blue.shade600),
          ),
          const SizedBox(height: 14),
          const Text('Set up your mess',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text(
            'Tell NutriSnap where you eat. Then add each day\'s menu (type it or paste it) and log a whole meal in one tap, with nutrition estimated on your phone.',
            style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          ProminentButton(label: 'Add my mess', icon: LucideIcons.plus, onPressed: () => showAddMessSheet(context)),
        ],
      ),
    );
  }

  Widget _menuView(Mess mess) {
    final all = ref.watch(messesProvider).valueOrNull ?? [mess];
    final menu = ref.watch(messMenuProvider((messId: mess.id, date: _date))).valueOrNull;
    final dates = ref.watch(messMenuDatesProvider(mess.id)).valueOrNull ?? const <String>[];

    return _scaffold(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _messChip(mess, all),
          const SizedBox(height: 14),
          _dateBar(),
          const SizedBox(height: 14),
          _menuActions(mess, menu, dates),
          for (final type in MealType.all) ...[
            _MealCard(
              key: ValueKey('$_date-$type'),
              mess: mess,
              date: _date,
              type: type,
              meal: menu?.meal(type),
            ),
            const SizedBox(height: 14),
          ],
          if (dates.isNotEmpty) _history(dates),
        ],
      ),
      subtitle: mess.subtitle,
    );
  }

  Widget _messChip(Mess mess, List<Mess> all) => Align(
        alignment: Alignment.centerLeft,
        child: PressableScale(
          onTap: () => showSwitchMessSheet(context, all, mess),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.school, size: 16, color: Colors.blue.shade600),
              const SizedBox(width: 8),
              Text(mess.label, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              const Icon(LucideIcons.chevronsUpDown, size: 14, color: AppColors.textTertiary),
            ]),
          ),
        ),
      );

  Widget _dateBar() => Row(children: [
        RoundIconButton(icon: LucideIcons.chevronLeft, tooltip: 'Previous day', onTap: () => _shift(-1)),
        Expanded(
          child: Column(children: [
            Text(_isToday ? 'Today' : DateFormat('EEEE').format(_day),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(DateFormat('d MMMM y').format(_day), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ),
        RoundIconButton(icon: LucideIcons.chevronRight, tooltip: 'Next day', onTap: () => _shift(1)),
      ]);

  Widget _menuActions(Mess mess, MessMenu? menu, List<String> dates) {
    final empty = menu == null || menu.meals.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(spacing: 10, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: () => showPasteMenuSheet(context, mess: mess, date: _date),
          icon: const Icon(LucideIcons.clipboardPaste, size: 16),
          label: const Text('Paste menu'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: Colors.white),
        ),
        if (empty)
          FutureBuilder<String?>(
            future: ref.read(messServiceProvider).suggestCopySource(mess.id, _date),
            builder: (context, snap) {
              final from = snap.data;
              if (from == null) return const SizedBox.shrink();
              return OutlinedButton.icon(
                onPressed: () async {
                  await ref.read(messRepositoryProvider).copyMenu(mess.id, from, _date);
                  HapticFeedback.mediumImpact();
                },
                icon: const Icon(LucideIcons.copy, size: 16),
                label: Text('Copy from ${DateFormat('EEE d MMM').format(DateTime.parse(from))}'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44), backgroundColor: Colors.white),
              );
            },
          ),
      ]),
    );
  }

  Widget _history(List<String> dates) {
    final other = dates.where((d) => d != _date).take(10).toList();
    if (other.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Menu history'),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: other.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final d = DateTime.parse(other[i]);
              return ActionChip(
                label: Text(DateFormat('EEE d MMM').format(d)),
                onPressed: () => setState(() => _day = d),
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.border),
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              );
            },
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------

class _MealCard extends ConsumerWidget {
  const _MealCard({super.key, required this.mess, required this.date, required this.type, required this.meal});
  final Mess mess;
  final String date;
  final String type;
  final MessMeal? meal;

  static IconData _icon(String t) => switch (t) {
        MealType.breakfast => LucideIcons.sunrise,
        MealType.lunch => LucideIcons.sun,
        MealType.snacks => LucideIcons.coffee,
        _ => LucideIcons.moon,
      };

  Future<void> _edit(BuildContext context) => showEditMessMealSheet(
        context,
        mess: mess,
        date: date,
        mealType: type,
        initial: meal?.dishes ?? const [],
      );

  Future<void> _log(BuildContext context, WidgetRef ref) async {
    final m = meal;
    if (m == null) return;
    final est = m.nutrition;
    if (est.unknownDishes.isNotEmpty && est.knownCount > 0) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Some dishes have no nutrition'),
          content: Text(
              '${est.unknownDishes.join(', ')} won\'t be counted. Estimate or enter them first for a complete log, or log what is known.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Edit menu')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log anyway')),
          ],
        ),
      );
      if (go != true) return;
    }
    try {
      final saved = await ref.read(messServiceProvider).logMeal(m, mess, menuDate: date);
      HapticFeedback.mediumImpact();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Logged ${MealType.label(type)} · ${saved.calories} kcal'),
        ));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not log this meal.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = meal;
    final est = m?.nutrition;

    return IosCard(
      semanticLabel: m == null
          ? '${MealType.label(type)}: no menu yet'
          : '${MealType.label(type)}: ${m.dishes.map((d) => d.name).join(', ')}. ${est!.calories} calories.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_icon(type), size: 20, color: Colors.orange.shade600),
            const SizedBox(width: 10),
            Expanded(child: Text(MealType.label(type), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            if (m != null && m.isLogged) const SourceChip('Logged'),
            IconButton(
              tooltip: m == null ? 'Add ${MealType.label(type)} menu' : 'Edit ${MealType.label(type)} menu',
              onPressed: () => _edit(context),
              icon: Icon(m == null ? LucideIcons.plus : LucideIcons.pencil, size: 18),
            ),
          ]),
          if (m == null || m.dishes.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: TextButton(
                onPressed: () => _edit(context),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 44), alignment: Alignment.centerLeft),
                child: const Text('Add today\'s menu'),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            for (final d in m.dishes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(
                    child: Text(d.servings == 1 ? d.name : '${d.servings == d.servings.roundToDouble() ? d.servings.round() : d.servings}× ${d.name}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  Text(d.needsEstimate ? 'needs estimate' : '${d.totalCalories.round()} kcal',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: d.needsEstimate ? Colors.orange.shade800 : AppColors.textSecondary)),
                ]),
              ),
            const Divider(height: 22, color: AppColors.border),
            Row(children: [
              Text('${est!.calories}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -1)),
              const SizedBox(width: 4),
              const Text('kcal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(width: 12),
              Expanded(
                child: Text('P ${est.protein}  C ${est.carbs}  F ${est.fats} g',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                est.unknownDishes.isNotEmpty
                    ? '${est.unknownDishes.length} dish${est.unknownDishes.length == 1 ? '' : 'es'} not counted yet'
                    : 'Estimate · ${(est.confidence * 100).round()}% confident. Portions vary.',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: est.unknownDishes.isNotEmpty ? Colors.orange.shade800 : AppColors.textTertiary),
              ),
            ),
            const SizedBox(height: 12),
            if (m.isLogged)
              OutlinedButton.icon(
                onPressed: () => ref.read(messServiceProvider).unlogMeal(m),
                icon: const Icon(LucideIcons.undo2, size: 16),
                label: const Text('Undo log'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ProminentButton(
                  label: 'Log meal',
                  icon: LucideIcons.plus,
                  onPressed: est.knownCount == 0 ? null : () => _log(context, ref),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
