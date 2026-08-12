import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/meal_item.dart';
import '../services/supabase_service.dart';
import '../services/impact_engine.dart';
import '../services/app_events.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

/// Today's meal plan as a checklist.
/// The user marks each item as eaten, swaps it, or logs an off-plan food.
class MealPlanScreen extends StatefulWidget {
  final int initialDay;
  const MealPlanScreen({super.key, this.initialDay = 1});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> with TickerProviderStateMixin {
  late int _day;
  Classification? _cls;
  List<MealSlotPlan> _items = [];
  Map<String, MealLogEntry> _todayLog = {};
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
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await SupabaseService.getDailyRecommendation(_day);
      final clsJson = Map<String, dynamic>.from(result['classification'] as Map);
      final cls = Classification.fromJson(clsJson);
      final items = _expandPlan(result);

      final log = await SupabaseService.getDailyLog(planDay: _day);
      final today = <String, MealLogEntry>{};
      for (final e in log) {
        final key = '${e.mealSlot}|${e.foodId ?? ''}';
        today[key] = e;
      }

      if (!mounted) return;
      setState(() {
        _cls = cls;
        _items = items;
        _todayLog = today;
      });
      _entry.forward(from: 0);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Flatten the plan JSON into a list of MealSlotPlan.
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

  void _changeDay(int delta) {
    final next = _day + delta;
    if (next < 1 || next > 30) return;
    HapticFeedback.selectionClick();
    setState(() => _day = next);
    _load();
  }

  Future<void> _openItemSheet(MealSlotPlan item) async {
    final result = await showModalBottomSheet<_ItemSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      builder: (ctx) => _ItemSheet(item: item, cls: _cls!),
    );
    if (result == null) return;
    await _applyItemAction(item, result);
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
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
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
          Overline('আজকের পরিকল্পনা'),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'আজকের\nখাবার',
                  style: Theme.of(context).textTheme.displaySmall,
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
    final completed = _todayLog.values.length;
    final total = _items.length;
    final pct = total == 0 ? 0.0 : completed / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(AppRadius.lg),
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
                            'দিন $_day',
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    Pressable(
                      onTap: () => _changeDay(-1),
                      borderRadius: BorderRadius.circular(28),
                      child: const _StripBtn(icon: Icons.arrow_back, label: 'আগের'),
                    ),
                    const Spacer(),
                    Text(
                      '১ — ৩০ দিন',
                      style: TextStyle(
                        color: AppColors.paper.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Pressable(
                      onTap: () => _changeDay(1),
                      borderRadius: BorderRadius.circular(28),
                      child: const _StripBtn(icon: Icons.arrow_forward, label: 'পরের', trailing: true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_cls == null || _items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: const EmptyState(
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
    };
    for (final it in _items) {
      groups[it.slot]?.add(it);
    }

    final order = ['breakfast', 'morning_snack', 'lunch', 'evening_snack', 'dinner'];
    final titles = {
      'breakfast': 'সকালের নাস্তা',
      'morning_snack': 'সকালের স্ন্যাক',
      'lunch': 'দুপুরের খাবার',
      'evening_snack': 'বিকেলের স্ন্যাক',
      'dinner': 'রাতের খাবার',
    };
    final icons = {
      'breakfast': Icons.wb_sunny_outlined,
      'morning_snack': Icons.coffee_outlined,
      'lunch': Icons.lunch_dining_outlined,
      'evening_snack': Icons.cookie_outlined,
      'dinner': Icons.nightlight_outlined,
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
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.lg),
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

    return RevealOnEnter(
      child: Pressable(
        onTap: () => _openItemSheet(item),
        child: AnimatedContainer(
          duration: AppMotion.short,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: tapped ? AppColors.ink : AppColors.paper,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: tapped ? AppColors.ink : AppColors.graphite,
              width: 1,
            ),
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
                        color: tapped ? AppColors.paper : AppColors.ink,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.food.portionLabel ?? ''} · GI: ${ImpactEngine.giLabel(item.food.giCategory)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: tapped
                            ? AppColors.paper.withValues(alpha: 0.7)
                            : AppColors.smoke,
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
                              color: AppColors.paper.withValues(alpha: 0.85),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                log.impactReason!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.paper.withValues(alpha: 0.85),
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
                color: tapped ? AppColors.paper : AppColors.ink,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StripBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool trailing;
  const _StripBtn({required this.icon, required this.label, this.trailing = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.paper.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!trailing) Icon(icon, size: 16, color: AppColors.paper),
          if (!trailing) const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.paper,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (trailing) const SizedBox(width: 6),
          if (trailing) Icon(icon, size: 16, color: AppColors.paper),
        ],
      ),
    );
  }
}

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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
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
}

class _ItemSheet extends StatefulWidget {
  final MealSlotPlan item;
  final Classification cls;
  const _ItemSheet({required this.item, required this.cls});
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
                    Overline('কী খাবেন?'),
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
          Overline('একটি বিকল্প বেছে নিন'),
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
          Overline('খাবারের নাম লিখুন'),
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
