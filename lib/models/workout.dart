/// আমার ডায়েট — workouts model.
///
/// Mirrors the layout of `supabaset sql/13_workouts.sql`:
///   • [Workout]           — catalogue row from `public.workouts`.
///   • [WorkoutAssignment] — assignment for a (user, day) tuple.
///   • [WorkoutSession]    — one session per user per day.
///   • [WorkoutSessionItem]— one per exercise in a session.
///
/// All models are JSON-tolerant: missing fields fall back to safe
/// defaults so a partial response from the RPC never crashes the UI.
library;

import 'package:flutter/foundation.dart';

/// Coerce a JSON value to `int`. Supabase sometimes returns numeric
/// columns as `double` (e.g. when the upstream expression is a math
/// operation). A bare `as int?` then throws `type 'double' is not a
/// subtype of type 'int'` and breaks the whole tile. Centralised here
/// so every numeric field uses the same forgiving cast.
int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// Coarse exercise category. Drives the icon + color tint in the UI.
enum WorkoutCategory {
  cardio,
  strength,
  flexibility,
  balance,
  breathing,
  yoga,
  household,
  walking;

  /// Bangla label for the category.
  String get labelBn {
    switch (this) {
      case WorkoutCategory.cardio:
        return 'কার্ডিও';
      case WorkoutCategory.strength:
        return 'শক্তি';
      case WorkoutCategory.flexibility:
        return 'নমনীয়তা';
      case WorkoutCategory.balance:
        return 'ভারসাম্য';
      case WorkoutCategory.breathing:
        return 'শ্বাস-প্রশ্বাস';
      case WorkoutCategory.yoga:
        return 'যোগা';
      case WorkoutCategory.household:
        return 'ঘরোয়া কাজ';
      case WorkoutCategory.walking:
        return 'হাঁটা';
    }
  }

  static WorkoutCategory fromString(String? raw) {
    switch (raw) {
      case 'cardio':
        return WorkoutCategory.cardio;
      case 'strength':
        return WorkoutCategory.strength;
      case 'flexibility':
        return WorkoutCategory.flexibility;
      case 'balance':
        return WorkoutCategory.balance;
      case 'breathing':
        return WorkoutCategory.breathing;
      case 'yoga':
        return WorkoutCategory.yoga;
      case 'household':
        return WorkoutCategory.household;
      case 'walking':
        return WorkoutCategory.walking;
      default:
        return WorkoutCategory.cardio;
    }
  }
}

/// Beginner / intermediate / advanced. Defaults to beginner when unknown
/// so older / diabetic users land on the safer side of the catalogue.
enum WorkoutDifficulty {
  beginner,
  intermediate,
  advanced;

  String get labelBn {
    switch (this) {
      case WorkoutDifficulty.beginner:
        return 'শুরু';
      case WorkoutDifficulty.intermediate:
        return 'মধ্যম';
      case WorkoutDifficulty.advanced:
        return 'উন্নত';
    }
  }

  static WorkoutDifficulty fromString(String? raw) {
    switch (raw) {
      case 'beginner':
        return WorkoutDifficulty.beginner;
      case 'intermediate':
        return WorkoutDifficulty.intermediate;
      case 'advanced':
        return WorkoutDifficulty.advanced;
      default:
        return WorkoutDifficulty.beginner;
    }
  }
}

/// "Low / medium / high" — drives the warning chip in the UI.
enum WorkoutIntensity {
  low,
  medium,
  high;

  String get labelBn {
    switch (this) {
      case WorkoutIntensity.low:
        return 'হালকা';
      case WorkoutIntensity.medium:
        return 'মাঝারি';
      case WorkoutIntensity.high:
        return 'কঠিন';
    }
  }

  static WorkoutIntensity fromString(String? raw) {
    switch (raw) {
      case 'low':
        return WorkoutIntensity.low;
      case 'medium':
        return WorkoutIntensity.medium;
      case 'high':
        return WorkoutIntensity.high;
      default:
        return WorkoutIntensity.low;
    }
  }
}

/// Catalogue entry. Mirrors a row in `public.workouts`.
@immutable
class Workout {
  final String id;
  final String nameBn;
  final String? nameEn;
  final WorkoutCategory category;
  final String? subCategory;
  final WorkoutIntensity intensity;
  final WorkoutDifficulty difficulty;
  final int targetDurationSeconds;
  final int? durationMin;
  final int? sets;
  final String? repetitions;
  final int? frequencyPerWeek;
  final int targetCaloriesKcal;
  final String descriptionBn;
  final String? instructionsBn;
  final List<String> instructions;
  final List<String> equipment;
  final bool beginner;
  final bool elderlyFriendly;
  final bool chairSupported;
  final bool lowImpact;
  final bool jointFriendly;
  final bool balanceRequired;
  final bool diabetesSuitable;
  final bool hypertensionSuitable;
  final bool obesitySuitable;
  final bool anemiaSuitable;
  final String? videoUrl;
  final String? safetyNotesBn;
  final String? contraindications;

  const Workout({
    required this.id,
    required this.nameBn,
    required this.category,
    required this.intensity,
    required this.targetDurationSeconds,
    this.nameEn,
    this.subCategory,
    this.difficulty = WorkoutDifficulty.beginner,
    this.durationMin,
    this.sets,
    this.repetitions,
    this.frequencyPerWeek,
    this.targetCaloriesKcal = 0,
    this.descriptionBn = '',
    this.instructionsBn,
    this.instructions = const [],
    this.equipment = const [],
    this.beginner = false,
    this.elderlyFriendly = false,
    this.chairSupported = false,
    this.lowImpact = true,
    this.jointFriendly = false,
    this.balanceRequired = false,
    this.diabetesSuitable = true,
    this.hypertensionSuitable = true,
    this.obesitySuitable = true,
    this.anemiaSuitable = true,
    this.videoUrl,
    this.safetyNotesBn,
    this.contraindications,
  });

  /// "10:30" — friendly mm:ss string for the target duration.
  String get targetDurationLabel {
    final m = targetDurationSeconds ~/ 60;
    final s = targetDurationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// "3 × 10-15" — compact sets/reps line for the workout card.
  String? get setsRepsLabel {
    if (sets == null && (repetitions == null || repetitions!.isEmpty)) {
      return null;
    }
    final s = sets == null ? '–' : '$sets';
    final r = (repetitions == null || repetitions!.isEmpty) ? '–' : repetitions;
    return '$s × $r';
  }

  factory Workout.fromJson(Map<String, dynamic> json) {
    final rawInst = json['instructions'];
    final inst = <String>[];
    if (rawInst is List) {
      for (final v in rawInst) {
        if (v is String && v.isNotEmpty) inst.add(v);
      }
    }
    final rawEq = json['equipment'];
    final eq = <String>[];
    if (rawEq is List) {
      for (final v in rawEq) {
        if (v is String && v.isNotEmpty) eq.add(v);
      }
    }
    return Workout(
      id: (json['id'] ?? json['workout_id'] ?? '') as String,
      nameBn: (json['name_bn'] ?? '') as String,
      nameEn: json['name_en'] as String?,
      category: WorkoutCategory.fromString(json['category'] as String?),
      subCategory: json['sub_category'] as String?,
      intensity: WorkoutIntensity.fromString(json['intensity'] as String?),
      difficulty: WorkoutDifficulty.fromString(json['difficulty'] as String?),
      targetDurationSeconds:
          _asInt(json['target_duration_seconds']) ?? 60,
      durationMin: _asInt(json['duration_min']) ??
          ((json['target_duration_seconds'] != null)
              ? ((_asInt(json['target_duration_seconds']) ?? 60) / 60).round()
              : null),
      sets: _asInt(json['sets']),
      repetitions: json['repetitions'] as String?,
      frequencyPerWeek: _asInt(json['frequency_per_week']),
      targetCaloriesKcal: _asInt(json['target_calories_kcal']) ?? 0,
      descriptionBn: (json['description_bn'] ?? '') as String,
      instructionsBn: json['instructions_bn'] as String?,
      instructions: inst,
      equipment: eq,
      beginner: (json['beginner'] as bool?) ?? false,
      elderlyFriendly: (json['elderly_friendly'] as bool?) ?? false,
      chairSupported: (json['chair_supported'] as bool?) ?? false,
      lowImpact: (json['low_impact'] as bool?) ?? true,
      jointFriendly: (json['joint_friendly'] as bool?) ?? false,
      balanceRequired: (json['balance_required'] as bool?) ?? false,
      diabetesSuitable: (json['diabetes_suitable'] as bool?) ?? true,
      hypertensionSuitable: (json['hypertension_suitable'] as bool?) ?? true,
      obesitySuitable: (json['obesity_suitable'] as bool?) ?? true,
      anemiaSuitable: (json['anemia_suitable'] as bool?) ?? true,
      videoUrl: json['video_url'] as String?,
      safetyNotesBn: json['safety_notes_bn'] as String?,
      contraindications: json['contraindications'] as String?,
    );
  }

  @override
  String toString() => 'Workout($id, $nameBn)';
}

/// One row of `public.workout_assignments` — pairs a workout with a
/// program day. Carries enough catalogue fields so the plan list can
/// render a tile without a second fetch.
@immutable
class WorkoutAssignment {
  final Workout workout;
  final int dayIndex;
  final int position;

  const WorkoutAssignment({
    required this.workout,
    required this.dayIndex,
    required this.position,
  });

  factory WorkoutAssignment.fromJson(Map<String, dynamic> json) {
    return WorkoutAssignment(
      workout: Workout.fromJson(json),
      dayIndex: _asInt(json['day_index']) ?? 1,
      position: _asInt(json['position']) ?? 0,
    );
  }
}

/// One row of `public.workout_session_items`.
@immutable
class WorkoutSessionItem {
  final String id;
  final String workoutId;
  final int position;
  final bool isCompleted;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int durationSeconds;

  const WorkoutSessionItem({
    required this.id,
    required this.workoutId,
    required this.position,
    this.isCompleted = false,
    this.startedAt,
    this.finishedAt,
    this.durationSeconds = 0,
  });

  WorkoutSessionItem copyWith({
    bool? isCompleted,
    DateTime? startedAt,
    DateTime? finishedAt,
    int? durationSeconds,
  }) {
    return WorkoutSessionItem(
      id: id,
      workoutId: workoutId,
      position: position,
      isCompleted: isCompleted ?? this.isCompleted,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  factory WorkoutSessionItem.fromJson(Map<String, dynamic> json) {
    DateTime? parse(String? s) {
      if (s == null || s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    return WorkoutSessionItem(
      id: (json['id'] ?? '') as String,
      workoutId: (json['workout_id'] ?? '') as String,
      position: _asInt(json['position']) ?? 0,
      isCompleted: (json['is_completed'] as bool?) ?? false,
      startedAt: parse(json['started_at'] as String?),
      finishedAt: parse(json['finished_at'] as String?),
      durationSeconds: _asInt(json['duration_seconds']) ?? 0,
    );
  }
}

/// One row of `public.workout_sessions`.
@immutable
class WorkoutSession {
  final String id;
  final DateTime sessionDate;
  final int? programDay;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final int totalDurationSeconds;
  final int completedItems;
  final int totalItems;
  final bool isFinished;
  final List<WorkoutSessionItem> items;

  const WorkoutSession({
    required this.id,
    required this.sessionDate,
    required this.startedAt,
    this.programDay,
    this.finishedAt,
    this.totalDurationSeconds = 0,
    this.completedItems = 0,
    this.totalItems = 0,
    this.isFinished = false,
    this.items = const [],
  });

  WorkoutSession copyWith({
    DateTime? finishedAt,
    int? totalDurationSeconds,
    int? completedItems,
    int? totalItems,
    bool? isFinished,
    List<WorkoutSessionItem>? items,
  }) {
    return WorkoutSession(
      id: id,
      sessionDate: sessionDate,
      programDay: programDay,
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      completedItems: completedItems ?? this.completedItems,
      totalItems: totalItems ?? this.totalItems,
      isFinished: isFinished ?? this.isFinished,
      items: items ?? this.items,
    );
  }

  /// 0..1 progress for the progress bar.
  double get progress {
    if (totalItems <= 0) return 0;
    return (completedItems / totalItems).clamp(0.0, 1.0);
  }

  factory WorkoutSession.fromJson(Map<String, dynamic> json) {
    DateTime parse(String? s) =>
        s == null || s.isEmpty ? DateTime.now() : DateTime.parse(s);
    DateTime? parseOpt(String? s) =>
        s == null || s.isEmpty ? null : DateTime.parse(s);

    final rawItems = json['items'];
    final items = <WorkoutSessionItem>[];
    if (rawItems is List) {
      for (final v in rawItems) {
        if (v is Map) {
          items.add(WorkoutSessionItem.fromJson(
              Map<String, dynamic>.from(v)));
        }
      }
    }

    return WorkoutSession(
      id: (json['id'] ?? '') as String,
      sessionDate: parse(json['session_date'] as String?),
      programDay: _asInt(json['program_day']),
      startedAt: parse(json['started_at'] as String?),
      finishedAt: parseOpt(json['finished_at'] as String?),
      totalDurationSeconds:
          _asInt(json['total_duration_seconds']) ?? 0,
      completedItems: _asInt(json['completed_items']) ?? 0,
      totalItems: _asInt(json['total_items']) ?? 0,
      isFinished: (json['is_finished'] as bool?) ?? false,
      items: items,
    );
  }
}

/// Whole "today's workout" payload from `get_today_workout(p_day_index)`.
@immutable
class TodaysWorkout {
  final int dayIndex;
  final DateTime today;
  final List<WorkoutAssignment> assignments;
  final WorkoutSession? session;

  const TodaysWorkout({
    required this.dayIndex,
    required this.today,
    required this.assignments,
    this.session,
  });

  /// Total planned exercises for the day (regardless of session state).
  int get totalPlanned => assignments.length;

  /// Number of completed items in the session, or 0 if no session.
  int get completedCount => session?.completedItems ?? 0;

  bool get hasSession => session != null;

  bool get isFinished => session?.isFinished ?? false;

  double get progress {
    if (totalPlanned == 0) return 0;
    return (completedCount / totalPlanned).clamp(0.0, 1.0);
  }

  factory TodaysWorkout.fromJson(Map<String, dynamic> json) {
    final rawAssign = json['assignments'];
    final assignments = <WorkoutAssignment>[];
    if (rawAssign is List) {
      for (final v in rawAssign) {
        if (v is Map) {
          assignments.add(WorkoutAssignment.fromJson(
              Map<String, dynamic>.from(v)));
        }
      }
    }

    final sessionJson = json['session'];
    final WorkoutSession? session;
    if (sessionJson is Map && sessionJson.isNotEmpty) {
      session = WorkoutSession.fromJson(Map<String, dynamic>.from(sessionJson));
    } else {
      session = null;
    }

    DateTime parseDate(String? s) =>
        s == null || s.isEmpty ? DateTime.now() : DateTime.parse(s);

    return TodaysWorkout(
      dayIndex: (json['day_index'] as int?) ?? 1,
      today: parseDate(json['today'] as String?),
      assignments: assignments,
      session: session,
    );
  }
}

/// Window summary from `get_workout_adherence`.
@immutable
class WorkoutAdherence {
  final int totalSessions;
  final int completed;
  final double completedPct;
  final int currentStreakDays;
  final int windowDays;
  /// Number of distinct days in the window that had any session —
  /// handy for the dashboard's "active days" tile.
  final int daysActive;

  const WorkoutAdherence({
    required this.totalSessions,
    required this.completed,
    required this.completedPct,
    required this.currentStreakDays,
    required this.windowDays,
    this.daysActive = 0,
  });

  factory WorkoutAdherence.fromJson(Map<String, dynamic> json) {
    return WorkoutAdherence(
      totalSessions: (json['total_sessions'] ?? 0) as int,
      completed: (json['completed'] ?? 0) as int,
      completedPct: ((json['completed_pct'] ?? 0) as num).toDouble(),
      currentStreakDays: (json['current_streak_days'] ?? 0) as int,
      windowDays: (json['window_days'] ?? 7) as int,
      daysActive: (json['days_active'] ?? 0) as int,
    );
  }

  static const empty = WorkoutAdherence(
    totalSessions: 0,
    completed: 0,
    completedPct: 0,
    currentStreakDays: 0,
    windowDays: 7,
    daysActive: 0,
  );

  // Aliases used by the dashboard for a uniform "% X" tile.
  double get completedPercent => completedPct;
  int get total => totalSessions;
}

/// Window summary from `get_meal_adherence`.
@immutable
class MealAdherence {
  final int planned;
  final int eaten;
  final double eatenPct;
  final int currentStreakDays;
  final int windowDays;

  const MealAdherence({
    required this.planned,
    required this.eaten,
    required this.eatenPct,
    required this.currentStreakDays,
    required this.windowDays,
  });

  factory MealAdherence.fromJson(Map<String, dynamic> json) {
    return MealAdherence(
      planned: (json['planned'] ?? 0) as int,
      eaten: (json['eaten'] ?? 0) as int,
      eatenPct: ((json['eaten_pct'] ?? 0) as num).toDouble(),
      currentStreakDays: (json['current_streak_days'] ?? 0) as int,
      windowDays: (json['window_days'] ?? 7) as int,
    );
  }

  static const empty = MealAdherence(
    planned: 0,
    eaten: 0,
    eatenPct: 0,
    currentStreakDays: 0,
    windowDays: 7,
  );

  // Aliases used by the dashboard.
  double get takenPercent => eatenPct;
  int get total => planned;
}

/// Per-day row from `get_workout_logs(p_days)`.
@immutable
class WorkoutLogRow {
  final DateTime day;
  final int total;
  final int completed;
  final int totalMinutes;
  final int totalCalories;

  const WorkoutLogRow({
    required this.day,
    required this.total,
    required this.completed,
    this.totalMinutes = 0,
    this.totalCalories = 0,
  });

  factory WorkoutLogRow.fromJson(Map<String, dynamic> json) {
    DateTime parse(String? s) =>
        s == null || s.isEmpty ? DateTime.now() : DateTime.parse(s);
    return WorkoutLogRow(
      day: parse(json['day'] as String?),
      total: (json['total'] ?? 0) as int,
      completed: (json['completed'] ?? 0) as int,
      totalMinutes: (json['total_minutes'] ?? 0) as int,
      totalCalories: (json['total_calories'] ?? 0) as int,
    );
  }
}

/// Per-day row from `get_meal_adherence(...)` -- when the SQL is called
/// with a single-day window the result is a one-element list; the same
/// shape is convenient for the 7-day meal chart on the dashboard.
@immutable
class MealLogRow {
  final DateTime day;
  final int planned;
  final int eaten;

  const MealLogRow({
    required this.day,
    required this.planned,
    required this.eaten,
  });

  factory MealLogRow.fromJson(Map<String, dynamic> json) {
    DateTime parse(String? s) =>
        s == null || s.isEmpty ? DateTime.now() : DateTime.parse(s);
    return MealLogRow(
      day: parse(json['day'] as String?),
      planned: (json['planned'] ?? 0) as int,
      eaten: (json['eaten'] ?? 0) as int,
    );
  }
}

/// Per-day row from `get_medicine_adherence(...)` shaped for the chart.
@immutable
class MedicineLogRow {
  final DateTime day;
  final int total;
  final int taken;
  final double takenPct;

  const MedicineLogRow({
    required this.day,
    required this.total,
    required this.taken,
    required this.takenPct,
  });

  factory MedicineLogRow.fromJson(Map<String, dynamic> json) {
    DateTime parse(String? s) =>
        s == null || s.isEmpty ? DateTime.now() : DateTime.parse(s);
    return MedicineLogRow(
      day: parse(json['day'] as String?),
      total: (json['total'] ?? 0) as int,
      taken: (json['taken'] ?? 0) as int,
      takenPct: ((json['taken_pct'] ?? 0) as num).toDouble(),
    );
  }
}

/// Per-day time-tracking row from `get_workout_time_tracking(p_days)`.
/// Powers the "লক্ষ্য vs আপনার সময়" card on the workout tab.
@immutable
class WorkoutTimeRow {
  final DateTime day;
  final int targetSeconds;
  final int actualSeconds;
  final int targetMinutes;
  final int actualMinutes;
  final double pct;
  final int plannedCount;
  final int completedCount;

  const WorkoutTimeRow({
    required this.day,
    required this.targetSeconds,
    required this.actualSeconds,
    required this.targetMinutes,
    required this.actualMinutes,
    required this.pct,
    required this.plannedCount,
    required this.completedCount,
  });

  factory WorkoutTimeRow.fromJson(Map<String, dynamic> json) {
    DateTime parse(String? s) =>
        s == null || s.isEmpty ? DateTime.now() : DateTime.parse(s);
    return WorkoutTimeRow(
      day: parse(json['day'] as String?),
      targetSeconds: (json['target_seconds'] ?? 0) as int,
      actualSeconds: (json['actual_seconds'] ?? 0) as int,
      targetMinutes: (json['target_minutes'] ?? 0) as int,
      actualMinutes: (json['actual_minutes'] ?? 0) as int,
      pct: ((json['pct'] ?? 0) as num).toDouble(),
      plannedCount: (json['planned_count'] ?? 0) as int,
      completedCount: (json['completed_count'] ?? 0) as int,
    );
  }
}

/// Per-exercise feedback from `get_today_exercise_time_feedback()`.
/// One row per assigned workout for today.
@immutable
class WorkoutExerciseTimeFeedback {
  final String workoutId;
  final int targetSeconds;
  final int actualSeconds;
  final int targetMinutes;
  final int actualMinutes;
  final double pct;
  final String hintBn;
  final String status; // 'pending' | 'partial' | 'met'

  const WorkoutExerciseTimeFeedback({
    required this.workoutId,
    required this.targetSeconds,
    required this.actualSeconds,
    required this.targetMinutes,
    required this.actualMinutes,
    required this.pct,
    required this.hintBn,
    required this.status,
  });

  factory WorkoutExerciseTimeFeedback.fromJson(Map<String, dynamic> json) {
    return WorkoutExerciseTimeFeedback(
      workoutId: (json['workout_id'] ?? '') as String,
      targetSeconds: (json['target_seconds'] ?? 0) as int,
      actualSeconds: (json['actual_seconds'] ?? 0) as int,
      targetMinutes: (json['target_minutes'] ?? 0) as int,
      actualMinutes: (json['actual_minutes'] ?? 0) as int,
      pct: ((json['pct'] ?? 0) as num).toDouble(),
      hintBn: (json['hint_bn'] ?? '') as String,
      status: (json['status'] ?? 'pending') as String,
    );
  }

  static const empty = WorkoutExerciseTimeFeedback(
    workoutId: '',
    targetSeconds: 0,
    actualSeconds: 0,
    targetMinutes: 0,
    actualMinutes: 0,
    pct: 0,
    hintBn: '',
    status: 'pending',
  );
}

/// Bundled time-tracking payload — daily rows + a per-exercise feedback
/// map keyed by workout id. The workout screen consumes both.
@immutable
class WorkoutTimeTracking {
  final List<WorkoutTimeRow> daily;
  final Map<String, WorkoutExerciseTimeFeedback> byWorkout;

  const WorkoutTimeTracking({
    required this.daily,
    required this.byWorkout,
  });

  static const empty = WorkoutTimeTracking(daily: [], byWorkout: {});

  /// "Today's" row, or a synthesised zero row if today has no entry.
  WorkoutTimeRow get today {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final r in daily) {
      if (r.day.year == today.year &&
          r.day.month == today.month &&
          r.day.day == today.day) {
        return r;
      }
    }
    return WorkoutTimeRow(
      day: today,
      targetSeconds: 0,
      actualSeconds: 0,
      targetMinutes: 0,
      actualMinutes: 0,
      pct: 0,
      plannedCount: 0,
      completedCount: 0,
    );
  }

  /// Sum of target vs. actual across the window — used by the
  /// "এই ৭ দিনে" headline.
  int get totalTargetMinutes =>
      daily.fold(0, (sum, r) => sum + r.targetMinutes);
  int get totalActualMinutes =>
      daily.fold(0, (sum, r) => sum + r.actualMinutes);
}
