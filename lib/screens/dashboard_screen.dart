import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/app_events.dart';
import '../models/dashboard.dart';
import '../models/medicine.dart';
import '../models/meal_item.dart';
import '../models/workout.dart';
import '../models/user_meal_plan.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    AppEvents.profileChanged.addListener(_onChanged);
    AppEvents.mealLogged.addListener(_onChanged);
    AppEvents.medicineChanged.addListener(_onChanged);
    AppEvents.workoutChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    AppEvents.profileChanged.removeListener(_onChanged);
    AppEvents.mealLogged.removeListener(_onChanged);
    AppEvents.medicineChanged.removeListener(_onChanged);
    AppEvents.workoutChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  Future<_DashboardData> _load() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(const Duration(days: 6));
    
    final summary = await SupabaseService.getDashboardSummary(days: 7);
    final weekNutrition = await SupabaseService.getWeeklyNutrition(days: 7);
    final mealAdherence = await SupabaseService.getMealAdherence(days: 7);
    final medAdherence = await SupabaseService.getMedicineAdherence(days: 7);
    final workoutAdherence = await SupabaseService.getWorkoutAdherence(days: 7);
    final todayWorkout = await SupabaseService.getTodayWorkout();
    
    final weekDates = List<DateTime>.generate(
      7,
      (i) => weekStart.add(Duration(days: i)),
    );

    final mealDayStatuses = await Future.wait(
      weekDates.map((d) async {
        final logs = await SupabaseService.getDailyLog(date: d);
        final groups = <String, List<MealLogEntry>>{};
        for (final l in logs) {
          groups.putIfAbsent(l.mealSlot, () => []).add(l);
        }
        return DailyMealLog(
          date: d,
          slots: groups.entries.map((e) => MealSlotGroup(slot: e.key, items: e.value)).toList(),
        );
      }),
    );

    final medDayStatuses = await Future.wait(
      weekDates.map((d) async {
        final doses = await SupabaseService.getMedicineDosesForDate(d);
        return DailyMedicines(date: d, doses: doses);
      }),
    );

    final workoutDayStatuses = await Future.wait(
      weekDates.map((d) => SupabaseService.getWorkoutLog(d)),
    );

    final mealPlans = await SupabaseService.getUserDayPlan(today);
    final mealPlan = mealPlans.isNotEmpty ? mealPlans.first : null;

    return _DashboardData(
      summary: summary,
      weekNutrition: weekNutrition,
      mealAdherence: mealAdherence,
      medAdherence: medAdherence,
      workoutAdherence: workoutAdherence,
      todayWorkout: todayWorkout,
      mealDayStatuses: mealDayStatuses,
      medDayStatuses: medDayStatuses,
      workoutDayStatuses: workoutDayStatuses,
      mealPlan: mealPlan,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          color: t.colors.paper,
        ),
        child: SafeArea(
          child: FutureBuilder<_DashboardData>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: LoadingMark());
              }
              if (snap.hasError) {
                return _ErrorState(error: snap.error!, onRetry: _onChanged);
              }
              final data = snap.data!;
              return RefreshIndicator(
                color: t.colors.ink,
                backgroundColor: t.colors.paper,
                onRefresh: () async => _onChanged(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                  children: [
                    _Header(today: DateTime.now()),
                    const SizedBox(height: AppSpacing.lg),
                    _TopStatsRow(
                      summary: data.summary,
                      mealAdherence: data.mealAdherence,
                      medAdherence: data.medAdherence,
                      workoutAdherence: data.workoutAdherence,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _NutritionCard(weekly: data.weekNutrition),
                    const SizedBox(height: AppSpacing.lg),
                    _MealAdherenceCard(
                      adherence: data.mealAdherence,
                      weekDates: _weekDates(),
                      statuses: data.mealDayStatuses,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _MedicineAdherenceCard(
                      adherence: data.medAdherence,
                      weekDates: _weekDates(),
                      statuses: data.medDayStatuses,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _WorkoutAdherenceCard(
                      adherence: data.workoutAdherence,
                      weekDates: _weekDates(),
                      statuses: data.workoutDayStatuses,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _TodayWorkoutPreview(workout: data.todayWorkout),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<DateTime> _weekDates() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return List<DateTime>.generate(
      7,
      (i) => today.subtract(Duration(days: 6 - i)),
    );
  }
}

class _DashboardData {
  final DashboardSummary summary;
  final List<DailyNutrition> weekNutrition;
  final MealAdherence mealAdherence;
  final MedicineAdherence medAdherence;
  final WorkoutAdherence workoutAdherence;
  final TodaysWorkout? todayWorkout;
  final List<DailyMealLog> mealDayStatuses;
  final List<DailyMedicines> medDayStatuses;
  final List<WorkoutLogRow> workoutDayStatuses;
  final UserMealPlan? mealPlan;

  _DashboardData({
    required this.summary,
    required this.weekNutrition,
    required this.mealAdherence,
    required this.medAdherence,
    required this.workoutAdherence,
    required this.todayWorkout,
    required this.mealDayStatuses,
    required this.medDayStatuses,
    required this.workoutDayStatuses,
    required this.mealPlan,
  });
}

class _Header extends StatelessWidget {
  final DateTime today;
  const _Header({required this.today});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Overline(_dateLabel(today)),
              const SizedBox(height: 6),
              Text(
                'সারসংক্ষেপ',
                style: t.text.display.copyWith(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: t.colors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'গত ৭ দিনের খাবার, ওষুধ ও ব্যায়ামের সারাংশ',
                style: t.text.body.copyWith(
                  color: t.colors.ink.withValues(alpha: .66),
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        MonoButton(
          label: 'রিফ্রেশ',
          leading: Icons.refresh_rounded,
          onPressed: () {
            AppEvents.notifyProfileChanged();
          },
        ),
      ],
    );
  }

  String _dateLabel(DateTime d) {
    const days = ['সোম', 'মঙ্গল', 'বুধ', 'বৃহ', 'শুক্র', 'শনি', 'রবি'];
    const months = [
      'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রি', 'মে', 'জুন',
      'জুলা', 'আগ', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে',
    ];
    return '${days[d.weekday - 1]} • ${d.day} ${months[d.month - 1]}';
  }
}

class _TopStatsRow extends StatelessWidget {
  final DashboardSummary summary;
  final MealAdherence mealAdherence;
  final MedicineAdherence medAdherence;
  final WorkoutAdherence workoutAdherence;

  const _TopStatsRow({
    required this.summary,
    required this.mealAdherence,
    required this.medAdherence,
    required this.workoutAdherence,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > 480;
        final cards = [
          _StatCard(
            title: 'খাবার',
            value: '${mealAdherence.takenPercent.toStringAsFixed(0)}%',
            sub: '${mealAdherence.eaten}/${mealAdherence.planned} আইটেম',
            icon: Icons.restaurant_menu_rounded,
            color: Colors.cyan,
          ),
          _StatCard(
            title: 'ওষুধ',
            value: '${medAdherence.takenPercent.toStringAsFixed(0)}%',
            sub: '${medAdherence.taken}/${medAdherence.totalDoses} ডোজ',
            icon: Icons.medication_rounded,
            color: Colors.purple,
          ),
          _StatCard(
            title: 'ব্যায়াম',
            value: '${workoutAdherence.completedPercent.toStringAsFixed(0)}%',
            sub: '${workoutAdherence.completed}/${workoutAdherence.totalSessions} সেট',
            icon: Icons.fitness_center_rounded,
            color: Colors.green,
          ),
        ];
        if (wide) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i != cards.length - 1) const SizedBox(width: AppSpacing.md),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              cards[i],
              if (i != cards.length - 1) const SizedBox(height: AppSpacing.md),
            ],
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String sub;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.sub,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return MonoCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.0,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sub,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _NutritionCard extends StatelessWidget {
  final List<DailyNutrition> weekly;
  const _NutritionCard({required this.weekly});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final maxCal = weekly
        .map((e) => e.calories)
        .fold<int>(0, (a, b) => a > b ? a : b)
        .clamp(100, 9999);
    final maxCarb = weekly
        .map((e) => e.carbs)
        .fold<int>(0, (a, b) => a > b ? a : b)
        .clamp(10, 999);
    return MonoCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('সাপ্তাহিক পুষ্টি', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 170,
            child: BarChart(
              BarChartData(
                maxY: maxCal.toDouble(),
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                barTouchData: BarTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => t.colors.ink,
                    getTooltipItem: (group, gIdx, rod, rIdx) {
                      final day = weekly[group.x.toInt()];
                      return BarTooltipItem(
                        '${_dayShort(day.date)}\n${day.calories} কিলোক্যালোরি',
                        t.text.body.copyWith(
                          color: t.colors.paper,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxCal / 4,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: t.colors.ink.withValues(alpha: .08),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: maxCal / 4,
                      getTitlesWidget: (v, _) => Text(
                        v.toInt().toString(),
                        style: t.text.micro.copyWith(fontSize: 10),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= weekly.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _dayShort(weekly[i].date),
                            style: t.text.micro.copyWith(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (var i = 0; i < weekly.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: weekly[i].calories.toDouble(),
                          width: 14,
                          borderRadius: BorderRadius.circular(4),
                          color: t.colors.ink,
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxCal.toDouble(),
                            color: t.colors.ink.withValues(alpha: .04),
                          ),
                        ),
                        BarChartRodData(
                          toY: weekly[i].carbs.toDouble() /
                              (maxCarb == 0 ? 1 : maxCarb) *
                              maxCal,
                          width: 14,
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.orange,
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxCal.toDouble(),
                            color: t.colors.ink.withValues(alpha: .04),
                          ),
                        ),
                      ],
                      barsSpace: 4,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _LegendDot(label: 'ক্যালোরি', color: t.colors.ink),
              const SizedBox(width: AppSpacing.lg),
              const _LegendDot(
                label: 'কার্বস',
                color: Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final String label;
  final Color? color;
  const _LegendDot({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _MealAdherenceCard extends StatelessWidget {
  final MealAdherence adherence;
  final List<DateTime> weekDates;
  final List<DailyMealLog> statuses;

  const _MealAdherenceCard({
    required this.adherence,
    required this.weekDates,
    required this.statuses,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final spots = <FlSpot>[];
    for (var i = 0; i < weekDates.length; i++) {
      final s = statuses[i];
      final total = s.slots.fold<int>(0, (a, b) => a + b.items.length);
      final taken = s.slots
          .expand((sl) => sl.items)
          .where((it) => it.status == 'eaten')
          .length;
      final pct = total == 0 ? 0.0 : (taken / total) * 100.0;
      spots.add(FlSpot(i.toDouble(), pct));
    }
    return MonoCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('খাবারের অগ্রগতি', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
              _PillBadge(
                text: '${adherence.takenPercent.toStringAsFixed(0)}% গড়',
                background: t.colors.ink,
                foreground: t.colors.paper,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: t.colors.ink.withValues(alpha: .06),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 25,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}%',
                        style: t.text.micro.copyWith(fontSize: 10),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= weekDates.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _dayShort(weekDates[i]),
                            style: t.text.micro.copyWith(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.32,
                    preventCurveOverShooting: true,
                    color: Colors.blue,
                    barWidth: 4,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                        radius: 4,
                        color: t.colors.paper,
                        strokeWidth: 2,
                        strokeColor: t.colors.ink,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.blue.withValues(alpha: 0.1),
                    ),
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

class _MedicineAdherenceCard extends StatelessWidget {
  final MedicineAdherence adherence;
  final List<DateTime> weekDates;
  final List<DailyMedicines> statuses;

  const _MedicineAdherenceCard({
    required this.adherence,
    required this.weekDates,
    required this.statuses,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final spots = <FlSpot>[];
    for (var i = 0; i < weekDates.length; i++) {
      final s = statuses[i];
      final total = s.doses.length;
      final taken = s.doses.where((d) => d.status == 'taken').length;
      final pct = total == 0 ? 0.0 : (taken / total) * 100.0;
      spots.add(FlSpot(i.toDouble(), pct));
    }
    return MonoCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('ওষুধের অনুসরণ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
              _PillBadge(
                text: '${adherence.takenPercent.toStringAsFixed(0)}% গড়',
                background: t.colors.ink,
                foreground: t.colors.paper,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 6,
                minY: 0,
                maxY: 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: t.colors.ink.withValues(alpha: .06),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 25,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}%',
                        style: t.text.micro.copyWith(fontSize: 10),
                      ),
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= weekDates.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _dayShort(weekDates[i]),
                            style: t.text.micro.copyWith(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.32,
                    preventCurveOverShooting: true,
                    color: Colors.purple,
                    barWidth: 4,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                        radius: 4,
                        color: t.colors.paper,
                        strokeWidth: 2,
                        strokeColor: Colors.purple,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.purple.withValues(alpha: 0.1),
                    ),
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

class _WorkoutAdherenceCard extends StatelessWidget {
  final WorkoutAdherence adherence;
  final List<DateTime> weekDates;
  final List<WorkoutLogRow> statuses;

  const _WorkoutAdherenceCard({
    required this.adherence,
    required this.weekDates,
    required this.statuses,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final mn = weeklyTotalMinutes();
    final cn = weeklyTotalCalories();
    return MonoCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('ব্যায়ামের সারসংক্ষেপ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
              _PillBadge(
                text: '${adherence.completedPercent.toStringAsFixed(0)}% সম্পন্ন',
                background: t.colors.ink,
                foreground: t.colors.paper,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _MiniStat(
                label: 'সময়',
                value: '$mn মিনিট',
                icon: Icons.timer_rounded,
              ),
              const SizedBox(width: AppSpacing.md),
              _MiniStat(
                label: 'ক্যালোরি',
                value: '$cn কিলোক্যালোরি',
                icon: Icons.local_fire_department_rounded,
              ),
              const SizedBox(width: AppSpacing.md),
              _MiniStat(
                label: 'দিন',
                value: '${adherence.daysActive}/${weekDates.length}',
                icon: Icons.event_available_rounded,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 90,
            child: BarChart(
              BarChartData(
                maxY: 100,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(
                  show: false,
                  drawVerticalLine: false,
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i < 0 || i >= weekDates.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _dayShort(weekDates[i]),
                            style: t.text.micro.copyWith(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  for (var i = 0; i < weekDates.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: _dayWorkoutPct(i),
                          width: 16,
                          color: t.colors.ink,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _dayWorkoutPct(int i) {
    if (i < 0 || i >= statuses.length) return 0;
    final row = statuses[i];
    final total = row.total;
    final completed = row.completed;
    if (total == 0) return 0;
    return (completed / total) * 100.0;
  }

  int weeklyTotalMinutes() {
    var s = 0;
    for (var i = 0; i < statuses.length; i++) {
      s += statuses[i].totalMinutes;
    }
    return s;
  }

  int weeklyTotalCalories() {
    var s = 0;
    for (var i = 0; i < statuses.length; i++) {
      s += statuses[i].totalCalories;
    }
    return s;
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.cyan),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayWorkoutPreview extends StatelessWidget {
  final TodaysWorkout? workout;
  const _TodayWorkoutPreview({required this.workout});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    final w = workout;
    return MonoCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('আজকের ব্যায়াম', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: AppSpacing.md),
          if (w == null)
            Text(
              'আজ কোনো ব্যায়াম নির্ধারিত নেই',
              style: t.text.body.copyWith(
                color: t.colors.ink.withValues(alpha: .6),
                fontSize: 14,
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'কর্মসূচী দিন ${w.dayIndex}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${w.assignments.length}টি ব্যায়াম',
                        style: t.text.body.copyWith(
                          color: t.colors.ink.withValues(alpha: .6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                _PillBadge(
                  text: '${w.completedCount}/${w.totalPlanned}',
                  background: t.colors.ink,
                  foreground: t.colors.paper,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;
  const _PillBadge({
    required this.text,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: .3,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: t.colors.ink, size: 42),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'ড্যাশবোর্ড লোড করা যাচ্ছে না',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: t.text.body.copyWith(
                color: t.colors.ink.withValues(alpha: .6),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            MonoButton(
              label: 'আবার চেষ্টা',
              leading: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

String _dayShort(DateTime d) {
  const days = ['সোম', 'মঙ্গল', 'বুধ', 'বৃহ', 'শুক্র', 'শনি', 'রবি'];
  return days[d.weekday - 1];
}
