import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../models/meal_item.dart';
import '../services/app_events.dart';

/// Analytics dashboard powered by `get_dashboard_summary` and
/// `get_weekly_nutrition`. Designed for elderly eyes:
///   • large numbers
///   • thick bars
///   • Bengali labels
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
      appBar: AppBar(
        title: const Text('ড্যাশবোর্ড'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 26),
            onPressed: _loading ? null : _load,
            tooltip: 'রিফ্রেশ',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('ত্রুটি: $_error'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _streakCard(),
                      const SizedBox(height: 12),
                      _impactRatioCard(),
                      const SizedBox(height: 12),
                      _weeklyBarChart(),
                      const SizedBox(height: 12),
                      _macroCard(),
                      const SizedBox(height: 12),
                      _recentCard(),
                    ],
                  ),
                ),
    );
  }

  Widget _streakCard() {
    final streak = (_summary?['streak_days'] ?? 0) as int;
    final total = (_summary?['total_items'] ?? 0) as int;
    return Card(
      color: const Color(0xFFE8F5E9),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xFF2E7D32),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.local_fire_department,
                  color: Colors.white, size: 32),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$streak দিন ধারাবাহিক ভালো পছন্দ',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('গত ৭ দিনে $totalটি খাবার লগ হয়েছে',
                      style: const TextStyle(fontSize: 14, color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _impactRatioCard() {
    final good = (_summary?['good'] ?? 0) as int;
    final neutral = (_summary?['neutral'] ?? 0) as int;
    final bad = (_summary?['bad'] ?? 0) as int;
    final total = good + neutral + bad;
    final goodPct = total == 0 ? 0 : ((good / total) * 100).round();
    final neutralPct = total == 0 ? 0 : ((neutral / total) * 100).round();
    final badPct = total == 0 ? 0 : ((bad / total) * 100).round();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('গত ৭ দিনের খাবারের প্রভাব',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 22,
                child: Row(
                  children: [
                    if (goodPct > 0)
                      Expanded(
                        flex: goodPct,
                        child: Container(color: const Color(0xFF2E7D32)),
                      ),
                    if (neutralPct > 0)
                      Expanded(
                        flex: neutralPct,
                        child: Container(color: const Color(0xFFB0BEC5)),
                      ),
                    if (badPct > 0)
                      Expanded(
                        flex: badPct,
                        child: Container(color: const Color(0xFFC62828)),
                      ),
                    if (total == 0)
                      const Expanded(
                        child: ColoredBox(color: Color(0xFFE0E0E0)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                _legendDot(const Color(0xFF2E7D32), 'ভালো', good, goodPct),
                _legendDot(const Color(0xFFB0BEC5), 'মাঝারি', neutral, neutralPct),
                _legendDot(const Color(0xFFC62828), 'খারাপ', bad, badPct),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label, int count, int pct) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 16, height: 16,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text('$label · $count ($pct%)',
          style: const TextStyle(fontSize: 15)),
    ]);
  }

  Widget _weeklyBarChart() {
    final byDay = (_summary?['by_day'] as List?) ?? [];
    if (byDay.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('গত ৭ দিনের খাবার', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text('এখনো কোনো লগ নেই — আজকের খাবার থেকে শুরু করুন',
                  style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final maxItems = byDay
        .map((d) => ((d as Map)['items'] ?? 0) as int)
        .fold<int>(0, (a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('দৈনিক খাবারের সারসংক্ষেপ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in byDay.reversed) _dayBar(d as Map, maxItems),
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
    final h = maxItems == 0 ? 0.0 : (items / maxItems);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('$items', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Container(
              height: 110 * h + 6,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                gradient: LinearGradient(
                  colors: bad > good
                      ? const [Color(0xFFC62828), Color(0xFFEF5350)]
                      : good > bad
                          ? const [Color(0xFF2E7D32), Color(0xFF66BB6A)]
                          : const [Color(0xFFB0BEC5), Color(0xFFECEFF1)],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(DateFormat('E', 'bn').format(date),
                style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _macroCard() {
    final n = _nutrition;
    if (n == null) return const SizedBox.shrink();
    final carb = ((n['carb_g'] ?? 0) as num).toDouble();
    final protein = ((n['protein_g'] ?? 0) as num).toDouble();
    final fat = ((n['fat_g'] ?? 0) as num).toDouble();
    final fiber = ((n['fiber_g'] ?? 0) as num).toDouble();
    final sodium = ((n['sodium_mg'] ?? 0) as num).toDouble();
    final days = ((n['days'] ?? 7) as num).toInt();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('গত $days দিনের গড় পুষ্টি (প্রতিদিন)',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _macroRow('কার্বোহাইড্রেট', carb / days, 'গ্রাম', const Color(0xFFEF6C00)),
            _macroRow('প্রোটিন', protein / days, 'গ্রাম', const Color(0xFF1565C0)),
            _macroRow('চর্বি', fat / days, 'গ্রাম', const Color(0xFF6A1B9A)),
            _macroRow('ফাইবার', fiber / days, 'গ্রাম', const Color(0xFF2E7D32)),
            const SizedBox(height: 6),
            _macroRow('সোডিয়াম', sodium / days, 'মিগ্রা', const Color(0xFFC62828)),
          ],
        ),
      ),
    );
  }

  Widget _macroRow(String label, double v, String unit, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 12, height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label, style: const TextStyle(fontSize: 15))),
          Text('${v.toStringAsFixed(1)} $unit',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _recentCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('আজকের খাবারের লগ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_recent.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('আজ এখনো কোনো খাবার লগ হয়নি',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              for (final e in _recent.take(20)) _logRow(e),
          ],
        ),
      ),
    );
  }

  Widget _logRow(MealLogEntry e) {
    final color = e.impact == 'good'
        ? const Color(0xFF2E7D32)
        : e.impact == 'bad'
            ? const Color(0xFFC62828)
            : const Color(0xFF6B6B6B);
    final icon = e.impact == 'good'
        ? Icons.check_circle
        : e.impact == 'bad'
            ? Icons.cancel
            : Icons.remove_circle_outline;
    final slotLabel = {
      'breakfast': 'সকালের নাস্তা',
      'morning_snack': 'সকালের স্ন্যাক',
      'lunch': 'দুপুর',
      'evening_snack': 'বিকেলের স্ন্যাক',
      'dinner': 'রাত',
    }[e.mealSlot] ?? e.mealSlot;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.foodNameBn,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text('$slotLabel · ${e.status == "eaten" ? "গ্রহণ" : e.status == "swap" ? "বিকল্প" : "বাইরে"}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if (e.impactReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(e.impactReason!, style: TextStyle(fontSize: 12, color: color)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}