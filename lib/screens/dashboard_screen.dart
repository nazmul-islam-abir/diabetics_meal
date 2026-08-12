import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/supabase_service.dart';
import '../models/meal_item.dart';
import '../services/app_events.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

/// Analytics dashboard powered by `get_dashboard_summary` and
/// `get_weekly_nutrition`. Pure monochrome editorial layout.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _nutrition;
  List<MealLogEntry> _recent = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    AppEvents.profileChanged.addListener(_refresh);
    AppEvents.mealLogged.addListener(_refresh);
  }

  @override
  void dispose() {
    AppEvents.profileChanged.removeListener(_refresh);
    AppEvents.mealLogged.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await SupabaseService.getDashboardSummary(days: 7);
      final n = await SupabaseService.getWeeklyNutrition(days: 7);
      final log = await SupabaseService.getDailyLog();
      if (!mounted) return;
      setState(() {
        _summary = s;
        _nutrition = n;
        _recent = log.reversed.toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      child: Text('ত্রুটি: $_error',
                          style: Theme.of(context).textTheme.bodyLarge),
                    ),
                  )
                : RefreshIndicator(
                    color: AppColors.ink,
                    backgroundColor: AppColors.paper,
                    onRefresh: _load,
                    child: CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(child: _buildTopBar()),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                          sliver: SliverList.list(children: _buildBody()),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Overline('সামগ্রিক চিত্র'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'ড্যাশবোর্ড',
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
          const SizedBox(height: 6),
          const Text(
            'গত ৭ দিনের খাবার ও পুষ্টির সারসংক্ষেপ',
            style: TextStyle(
              fontSize: 15,
              color: AppColors.smoke,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBody() {
    return [
      _streakCard(),
      const SizedBox(height: 14),
      _impactRatioCard(),
      const SizedBox(height: 14),
      _weeklyBarChart(),
      const SizedBox(height: 14),
      _macroCard(),
      const SizedBox(height: 14),
      _recentCard(),
    ];
  }

  // ────────────────────────────── Streak ──────────────────────────────
  Widget _streakCard() {
    final streak = (_summary?['streak_days'] ?? 0) as int;
    final total = (_summary?['total_items'] ?? 0) as int;
    return RevealOnEnter(
      delay: const Duration(milliseconds: 60),
      child: MonoCard(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.local_fire_department,
                            color: AppColors.paper, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'ধারাবাহিকতা',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      MonoCounter(
                        value: streak,
                        style: const TextStyle(
                          fontSize: 56,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          letterSpacing: -1.5,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'দিন',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'গত ৭ দিনে $totalটি খাবার লগ হয়েছে',
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.smoke,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            MonoRing(
              value: streak == 0 ? 0 : (streak.clamp(0, 7) / 7).toDouble(),
              size: 86,
              stroke: 8,
              child: Text(
                '৭',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────── Impact ratio ──────────────────────────────
  Widget _impactRatioCard() {
    final good = (_summary?['good'] ?? 0) as int;
    final neutral = (_summary?['neutral'] ?? 0) as int;
    final bad = (_summary?['bad'] ?? 0) as int;
    final total = good + neutral + bad;
    final goodPct = total == 0 ? 0 : ((good / total) * 100).round();
    final neutralPct = total == 0 ? 0 : ((neutral / total) * 100).round();
    final badPct = total == 0 ? 0 : ((bad / total) * 100).round();

    return RevealOnEnter(
      delay: const Duration(milliseconds: 120),
      child: MonoCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('গত ৭ দিনের খাবারের প্রভাব', padding: EdgeInsets.only(top: 0, bottom: 14)),
            if (total == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'এখনও কোনো খাবার লগ হয়নি',
                  style: TextStyle(color: AppColors.smoke, fontSize: 15),
                ),
              )
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 22,
                  child: Row(
                    children: [
                      if (goodPct > 0)
                        Expanded(
                          flex: goodPct,
                          child: AnimatedContainer(
                            duration: AppMotion.medium,
                            color: AppColors.ink,
                          ),
                        ),
                      if (neutralPct > 0)
                        Expanded(
                          flex: neutralPct,
                          child: AnimatedContainer(
                            duration: AppMotion.medium,
                            color: AppColors.ash,
                          ),
                        ),
                      if (badPct > 0)
                        Expanded(
                          flex: badPct,
                          child: AnimatedContainer(
                            duration: AppMotion.medium,
                            color: AppColors.graphite,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _legendBlock('ভালো', good, goodPct, AppColors.ink)),
                  const SizedBox(width: 10),
                  Expanded(child: _legendBlock('মাঝারি', neutral, neutralPct, AppColors.ash)),
                  const SizedBox(width: 10),
                  Expanded(child: _legendBlock('খারাপ', bad, badPct, AppColors.graphite)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legendBlock(String label, int count, int pct, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.chalk,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.graphite),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.smoke,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          MonoCounter(
            value: count,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              height: 1,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$pct%',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.smoke,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────── Weekly bar chart ──────────────────────────────
  Widget _weeklyBarChart() {
    final byDayRaw = (_summary?['by_day'] as List?) ?? [];
    final byDay = byDayRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    final maxItems = byDay
        .map((d) => (d['items'] ?? 0) as int)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return RevealOnEnter(
      delay: const Duration(milliseconds: 180),
      child: MonoCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('দৈনিক খাবারের সারসংক্ষেপ', padding: EdgeInsets.only(top: 0, bottom: 14)),
            SizedBox(
              height: 200,
              child: byDay.isEmpty
                  ? const Center(
                      child: Text(
                        'কোনো তথ্য নেই',
                        style: TextStyle(color: AppColors.smoke, fontSize: 15),
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final d in byDay.reversed) _dayBar(d, maxItems),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayBar(Map day, int maxItems) {
    final date = DateTime.parse(day['meal_date'] as String);
    final items = (day['items'] ?? 0) as int;
    final good = (day['good'] ?? 0) as int;
    final bad = (day['bad'] ?? 0) as int;
    final ratio = maxItems == 0 ? 0.0 : items / maxItems;
    final h = 110 * ratio + 8;
    final barColor = bad > good
        ? AppColors.graphite
        : good > bad
            ? AppColors.ink
            : AppColors.ash;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '$items',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: AppMotion.long,
              curve: AppMotion.emphasized,
              height: h,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              DateFormat('E', 'bn').format(date),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.smoke,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────── Macro card ──────────────────────────────
  Widget _macroCard() {
    final n = _nutrition;
    if (n == null) return const SizedBox.shrink();
    final carb = ((n['carb_g'] ?? 0) as num).toDouble();
    final protein = ((n['protein_g'] ?? 0) as num).toDouble();
    final fat = ((n['fat_g'] ?? 0) as num).toDouble();
    final fiber = ((n['fiber_g'] ?? 0) as num).toDouble();
    final sodium = ((n['sodium_mg'] ?? 0) as num).toDouble();
    final days = ((n['days'] ?? 7) as num).toInt();

    // Normalize against recommended daily ranges for visualization.
    final targets = <String, double>{
      'carb': 200.0,
      'protein': 70.0,
      'fat': 50.0,
      'fiber': 25.0,
    };
    final carbP = (carb / days) / targets['carb']!;
    final proP = (protein / days) / targets['protein']!;
    final fatP = (fat / days) / targets['fat']!;
    final fibP = (fiber / days) / targets['fiber']!;

    return RevealOnEnter(
      delay: const Duration(milliseconds: 240),
      child: MonoCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Overline('গত $days দিনের গড় পুষ্টি (প্রতিদিন)', padding: const EdgeInsets.only(top: 0, bottom: 14)),
            _macroRow('কার্বোহাইড্রেট', carb / days, 'গ্রাম', carbP.clamp(0.0, 1.0)),
            const SizedBox(height: 12),
            _macroRow('প্রোটিন', protein / days, 'গ্রাম', proP.clamp(0.0, 1.0)),
            const SizedBox(height: 12),
            _macroRow('চর্বি', fat / days, 'গ্রাম', fatP.clamp(0.0, 1.0)),
            const SizedBox(height: 12),
            _macroRow('ফাইবার', fiber / days, 'গ্রাম', fibP.clamp(0.0, 1.0)),
            const SizedBox(height: 12),
            _macroRow('সোডিয়াম', sodium / days, 'মিগ্রা', null, danger: true),
          ],
        ),
      ),
    );
  }

  Widget _macroRow(String label, double v, String unit, double? ratio, {bool danger = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppColors.ink,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            Text(
              '${v.toStringAsFixed(1)} $unit',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        if (ratio != null) ...[
          const SizedBox(height: 8),
          MonoBar(value: ratio, height: 6, fill: danger ? AppColors.graphite : AppColors.ink),
        ],
      ],
    );
  }

  // ────────────────────────────── Recent log ──────────────────────────────
  Widget _recentCard() {
    return RevealOnEnter(
      delay: const Duration(milliseconds: 300),
      child: MonoCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Overline('আজকের খাবারের লগ', padding: const EdgeInsets.only(top: 0, bottom: 12)),
            if (_recent.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.chalk,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.graphite),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.restaurant_outlined, color: AppColors.smoke, size: 28),
                    SizedBox(height: 8),
                    Text(
                      'আজ এখনও কোনো খাবার লগ হয়নি',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.smoke,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (int i = 0; i < _recent.length && i < 20; i++)
                StaggeredReveal(
                  index: i,
                  child: Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                    child: _logRow(_recent[i]),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _logRow(MealLogEntry e) {
    final isGood = e.impact == 'good';
    final isBad = e.impact == 'bad';
    final dotColor = isGood
        ? AppColors.ink
        : isBad
            ? AppColors.graphite
            : AppColors.ash;
    final icon = isGood
        ? Icons.check_circle
        : isBad
            ? Icons.cancel
            : Icons.remove_circle_outline;
    final slotLabel = {
      'breakfast': 'সকালের নাস্তা',
      'morning_snack': 'সকালের স্ন্যাক',
      'lunch': 'দুপুর',
      'evening_snack': 'বিকেলের স্ন্যাক',
      'dinner': 'রাত',
    }[e.mealSlot] ?? e.mealSlot;
    final statusLabel = e.status == 'eaten'
        ? 'গ্রহণ'
        : e.status == 'swap'
            ? 'বিকল্প'
            : 'বাইরে';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.chalk,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.graphite),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.paper,
              shape: BoxShape.circle,
              border: Border.all(color: dotColor, width: 1.6),
            ),
            child: Icon(icon, color: dotColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.foodNameBn,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    MonoBadge(text: slotLabel, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                    const SizedBox(width: 6),
                    MonoBadge(text: statusLabel, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                  ],
                ),
                if (e.impactReason != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    e.impactReason!,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.smoke,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}