/// User-defined meal plan entry.
///
/// Mirrors the `user_meal_plans` table in the Supabase schema. These
/// are the user's own custom meals — anything the AI-suggested 30-day
/// rotation doesn't cover. Examples:
///   * a doctor-prescribed food at a specific time
///   * a free-text "tiffin" or "before-bed warm milk"
///   * the user swapping the suggested lunch for their own choice
///
/// The `food` field is populated when the entry points to the master
/// `foods` table; otherwise it's null and only `customFoodName` is set.
class UserMealPlan {
  final String id;
  final DateTime effectiveDate;
  final String slot; // breakfast | morning_snack | lunch | evening_snack | dinner | tiffin | late_night | pre_workout | post_workout | other
  final String? scheduledTime; // HH:mm:ss string from Postgres time
  final String? foodId;
  final String? customFoodName;
  final String? portionLabel;
  final String? notes;
  final int position;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Resolved master food (if food_id is set). May be null if the row
  /// was created for a food that's been deleted.
  final Map<String, dynamic>? food;

  const UserMealPlan({
    required this.id,
    required this.effectiveDate,
    required this.slot,
    this.scheduledTime,
    this.foodId,
    this.customFoodName,
    this.portionLabel,
    this.notes,
    this.position = 0,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.food,
  });

  factory UserMealPlan.fromJson(Map<String, dynamic> json) {
    return UserMealPlan(
      id: (json['id'] ?? '') as String,
      effectiveDate: DateTime.parse(json['effective_date'] as String),
      slot: (json['slot'] ?? 'other') as String,
      scheduledTime: json['scheduled_time'] as String?,
      foodId: json['food_id'] as String?,
      customFoodName: json['custom_food_name'] as String?,
      portionLabel: json['portion_label'] as String?,
      notes: json['notes'] as String?,
      position: (json['position'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      food: (json['food'] is Map)
          ? Map<String, dynamic>.from(json['food'] as Map)
          : null,
    );
  }

  String get displayName {
    if (food != null && (food!['name_bn'] as String?)?.isNotEmpty == true) {
      return food!['name_bn'] as String;
    }
    return customFoodName ?? '';
  }

  /// "MM" or "HH:mm" depending on length — render-friendly time.
  String get displayTime {
    final t = scheduledTime;
    if (t == null || t.isEmpty) return '';
    // Postgres "time" returns HH:mm:ss or HH:mm:ss.ffffff
    final parts = t.split(':');
    if (parts.length < 2) return t;
    return '${parts[0]}:${parts[1]}';
  }

  UserMealPlan copyWith({
    DateTime? effectiveDate,
    String? slot,
    String? scheduledTime,
    bool clearScheduledTime = false,
    String? foodId,
    bool clearFoodId = false,
    String? customFoodName,
    String? portionLabel,
    String? notes,
    int? position,
    bool? isActive,
  }) {
    return UserMealPlan(
      id: id,
      effectiveDate: effectiveDate ?? this.effectiveDate,
      slot: slot ?? this.slot,
      scheduledTime: clearScheduledTime ? null : (scheduledTime ?? this.scheduledTime),
      foodId: clearFoodId ? null : (foodId ?? this.foodId),
      customFoodName: customFoodName ?? this.customFoodName,
      portionLabel: portionLabel ?? this.portionLabel,
      notes: notes ?? this.notes,
      position: position ?? this.position,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
      food: food,
    );
  }
}

/// Built-in slot options exposed in the picker. The `slot` column also
/// accepts free-form text, but these are the ones we suggest.
const List<String> kSlotOptions = [
  'breakfast',
  'morning_snack',
  'lunch',
  'evening_snack',
  'dinner',
  'tiffin',
  'late_night',
  'pre_workout',
  'post_workout',
  'other',
];

/// Translate a slot code into a Bangla label.
String slotLabelBn(String slot) {
  switch (slot) {
    case 'breakfast':
      return 'সকালের নাস্তা';
    case 'morning_snack':
      return 'সকালের স্ন্যাক';
    case 'lunch':
      return 'দুপুরের খাবার';
    case 'evening_snack':
      return 'বিকেলের স্ন্যাক';
    case 'dinner':
      return 'রাতের খাবার';
    case 'tiffin':
      return 'টিফিন';
    case 'late_night':
      return 'রাতে';
    case 'pre_workout':
      return 'ব্যায়ামের আগে';
    case 'post_workout':
      return 'ব্যায়ামের পরে';
    case 'other':
      return 'অন্যান্য';
    default:
      return slot;
  }
}

/// Icon for a slot — used in the UI.
const Map<String, String> slotIconName = {
  'breakfast': 'wb_sunny_outlined',
  'morning_snack': 'coffee_outlined',
  'lunch': 'lunch_dining_outlined',
  'evening_snack': 'cookie_outlined',
  'dinner': 'nightlight_outlined',
  'tiffin': 'fastfood_outlined',
  'late_night': 'bedtime_outlined',
  'pre_workout': 'fitness_center_outlined',
  'post_workout': 'sports_handball_outlined',
  'other': 'restaurant_outlined',
};

/// Result of `get_plan_progress` RPC.
///
/// The app derives the *active* 30-day plan slot from this:
/// `day = (today - plan_start_date) % total_days + 1`.
/// When `plan_complete` is true, the backend has rolled the start
/// date forward, so the next plan cycle starts immediately.
class PlanProgress {
  final int day;
  final int totalDays;
  final bool planComplete;
  final DateTime? planStartDate;
  final int daysElapsed;

  const PlanProgress({
    required this.day,
    required this.totalDays,
    required this.planComplete,
    required this.planStartDate,
    required this.daysElapsed,
  });

  factory PlanProgress.fromRow(Map<String, dynamic> row) {
    final d = row['day'];
    final t = row['total_days'];
    final c = row['plan_complete'];
    final s = row['plan_start_date'];
    final e = row['days_elapsed'];
    return PlanProgress(
      day: (d is num) ? d.toInt() : 1,
      totalDays: (t is num) ? t.toInt() : 30,
      planComplete: c == true,
      planStartDate: s is String
          ? DateTime.tryParse(s)
          : (s is DateTime ? s : null),
      daysElapsed: (e is num) ? e.toInt() : 0,
    );
  }

  factory PlanProgress.fallback() =>
      const PlanProgress(day: 1, totalDays: 30, planComplete: false, planStartDate: null, daysElapsed: 0);

  /// Fraction complete in the active 30-day cycle (0..1).
  double get cycleFraction =>
      totalDays == 0 ? 0 : (day - 1) / totalDays;

  bool get isFinalDay => day >= totalDays;
}
