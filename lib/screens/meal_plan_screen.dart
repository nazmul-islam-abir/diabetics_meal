import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/meal_item.dart';
import '../services/supabase_service.dart';
import '../services/impact_engine.dart';
import '../services/app_events.dart';

/// Today's meal plan as a checklist.
/// The user marks each item as eaten, swaps it, or logs an off-plan food.
class MealPlanScreen extends StatefulWidget {
  final int initialDay;
  const MealPlanScreen({super.key, this.initialDay = 1});

  @override
  State<MealPlanScreen> createState() => _MealPlanScreenState();
}

class _MealPlanScreenState extends State<MealPlanScreen> {
  late int _day;
  Classification? _cls;
  List<MealSlotPlan> _items = [];
  Map<String, MealLogEntry> _todayLog = {}; // keyed by "slot|role" for the current _day
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _day = widget.initialDay;
    _load();
    // Re-fetch whenever the user saves a new clinical profile. The
    // classification (CKD flag, glucose tier, carb cap) flows into the
    // daily recommendation, so the meal plan must refresh in lockstep.
    AppEvents.profileChanged.addListener(_onProfileChanged);
  }

  @override
  void dispose() {
    AppEvents.profileChanged.removeListener(_onProfileChanged);
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
        // Server already filters by plan_day; key by slot so a slot's
        // most recent entry wins (e.g. "lunch" with multiple rows for
        // carb/protein/vegetable). We deduplicate by role where possible.
        // Use slot+foodId fallback so distinct foods in the same slot
        // (lunch.carb vs lunch.protein) don't overwrite each other.
        final key = '${e.mealSlot}|${e.foodId ?? ''}';
        today[key] = e;
      }

      if (!mounted) return;
      setState(() {
        _cls = cls;
        _items = items;
        _todayLog = today;
      });
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
      addSlot('lunch', 'vegetable',
          (m['vegetable'] as Map?)?.cast<String, dynamic>());
      addSlot('lunch', 'dal', (m['dal'] as Map?)?.cast<String, dynamic>());
    }

    final dinner = data['dinner'];
    if (dinner is Map) {
      final m = Map<String, dynamic>.from(dinner);
      addSlot('dinner', 'carb', (m['carb'] as Map?)?.cast<String, dynamic>());
      addSlot('dinner', 'protein', (m['protein'] as Map?)?.cast<String, dynamic>());
      addSlot('dinner', 'vegetable',
          (m['vegetable'] as Map?)?.cast<String, dynamic>());
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
    setState(() => _day = next);
    _load();
  }

  Future<void> _openItemSheet(MealSlotPlan item) async {
    final result = await showModalBottomSheet<_ItemSheetResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
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
      // Notify the dashboard so its aggregates stay fresh.
      AppEvents.notifyMealLogged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _impactColor(r.impact).withValues(alpha: 0.92),
          content: Text(
            r.impact == 'good'
                ? '✓ ${r.customLabel ?? r.food?.nameBn ?? item.food.nameBn} — ভালো পছন্দ'
                : r.impact == 'bad'
                    ? '⚠ ${r.customLabel ?? r.food?.nameBn ?? item.food.nameBn} — ${r.reason ?? "এই বিকল্পটি সুপারিশকৃত নয়"}'
                    : '✓ ${r.customLabel ?? r.food?.nameBn ?? item.food.nameBn} লগ হয়েছে',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('লগ করা যায়নি: $e')),
        );
      }
    }
  }

  Color _impactColor(String impact) {
    switch (impact) {
      case 'good':
        return const Color(0xFF2E7D32);
      case 'bad':
        return const Color(0xFFC62828);
      default:
        return const Color(0xFF6B6B6B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dateLabel = DateFormat('d MMM, EEEE', 'bn').format(today);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('আজকের খাবার', style: Theme.of(context).textTheme.titleLarge),
            Text(dateLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 28),
            tooltip: 'আগের দিন',
            onPressed: () => _changeDay(-1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: Text('দিন $_day',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 28),
            tooltip: 'পরের দিন',
            onPressed: () => _changeDay(1),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('ত্রুটি: $_error', style: const TextStyle(fontSize: 16)),
                  ),
                )
              : _buildList(),
    );
  }

  Widget _buildList() {
    if (_cls == null || _items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('আজকের জন্য কোনো পরিকল্পনা পাওয়া যায়নি', style: TextStyle(fontSize: 16)),
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _classificationBanner(),
        const SizedBox(height: 12),
        for (final slot in order) ...[
          if (groups[slot]!.isNotEmpty) _groupHeader(titles[slot]!, icons[slot]!),
          for (final item in groups[slot]!) _checklistTile(item),
        ],
        const SizedBox(height: 16),
        const Text(
          'এই পরিকল্পনা সাধারণ পুষ্টি নীতিমালার ওপর ভিত্তি করে তৈরি — চিকিৎসকের পরামর্শের বিকল্প নয়।',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _classificationBanner() {
    final cls = _cls!;
    if (cls.warnings.isEmpty) {
      return Card(
        color: const Color(0xFFE8F5E9),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
              SizedBox(width: 8),
              Expanded(
                child: Text('আজকের পরিকল্পনা আপনার স্বাস্থ্য ও সাশ্রয়ী অবস্থার জন্য মানানসই',
                    style: TextStyle(fontSize: 15)),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      color: const Color(0xFFFFF4E5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.warning_amber, color: Color(0xFFEF6C00)),
              SizedBox(width: 8),
              Text('গুরুত্বপূর্ণ তথ্য',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ]),
            const SizedBox(height: 8),
            for (final w in cls.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $w', style: const TextStyle(fontSize: 14)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _groupHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 0, 8),
      child: Row(
        children: [
          Icon(icon, size: 24, color: const Color(0xFF0F6E56)),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _checklistTile(MealSlotPlan item) {
    // Look up this slot's log by the planned food id first (matches swaps
    // too), then fall back to any log entry for the slot. Because the
    // server already filtered by plan_day, day-2 ticks won't leak in.
    final plannedKey = '${item.slot}|${item.food.id}';
    MealLogEntry? log = _todayLog[plannedKey];
    log ??= _todayLog['${item.slot}|'];
    log ??= _todayLog[item.slot];
    final tapped = log != null;
    final impact = log?.impact ?? 'good';
    final color = _impactColor(impact);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openItemSheet(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tapped ? color : const Color(0xFFE0E0E0),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  tapped
                      ? (impact == 'good'
                          ? Icons.check
                          : impact == 'bad'
                              ? Icons.close
                              : Icons.check)
                      : Icons.circle_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.food.nameBn,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: tapped ? color : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item.food.portionLabel ?? ''} · GI: ${ImpactEngine.giLabel(item.food.giCategory)}',
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    if (tapped && log.impactReason != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          log.impactReason!,
                          style: TextStyle(fontSize: 13, color: color),
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 24, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

/// Result of the action sheet.
class _ItemSheetResult {
  final MealItem? food; // null = off-plan (custom name only)
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
  String? _mode; // 'eaten' | 'swap' | 'off'
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
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('আপনি কী খাবেন?',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${widget.item.food.nameBn} · ${widget.item.food.portionLabel ?? ''}',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 18),
            _optionTile(
              title: 'হ্যাঁ, এটাই খেয়েছি',
              subtitle: 'পরিকল্পনা অনুযায়ী খাবার গ্রহণ করা হয়েছে',
              icon: Icons.check_circle_outline,
              color: const Color(0xFF2E7D32),
              onTap: () => _confirmEaten(),
            ),
            _optionTile(
              title: 'বিকল্প খাবার খেয়েছি',
              subtitle: 'এই খাবারের বদলে অন্য কিছু খেয়েছি',
              icon: Icons.swap_horiz,
              color: const Color(0xFF1565C0),
              onTap: () => setState(() => _mode = 'swap'),
            ),
            _optionTile(
              title: 'পরিকল্পনার বাইরে অন্য কিছু খেয়েছি',
              subtitle: 'খাবারের নাম লিখুন',
              icon: Icons.edit_outlined,
              color: const Color(0xFF6A1B9A),
              onTap: () => setState(() => _mode = 'off'),
            ),
            if (_mode == 'swap') _buildSwapList(),
            if (_mode == 'off') _buildOffPlan(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _optionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 26),
        ),
        title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
        onTap: onTap,
      ),
    );
  }

  Widget _buildSwapList() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_alts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('কোনো বিকল্প পাওয়া যায়নি'),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('একটি বিকল্প বেছে নিন',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          for (final alt in _alts) _altTile(alt),
        ],
      ),
    );
  }

  Widget _altTile(MealItem alt) {
    final impact = _judge(alt);
    final color = impact.level == 'good'
        ? const Color(0xFF2E7D32)
        : impact.level == 'bad'
            ? const Color(0xFFC62828)
            : const Color(0xFF6B6B6B);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: () => Navigator.pop(
          context,
          _ItemSheetResult(
            food: alt,
            status: 'swap',
            impact: impact.level,
            reason: impact.reason,
          ),
        ),
        leading: Icon(
          impact.level == 'good'
              ? Icons.thumb_up_alt_outlined
              : impact.level == 'bad'
                  ? Icons.thumb_down_alt_outlined
                  : Icons.help_outline,
          color: color,
          size: 26,
        ),
        title: Text(alt.nameBn, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${alt.portionLabel ?? ''} · GI: ${ImpactEngine.giLabel(alt.giCategory)}'
              '${alt.isCheap ? " · সাশ্রয়ী" : ""}'
              '${alt.isLocal ? "" : " · আমদানি"}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(impact.reason, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildOffPlan() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _customCtrl,
            decoration: const InputDecoration(
              labelText: 'খাবারের নাম',
              border: OutlineInputBorder(),
              hintText: 'যেমন: বিরিয়ানি, চা-বিস্কুট',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('লগ করুন'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(120, 52),
            ),
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
    // The original food is itself the "good" choice if it passes impact rules.
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
