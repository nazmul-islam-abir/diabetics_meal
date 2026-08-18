import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/workout.dart';
import '../services/app_events.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/mono_widgets.dart';
import '../widgets/workout_video_player.dart';

/// Per-exercise screen with a large countdown timer.
///
/// Behavior:
///   • The first time you open an exercise today, the timer reads whatever
///     you've already accumulated (from earlier today). Multiple
///     start/pause cycles add to that total — never reset.
///   • Pressing the center button toggles start/pause; pause auto-saves
///     the elapsed seconds to Supabase (no manual "save" dialog).
///   • Pressing "সম্পন্ন করুন" marks the exercise complete and pops back.
///
/// [sessionItemId] is optional: the underlying RPC lazy-creates the
/// session_item row from (sessionId, workoutId) when only the pair is
/// provided. That removes the "session item not found" error that used
/// to fire when a user clicked a tile on a different program day than
/// the session was originally opened for.
class WorkoutDetailsScreen extends StatefulWidget {
  final WorkoutAssignment assignment;
  final String? sessionItemId;
  final String sessionId;

  const WorkoutDetailsScreen({
    super.key,
    required this.assignment,
    required this.sessionId,
    this.sessionItemId,
  });

  @override
  State<WorkoutDetailsScreen> createState() => _WorkoutDetailsScreenState();
}

class _WorkoutDetailsScreenState extends State<WorkoutDetailsScreen> {
  Timer? _ticker;

  /// Persisted seconds already saved for this exercise today (e.g. from
  /// an earlier session). Loaded once in [initState] and treated as the
  /// cumulative baseline — it never goes down.
  int _baseSeconds = 0;

  /// Seconds accumulated in the current active run; resets to 0 on pause.
  int _runSeconds = 0;

  bool _running = false;
  bool _completed = false;
  bool _saving = false;

  /// True once the demo video has played through (or the user skipped
  /// it). The video is purely informational — the timer can be used
  /// independently at any moment.
  bool _videoDone = false;

  int get _totalSeconds => _baseSeconds + _runSeconds;

  @override
  void initState() {
    super.initState();
    // Load any previously logged duration for this exercise today so the
    // countdown reflects cumulative progress (e.g. 2 min walked at 7am
    // + current run = total so far).
    _loadBaseline();
  }

  Future<void> _loadBaseline() async {
    try {
      final map = await SupabaseService.getTodayExerciseTimeFeedback();
      final fb = map[widget.assignment.workout.id];
      if (!mounted) return;
      setState(() {
        _baseSeconds = fb?.actualSeconds ?? 0;
        _completed = (fb?.actualSeconds ?? 0) >=
            (widget.assignment.workout.targetDurationSeconds);
      });
    } catch (_) {
      // Baseline is best-effort; if the RPC fails the timer just starts
      // from zero — analytics still work on the next page load.
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _toggleTimer() {
    HapticFeedback.selectionClick();
    if (_completed) return;
    if (_running) {
      _pause();
    } else {
      _start();
    }
  }

  void _start() {
    if (_running || _completed) return;
    setState(() => _running = true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _runSeconds += 1);
    });
  }

  Future<void> _pause() async {
    if (!_running) return;
    _ticker?.cancel();
    _ticker = null;
    final runAtPause = _runSeconds;
    setState(() {
      _running = false;
      // Optimistically roll the run into the baseline so the display
      // doesn't visually jump back to the saved value while the RPC
      // is in flight.
      _baseSeconds += runAtPause;
      _runSeconds = 0;
    });
    if (runAtPause <= 0) return;
    await _persist(seconds: _baseSeconds, completed: false, runAtPause: runAtPause);
  }

  Future<void> _persist({
    required int seconds,
    required bool completed,
    int? runAtPause,
  }) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // The RPC is idempotent on (session_id, workout_id): when no
      // itemId is provided it upserts the session_item row, so we can
      // safely call it on every pause / completion without worrying
      // about which program day the session was opened for.
      await SupabaseService.finishWorkoutSessionItem(
        itemId: widget.sessionItemId,
        sessionId: widget.sessionId,
        workoutId: widget.assignment.workout.id,
        durationSeconds: seconds,
        completed: completed,
      );
      AppEvents.notifyWorkoutChanged();
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (completed) _completed = true;
        // If we already rolled the optimistic seconds into _baseSeconds
        // before awaiting, undo that delta now so the math stays clean.
        if (runAtPause != null && runAtPause > 0) {
          _baseSeconds -= runAtPause;
        }
        _baseSeconds = seconds;
      });
    } catch (_) {
      // Silent failure — the timer's optimistic state already kept the
      // user moving; the next loadBaseline() will reconcile with the DB.
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  Future<void> _markCompleted() async {
    HapticFeedback.mediumImpact();
    _ticker?.cancel();
    _ticker = null;
    final run = _runSeconds;
    setState(() {
      _running = false;
      _baseSeconds += run;
      _runSeconds = 0;
    });
    await _persist(seconds: _baseSeconds, completed: true, runAtPause: run);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.assignment.workout;
    final targetSec = w.targetDurationSeconds;
    final progress = targetSec <= 0
        ? 0.0
        : (_totalSeconds / targetSec).clamp(0.0, 1.0);
    final overshoot = targetSec > 0 && _totalSeconds > targetSec;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop && _running) {
          _ticker?.cancel();
          _ticker = null;
          await _pause();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.paper,
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(w)),
              SliverToBoxAdapter(child: _buildVideoSection(w)),
              SliverToBoxAdapter(child: _buildTimerCard(progress, overshoot)),
              if (w.descriptionBn.isNotEmpty)
                SliverToBoxAdapter(child: _buildDescription(w)),
              SliverToBoxAdapter(child: _buildDetails(w)),
              if (w.equipment.isNotEmpty)
                SliverToBoxAdapter(child: _buildEquipment(w)),
              if (w.instructions.isNotEmpty)
                SliverToBoxAdapter(child: _buildInstructions(w)),
              if (_hasSafetyOrContra(w))
                SliverToBoxAdapter(child: _buildSafety(w)),
              SliverToBoxAdapter(child: _buildControls()),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasSafetyOrContra(Workout w) =>
      (w.safetyNotesBn != null && w.safetyNotesBn!.trim().isNotEmpty) ||
      (w.contraindications != null && w.contraindications!.trim().isNotEmpty);

  Widget _buildHeader(Workout w) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          MonoButton(
            label: '',
            leading: Icons.arrow_back_rounded,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Overline('ব্যায়াম'),
                const SizedBox(height: 4),
                Text(w.nameBn,
                    style: Theme.of(context).textTheme.headlineSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoSection(Workout w) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkoutVideoPlayer(
            storagePath: w.videoUrl,
            label: w.nameBn,
            autoLoop: false,
            onFinished: _onVideoFinished,
            onSkip: _onVideoFinished,
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'ভিডিওটি দেখে অনুশীলন শুরু করুন — চাইলে স্কিপ করতে পারেন',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onVideoFinished() {
    if (_videoDone || !mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _videoDone = true);
  }

  Widget _buildTimerCard(double progress, bool overshoot) {
    final remaining = (widget.assignment.workout.targetDurationSeconds - _totalSeconds)
        .clamp(0, widget.assignment.workout.targetDurationSeconds);
    final subtitle = _running
        ? 'গণনা চলছে • এই রানে ${_fmt(_runSeconds)}'
        : _completed
            ? 'লক্ষ্য পূরণ — আজ মোট ${_fmt(_baseSeconds)}'
            : _baseSeconds > 0
                ? 'আজ ${_fmt(_baseSeconds)} হয়েছে • বাকি ${_fmt(remaining)}'
                : 'লক্ষ্য ${_fmt(widget.assignment.workout.targetDurationSeconds)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Column(
          children: [
            MonoRing(
              value: progress.clamp(0.0, 1.0),
              size: 240,
              stroke: 12,
              track: Colors.white.withValues(alpha: 0.18),
              fill: AppColors.cyan,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _fmt(_totalSeconds),
                    style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.w900,
                      color: AppColors.void1,
                      letterSpacing: -1.5,
                      height: 1.0,
                      fontFeatures: [FontFeature.tabularFigures()],
                      // Subtle glow, not a heavy shadow. The previous
                      // 0x88000000 shadow made the white digits look
                      // dark on OLED; the user reported the countdown
                      // text was unreadable. A faint colored glow keeps
                      // the digits crisp against the dark ring fill.
                      shadows: [
                        Shadow(
                          color: Color(0x33000000),
                          offset: Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.void1.withValues(alpha: 0.92),
                      letterSpacing: 0.3,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildCenterToggle(),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _buildMetaPill(
                    'তীব্রতা ${widget.assignment.workout.intensity.labelBn}'),
                if (widget.assignment.workout.targetCaloriesKcal > 0)
                  _buildMetaPill(
                      '${widget.assignment.workout.targetCaloriesKcal} ক্যাল'),
                _buildMetaPill(widget.assignment.workout.category.labelBn),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Big circular play/pause toggle that lives inside the timer ring,
  /// right under the countdown text. The whole experience is now a
  /// single press: start / pause / resume — nothing else to chase.
  Widget _buildCenterToggle() {
    final IconData icon = _completed
        ? Icons.check_rounded
        : (_running
            ? Icons.pause_rounded
            : Icons.play_arrow_rounded);
    final String label = _completed
        ? 'সম্পন্ন'
        : _running
            ? 'বিরতি'
            : (_baseSeconds > 0 ? 'চালিয়ে যান' : 'শুরু');
    final Color bg = _completed
        ? AppColors.mint
        : AppColors.void1;
    final Color fg = _completed
        ? AppColors.void1
        : AppColors.ink;

    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: _completed ? null : _toggleTimer,
        child: AnimatedContainer(
          duration: AppMotion.short,
          curve: AppMotion.standard,
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: _saving
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation(fg),
                  ),
                )
              : Icon(icon, color: fg, size: 36),
        ),
      ),
    );
  }

  Widget _buildMetaPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.graphite,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.smoke, width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppColors.paper,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildDescription(Workout w) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Overline('বিবরণ'),
          const SizedBox(height: 8),
          Text(
            w.descriptionBn,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructions(Workout w) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.chalk, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('ধাপে ধাপে'),
            const SizedBox(height: 8),
            ...List.generate(w.instructions.length, (i) {
              final step = '${i + 1}. ${w.instructions[i]}';
              return Padding(
                padding: EdgeInsets.only(
                    bottom: i == w.instructions.length - 1 ? 0 : 10),
                child: Text(
                  step,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                    height: 1.4,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Sets / reps / frequency card. Falls back to duration/equipment
  /// hints when no structured sets/reps exist.
  Widget _buildDetails(Workout w) {
    final rows = <_DetailRow>[];
    final setsReps = w.setsRepsLabel;
    if (setsReps != null) {
      rows.add(_DetailRow(icon: Icons.fitness_center_rounded, text: 'সেট/রিপিট: $setsReps'));
    }
    if (w.durationMin != null && w.durationMin! > 0) {
      rows.add(_DetailRow(icon: Icons.timer_outlined, text: 'প্রতি সেশন: ${w.durationMin} মিনিট'));
    }
    if (w.frequencyPerWeek != null && w.frequencyPerWeek! > 0) {
      final plural = w.frequencyPerWeek! == 1 ? 'দিন' : 'দিন';
      rows.add(_DetailRow(icon: Icons.calendar_today_rounded, text: 'সপ্তাহে ${w.frequencyPerWeek} $plural'));
    }
    final flags = <String>[];
    if (w.beginner) flags.add('শুরু-বান্ধব');
    if (w.elderlyFriendly) flags.add('বয়স্ক-উপযোগী');
    if (w.chairSupported) flags.add('চেয়ার-সাপোর্টেড');
    if (w.lowImpact) flags.add('লো-ইমপ্যাক্ট');
    if (w.jointFriendly) flags.add('জয়েন্ট-ফ্রেন্ডলি');
    if (w.balanceRequired) flags.add('ভারসাম্য প্রয়োজন');

    final suitability = <String>[];
    if (w.diabetesSuitable) suitability.add('ডায়াবেটিস');
    if (w.hypertensionSuitable) suitability.add('উচ্চ রক্তচাপ');
    if (w.obesitySuitable) suitability.add('স্থূলতা');
    if (w.anemiaSuitable) suitability.add('অ্যানিমিয়া');

    if (rows.isEmpty && flags.isEmpty && suitability.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.chalk, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('বিস্তারিত'),
            const SizedBox(height: 10),
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(r.icon, size: 18, color: AppColors.smoke),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          r.text,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 6),
            _buildTimeGuidance(w),
            if (flags.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildChips('বৈশিষ্ট্য', flags, AppColors.ink),
            ],
            if (suitability.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildChips('উপযুক্ত', suitability, AppColors.ink),
            ],
          ],
        ),
      ),
    );
  }

  /// "সুপারিশকৃত সময়" hint for this exercise — sets the expectation
  /// the timer is tracking against. Also shows the user's actual
  /// duration once they've saved once today.
  Widget _buildTimeGuidance(Workout w) {
    final target = w.targetDurationSeconds;
    if (target <= 0) return const SizedBox.shrink();
    final m = target ~/ 60;
    final s = target % 60;
    final mLabel = s == 0 ? '$m' : '$m মি. $s সে.';
    final done = _totalSeconds;
    final completedToday = done >= target;
    final String status;
    final Color color;
    if (completedToday) {
      status = 'সময় পূরণ — আপনি $done সেকেন্ড নিয়েছেন';
      color = AppColors.ink;
    } else if (done > 0) {
      status = 'আপনি $done সেকেন্ড নিয়েছেন — আরও ${target - done} সে. দরকার';
      color = AppColors.smoke;
    } else {
      status = 'সুপারিশকৃত সময়: $mLabel';
      color = AppColors.ink;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.chalk, width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChips(String label, List<String> items, Color fg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.smoke,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: items
              .map((t) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.chalk, width: 1),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildEquipment(Workout w) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.chalk, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Overline('যন্ত্রপাতি'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: w.equipment
                  .map((e) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.paper,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AppColors.chalk, width: 1),
                        ),
                        child: Text(
                          _equipmentLabel(e),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _equipmentLabel(String raw) {
    switch (raw) {
      case 'chair':
        return 'চেয়ার';
      case 'resistance_band':
        return 'রেজিস্ট্যান্স ব্যান্ড';
      case 'dumbbell':
        return 'ডাম্বেল';
      case 'bench':
        return 'বেঞ্চ';
      case 'mat':
        return 'ম্যাট';
      case 'pool':
        return 'পুকুর/পুল';
      case 'broom':
        return 'ঝাড়ু';
      case 'mop':
        return 'মপ';
      case 'rowing_machine':
        return 'রোয়িং মেশিন';
      case 'stationary_bike':
        return 'স্থির সাইকেল';
      case 'bicycle':
        return 'সাইকেল';
      case 'step':
        return 'স্টেপ';
      default:
        return raw;
    }
  }

  Widget _buildSafety(Workout w) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.chalk, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (w.safetyNotesBn != null && w.safetyNotesBn!.trim().isNotEmpty) ...[
              const Overline('নিরাপত্তা'),
              const SizedBox(height: 8),
              Text(
                w.safetyNotesBn!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                  height: 1.4,
                ),
              ),
            ],
            if (w.contraindications != null && w.contraindications!.trim().isNotEmpty) ...[
              if (w.safetyNotesBn != null && w.safetyNotesBn!.trim().isNotEmpty)
                const SizedBox(height: 12),
              const Overline('সতর্কতা'),
              const SizedBox(height: 8),
              Text(
                w.contraindications!,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Bottom action row — single "সম্পন্ন করুন" button that closes the
  /// workout out and marks it complete. Auto-save happens on every
  /// pause, so this is just the explicit "I'm done" signal.
  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: MonoButton(
              label: _completed ? 'সম্পন্ন হয়েছে' : 'সম্পন্ন করুন',
              leading: _completed
                  ? Icons.check_circle_rounded
                  : Icons.check_rounded,
              variant: MonoButtonVariant.primary,
              onPressed: _completed
                  ? null
                  : (_running ? _markCompleted : _markCompleted),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'পজ করলে সময় স্বয়ংক্রিয়ভাবে সেভ হয়। সেভ বোতাম লাগবে না।',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.smoke,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

/// Internal row helper, kept private to this file.
class _DetailRow {
  final IconData icon;
  final String text;
  const _DetailRow({required this.icon, required this.text});
}