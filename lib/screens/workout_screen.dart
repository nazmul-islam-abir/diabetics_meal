import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/workout.dart';
import '../services/app_events.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import 'workout_details_screen.dart';

/// "ব্যায়াম" tab — today's workout for the 30-day program.
///
/// Loads the day's assignment list via `get_today_workout(p_day_index)`,
/// groups it into a hero progress card and a vertical list of tiles.
/// Each tile opens `WorkoutDetailsScreen` for the per-exercise timer.
///
/// Designed for the elderly user:
///   • 56 dp tap targets, oversized Bangla labels.
///   • Single chunky "শুরু করুন / পরবর্তী" call to action.
///   • Live progress (completed / total + elapsed time).
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  TodaysWorkout? _todays;
  WorkoutTimeTracking _tracking = WorkoutTimeTracking.empty;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    AppEvents.workoutChanged.addListener(_onChanged);
  }

  @override
  void dispose() {
    AppEvents.workoutChanged.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Make sure the user has assignments before fetching — idempotent.
      await SupabaseService.ensureDefaultWorkoutAssignments();
      // Also call the self-healing per-user RPC which re-activates
      // any soft-deactivated rows AND seeds the full 30-day plan for
      // this user. Together they guarantee the analytics + today list
      // always reflect every exercise the user is meant to do.
      await SupabaseService.seedMyWorkoutAssignments();
      // Day index is 1-based; we keep "today = dayIndex 1" for now and let
      // the day-progression work in `meal_plan_screen.dart` push it later.
      final results = await Future.wait([
        SupabaseService.getTodayWorkout(),
        SupabaseService.getWorkoutTimeRows(days: 7),
        SupabaseService.getTodayExerciseTimeFeedback(),
      ]);
      if (!mounted) return;
      final t = results[0] as TodaysWorkout?;
      final rows = (results[1] as List?)?.cast<WorkoutTimeRow>() ?? const [];
      final fb = (results[2] as Map?)?.cast<String, WorkoutExerciseTimeFeedback>() ?? const {};
      setState(() {
        _todays = t;
        _tracking = WorkoutTimeTracking(daily: rows, byWorkout: fb);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDetails(WorkoutAssignment assignment) async {
    final t = _todays;
    if (t == null) return;

    // If the session isn't open yet, start it now.
    WorkoutSession? session = t.session;
    if (session == null) {
      try {
        await SupabaseService.startWorkoutSession(dayIndex: t.dayIndex);
        // Reload so we have the freshly-created session + items.
        await _load();
        if (!mounted) return;
        session = _todays?.session;
        if (session == null) return;
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('সেশন শুরু করা যায়নি — আবার চেষ্টা করুন।')),
        );
        return;
      }
    }

    // We don't require a pre-existing session_item row anymore — the
    // `finish_workout_session_item` RPC lazy-creates it from
    // (sessionId, workoutId). That removes the "এই ব্যায়ামের সেশন
    // আইটেম পাওয়া যায়নি" snackbar that used to fire when a user
    // clicked a tile on a day the open session wasn't seeded for.
    // We still try to find the existing item first so that pre-seeded
    // rows get reused (cheaper + consistent with analytics).
    WorkoutSessionItem? existingItem;
    for (final it in session.items) {
      if (it.workoutId == assignment.workout.id) {
        existingItem = it;
        break;
      }
    }

    if (!mounted) return;
    final sessionId = session.id;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkoutDetailsScreen(
          assignment: assignment,
          sessionItemId: existingItem?.id,
          sessionId: sessionId,
        ),
      ),
    );
    AppEvents.notifyWorkoutChanged();
    _load();
  }

  Future<void> _startSession() async {
    final t = _todays;
    if (t == null) return;
    try {
      await SupabaseService.startWorkoutSession(dayIndex: t.dayIndex);
      AppEvents.notifyWorkoutChanged();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('শুরু করা যায়নি: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.ink,
          backgroundColor: AppColors.paper,
          onRefresh: _load,
          child: _loading
              ? const Center(child: LoadingMark(size: 36))
              : _error != null
                  ? _buildError()
                  : _todays == null
                      ? const SizedBox.shrink()
                      : CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(child: _buildHeader()),
                            if (_todays != null && _todays!.assignments.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: _buildEmpty(),
                              )
                            else if (_todays != null)
                              ..._buildAssignmentSlivers(),
                            const SliverToBoxAdapter(child: SizedBox(height: 120)),
                          ],
                        ),
        ),
      ),
    );
  }

  // ── Header / progress ────────────────────────────────────────────

  Widget _buildHeader() {
    final t = _todays!;
    final today = t.today;
    final total = t.assignments.length;
    final done = t.completedCount;
    final pct = t.progress;
    final elapsedMin = (t.session?.totalDurationSeconds ?? 0) ~/ 60;
    final started = t.session != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Overline('আজকের ব্যায়াম'),
                    const SizedBox(height: 6),
                    Text(
                      'দিন ${t.dayIndex} / ৩০',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('d MMMM, EEEE', 'bn').format(today),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.smoke,
                      ),
                    ),
                  ],
                ),
              ),
              if (!started && total > 0)
                MonoButton(
                  label: 'শুরু করুন',
                  leading: Icons.play_arrow_rounded,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  onPressed: _startSession,
                ),
            ],
          ),
          if (total > 0) ...[
            const SizedBox(height: 20),
            _buildProgressCard(
              done: done,
              total: total,
              pct: pct,
              elapsedMin: elapsedMin,
              started: started,
              finished: t.isFinished,
            ),
          ],
          if (_hasTrackingData()) ...[
            const SizedBox(height: 16),
            _buildTimeCard(),
          ],
        ],
      ),
    );
  }

  bool _hasTrackingData() {
    final daily = _tracking.daily;
    if (daily.isEmpty) return false;
    return daily.any((r) =>
        r.targetSeconds > 0 ||
        r.actualSeconds > 0 ||
        r.plannedCount > 0 ||
        r.completedCount > 0);
  }

  Widget _buildProgressCard({
    required int done,
    required int total,
    required double pct,
    required int elapsedMin,
    required bool started,
    required bool finished,
  }) {
    final headline = finished
        ? 'আজকের ব্যায়াম সম্পন্ন — চমৎকার!'
        : started
            ? 'চলছে — আরও ${total - done}টি বাকি'
            : 'আজকের $totalটি ব্যায়াম প্রস্তুত';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$done',
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  color: AppColors.paper,
                  height: 1.0,
                  letterSpacing: -1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Text(
                  '/$total টি',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.paper,
                    height: 1.0,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${(pct * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: AppColors.smoke,
              color: AppColors.paper,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.paper,
                  ),
                ),
              ),
              if (started && elapsedMin > 0)
                Text(
                  '$elapsedMin মিনিট',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.paper,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // "আজকের লক্ষ্য vs আপনার সময়" — daily target vs. actual minutes
  // with a 7-day sparkline beneath. Shows the user whether they're
  // actually meeting the suggested duration.
  Widget _buildTimeCard() {
    final today = _tracking.today;

    // Fallback to per-exercise feedback when the daily tracking RPC
    // returns target=0 for today (e.g., before sessions are recorded
    // or when program_day ≠ day_index 1). The feedback map is keyed by
    // workout id and reflects today's actual assignments + targets.
    final fbValues = _tracking.byWorkout.values.toList();
    final fbTarget = fbValues.fold<int>(0, (s, f) => s + f.targetMinutes);
    final fbActual = fbValues.fold<int>(0, (s, f) => s + f.actualMinutes);
    final fbPct = fbTarget == 0
        ? 0.0
        : (fbActual / fbTarget).clamp(0.0, 1.0);

    final chartT = today.targetMinutes;
    final chartA = today.actualMinutes;

    final hasFb = fbValues.isNotEmpty;
    final tMin = chartT > 0 ? chartT : (hasFb ? fbTarget : 0);
    final aMin = chartA > 0 ? chartA : (hasFb ? fbActual : 0);
    final tLabel = tMin > 0 ? '$tMin' : '০';
    final aLabel = aMin > 0 ? '$aMin' : '০';
    final pct = (today.pct > 0 ? today.pct : fbPct).clamp(0.0, 1.0);
    final weekTarget = _tracking.totalTargetMinutes;
    final weekActual = _tracking.totalActualMinutes;
    final weekPct = weekTarget == 0
        ? 0.0
        : (weekActual / weekTarget).clamp(0.0, 1.0);

    String headline;
    if (!hasFb && tMin == 0 && aMin == 0) {
      headline = 'আজকের জন্য নির্ধারিত কোনো ব্যায়াম নেই';
    } else if (hasFb && chartT == 0 && chartA == 0) {
      // Chart is empty for today (likely a fresh install) but the
      // per-exercise feedback knows we have assignments — say so.
      headline = 'আজকের লক্ষ্য: $tLabel মিনিট';
    } else if (tMin == 0) {
      headline = 'আপনি আজ $aLabel মিনিট ব্যায়াম করেছেন';
    } else if (aMin >= tMin) {
      headline = 'লক্ষ্য পূরণ! আজ $aLabel মিনিট করেছেন (লক্ষ্য $tLabel)';
    } else if (aMin > 0) {
      final left = tMin - aMin;
      headline = 'আরও $left মিনিট বাকি — লক্ষ্য $tLabel, করেছেন $aLabel';
    } else {
      headline = 'আজকের লক্ষ্য: $tLabel মিনিট';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.chalk, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('সময় ট্র্যাকিং'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                aLabel,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  height: 1.0,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4),
                child: Text(
                  '/ $tLabel মিনিট',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.smoke,
                  ),
                ),
              ),
              const Spacer(),
              _buildTimePctBadge(pct),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: AppColors.chalk,
              color: _pctColor(pct),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            headline,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          _buildWeekRow(),
          const SizedBox(height: 6),
          Text(
            'এই ৭ দিনে: $weekActual / $weekTarget মিনিট  •  ${(weekPct * 100).round()}%',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.smoke,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekRow() {
    final rows = _tracking.daily;
    if (rows.isEmpty) return const SizedBox.shrink();
    final maxTarget = rows
        .map((r) => r.targetSeconds)
        .fold<int>(0, (m, v) => v > m ? v : m);
    return SizedBox(
      height: 64,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final r in rows)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _buildDayBar(r, maxTarget),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayBar(WorkoutTimeRow r, int maxTarget) {
    final t = r.targetSeconds;
    final a = r.actualSeconds;
    const maxH = 44.0;
    final targetH = maxTarget == 0 ? 0.0 : (t / maxTarget) * maxH;
    final actualH = t == 0 ? 0.0 : (a / t).clamp(0.0, 1.0) * targetH;
    final empty = t == 0 && a == 0;
    final label = _weekdayShort(r.day);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: maxH,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                height: maxH,
                decoration: BoxDecoration(
                  color: AppColors.chalk,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                height: targetH == 0 ? 0 : targetH,
                decoration: BoxDecoration(
                  color: empty ? AppColors.chalk : AppColors.smoke,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Container(
                height: actualH,
                decoration: BoxDecoration(
                  color: _pctColor(r.pct),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: AppColors.smoke,
          ),
        ),
      ],
    );
  }

  String _weekdayShort(DateTime d) {
    switch (d.weekday) {
      case DateTime.monday:
        return 'সোম';
      case DateTime.tuesday:
        return 'মঙ্গল';
      case DateTime.wednesday:
        return 'বুধ';
      case DateTime.thursday:
        return 'বৃহঃ';
      case DateTime.friday:
        return 'শুক্র';
      case DateTime.saturday:
        return 'শনি';
      case DateTime.sunday:
        return 'রবি';
    }
    return '';
  }

  Widget _buildTimePctBadge(double pct) {
    final pctInt = (pct * 100).round();
    final color = _pctColor(pct);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$pctInt%',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.paper,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Color _pctColor(double pct) {
    if (pct >= 0.95) return AppColors.ink;
    if (pct >= 0.5) return AppColors.graphite;
    return AppColors.smoke;
  }

  // ── List ─────────────────────────────────────────────────────────

  List<Widget> _buildAssignmentSlivers() {
    final t = _todays!;
    final items = <Widget>[];
    items.add(const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
        child: Overline('আজকের রুটিন'),
      ),
    ));

    final ordered = [...t.assignments]
      ..sort((a, b) => a.position.compareTo(b.position));

    for (final a in ordered) {
      items.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          child: _AssignmentTile(
            assignment: a,
            item: _findItem(a),
            feedback: _tracking.byWorkout[a.workout.id],
            onTap: () => _openDetails(a),
          ),
        ),
      ));
    }
    return items;
  }

  WorkoutSessionItem? _findItem(WorkoutAssignment a) {
    final session = _todays?.session;
    if (session == null) return null;
    for (final it in session.items) {
      if (it.workoutId == a.workout.id) return it;
    }
    return null;
  }

  // ── States ───────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.fitness_center,
                  color: AppColors.paper, size: 36),
            ),
            const SizedBox(height: 18),
            Text(
              'আজকের জন্য কোনো ব্যায়াম নেই',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'পরে আবার দেখুন — প্রোগ্রাম স্বয়ংক্রিয়ভাবে চলবে।',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.smoke,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56, color: AppColors.ink),
            const SizedBox(height: 12),
            Text('লোড করা যায়নি', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.smoke, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            MonoButton(label: 'আবার চেষ্টা করুন', onPressed: _load),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────

class _AssignmentTile extends StatelessWidget {
  final WorkoutAssignment assignment;
  final WorkoutSessionItem? item;
  final WorkoutExerciseTimeFeedback? feedback;
  final VoidCallback onTap;

  const _AssignmentTile({
    required this.assignment,
    required this.item,
    required this.onTap,
    this.feedback,
  });

  @override
  Widget build(BuildContext context) {
    final w = assignment.workout;
    final completed = item?.isCompleted ?? false;
    final categoryLabel = w.category.labelBn;
    final intensityLabel = w.intensity.labelBn;
    final bg = completed ? AppColors.ink : AppColors.surface;
    final fg = completed ? AppColors.paper : AppColors.smoke;
    final pillBg = completed ? AppColors.ink : AppColors.paper;

    final pills = <Widget>[];
    pills.add(_buildPill('$categoryLabel · $intensityLabel', fg, pillBg));
    pills.add(_buildPill(w.targetDurationLabel, fg, pillBg));
    if (w.targetCaloriesKcal > 0) {
      pills.add(_buildPill('${w.targetCaloriesKcal} ক্যাল', fg, pillBg));
    }
    if (w.setsRepsLabel != null) {
      pills.add(_buildPill(w.setsRepsLabel!, fg, pillBg));
    }
    if (w.chairSupported) {
      pills.add(_buildPill('চেয়ার-সাপোর্টেড', fg, pillBg));
    }
    if (w.videoUrl != null && w.videoUrl!.trim().isNotEmpty) {
      pills.add(_buildVideoPill(fg, pillBg));
    }
    final fb = feedback;
    if (fb != null && fb.targetSeconds > 0) {
      pills.add(_buildTimePill(fb, completed));
    }

    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.chalk, width: 1),
        ),
        child: Row(
          children: [
            _buildCheck(completed),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.nameBn,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: completed ? AppColors.paper : AppColors.ink,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: pills,
                  ),
                  if (fb != null && fb.targetSeconds > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _buildTimeProgressBar(fb, completed),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: completed ? AppColors.paper : AppColors.ink, size: 26),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePill(WorkoutExerciseTimeFeedback fb, bool completed) {
    final IconData icon;
    final Color fg;
    final Color bg;
    if (fb.status == 'met') {
      icon = Icons.check_circle_rounded;
      fg = completed ? AppColors.paper : AppColors.ink;
      bg = completed ? AppColors.ink : AppColors.paper;
    } else if (fb.status == 'partial') {
      icon = Icons.timer_rounded;
      fg = completed ? AppColors.paper : AppColors.ink;
      bg = completed ? AppColors.ink : AppColors.paper;
    } else {
      icon = Icons.timer_outlined;
      fg = completed ? AppColors.paper : AppColors.smoke;
      bg = completed ? AppColors.ink : AppColors.paper;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            fb.hintBn,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: fg,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeProgressBar(WorkoutExerciseTimeFeedback fb, bool completed) {
    final pct = fb.pct.clamp(0.0, 1.0);
    final fg = completed ? AppColors.paper : AppColors.ink;
    final bg = completed ? AppColors.smoke : AppColors.chalk;
    final fill = fb.status == 'met'
        ? (completed ? AppColors.paper : AppColors.ink)
        : (completed ? AppColors.smoke : AppColors.graphite);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 5,
            backgroundColor: bg,
            color: fill,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          fb.status == 'met'
              ? 'সময় পূরণ হয়েছে — দারুণ!'
              : fb.status == 'partial'
                  ? 'চলছে — ${fb.actualMinutes}/${fb.targetMinutes} মিনিট'
                  : 'সুপারিশকৃত ${fb.targetMinutes} মিনিট',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ],
    );
  }

  Widget _buildCheck(bool completed) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: completed ? AppColors.paper : AppColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: completed ? AppColors.paper : AppColors.ink, width: 2),
      ),
      child: Icon(
        completed ? Icons.check_rounded : Icons.timer_outlined,
        color: completed ? AppColors.ink : AppColors.ink,
        size: 22,
      ),
    );
  }

  Widget _buildPill(String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildVideoPill(Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_circle_fill_rounded, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            'ভিডিও',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: fg,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}