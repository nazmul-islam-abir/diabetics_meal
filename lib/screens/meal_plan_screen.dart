import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/meal_item.dart';
import '../models/user_meal_plan.dart';
import '../services/supabase_service.dart';
import '../services/impact_engine.dart';
import '../services/app_events.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import 'plan_editor.dart';

/// Today's meal plan as a checklist.
/// The user marks each item as eaten, swaps it, or logs an off-plan food.
class MealPlanScreen extends StatefulWidget {
  final int initialDay;
  const MealPlanScreen({super.key, this.initialDay = 1});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> with TickerProviderStateMixin {
  // The active day is locked to today's slot in the 30-day plan and
  // is computed server-side from `plan_start_date` in `user_profiles`.
  // Editing/adding is only meaningful for the current day.
  int _day = 1;
  int _totalDays = 30;
  /// Server-computed "today" slot inside the rotating plan. Null
  /// until the first plan-progress fetch resolves. Used by the day
  /// picker to highlight today's row and by [_goToday] to jump back.
  int? _todayDayIndex;
  Classification? _cls;
  List<MealSlotPlan> _items = [];
  Map<String, MealLogEntry> _todayLog = {};
  List<UserMealPlan> _customEntries = [];
  bool _loading = true;
  String? _error;

  late final AnimationController _entry;

  @override
  void initState() {
    super.initState();
    _day = widget.initialDay;
    _entry = AnimationController(vsync: this, duration: AppMotion.long);
    _load();
    AppEvents.profileChanged.addListener(_onProfileChanged);
  }

  @override
  void dispose() {
    AppEvents.profileChanged.removeListener(_onProfileChanged);
    _entry.dispose();
    super.dispose();
  }

  void _onProfileChanged() {
    if (!mounted) return;
    // A profile change can invalidate the plan shape — reset to
    // today so the user sees the freshly-recomputed recommendation
    // instead of a stale past/future day.
    _todayDayIndex = null;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // First resolve which day of the 30-day plan is "today" via
      // the server (so multiple devices / day-rollovers stay in
      // sync). Then ask for the chosen day's plan + log.
      final progress = await SupabaseService.getPlanProgress();

      // Decide which day's plan to show:
      //  * First load (_todayDayIndex == null) → show today's day.
      //  * Auto-rollover: if we were showing today last time and
      //    the calendar has rolled forward, advance with it.
      //  * Otherwise preserve the user's currently displayed day.
      final hadToday = _todayDayIndex;
      var targetDay = _day.clamp(1, progress.totalDays);
      if (hadToday == null) {
        targetDay = progress.day;
      } else if (_day == hadToday && progress.day > hadToday) {
        // The user was viewing today and the world has rolled
        // forward — keep them on today (which is a new day).
        targetDay = progress.day;
      } else {
        // The user was viewing a past or future day. If their
        // chosen day is still in the valid range, keep it.
        targetDay = _day.clamp(1, progress.totalDays);
      }

      // Use the override-aware RPC so any user-pinned food comes
      // back already merged into the recommendation. Falls back to
      // the baseline RPC if 11_*.sql hasn't been run yet.
      final result =
          await SupabaseService.getDailyRecommendationWithOverrides(targetDay);
      final clsJson = Map<String, dynamic>.from(result['classification'] as Map);
      final cls = Classification.fromJson(clsJson);

      // Fetch custom entries for the chosen day in parallel.
      // These are *extra* slots the user added (or a swap they
      // chose to keep as an off-AI row).
      final results = await Future.wait([
        Future(() => _expandPlan(result)),
        SupabaseService.getDailyLog(planDay: targetDay),
        _safeGetUserDayPlan(),
      ]);
      final items = results[0] as List<MealSlotPlan>;
      final log = results[1] as List<MealLogEntry>;
      final custom = results[2] as List<UserMealPlan>;

      final today = <String, MealLogEntry>{};
      for (final e in log) {
        final key = '${e.mealSlot}|${e.foodId ?? ''}';
        today[key] = e;
      }

      // Merge custom entries into the slot groups so each one shows
      // up under its own slot alongside the AI suggestions.
      final merged = _mergeCustomIntoPlan(items, custom);

      if (!mounted) return;
      setState(() {
        _day = targetDay;
        _totalDays = progress.totalDays;
        _todayDayIndex = progress.day;
        _cls = cls;
        _items = merged;
        _todayLog = today;
        _customEntries = custom;
      });
      _entry.forward(from: 0);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<UserMealPlan>> _safeGetUserDayPlan() async {
    try {
      return await SupabaseService.getUserDayPlan(_todayDate());
    } catch (_) {
      return const [];
    }
  }

  /// The calendar date that "today" maps to inside the rotating 30-day plan.
  /// The backend treats today as day 1, so this is just today.
  DateTime _todayDate() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Flatten the plan JSON into a list of MealSlotPlan.
  /// Each AI tile is tagged with role=null for single-item slots
  /// (breakfast, snacks) and the appropriate role otherwise. We
  /// don't know here which slots were overridden — that requires a
  /// separate override-list call which the screen doesn't need
  /// today, so we render all rows as 'ai' and rely on the food
  /// change itself to indicate an override.
  List<MealSlotPlan> _expandPlan(Map<String, dynamic> data) {
    final out = <MealSlotPlan>[];

    void addSlot(String slot, String role, Map<String, dynamic>? foodMap) {
      if (foodMap == null || foodMap.isEmpty) return;
      final id = foodMap['id'] as String?;
      if (id == null || id.isEmpty) return;
      final item = MealItem.fromJson(foodMap);
      out.add(MealSlotPlan(slot: slot, role: role, food: item));
    }

    final breakfast = data['breakfast'];
    if (breakfast is Map) {
      addSlot('breakfast', 'main', Map<String, dynamic>.from(breakfast));
    }

    final lunch = data['lunch'];
    if (lunch is Map) {
      final m = Map<String, dynamic>.from(lunch);
      addSlot('lunch', 'carb', (m['carb'] as Map?)?.cast<String, dynamic>());
      addSlot('lunch', 'protein', (m['protein'] as Map?)?.cast<String, dynamic>());
      addSlot('lunch', 'vegetable', (m['vegetable'] as Map?)?.cast<String, dynamic>());
      addSlot('lunch', 'dal', (m['dal'] as Map?)?.cast<String, dynamic>());
    }

    final dinner = data['dinner'];
    if (dinner is Map) {
      final m = Map<String, dynamic>.from(dinner);
      addSlot('dinner', 'carb', (m['carb'] as Map?)?.cast<String, dynamic>());
      addSlot('dinner', 'protein', (m['protein'] as Map?)?.cast<String, dynamic>());
      addSlot('dinner', 'vegetable', (m['vegetable'] as Map?)?.cast<String, dynamic>());
    }

    final ms = data['morning_snack'];
    if (ms is Map) addSlot('morning_snack', 'snack', Map<String, dynamic>.from(ms));
    final es = data['evening_snack'];
    if (es is Map) addSlot('evening_snack', 'snack', Map<String, dynamic>.from(es));

    return out;
  }

  /// Slot name for a custom entry: either an explicit
  /// breakfast/lunch/etc. bucket, or 'other' if the user picked
  /// a free-form slot. We treat the custom food's category as the
  /// role so it renders next to the matching AI suggestion when
  /// the categories line up.
  String _slotForCustom(UserMealPlan e) {
    if (kSlotOptions.contains(e.slot)) return e.slot;
    return 'other';
  }

  /// Slot key used to group tiles for display. Custom entries
  /// piggy-back on the canonical slot buckets; 'other' gets its
  /// own section.
  String _bucketKeyForSlot(String slot) => slot;

  /// Map a custom entry to a MealSlotPlan tile so it renders
  /// inside the standard checklist UI. `food` is a synthesized
  /// MealItem if the row points to a master food; otherwise we
  /// surface a placeholder with the free-text name.
  MealSlotPlan _customToSlotPlan(UserMealPlan e) {
    final f = e.food;
    final MealItem item;
    if (f != null) {
      item = MealItem.fromJson(f);
    } else {
      item = MealItem(
        id: 'custom-${e.id}',
        nameBn: e.customFoodName ?? '(নাম ছাড়া)',
        category: 'other',
        carbG: 0,
        proteinG: 0,
        fatG: 0,
        fiberG: 0,
        sodiumMg: 0,
        potassiumMg: 0,
        phosphorusMg: 0,
        giCategory: 'low',
        portionLabel: e.portionLabel,
      );
    }
    return MealSlotPlan(
      slot: _bucketKeyForSlot(_slotForCustom(e)),
      role: 'custom',
      food: item,
      source: 'custom',
      customId: e.id,
      customTime: e.displayTime,
      customPortionLabel: e.portionLabel,
    );
  }

  /// Append custom entries to the AI tile list, slot by slot. The
  /// render order stays AI-first, custom-last, which matches the
  /// mental model "your plan, with anything extra at the bottom".
  List<MealSlotPlan> _mergeCustomIntoPlan(
      List<MealSlotPlan> ai, List<UserMealPlan> custom) {
    if (custom.isEmpty) return ai;
    final out = List<MealSlotPlan>.from(ai);
    for (final e in custom) {
      out.add(_customToSlotPlan(e));
    }
    return out;
  }

  // No manual day navigation: the active slot in the 30-day plan is
  // resolved server-side per calendar day, so editing/customizing is
  // only meaningful for today.

  Future<void> _openItemSheet(MealSlotPlan item) async {
    final isAiOrOverride = item.isAi || item.isOverride;
    final result = await showModalBottomSheet<_ItemSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      builder: (ctx) => _ItemSheet(
        item: item,
        cls: _cls!,
        onEditAi: isAiOrOverride
            ? () async {
                Navigator.pop(ctx, const _ItemSheetResult._noop());
                await _editAiFood(item);
              }
            : null,
        onResetAi: isAiOrOverride && item.isOverride
            ? () async {
                Navigator.pop(ctx, const _ItemSheetResult._noop());
                await _resetAiFood(item);
              }
            : null,
      ),
    );
    if (result == null || result.isNoop) return;
    await _applyItemAction(item, result);
  }

  /// Custom-tile quick actions: Edit (opens PlanEditorSheet) /
  /// Delete / Mark eaten. Renders as a clean two-row list inside
  /// a modal sheet so it matches the AI sheet pattern.
  Future<void> _openCustomTile(MealSlotPlan tile) async {
    final id = tile.customId;
    if (id == null) return;
    final entry = _customEntries.firstWhere(
      (e) => e.id == id,
      orElse: () => _customEntries.first,
    );
    HapticFeedback.selectionClick();
    final mq = MediaQuery.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.graphite,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Overline('আমার খাবার'),
                const SizedBox(height: 4),
                Text(
                  entry.displayName.isEmpty ? '(নাম ছাড়া)' : entry.displayName,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  slotLabelBn(entry.slot),
                  style: const TextStyle(
                    color: AppColors.smoke,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                _modalOption(
                  ctx,
                  title: 'সম্পাদনা করুন',
                  subtitle: 'সময়, খাবার, পরিমাণ, নোট পরিবর্তন',
                  icon: Icons.edit_outlined,
                  onTap: () => Navigator.pop(ctx, 'edit'),
                ),
                const SizedBox(height: 10),
                _modalOption(
                  ctx,
                  title: 'খেয়েছি বলে লগ করুন',
                  subtitle: 'আজকের খাবারের হিসাবে যোগ হবে',
                  icon: Icons.check,
                  onTap: () => Navigator.pop(ctx, 'log'),
                ),
                const SizedBox(height: 10),
                _modalOption(
                  ctx,
                  title: 'পরিকল্পনা থেকে মুছুন',
                  subtitle: 'এই এন্ট্রিটি আজকের পরিকল্পনা থেকে বাদ যাবে',
                  icon: Icons.delete_outline,
                  destructive: true,
                  onTap: () => Navigator.pop(ctx, 'delete'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'edit':
        await _editCustomEntry(entry);
        break;
      case 'log':
        await _applyItemAction(tile, _ItemSheetResult(
          food: tile.food,
          status: 'eaten',
          impact: 'neutral',
        ));
        break;
      case 'delete':
        if (await _confirmDelete(entry) ?? false) {
          try {
            await SupabaseService.deleteUserMealPlan(entry.id);
            HapticFeedback.lightImpact();
            await _load();
            AppEvents.notifyMealLogged();
          } catch (e) {
            _showError('মুছে ফেলা যায়নি: $e');
          }
        }
        break;
    }
  }

  Widget _modalOption(
    BuildContext ctx, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final color = destructive ? Colors.red.shade600 : AppColors.ink;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.chalk,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.graphite),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.smoke,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward, size: 20, color: color),
          ],
        ),
      ),
    );
  }

  /// Lets the user replace the AI-suggested food for the current
  /// (day, slot, role) with another master food. Persists via
  /// meal_plan_overrides; the next _load fetches the merged plan.
  Future<void> _editAiFood(MealSlotPlan item) async {
    final selected = await _pickFoodFromMaster(item.food.nameBn);
    if (selected == null || !mounted) return;
    try {
      await SupabaseService.upsertAiPlanOverride(
        planDay: _day,
        slot: item.slot,
        role: item.role == 'main' ? null : item.role,
        foodId: selected.id,
      );
      HapticFeedback.lightImpact();
      await _load();
    } catch (e) {
      _showError('সম্পাদনা হয়নি: $e');
    }
  }

  Future<void> _resetAiFood(MealSlotPlan item) async {
    try {
      await SupabaseService.deleteAiPlanOverride(
        planDay: _day,
        slot: item.slot,
        role: item.role == 'main' ? null : item.role,
      );
      HapticFeedback.lightImpact();
      await _load();
    } catch (e) {
      _showError('রিসেট হয়নি: $e');
    }
  }

  /// Search-and-pick sheet for the master foods list. Used both
  /// by "Edit AI food" and as a quick swap during log actions.
  Future<MealItem?> _pickFoodFromMaster(String initialQuery) {
    return showModalBottomSheet<MealItem>(
      context: context,
      backgroundColor: AppColors.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _FoodPickerSheet(initialQuery: initialQuery),
    );
  }

  Future<void> _applyItemAction(MealSlotPlan item, _ItemSheetResult r) async {
    try {
      await SupabaseService.logMeal(
        mealSlot: item.slot,
        foodId: r.food?.id,
        foodNameBn: r.food?.nameBn ?? r.customLabel ?? item.food.nameBn,
        status: r.status,
        impact: r.impact,
        planDay: _day,
        reason: r.reason,
        notes: r.notes,
      );

      // When the user picks a real alternative (swap) for an AI-suggested
      // tile, also persist it as a per-day override so the next _load()
      // refetches the merged plan and shows the new food in place of the
      // original papaya / rice / etc. Off-plan entries and free-text custom
      // labels don't need an override because the user is just recording
      // what they ate, not changing tomorrow's plan.
      if (r.status == 'swap' &&
          r.food != null &&
          r.food!.id.trim().isNotEmpty &&
          r.food!.id != item.food.id) {
        try {
          await SupabaseService.upsertAiPlanOverride(
            planDay: _day,
            slot: item.slot,
            role: item.role == 'main' ? null : item.role,
            foodId: r.food!.id,
          );
        } catch (e) {
          // Override is best-effort — the logMeal row still records the
          // swap for analytics even if the override RPC isn't available.
          debugPrint('upsertAiPlanOverride failed: $e');
        }
      }

      if (!mounted) return;
      await _load();
      AppEvents.notifyMealLogged();
      HapticFeedback.lightImpact();
      if (!mounted) return;
      _showThankYou();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('লগ করা যায়নি')),
        );
      }
    }
  }

  void _showThankYou() {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(builder: (_) => const _ThankYouToast());
    overlay.insert(entry);
    Future.delayed(AppMotion.medium * 2, entry.remove);
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dateLabel = DateFormat('d MMM, EEEE', 'bn').format(today);
    return Scaffold(
      backgroundColor: AppColors.paper,
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.ink,
              foregroundColor: AppColors.paper,
              onPressed: _addCustomEntry,
              icon: const Icon(Icons.add),
              label: const Text(
                'নিজের খাবার',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: LoadingMark(size: 36))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('ত্রুটি: $_error', style: Theme.of(context).textTheme.bodyLarge),
                    ),
                  )
                : CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _buildTopBar(dateLabel)),
                      SliverToBoxAdapter(child: _buildDayStrip()),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                        sliver: _buildBody(),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildTopBar(String dateLabel) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('আজকের পরিকল্পনা'),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'আজকের\nখাবার',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                ),
              ),
              Pressable(
                onTap: _loading ? null : _load,
                borderRadius: BorderRadius.circular(40),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.chalk,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.graphite),
                  ),
                  child: const Icon(Icons.refresh, size: 22, color: AppColors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            dateLabel,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.smoke,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayStrip() {
    // The 30-day plan auto-advances per calendar day. The hero card
    // shows today's locked slot but we also expose prev/next arrows
    // (and an "আজ" jump button) so the user can browse yesterday's
    // or tomorrow's plan and log intake for those days too.
    final completed = _todayLog.values.length;
    final total = _items.length;
    final pct = total == 0 ? 0.0 : completed / total;
    final cycleStart = _day == 1;
    final cycleEnd = _day >= _totalDays;
    final isToday = _day == _todayDayIndex;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              gradient: AppGradients.aurora,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cyan.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'দিন $_day${isToday ? " • আজ" : ""}',
                            style: const TextStyle(
                              color: AppColors.paper,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              MonoCounter(
                                value: completed,
                                suffix: '/$total',
                                style: const TextStyle(
                                  color: AppColors.paper,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  height: 1,
                                  letterSpacing: -0.6,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  'লগ হয়েছে',
                                  style: TextStyle(
                                    color: AppColors.paper.withValues(alpha: 0.75),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    MonoRing(
                      value: pct,
                      size: 64,
                      stroke: 6,
                      fill: AppColors.paper,
                      track: AppColors.paper.withValues(alpha: 0.18),
                      child: Text(
                        '${(pct * 100).round()}%',
                        style: const TextStyle(
                          color: AppColors.paper,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: (_day - 1) / _totalDays,
                    minHeight: 6,
                    backgroundColor: AppColors.paper.withValues(alpha: 0.18),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.paper,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      cycleStart
                          ? Icons.flag_circle_outlined
                          : Icons.bolt_outlined,
                      size: 14,
                      color: AppColors.paper.withValues(alpha: 0.78),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        cycleStart
                            ? 'নতুন ৩০-দিনের প্ল্যান শুরু'
                            : (cycleEnd
                                ? 'শেষ দিন! কাল থেকে নতুন সাইকেল শুরু'
                                : 'প্রতিদিন একটি নতুন দিন স্বয়ংক্রিয়ভাবে শুরু হবে'),
                        style: TextStyle(
                          color: AppColors.paper.withValues(alpha: 0.78),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${_day.clamp(1, _totalDays)}/$_totalDays',
                      style: TextStyle(
                        color: AppColors.paper.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildDayNav(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Day-navigation strip embedded in the hero card. Lets the user
  /// browse yesterday / tomorrow's plan and jump straight back to
  /// today. Day values wrap around 1..[totalDays] so the user can
  /// tap ◀ forever without ever getting stuck on day 1.
  Widget _buildDayNav() {
    return Row(
      children: [
        _navBtn(
          icon: Icons.chevron_left_rounded,
          tooltip: 'আগের দিন',
          onTap: _goPrevDay,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Pressable(
            onTap: _showDayPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.paper.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.paper.withValues(alpha: 0.28),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  _todayDayIndex != null && _day != _todayDayIndex
                      ? 'দিন $_day থেকে $_totalDays দূরে — "আজ" এ ফিরতে ট্যাপ করুন'
                      : 'আগের/পরের দিন দেখুন',
                  style: const TextStyle(
                    color: AppColors.paper,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _navBtn(
          icon: Icons.chevron_right_rounded,
          tooltip: 'পরের দিন',
          onTap: _goNextDay,
        ),
        if (_todayDayIndex != null && _day != _todayDayIndex) ...[
          const SizedBox(width: 6),
          _navBtn(
            icon: Icons.today_rounded,
            tooltip: 'আজ',
            onTap: _goToday,
          ),
        ],
      ],
    );
  }

  Widget _navBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Pressable(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.paper.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.paper.withValues(alpha: 0.28),
              width: 1,
            ),
          ),
          child: Icon(icon, color: AppColors.paper, size: 24),
        ),
      ),
    );
  }

  void _goPrevDay() {
    final next = _day <= 1 ? _totalDays : _day - 1;
    setState(() => _day = next);
    _load();
  }

  void _goNextDay() {
    final next = _day >= _totalDays ? 1 : _day + 1;
    setState(() => _day = next);
    _load();
  }

  void _goToday() {
    final t = _todayDayIndex;
    if (t == null) return;
    setState(() => _day = t);
    _load();
  }

  Future<void> _showDayPicker() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.paper,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _DayPickerSheet(
        current: _day,
        total: _totalDays,
        today: _todayDayIndex,
      ),
    );
    if (picked != null && picked != _day) {
      setState(() => _day = picked);
      _load();
    }
  }

  Widget _buildBody() {
    if (_cls == null || _items.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: EmptyState(
          icon: Icons.no_meals,
          title: 'কোনো পরিকল্পনা নেই',
          message: 'আপনার প্রোফাইল আপডেট করে আবার চেষ্টা করুন।',
        ),
      );
    }

    final groups = <String, List<MealSlotPlan>>{
      'breakfast': [],
      'morning_snack': [],
      'lunch': [],
      'evening_snack': [],
      'dinner': [],
      'other': [],
    };
    for (final it in _items) {
      groups[it.slot]?.add(it);
    }

    final order = [
      'breakfast',
      'morning_snack',
      'lunch',
      'evening_snack',
      'dinner',
    ];
    final titles = {
      'breakfast': 'সকালের নাস্তা',
      'morning_snack': 'সকালের স্ন্যাক',
      'lunch': 'দুপুরের খাবার',
      'evening_snack': 'বিকেলের স্ন্যাক',
      'dinner': 'রাতের খাবার',
      'other': 'অন্যান্য',
    };
    final icons = {
      'breakfast': Icons.wb_sunny_outlined,
      'morning_snack': Icons.coffee_outlined,
      'lunch': Icons.lunch_dining_outlined,
      'evening_snack': Icons.cookie_outlined,
      'dinner': Icons.nightlight_outlined,
      'other': Icons.restaurant_outlined,
    };

    final kids = <Widget>[];
    kids.add(_buildClassificationBanner());
    kids.add(const SizedBox(height: 18));

    int counter = 0;
    for (final slot in order) {
      final list = groups[slot]!;
      if (list.isEmpty) continue;
      kids.add(_groupHeader(titles[slot]!, icons[slot]!));
      for (final item in list) {
        kids.add(StaggeredReveal(
          index: counter++,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildChecklistTile(item),
          ),
        ));
      }
      kids.add(const SizedBox(height: 10));
    }

    final others = groups['other']!;
    if (others.isNotEmpty) {
      kids.add(_groupHeader(titles['other']!, icons['other']!));
      for (final item in others) {
        kids.add(StaggeredReveal(
          index: counter++,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildChecklistTile(item),
          ),
        ));
      }
      kids.add(const SizedBox(height: 10));
    }

    kids.add(
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'এই পরিকল্পনা সাধারণ পুষ্টি নীতিমালার ওপর ভিত্তি করে তৈরি — চিকিৎসকের পরামর্শের বিকল্প নয়।',
          style: TextStyle(fontSize: 13, color: AppColors.smoke, height: 1.4),
        ),
      ),
    );

    return SliverList.list(children: kids);
  }

  Widget _buildClassificationBanner() {
    final cls = _cls!;
    if (cls.warnings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.chalk,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.graphite),
        ),
        child: const Row(
          children: [
            Icon(Icons.verified_outlined, color: AppColors.ink),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'আজকের পরিকল্পনা আপনার স্বাস্থ্য ও সাশ্রয়ী অবস্থার জন্য মানানসই',
                style: TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppGradients.aurora,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: AppColors.cyan.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.priority_high, size: 18, color: AppColors.ink),
              ),
              const SizedBox(width: 12),
              const Text(
                'গুরুত্বপূর্ণ তথ্য',
                style: TextStyle(
                  color: AppColors.paper,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final w in cls.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• $w',
                style: const TextStyle(
                  color: AppColors.paper,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(UserMealPlan entry) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: const Text('মুছে ফেলবেন?'),
        content: Text(
          '“${entry.displayName.isEmpty ? 'এই খাবার' : entry.displayName}” আজকের পরিকল্পনা থেকে সরানো হবে।',
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('বাতিল'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('মুছুন'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _addCustomEntry() async {
    final result = await PlanEditorSheet.show(
      context,
      date: _todayDate(),
    );
    if (result == null || !mounted) return;
    try {
      await SupabaseService.createUserMealPlan(
        effectiveDate: _todayDate(),
        slot: result.slot,
        scheduledTime: result.scheduledTime,
        foodId: result.foodId,
        customFoodName: result.customFoodName,
        portionLabel: result.portionLabel,
        notes: result.notes,
      );
      HapticFeedback.lightImpact();
      await _load();
      AppEvents.notifyMealLogged();
    } catch (e) {
      _showError('যোগ করা যায়নি: $e');
    }
  }

  Future<void> _editCustomEntry(UserMealPlan entry) async {
    final result = await PlanEditorSheet.show(
      context,
      date: _todayDate(),
      existing: entry,
    );
    if (result == null || !mounted) return;
    try {
      await SupabaseService.updateUserMealPlan(
        id: entry.id,
        effectiveDate: _todayDate(),
        slot: result.slot,
        scheduledTime: result.scheduledTime,
        clearScheduledTime: result.clearScheduledTime,
        foodId: result.foodId,
        clearFoodId: result.clearFoodId,
        customFoodName: result.customFoodName,
        portionLabel: result.portionLabel,
        notes: result.notes,
      );
      HapticFeedback.selectionClick();
      await _load();
      AppEvents.notifyMealLogged();
    } catch (e) {
      _showError('সম্পাদনা হয়নি: $e');
    }
  }

  Widget _groupHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 0, 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.chalk,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.graphite),
            ),
            child: Icon(icon, size: 20, color: AppColors.ink),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistTile(MealSlotPlan item) {
    final plannedKey = '${item.slot}|${item.food.id}';
    MealLogEntry? log = _todayLog[plannedKey];
    log ??= _todayLog['${item.slot}|'];
    log ??= _todayLog[item.slot];
    final tapped = log != null;
    final impact = log?.impact ?? 'good';
    final isCustom = item.isCustom;

    return RevealOnEnter(
      child: Pressable(
        onTap: () => isCustom
            ? _openCustomTile(item)
            : _openItemSheet(item),
        child: AnimatedContainer(
          duration: AppMotion.short,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: tapped ? AppGradients.aurora : null,
            color: tapped ? null : AppColors.paper,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: tapped ? Colors.transparent : AppColors.line,
              width: 1,
            ),
            boxShadow: tapped
                ? [
                    BoxShadow(
                      color: AppColors.cyan.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              AnimatedCheck(done: tapped),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.food.nameBn,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: tapped ? AppColors.void1 : AppColors.text,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.food.portionLabel ?? ''} · GI: ${ImpactEngine.giLabel(item.food.giCategory)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: tapped
                            ? AppColors.void1.withValues(alpha: 0.8)
                            : AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (tapped && log.impactReason != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            Icon(
                              impact == 'good'
                                  ? Icons.check_circle
                                  : impact == 'bad'
                                      ? Icons.error
                                      : Icons.info,
                              size: 14,
                              color: AppColors.void1.withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                log.impactReason!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.void1.withValues(alpha: 0.9),
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_outward,
                size: 22,
                color: tapped ? AppColors.void1 : AppColors.text,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// `_StripBtn` was removed when the day-strip nav was taken out —
// the active day is now locked to today's slot in the 30-day plan.

class _ThankYouToast extends StatelessWidget {
  const _ThankYouToast();

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Positioned(
      left: 20,
      right: 20,
      bottom: mq.padding.bottom + 110,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: AppColors.paper, size: 18),
                SizedBox(width: 10),
                Text(
                  'লগ হয়েছে',
                  style: TextStyle(
                    color: AppColors.paper,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Result of the action sheet.
class _ItemSheetResult {
  final MealItem? food;
  final String? customLabel;
  final String status; // eaten | swap | off_plan
  final String impact; // good | neutral | bad
  final String? reason;
  final String? notes;
  _ItemSheetResult({
    this.food,
    this.customLabel,
    required this.status,
    required this.impact,
    this.reason,
    this.notes,
  });

  /// Sentinel — AI-edit / reset buttons pop the sheet without
  /// committing a meal-log action.
  const _ItemSheetResult._noop()
      : food = null,
        customLabel = null,
        status = '',
        impact = '',
        reason = null,
        notes = null;

  bool get isNoop => status.isEmpty && impact.isEmpty && food == null;
}

class _ItemSheet extends StatefulWidget {
  final MealSlotPlan item;
  final Classification cls;
  final VoidCallback? onEditAi;
  final VoidCallback? onResetAi;
  const _ItemSheet({
    required this.item,
    required this.cls,
    this.onEditAi,
    this.onResetAi,
  });
  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  List<MealItem> _alts = [];
  bool _loading = true;
  String? _mode;
  final _customCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAlternatives();
  }

  Future<void> _loadAlternatives() async {
    try {
      final alts = await SupabaseService.getAlternatives(widget.item.food.id);
      if (!mounted) return;
      setState(() {
        _alts = alts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  MealImpact _judge(MealItem food) {
    return ImpactEngine.judge(
      food: food,
      original: widget.item.food,
      cls: widget.cls,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.graphite,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Overline('কী খাবেন?'),
                    Text(
                      widget.item.food.nameBn,
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.item.food.portionLabel ?? '',
                      style: const TextStyle(
                        color: AppColors.smoke,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _optionTile(
                      title: 'হ্যাঁ, এটাই খেয়েছি',
                      subtitle: 'পরিকল্পনা অনুযায়ী খাবার গ্রহণ',
                      icon: Icons.check,
                      onTap: _confirmEaten,
                    ),
                    const SizedBox(height: 10),
                    _optionTile(
                      title: 'বিকল্প খাবার খেয়েছি',
                      subtitle: 'প্রস্তাবিত বিকল্পগুলো থেকে বেছে নিন',
                      icon: Icons.swap_horiz,
                      onTap: () => setState(() => _mode = 'swap'),
                    ),
                    const SizedBox(height: 10),
                    _optionTile(
                      title: 'পরিকল্পনার বাইরে',
                      subtitle: 'অন্য কিছু খেয়ে থাকলে নাম লিখুন',
                      icon: Icons.edit_outlined,
                      onTap: () => setState(() => _mode = 'off'),
                    ),
                    if (widget.onEditAi != null) ...[
                      const SizedBox(height: 10),
                      _optionTile(
                        title: widget.item.isOverride
                            ? 'অন্য খাবার দিয়ে বদলান'
                            : 'এই খাবারটি বদলান',
                        subtitle: 'AI এর পরামর্শ এই দিনের জন্য বদলে যাবে',
                        icon: Icons.restaurant_menu,
                        onTap: widget.onEditAi!,
                      ),
                    ],
                    if (widget.onResetAi != null) ...[
                      const SizedBox(height: 10),
                      _optionTile(
                        title: 'AI এর আসল পরামর্শে ফেরত যান',
                        subtitle: 'বদলানো খাবার বাদ দিয়ে মূল পরিকল্পনা ফিরিয়ে আনুন',
                        icon: Icons.refresh,
                        onTap: widget.onResetAi!,
                      ),
                    ],
                    if (_mode == 'swap') _buildSwapList(),
                    if (_mode == 'off') _buildOffPlan(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.chalk,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.graphite),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: AppColors.paper),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.smoke,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, size: 22, color: AppColors.ink),
          ],
        ),
      ),
    );
  }

  Widget _buildSwapList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: LoadingMark(size: 28)),
      );
    }
    if (_alts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'কোনো বিকল্প পাওয়া যায়নি',
          style: TextStyle(color: AppColors.smoke),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('একটি বিকল্প বেছে নিন'),
          for (final alt in _alts) Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _altTile(alt),
          ),
        ],
      ),
    );
  }

  Widget _altTile(MealItem alt) {
    final impact = _judge(alt);

    return Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.pop(
          context,
          _ItemSheetResult(
            food: alt,
            status: 'swap',
            impact: impact.level,
            reason: impact.reason,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.graphite),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alt.nameBn,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${alt.portionLabel ?? ''} · GI: ${ImpactEngine.giLabel(alt.giCategory)}'
                    '${alt.isCheap ? " · সাশ্রয়ী" : ""}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.smoke,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    impact.reason,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, size: 22, color: AppColors.ink),
          ],
        ),
      ),
    );
  }

  Widget _buildOffPlan() {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('খাবারের নাম লিখুন'),
          TextField(
            controller: _customCtrl,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
            decoration: const InputDecoration(
              hintText: 'যেমন: বিরিয়ানি, চা-বিস্কুট',
              prefixIcon: Icon(Icons.edit_outlined),
            ),
          ),
          const SizedBox(height: 16),
          MonoButton(
            label: 'লগ করুন',
            leading: Icons.check,
            onPressed: () {
              final txt = _customCtrl.text.trim();
              if (txt.isEmpty) return;
              Navigator.pop(
                context,
                _ItemSheetResult(
                  customLabel: txt,
                  status: 'off_plan',
                  impact: 'neutral',
                  reason: 'পরিকল্পনার বাইরে',
                  notes: txt,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _confirmEaten() {
    final impact = _judge(widget.item.food);
    Navigator.pop(
      context,
      _ItemSheetResult(
        food: widget.item.food,
        status: 'eaten',
        impact: impact.level,
        reason: impact.reason,
      ),
    );
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }
}

/// Search-and-pick sheet for the master foods list. Used by
/// "Edit AI food" to replace the AI suggestion with a different
/// master food from `public.foods`.
class _FoodPickerSheet extends StatefulWidget {
  final String initialQuery;
  const _FoodPickerSheet({required this.initialQuery});

  @override
  State<_FoodPickerSheet> createState() => _FoodPickerSheetState();
}

class _FoodPickerSheetState extends State<_FoodPickerSheet> {
  late final TextEditingController _ctrl;
  List<MealItem> _results = const [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialQuery);
    _runSearch();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _ctrl.text.trim();
    setState(() => _loading = true);
    try {
      final list = await SupabaseService.searchFoods(q);
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.graphite,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'খাবার নির্বাচন',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 4),
              const Text(
                'মাস্টার তালিকা থেকে যেকোনো খাবার বেছে নিতে পারেন',
                style: TextStyle(
                  color: AppColors.smoke,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  hintText: 'খাবার খুঁজুন…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: AppColors.chalk,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _results.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'কোনো খাবার পাওয়া যায়নি',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.smoke,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (_, i) {
                              final f = _results[i];
                              return Pressable(
                                onTap: () => Navigator.pop(context, f),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: AppColors.chalk,
                                    borderRadius: BorderRadius.circular(AppRadius.md),
                                    border: Border.all(color: AppColors.graphite),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              f.nameBn.isEmpty ? '(নাম ছাড়া)' : f.nameBn,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.ink,
                                              ),
                                            ),
                                            if (f.portionLabel != null && f.portionLabel!.isNotEmpty)
                                              Text(
                                                f.portionLabel!,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.smoke,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        f.category,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.smoke,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal bottom sheet that lists all days in the current plan as a
/// scrollable grid. Pops the picked day index (1-based) when the
/// user taps a tile; tapping today (highlighted cyan) jumps there
/// immediately. Designed for elderly users: huge tiles, Bangla
/// labels, and a clear "আজ" jump button at the top.
class _DayPickerSheet extends StatelessWidget {
  const _DayPickerSheet({
    required this.current,
    required this.total,
    required this.today,
  });

  final int current;
  final int total;
  final int? today;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.smoke.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'দিন বাছাই করুন',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                if (today != null && today != current)
                  Pressable(
                    onTap: () => Navigator.of(context).pop(today),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.cyan,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: const Text(
                        'আজ',
                        style: TextStyle(
                          color: AppColors.paper,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'যেকোনো দিনের পরিকল্পনা দেখতে ট্যাপ করুন',
              style: TextStyle(
                color: AppColors.smoke,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 1; i <= total; i++)
                      _DayTile(
                        day: i,
                        isCurrent: i == current,
                        isToday: today != null && i == today,
                        onTap: () => Navigator.of(context).pop(i),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'মোট $total দিনের পরিকল্পনা',
                style: const TextStyle(
                  color: AppColors.smoke,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 0),
          ],
        ),
      ),
    );
  }
}

/// One row tile inside [_DayPickerSheet]. Highlights today's slot
/// (cyan ring), the currently-shown slot (filled cyan), and dims
/// anything else with a calm paper background.
class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.isCurrent,
    required this.isToday,
    required this.onTap,
  });

  final int day;
  final bool isCurrent;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = (MediaQuery.of(context).size.width - 20 * 2 - 10 * 4) / 5;
    final fill = isCurrent;
    final borderColor =
        isToday ? AppColors.cyan : AppColors.smoke.withValues(alpha: 0.18);
    final borderWidth = isToday ? 2.5 : 1.0;

    return Pressable(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill ? AppColors.cyan : AppColors.paper,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: fill
              ? [
                  BoxShadow(
                    color: AppColors.cyan.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                color: fill ? AppColors.paper : AppColors.ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isToday ? 'আজ' : 'দিন',
              style: TextStyle(
                color: fill
                    ? AppColors.paper.withValues(alpha: 0.85)
                    : AppColors.smoke,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
